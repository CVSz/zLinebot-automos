import json
import os
import time

import requests
from kafka import KafkaConsumer, KafkaProducer
from sqlalchemy import create_engine, text

DB = create_engine(
    os.getenv("DATABASE_URL", "postgresql://zlinebot:zlinebot@db:5432/zlinebot_automos"),
    pool_pre_ping=True,
)

producer = KafkaProducer(
    bootstrap_servers=os.getenv("KAFKA_BROKER", "kafka:9092"),
    value_serializer=lambda value: json.dumps(value).encode(),
)

consumer = KafkaConsumer(
    "events.messages",
    "events.broadcasts",
    bootstrap_servers=os.getenv("KAFKA_BROKER", "kafka:9092"),
    value_deserializer=lambda message: json.loads(message.decode()),
)

LINE_PUSH_URL = "https://api.line.me/v2/bot/message/push"


def line_push(channel_token: str | None, user_id: str, text: str) -> None:
    if not channel_token:
        return

    requests.post(
        LINE_PUSH_URL,
        headers={
            "Authorization": f"Bearer {channel_token}",
            "Content-Type": "application/json",
        },
        json={"to": user_id, "messages": [{"type": "text", "text": text[:1000]}]},
        timeout=10,
    )


for msg in consumer:
    try:
        payload = msg.value
        topic = msg.topic

        if topic == "events.broadcasts":
            tenant_id = str(payload.get("tenant_id", "")).strip()
            campaign_id = payload.get("campaign_id")
            message = str(payload.get("message", "")).strip()
            target_status = payload.get("target_status")
            if not tenant_id or not campaign_id or not message:
                raise ValueError("missing broadcast payload fields")

            with DB.begin() as conn:
                tenant = conn.execute(
                    text("SELECT line_channel_token FROM tenants WHERE id = :tenant_id"),
                    {"tenant_id": tenant_id},
                ).mappings().first()
                if tenant is None:
                    raise ValueError("tenant not found")

                query = "SELECT user_id FROM leads WHERE tenant_id = :tenant_id"
                params = {"tenant_id": tenant_id}
                if target_status:
                    query += " AND status = :target_status"
                    params["target_status"] = target_status

                recipients = conn.execute(text(query), params).mappings().all()
                sent = 0
                for recipient in recipients:
                    line_push(tenant["line_channel_token"], recipient["user_id"], message)
                    conn.execute(
                        text(
                            """
                            INSERT INTO messages (tenant_id, lead_user_id, campaign_id, direction, channel, content)
                            VALUES (:tenant_id, :lead_user_id, :campaign_id, 'outbound', 'line', :content)
                            """
                        ),
                        {
                            "tenant_id": tenant_id,
                            "lead_user_id": recipient["user_id"],
                            "campaign_id": campaign_id,
                            "content": message,
                        },
                    )
                    sent += 1

                conn.execute(
                    text(
                        """
                        UPDATE campaigns
                        SET sent_count = :sent_count, delivery_status = 'sent'
                        WHERE id = :campaign_id AND tenant_id = :tenant_id
                        """
                    ),
                    {"sent_count": sent, "campaign_id": campaign_id, "tenant_id": tenant_id},
                )
            continue

        tenant_id = str(payload.get("tenant_id", "")).strip()
        if not tenant_id:
            raise ValueError("missing tenant_id")

        with DB.begin() as conn:
            conn.execute(
                text("INSERT INTO messages (tenant_id, content, direction, channel) VALUES (:tenant_id, :content, 'inbound', 'line')"),
                {"tenant_id": tenant_id, "content": payload.get("msg", "")},
            )
    except Exception:
        try:
            producer.send("events.dlq", msg.value).get(timeout=5)
        except Exception:
            pass
        time.sleep(1)
