import json
import logging
import os
import signal
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse

import requests
from kafka import KafkaConsumer, KafkaProducer
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

LOGGER = logging.getLogger("zline.worker")
LINE_PUSH_URL = "https://api.line.me/v2/bot/message/push"
DEFAULT_DATABASE_URL = "postgresql://zlinebot:zlinebot@db:5432/zlinebot_automos"
DEFAULT_KAFKA_BROKER = "kafka:9092"
WORKER_TOPICS = ("events.messages", "events.broadcasts")


@dataclass(frozen=True)
class WorkerConfig:
    database_url: str
    kafka_broker: str
    kafka_group_id: str
    line_push_timeout: int
    idle_sleep_seconds: float

    @classmethod
    def from_env(cls) -> "WorkerConfig":
        return cls(
            database_url=os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL),
            kafka_broker=os.getenv("KAFKA_BROKER", DEFAULT_KAFKA_BROKER),
            kafka_group_id=os.getenv("KAFKA_GROUP_ID", "zline-worker"),
            line_push_timeout=int(os.getenv("LINE_PUSH_TIMEOUT_SECONDS", "10")),
            idle_sleep_seconds=float(os.getenv("WORKER_IDLE_SLEEP_SECONDS", "1")),
        )


class WorkerError(RuntimeError):
    pass


class Worker:
    def __init__(self, config: WorkerConfig):
        self.config = config
        self.engine = self._make_engine(config.database_url)
        self.producer = KafkaProducer(
            bootstrap_servers=config.kafka_broker,
            value_serializer=lambda value: json.dumps(value).encode("utf-8"),
            retries=3,
        )
        self.consumer = KafkaConsumer(
            *WORKER_TOPICS,
            bootstrap_servers=config.kafka_broker,
            group_id=config.kafka_group_id,
            enable_auto_commit=False,
            auto_offset_reset="earliest",
            value_deserializer=lambda message: json.loads(message.decode("utf-8")),
            consumer_timeout_ms=1000,
        )
        self.running = True

    @staticmethod
    def _make_engine(database_url: str) -> Engine:
        parsed = urlparse(database_url)
        if parsed.scheme == "sqlite":
            return create_engine(database_url, future=True, connect_args={"check_same_thread": False})
        return create_engine(database_url, future=True, pool_pre_ping=True)

    def stop(self, *_args: Any) -> None:
        LOGGER.info("shutdown requested")
        self.running = False

    def close(self) -> None:
        try:
            self.consumer.close()
        finally:
            try:
                self.producer.flush(timeout=5)
                self.producer.close(timeout=5)
            finally:
                self.engine.dispose()

    def run(self) -> None:
        LOGGER.info("worker started", extra={"topics": WORKER_TOPICS, "group_id": self.config.kafka_group_id})
        while self.running:
            batch = self.consumer.poll(timeout_ms=1000)
            if not batch:
                time.sleep(self.config.idle_sleep_seconds)
                continue

            for topic_partition, records in batch.items():
                for record in records:
                    processed = False
                    try:
                        self.process_record(record.topic, record.value)
                        processed = True
                    except Exception as exc:  # noqa: BLE001
                        LOGGER.exception("failed to process kafka record", extra={"topic": record.topic})
                        try:
                            self.publish_dead_letter(record.topic, record.value, exc)
                            processed = True
                        except Exception:  # noqa: BLE001
                            LOGGER.exception("failed to publish dead-letter event", extra={"topic": record.topic})

                    if processed:
                        self.consumer.commit()
                    else:
                        time.sleep(self.config.idle_sleep_seconds)

        LOGGER.info("worker stopped")

    def process_record(self, topic: str, payload: dict[str, Any]) -> None:
        if topic == "events.broadcasts":
            result = self.process_broadcast(payload)
            LOGGER.info("broadcast processed", extra=result)
            return

        if topic == "events.messages":
            result = self.process_message(payload)
            LOGGER.info("message persisted", extra=result)
            return

        raise WorkerError(f"unsupported topic: {topic}")

    def process_broadcast(self, payload: dict[str, Any]) -> dict[str, Any]:
        tenant_id = self._required_text(payload, "tenant_id")
        campaign_id = self._required_int(payload, "campaign_id")
        message = self._required_text(payload, "message")[:1000]
        target_status = self._optional_text(payload, "target_status")

        with self.engine.begin() as conn:
            tenant = conn.execute(
                text(
                    """
                    SELECT id, line_channel_token
                    FROM tenants
                    WHERE id = :tenant_id
                    """
                ),
                {"tenant_id": tenant_id},
            ).mappings().first()
            if tenant is None:
                raise WorkerError("tenant not found")

            campaign = conn.execute(
                text(
                    """
                    SELECT id, tenant_id, sent_count, reply_count
                    FROM campaigns
                    WHERE id = :campaign_id AND tenant_id = :tenant_id
                    """
                ),
                {"campaign_id": campaign_id, "tenant_id": tenant_id},
            ).mappings().first()
            if campaign is None:
                raise WorkerError("campaign not found")

            query = """
                SELECT user_id
                FROM leads
                WHERE tenant_id = :tenant_id
            """
            params: dict[str, Any] = {"tenant_id": tenant_id}
            if target_status:
                query += " AND status = :target_status"
                params["target_status"] = target_status

            recipients = conn.execute(text(query), params).mappings().all()
            sent_count = 0
            failed_count = 0

            for recipient in recipients:
                user_id = str(recipient["user_id"]).strip()
                if not user_id:
                    failed_count += 1
                    continue

                delivered = self.line_push(tenant["line_channel_token"], user_id, message)
                if not delivered:
                    failed_count += 1
                    continue

                conn.execute(
                    text(
                        """
                        INSERT INTO messages (tenant_id, lead_user_id, campaign_id, direction, channel, content)
                        VALUES (:tenant_id, :lead_user_id, :campaign_id, 'outbound', 'line', :content)
                        """
                    ),
                    {
                        "tenant_id": tenant_id,
                        "lead_user_id": user_id,
                        "campaign_id": campaign_id,
                        "content": message,
                    },
                )
                sent_count += 1

            delivery_status = "sent"
            if failed_count and sent_count:
                delivery_status = "partial"
            elif failed_count and not sent_count:
                delivery_status = "failed"

            conn.execute(
                text(
                    """
                    UPDATE campaigns
                    SET sent_count = :sent_count,
                        delivery_status = :delivery_status
                    WHERE id = :campaign_id AND tenant_id = :tenant_id
                    """
                ),
                {
                    "sent_count": sent_count,
                    "delivery_status": delivery_status,
                    "campaign_id": campaign_id,
                    "tenant_id": tenant_id,
                },
            )

        return {
            "tenant_id": tenant_id,
            "campaign_id": campaign_id,
            "sent_count": sent_count,
            "failed_count": failed_count,
            "target_status": target_status or "all",
        }

    def process_message(self, payload: dict[str, Any]) -> dict[str, Any]:
        tenant_id = self._required_text(payload, "tenant_id")
        content = self._first_text(payload, "content", "msg", "message")
        if not content:
            raise WorkerError("message content is required")

        direction = self._optional_text(payload, "direction") or "inbound"
        channel = self._optional_text(payload, "channel") or "line"
        lead_user_id = self._optional_text(payload, "lead_user_id") or self._optional_text(payload, "user_id")
        campaign_id = self._optional_int(payload, "campaign_id")

        with self.engine.begin() as conn:
            conn.execute(
                text(
                    """
                    INSERT INTO messages (tenant_id, lead_user_id, campaign_id, direction, channel, content)
                    VALUES (:tenant_id, :lead_user_id, :campaign_id, :direction, :channel, :content)
                    """
                ),
                {
                    "tenant_id": tenant_id,
                    "lead_user_id": lead_user_id,
                    "campaign_id": campaign_id,
                    "direction": direction,
                    "channel": channel,
                    "content": content,
                },
            )

            if campaign_id and direction == "inbound":
                conn.execute(
                    text(
                        """
                        UPDATE campaigns
                        SET reply_count = reply_count + 1
                        WHERE id = :campaign_id AND tenant_id = :tenant_id
                        """
                    ),
                    {"campaign_id": campaign_id, "tenant_id": tenant_id},
                )

        return {
            "tenant_id": tenant_id,
            "campaign_id": campaign_id,
            "direction": direction,
            "channel": channel,
        }

    def line_push(self, channel_token: str | None, user_id: str, message: str) -> bool:
        if not channel_token:
            LOGGER.warning("skipping line push because tenant is missing channel token", extra={"user_id": user_id})
            return False

        try:
            response = requests.post(
                LINE_PUSH_URL,
                headers={
                    "Authorization": f"Bearer {channel_token}",
                    "Content-Type": "application/json",
                },
                json={"to": user_id, "messages": [{"type": "text", "text": message[:1000]}]},
                timeout=self.config.line_push_timeout,
            )
        except requests.RequestException as exc:
            LOGGER.warning("line push request failed", extra={"user_id": user_id, "error": str(exc)})
            return False

        if response.ok:
            return True

        LOGGER.warning(
            "line push failed",
            extra={"user_id": user_id, "status_code": response.status_code, "response": response.text[:300]},
        )
        return False

    def publish_dead_letter(self, topic: str, payload: dict[str, Any], exc: Exception) -> None:
        dead_letter_payload = {
            "source_topic": topic,
            "payload": payload,
            "error": str(exc),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self.producer.send("events.dlq", dead_letter_payload).get(timeout=5)

    @staticmethod
    def _required_text(payload: dict[str, Any], key: str) -> str:
        value = str(payload.get(key, "")).strip()
        if not value:
            raise WorkerError(f"{key} is required")
        return value

    @staticmethod
    def _optional_text(payload: dict[str, Any], key: str) -> str | None:
        value = str(payload.get(key, "")).strip()
        return value or None

    @staticmethod
    def _first_text(payload: dict[str, Any], *keys: str) -> str | None:
        for key in keys:
            value = str(payload.get(key, "")).strip()
            if value:
                return value
        return None

    @staticmethod
    def _required_int(payload: dict[str, Any], key: str) -> int:
        value = Worker._optional_int(payload, key)
        if value is None:
            raise WorkerError(f"{key} is required")
        return value

    @staticmethod
    def _optional_int(payload: dict[str, Any], key: str) -> int | None:
        raw = payload.get(key)
        if raw in (None, ""):
            return None
        try:
            return int(raw)
        except (TypeError, ValueError) as exc:
            raise WorkerError(f"{key} must be an integer") from exc


def configure_logging() -> None:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def main() -> None:
    configure_logging()
    config = WorkerConfig.from_env()
    worker = Worker(config)
    signal.signal(signal.SIGTERM, worker.stop)
    signal.signal(signal.SIGINT, worker.stop)

    try:
        worker.run()
    finally:
        worker.close()


if __name__ == "__main__":
    main()
