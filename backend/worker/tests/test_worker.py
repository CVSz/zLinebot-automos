from pathlib import Path

from sqlalchemy import create_engine, text

import backend.worker.worker as worker_module


class FakeProducer:
    def __init__(self, *args, **kwargs):
        self.sent = []

    def send(self, topic, payload):
        self.sent.append((topic, payload))

        class Result:
            def get(self, timeout=None):
                return None

        return Result()

    def flush(self, timeout=None):
        return None

    def close(self, timeout=None):
        return None


class FakeConsumer:
    def __init__(self, *args, **kwargs):
        self.commits = 0

    def poll(self, timeout_ms=None):
        return {}

    def commit(self):
        self.commits += 1
        return None

    def close(self):
        return None


class FakeRedis:
    def __init__(self):
        self.records = []

    def brpop(self, *_args, **_kwargs):
        return None

    def close(self):
        return None


class FakeResponse:
    ok = True
    status_code = 200
    text = "ok"


class FakeFailedResponse:
    ok = False
    status_code = 500
    text = "boom"


def make_worker(tmp_path: Path, monkeypatch):
    db_path = tmp_path / "worker.db"
    engine = create_engine(f"sqlite:///{db_path}", future=True)

    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE tenants (id TEXT PRIMARY KEY, name TEXT, line_channel_token TEXT)"))
        conn.execute(
            text(
                "CREATE TABLE campaigns (id INTEGER PRIMARY KEY, tenant_id TEXT, sent_count INTEGER DEFAULT 0, reply_count INTEGER DEFAULT 0, delivery_status TEXT DEFAULT 'queued')"
            )
        )
        conn.execute(text("CREATE TABLE leads (id INTEGER PRIMARY KEY, tenant_id TEXT, user_id TEXT, status TEXT)"))
        conn.execute(
            text(
                "CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, tenant_id TEXT, lead_user_id TEXT, campaign_id INTEGER, direction TEXT, channel TEXT, content TEXT)"
            )
        )
        conn.execute(text("INSERT INTO tenants (id, name, line_channel_token) VALUES ('tenant-1', 'Tenant 1', 'token')"))
        conn.execute(
            text(
                "INSERT INTO campaigns (id, tenant_id, sent_count, reply_count, delivery_status) VALUES (1, 'tenant-1', 0, 0, 'queued')"
            )
        )
        conn.execute(text("INSERT INTO leads (tenant_id, user_id, status) VALUES ('tenant-1', 'u-1', 'hot')"))
        conn.execute(text("INSERT INTO leads (tenant_id, user_id, status) VALUES ('tenant-1', 'u-2', 'cold')"))

    monkeypatch.setattr(worker_module, "KafkaProducer", FakeProducer)
    monkeypatch.setattr(worker_module, "KafkaConsumer", FakeConsumer)
    monkeypatch.setattr(worker_module.Redis, "from_url", lambda *args, **kwargs: FakeRedis())

    config = worker_module.WorkerConfig(
        database_url=f"sqlite:///{db_path}",
        kafka_broker="unused:9092",
        kafka_group_id="test-worker",
        redis_url="redis://unused:6379/0",
        redis_queue_key="queue:broadcasts",
        line_push_timeout=1,
        idle_sleep_seconds=0,
    )
    worker = worker_module.Worker(config)
    return worker, engine


def test_process_message_persists_rows_and_increments_replies(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(worker_module.requests, "post", lambda *args, **kwargs: FakeResponse())
    worker, engine = make_worker(tmp_path, monkeypatch)

    try:
        result = worker.process_message(
            {
                "tenant_id": "tenant-1",
                "message": "Inbound hello",
                "direction": "inbound",
                "user_id": "u-1",
                "campaign_id": 1,
            }
        )

        with engine.begin() as conn:
            message_count = conn.execute(text("SELECT COUNT(*) FROM messages")).scalar_one()
            reply_count = conn.execute(text("SELECT reply_count FROM campaigns WHERE id = 1")).scalar_one()

        assert result["direction"] == "inbound"
        assert result["campaign_id"] == 1
        assert message_count == 1
        assert reply_count == 1
    finally:
        worker.close()


def test_process_broadcast_filters_recipients_and_updates_campaign(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(worker_module.requests, "post", lambda *args, **kwargs: FakeResponse())
    worker, engine = make_worker(tmp_path, monkeypatch)

    try:
        result = worker.process_broadcast(
            {
                "tenant_id": "tenant-1",
                "campaign_id": 1,
                "message": "Promo blast",
                "target_status": "hot",
            }
        )

        with engine.begin() as conn:
            campaign = conn.execute(
                text("SELECT sent_count, delivery_status FROM campaigns WHERE id = 1")
            ).mappings().one()
            rows = conn.execute(text("SELECT lead_user_id, direction, channel, content FROM messages")).mappings().all()

        assert result["sent_count"] == 1
        assert result["failed_count"] == 0
        assert campaign["sent_count"] == 1
        assert campaign["delivery_status"] == "sent"
        assert rows == [
            {
                "lead_user_id": "u-1",
                "direction": "outbound",
                "channel": "line",
                "content": "Promo blast",
            }
        ]
    finally:
        worker.close()


def test_process_broadcast_marks_failures_when_line_push_fails(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(worker_module.requests, "post", lambda *args, **kwargs: FakeFailedResponse())
    worker, engine = make_worker(tmp_path, monkeypatch)

    try:
        result = worker.process_broadcast(
            {
                "tenant_id": "tenant-1",
                "campaign_id": 1,
                "message": "Promo blast",
            }
        )

        with engine.begin() as conn:
            campaign = conn.execute(
                text("SELECT sent_count, delivery_status FROM campaigns WHERE id = 1")
            ).mappings().one()
            message_count = conn.execute(text("SELECT COUNT(*) FROM messages")).scalar_one()

        assert result["sent_count"] == 0
        assert result["failed_count"] == 2
        assert campaign["sent_count"] == 0
        assert campaign["delivery_status"] == "failed"
        assert message_count == 0
    finally:
        worker.close()


def test_publish_dead_letter_includes_context(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(worker_module.requests, "post", lambda *args, **kwargs: FakeResponse())
    worker, _engine = make_worker(tmp_path, monkeypatch)

    try:
        worker.publish_dead_letter("events.messages", {"tenant_id": "tenant-1"}, RuntimeError("boom"))
        assert worker.producer.sent == [
            (
                "events.dlq",
                {
                    "source_topic": "events.messages",
                    "payload": {"tenant_id": "tenant-1"},
                    "error": "boom",
                    "timestamp": worker.producer.sent[0][1]["timestamp"],
                },
            )
        ]
    finally:
        worker.close()
