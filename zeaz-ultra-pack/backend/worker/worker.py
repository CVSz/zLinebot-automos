import json
import os
import time

from kafka import KafkaConsumer, KafkaProducer
from sqlalchemy import create_engine, text

DB = create_engine(os.getenv("DATABASE_URL", "postgresql://zeaz:zeaz@db:5432/zeaz"), pool_pre_ping=True)

producer = KafkaProducer(
    bootstrap_servers=os.getenv("KAFKA_BROKER", "kafka:9092"),
    value_serializer=lambda value: json.dumps(value).encode(),
)

consumer = KafkaConsumer(
    "events.messages",
    bootstrap_servers=os.getenv("KAFKA_BROKER", "kafka:9092"),
    value_deserializer=lambda message: json.loads(message.decode()),
)

for msg in consumer:
    try:
        payload = msg.value
        tenant_id = str(payload.get("tenant_id", "")).strip()
        if not tenant_id:
            raise ValueError("missing tenant_id")

        with DB.begin() as conn:
            conn.execute(
                text("INSERT INTO messages (tenant_id, content) VALUES (:tenant_id, :content)"),
                {"tenant_id": tenant_id, "content": payload.get("msg", "")},
            )
    except Exception:
        try:
            producer.send("events.dlq", msg.value).get(timeout=5)
        except Exception:
            pass
        time.sleep(1)
