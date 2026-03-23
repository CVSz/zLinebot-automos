import base64
import binascii
import hashlib
import hmac
import os
import re
import time
import uuid
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Annotated
from urllib.parse import urlparse

import requests
import stripe
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import jwt
from kafka import KafkaProducer
from pydantic import BaseModel, ConfigDict, Field
from redis import Redis
from sqlalchemy import DateTime, Integer, String, Text, UniqueConstraint, create_engine, func, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

JWT_ALG = "HS256"
JWT_SECRET = os.getenv("JWT_SECRET_CURRENT", "dev-secret")
DEFAULT_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./zlinebot.db")
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "kafka:9092")
REDIS_URL = os.getenv("REDIS_URL")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/api/generate")
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
DEFAULT_PRICE_ID = os.getenv("STRIPE_PRICE_ID", "")
DEFAULT_APP_URL = os.getenv("APP_BASE_URL", "http://localhost:5173")
LINE_API_BASE = "https://api.line.me/v2/bot/message"
THAI_PHONE_RE = re.compile(r"(0\d{8,9})")
NAME_RE = re.compile(r"(?:ชื่อ|name)\s*[:：]?\s*([^\n,]+)", re.IGNORECASE)
STATUS_ORDER = ["new", "cold", "warm", "hot", "closed"]
STATUS_SET = set(STATUS_ORDER)

security = HTTPBearer(auto_error=False)
stripe.api_key = STRIPE_SECRET_KEY or None


class Base(DeclarativeBase):
    pass


class Tenant(Base):
    __tablename__ = "tenants"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)
    line_channel_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    rate_limit_per_minute: Mapped[int] = mapped_column(Integer, default=20)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(120), unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(32), default="admin")
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    subscription_status: Mapped[str] = mapped_column(String(32), default="free")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Lead(Base):
    __tablename__ = "leads"
    __table_args__ = (UniqueConstraint("tenant_id", "user_id", name="uq_leads_tenant_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(120), index=True)
    name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    interest: Mapped[str] = mapped_column(Text, default="")
    score: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(32), default="new")
    price: Mapped[int] = mapped_column(Integer, default=0)
    source: Mapped[str] = mapped_column(String(32), default="line")
    last_contact_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Template(Base):
    __tablename__ = "templates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    name: Mapped[str] = mapped_column(String(120))
    message: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Campaign(Base):
    __tablename__ = "campaigns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    name: Mapped[str] = mapped_column(String(120))
    message: Mapped[str] = mapped_column(Text)
    target_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    sent_count: Mapped[int] = mapped_column(Integer, default=0)
    reply_count: Mapped[int] = mapped_column(Integer, default=0)
    delivery_status: Mapped[str] = mapped_column(String(32), default="queued")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    lead_user_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    campaign_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    direction: Mapped[str] = mapped_column(String(16))
    channel: Mapped[str] = mapped_column(String(16), default="line")
    content: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class AuthPayload(BaseModel):
    username: str
    password: str
    tenant_name: str | None = None


class ChatPayload(BaseModel):
    message: str


class LeadUpdatePayload(BaseModel):
    status: str | None = None
    price: int | None = Field(default=None, ge=0)


class TemplatePayload(BaseModel):
    name: str
    message: str


class BroadcastPayload(BaseModel):
    name: str = "campaign"
    message: str
    target_status: str | None = None


class CheckoutPayload(BaseModel):
    price_id: str | None = None
    success_url: str | None = None
    cancel_url: str | None = None


class WebhookTextMessage(BaseModel):
    text: str = ""


class WebhookSource(BaseModel):
    userId: str


class WebhookEvent(BaseModel):
    replyToken: str | None = None
    source: WebhookSource
    message: WebhookTextMessage


class WebhookPayload(BaseModel):
    events: list[WebhookEvent]


class LeadResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: str
    name: str | None
    phone: str | None
    interest: str
    score: int
    status: str
    price: int
    source: str
    last_contact_at: datetime
    created_at: datetime
    updated_at: datetime


class CampaignResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    message: str
    target_status: str | None
    sent_count: int
    reply_count: int
    delivery_status: str
    created_at: datetime


class TemplateResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    message: str
    created_at: datetime


class InMemoryRateLimiter:
    def __init__(self):
        self.buckets: dict[str, list[float]] = defaultdict(list)

    def allow(self, key: str, limit: int, window_seconds: int = 60) -> bool:
        now = time.time()
        recent = [stamp for stamp in self.buckets[key] if now - stamp < window_seconds]
        self.buckets[key] = recent
        if len(recent) >= limit:
            return False
        recent.append(now)
        return True


memory_rate_limiter = InMemoryRateLimiter()


def make_engine(database_url: str):
    parsed = urlparse(database_url)
    if parsed.scheme == "sqlite":
        return create_engine(database_url, future=True, connect_args={"check_same_thread": False})
    return create_engine(database_url, future=True, pool_pre_ping=True)


async def verify_line_signature(request: Request, tenant: Tenant | None) -> None:
    signature = request.headers.get("x-line-signature")
    secret = tenant.line_channel_token if tenant else None
    if not signature or not secret:
        return


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1)
    return "scrypt$16384$8$1${}${}".format(
        base64.b64encode(salt).decode("utf-8"),
        base64.b64encode(digest).decode("utf-8"),
    )



def verify_password(password: str, encoded_hash: str) -> bool:
    try:
        _, n_value, r_value, p_value, salt_b64, digest_b64 = encoded_hash.split("$", 5)
        salt = base64.b64decode(salt_b64.encode("utf-8"))
        expected = base64.b64decode(digest_b64.encode("utf-8"))
        actual = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(n_value),
            r=int(r_value),
            p=int(p_value),
        )
    except (AttributeError, ValueError, TypeError, binascii.Error):
        return False

    return hmac.compare_digest(actual, expected)



def slugify_tenant(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return cleaned or f"tenant-{uuid.uuid4().hex[:8]}"



def extract_phone(text: str) -> str | None:
    match = THAI_PHONE_RE.search(text)
    return match.group(1) if match else None



def extract_name(text: str) -> str | None:
    match = NAME_RE.search(text)
    if match:
        return match.group(1).strip()
    return None


def clean_text(value: str | None) -> str:
    return (value or "").strip()


def normalize_status(status: str | None, *, allow_blank: bool = False) -> str | None:
    if status is None:
        return None

    normalized = status.strip().lower()
    if not normalized and allow_blank:
        return None
    if normalized not in STATUS_SET:
        raise HTTPException(status_code=400, detail=f"status must be one of: {', '.join(STATUS_ORDER)}")
    return normalized


def calculate_score(text: str, phone: str | None) -> int:
    lowered = text.lower()
    score = 0
    if "ราคา" in lowered or "price" in lowered:
        score += 1
    if any(keyword in lowered for keyword in ["ซื้อ", "สั่ง", "buy", "order", "เอา"]):
        score += 3
    if phone:
        score += 5
    if any(keyword in lowered for keyword in ["โอนแล้ว", "paid", "payment", "confirm"]):
        score += 4
    return score



def determine_status(text: str, score: int) -> str:
    lowered = text.lower()
    if any(keyword in lowered for keyword in ["โอนแล้ว", "paid", "payment sent", "สั่งแล้ว"]):
        return "closed"
    if score >= 8:
        return "hot"
    if score >= 4:
        return "warm"
    if score >= 1:
        return "cold"
    return "new"



def generate_sales_reply(message: str) -> str:
    stripped = message.strip()
    if not stripped:
        return "Please send a message so I can help you close the sale."

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": os.getenv("OLLAMA_MODEL", "llama3"),
                "prompt": (
                    "You are a concise sales assistant for LINE chats. "
                    "Reply warmly, ask for the next conversion step, and keep it under 80 words.\n"
                    f"Customer message: {stripped}"
                ),
                "stream": False,
            },
            timeout=6,
        )
        response.raise_for_status()
        data = response.json()
        reply = data.get("response", "").strip()
        if reply:
            return reply
    except requests.RequestException:
        pass

    lowered = stripped.lower()
    if "ราคา" in lowered or "price" in lowered:
        return "สินค้ารุ่นนี้พร้อมโปรพิเศษครับ สนใจรับราคาสรุปและวิธีสั่งซื้อไหมครับ?"
    if any(keyword in lowered for keyword in ["ซื้อ", "buy", "order", "สั่ง"]):
        return "ได้เลยครับ ส่งชื่อและเบอร์โทรไว้ได้เลย เดี๋ยวผมสรุปออเดอร์ให้ทันทีครับ"
    if extract_phone(stripped):
        return "รับข้อมูลแล้วครับ ทีมงานจะติดต่อกลับเพื่อปิดการขายและยืนยันคำสั่งซื้อให้ครับ"
    return "ยินดีช่วยปิดการขายครับ บอกชื่อสินค้า งบ หรือเบอร์โทรไว้ได้เลย เดี๋ยวผมช่วยต่อบทสนทนาให้ครับ"



def build_json_headers(token: str | None = None) -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers



def send_line_reply(channel_token: str | None, reply_token: str | None, text: str) -> None:
    if not channel_token or not reply_token:
        return
    requests.post(
        f"{LINE_API_BASE}/reply",
        headers=build_json_headers(channel_token),
        json={"replyToken": reply_token, "messages": [{"type": "text", "text": text[:1000]}]},
        timeout=10,
    )



def send_line_push(channel_token: str | None, user_id: str, text: str) -> None:
    if not channel_token:
        return
    requests.post(
        f"{LINE_API_BASE}/push",
        headers=build_json_headers(channel_token),
        json={"to": user_id, "messages": [{"type": "text", "text": text[:1000]}]},
        timeout=10,
    )



def send_sheet_sync_stub(payload: list[str]) -> None:
    _ = payload



def serialize_lead(lead: Lead) -> dict:
    return LeadResponse.model_validate(lead).model_dump(mode="json")



def serialize_campaign(campaign: Campaign) -> dict:
    data = CampaignResponse.model_validate(campaign).model_dump(mode="json")
    data["reply_rate"] = round((campaign.reply_count / campaign.sent_count) * 100, 2) if campaign.sent_count else 0
    return data



def serialize_template(template: Template) -> dict:
    return TemplateResponse.model_validate(template).model_dump(mode="json")



def queue_broadcast_event(payload: dict) -> bool:
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKER,
            value_serializer=lambda value: __import__("json").dumps(value).encode("utf-8"),
        )
        producer.send("events.broadcasts", payload).get(timeout=5)
        producer.flush(timeout=5)
        producer.close(timeout=5)
        return True
    except Exception:
        return False



def check_rate_limit(tenant: Tenant, user_id: str) -> bool:
    key = f"rate:{tenant.id}:{user_id}"
    if REDIS_URL:
        try:
            redis = Redis.from_url(REDIS_URL, decode_responses=True)
            pipe = redis.pipeline()
            pipe.incr(key)
            pipe.expire(key, 60)
            current, _ = pipe.execute()
            return int(current) <= tenant.rate_limit_per_minute
        except Exception:
            pass
    return memory_rate_limiter.allow(key, tenant.rate_limit_per_minute)



def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    request: Request,
):
    if credentials is None:
        raise HTTPException(status_code=401, detail="missing credentials")

    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALG])
    except Exception as exc:
        raise HTTPException(status_code=401, detail="invalid credentials") from exc

    session = request.state.session_factory()
    try:
        user = session.scalar(select(User).where(User.username == payload.get("sub")))
        if user is None:
            raise HTTPException(status_code=401, detail="invalid credentials")
        return user
    finally:
        session.close()



def require_role(*roles: str):
    def dependency(user: Annotated[User, Depends(get_current_user)]):
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="forbidden")
        return user

    return dependency



def get_tenant_scope(
    request: Request,
    user: Annotated[User, Depends(get_current_user)],
    x_tenant_id: Annotated[str | None, Header()] = None,
) -> str:
    tenant_id = x_tenant_id or user.tenant_id
    if user.role != "superadmin" and tenant_id != user.tenant_id:
        raise HTTPException(status_code=403, detail="tenant scope mismatch")
    session = request.state.session_factory()
    try:
        tenant = session.get(Tenant, tenant_id)
        if tenant is None:
            raise HTTPException(status_code=404, detail="tenant not found")
        return tenant_id
    finally:
        session.close()



def _health_payload():
    return {"status": "ok", "service": "api"}



def create_app(database_url: str | None = None) -> FastAPI:
    engine = make_engine(database_url or DEFAULT_DATABASE_URL)
    session_factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        Base.metadata.create_all(bind=engine)
        yield
        engine.dispose()

    app = FastAPI(title="zLineBot-automos CRM API", lifespan=lifespan)
    app.state.engine = engine
    app.state.session_factory = session_factory

    if urlparse(database_url or DEFAULT_DATABASE_URL).scheme == "sqlite":
        Base.metadata.create_all(bind=engine)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=os.getenv("CORS_ALLOW_ORIGINS", "*").split(","),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    def db_session() -> Session:
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    @app.middleware("http")
    async def attach_session_factory(request: Request, call_next):
        request.state.session_factory = session_factory
        return await call_next(request)

    @app.get("/health")
    def health():
        return _health_payload()

    @app.get("/api/health")
    def health_api():
        return _health_payload()

    @app.post("/api/register")
    def register(payload: AuthPayload, session: Annotated[Session, Depends(db_session)]):
        username = clean_text(payload.username)
        password = payload.password
        tenant_name = clean_text(payload.tenant_name) or f"{username} Workspace"

        if len(username) < 3:
            raise HTTPException(status_code=400, detail="username too short")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", username):
            raise HTTPException(
                status_code=400,
                detail="username may only contain letters, numbers, dots, dashes, and underscores",
            )
        if len(password) < 8:
            raise HTTPException(status_code=400, detail="password must be at least 8 characters")
        if len(tenant_name) < 3:
            raise HTTPException(status_code=400, detail="workspace name too short")

        existing_user = session.scalar(select(User).where(User.username == username))
        if existing_user is not None:
            raise HTTPException(status_code=409, detail="username already exists")

        base_tenant_id = slugify_tenant(tenant_name)
        tenant_id = base_tenant_id
        suffix = 1
        while session.get(Tenant, tenant_id) is not None:
            tenant_id = f"{base_tenant_id}-{suffix}"
            suffix += 1

        tenant = Tenant(id=tenant_id, name=tenant_name)
        user = User(
            username=username,
            password_hash=hash_password(password),
            role="admin",
            tenant_id=tenant_id,
        )
        session.add_all([tenant, user])
        session.commit()
        session.refresh(user)

        return {
            "ok": True,
            "user": {
                "id": user.id,
                "username": user.username,
                "role": user.role,
                "tenant_id": user.tenant_id,
                "created_at": user.created_at.isoformat(),
            },
            "tenant": {"id": tenant.id, "name": tenant.name},
        }

    @app.post("/api/login")
    def login(payload: AuthPayload, session: Annotated[Session, Depends(db_session)]):
        username = clean_text(payload.username)
        password = payload.password

        if not username or not password:
            raise HTTPException(status_code=400, detail="invalid credentials")

        user = session.scalar(select(User).where(User.username == username))
        if user is None or not verify_password(password, user.password_hash):
            raise HTTPException(status_code=401, detail="invalid credentials")

        exp = datetime.now(tz=timezone.utc) + timedelta(hours=12)
        token = jwt.encode(
            {
                "sub": user.username,
                "role": user.role,
                "tenant_id": user.tenant_id,
                "exp": exp,
            },
            JWT_SECRET,
            algorithm=JWT_ALG,
        )
        return {
            "access_token": token,
            "token_type": "bearer",
            "user": {
                "id": user.id,
                "username": user.username,
                "role": user.role,
                "tenant_id": user.tenant_id,
                "subscription_status": user.subscription_status,
            },
        }

    @app.get("/api/me")
    def me(user: Annotated[User, Depends(get_current_user)]):
        return {
            "id": user.id,
            "username": user.username,
            "role": user.role,
            "tenant_id": user.tenant_id,
            "subscription_status": user.subscription_status,
        }

    @app.post("/api/chat")
    def chat(payload: ChatPayload):
        text = clean_text(payload.message)
        if not text:
            raise HTTPException(status_code=400, detail="message is required")
        return {"reply": generate_sales_reply(text)}

    @app.post("/webhook/{tenant_id}")
    async def webhook(tenant_id: str, payload: WebhookPayload, request: Request, session: Annotated[Session, Depends(db_session)]):
        tenant = session.get(Tenant, tenant_id)
        if tenant is None:
            raise HTTPException(status_code=404, detail="tenant not found")

        await verify_line_signature(request, tenant)

        if not payload.events:
            return {"ok": True, "processed": 0}

        processed = 0
        for event in payload.events:
            incoming_text = event.message.text.strip()
            if not check_rate_limit(tenant, event.source.userId):
                raise HTTPException(status_code=429, detail="rate limit exceeded")

            lead = session.scalar(
                select(Lead).where(Lead.tenant_id == tenant_id, Lead.user_id == event.source.userId)
            )
            phone = extract_phone(incoming_text)
            name = extract_name(incoming_text)
            score = calculate_score(incoming_text, phone or (lead.phone if lead else None) if lead else None)
            status = determine_status(incoming_text, score)
            now = datetime.now(timezone.utc)

            if lead is None:
                lead = Lead(
                    tenant_id=tenant_id,
                    user_id=event.source.userId,
                    name=name,
                    phone=phone,
                    interest=incoming_text,
                    score=score,
                    status=status,
                    price=299 if status == "closed" else 0,
                    last_contact_at=now,
                    created_at=now,
                    updated_at=now,
                )
                session.add(lead)
            else:
                lead.name = name or lead.name
                lead.phone = phone or lead.phone
                lead.interest = incoming_text
                lead.score = score
                lead.status = status
                lead.price = lead.price or (299 if status == "closed" else 0)
                lead.last_contact_at = now
                lead.updated_at = now

            session.add(
                Message(
                    tenant_id=tenant_id,
                    lead_user_id=event.source.userId,
                    direction="inbound",
                    content=incoming_text,
                )
            )

            campaign = session.scalar(
                select(Campaign)
                .where(Campaign.tenant_id == tenant_id)
                .order_by(Campaign.id.desc())
                .limit(1)
            )
            if campaign is not None:
                campaign.reply_count += 1

            reply = generate_sales_reply(incoming_text)
            send_line_reply(tenant.line_channel_token, event.replyToken, reply)
            session.add(
                Message(
                    tenant_id=tenant_id,
                    lead_user_id=event.source.userId,
                    direction="outbound",
                    content=reply,
                )
            )
            send_sheet_sync_stub([tenant_id, event.source.userId, name or "", phone or "", incoming_text, status])
            processed += 1

        session.commit()
        return {"ok": True, "processed": processed}

    @app.get("/api/leads")
    def get_leads(
        status: str | None = None,
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
    ):
        query = select(Lead).where(Lead.tenant_id == tenant_id)
        normalized_status = normalize_status(status, allow_blank=True)
        if normalized_status:
            query = query.where(Lead.status == normalized_status)
        query = query.order_by(Lead.updated_at.desc(), Lead.created_at.desc())
        leads = session.scalars(query).all()
        return [serialize_lead(lead) for lead in leads]

    @app.patch("/api/leads/{lead_id}")
    def update_lead(
        lead_id: int,
        payload: LeadUpdatePayload,
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
    ):
        lead = session.scalar(select(Lead).where(Lead.id == lead_id, Lead.tenant_id == tenant_id))
        if lead is None:
            raise HTTPException(status_code=404, detail="lead not found")

        if payload.status is not None:
            lead.status = normalize_status(payload.status)
        if payload.price is not None:
            lead.price = payload.price
        now = datetime.now(timezone.utc)
        lead.updated_at = now
        lead.last_contact_at = now
        session.commit()
        session.refresh(lead)
        return {"ok": True, "lead": serialize_lead(lead)}

    @app.get("/api/stats")
    def get_stats(
        user: Annotated[User, Depends(require_role("admin", "staff", "superadmin"))],
        session: Annotated[Session, Depends(db_session)],
    ):
        tenant_id = user.tenant_id
        rows = session.execute(
            select(Lead.status, func.count(Lead.id)).where(Lead.tenant_id == tenant_id).group_by(Lead.status)
        ).all()
        revenue = session.scalar(
            select(func.coalesce(func.sum(Lead.price), 0)).where(Lead.tenant_id == tenant_id, Lead.status == "closed")
        )
        hot = session.scalar(
            select(func.count(Lead.id)).where(Lead.tenant_id == tenant_id, Lead.status == "hot")
        ) or 0
        total = session.scalar(select(func.count(Lead.id)).where(Lead.tenant_id == tenant_id)) or 0
        return {
            "status": {status: count for status, count in rows},
            "revenue": revenue or 0,
            "total_leads": total,
            "hot_leads": hot,
            "conversion_rate": round(((rows_dict := dict(rows)).get("closed", 0) / total) * 100, 2) if total else 0,
        }

    @app.get("/api/revenue/daily")
    def get_revenue_daily(
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
    ):
        engine_name = session.bind.dialect.name
        date_bucket = func.date(Lead.created_at)
        if engine_name == "sqlite":
            date_bucket = func.date(Lead.created_at)
        rows = session.execute(
            select(date_bucket, func.coalesce(func.sum(Lead.price), 0))
            .where(Lead.tenant_id == tenant_id, Lead.status == "closed")
            .group_by(date_bucket)
            .order_by(date_bucket)
        ).all()
        return [{"date": str(day), "revenue": revenue} for day, revenue in rows]

    @app.post("/api/templates")
    def create_template(
        payload: TemplatePayload,
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
        _: Annotated[User, Depends(require_role("admin", "superadmin"))] = None,
    ):
        name = clean_text(payload.name)
        message = clean_text(payload.message)
        if not name:
            raise HTTPException(status_code=400, detail="template name is required")
        if not message:
            raise HTTPException(status_code=400, detail="template message is required")

        template = Template(tenant_id=tenant_id, name=name, message=message)
        session.add(template)
        session.commit()
        session.refresh(template)
        return {"ok": True, "template": serialize_template(template)}

    @app.get("/api/templates")
    def get_templates(
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
    ):
        templates = session.scalars(
            select(Template).where(Template.tenant_id == tenant_id).order_by(Template.created_at.desc())
        ).all()
        return [serialize_template(template) for template in templates]

    @app.post("/api/broadcast")
    def create_broadcast(
        payload: BroadcastPayload,
        user: Annotated[User, Depends(require_role("admin", "superadmin"))],
        session: Annotated[Session, Depends(db_session)],
    ):
        name = clean_text(payload.name) or "campaign"
        message = clean_text(payload.message)
        target_status = normalize_status(payload.target_status, allow_blank=True)
        if not message:
            raise HTTPException(status_code=400, detail="broadcast message is required")

        campaign = Campaign(
            tenant_id=user.tenant_id,
            name=name,
            message=message,
            target_status=target_status,
            delivery_status="queued",
        )
        session.add(campaign)
        session.commit()
        session.refresh(campaign)

        event = {
            "campaign_id": campaign.id,
            "tenant_id": user.tenant_id,
            "message": campaign.message,
            "target_status": campaign.target_status,
        }
        queued = queue_broadcast_event(event)
        if not queued:
            tenant = session.get(Tenant, user.tenant_id)
            query = select(Lead).where(Lead.tenant_id == user.tenant_id)
            if campaign.target_status:
                query = query.where(Lead.status == campaign.target_status)
            recipients = session.scalars(query).all()
            for lead in recipients:
                send_line_push(tenant.line_channel_token if tenant else None, lead.user_id, campaign.message)
                session.add(
                    Message(
                        tenant_id=user.tenant_id,
                        lead_user_id=lead.user_id,
                        campaign_id=campaign.id,
                        direction="outbound",
                        content=campaign.message,
                    )
                )
            campaign.sent_count = len(recipients)
            campaign.delivery_status = "sent"
            session.commit()
        return {"ok": True, "queued": queued, "campaign": serialize_campaign(campaign)}

    @app.get("/api/campaigns")
    def get_campaigns(
        tenant_id: Annotated[str, Depends(get_tenant_scope)] = "",
        session: Annotated[Session, Depends(db_session)] = None,
    ):
        campaigns = session.scalars(
            select(Campaign).where(Campaign.tenant_id == tenant_id).order_by(Campaign.created_at.desc())
        ).all()
        return [serialize_campaign(campaign) for campaign in campaigns]

    @app.post("/api/billing/checkout")
    def create_checkout_session(
        payload: CheckoutPayload,
        user: Annotated[User, Depends(require_role("admin", "superadmin"))],
    ):
        price_id = payload.price_id or DEFAULT_PRICE_ID
        if not stripe.api_key or not price_id:
            raise HTTPException(status_code=503, detail="stripe is not configured")
        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            mode="subscription",
            line_items=[{"price": price_id, "quantity": 1}],
            success_url=payload.success_url or f"{DEFAULT_APP_URL}/dashboard?billing=success",
            cancel_url=payload.cancel_url or f"{DEFAULT_APP_URL}/dashboard?billing=cancel",
            metadata={"username": user.username, "tenant_id": user.tenant_id},
        )
        return {"url": session.url}

    @app.post("/stripe/webhook")
    async def stripe_webhook(request: Request, session: Annotated[Session, Depends(db_session)]):
        if not stripe.api_key or not STRIPE_WEBHOOK_SECRET:
            raise HTTPException(status_code=503, detail="stripe is not configured")
        payload = await request.body()
        signature = request.headers.get("stripe-signature")
        try:
            event = stripe.Webhook.construct_event(payload=payload, sig_header=signature, secret=STRIPE_WEBHOOK_SECRET)
        except Exception as exc:
            raise HTTPException(status_code=400, detail="invalid stripe webhook") from exc

        if event["type"] == "checkout.session.completed":
            data = event["data"]["object"]
            username = data.get("metadata", {}).get("username")
            if username:
                user = session.scalar(select(User).where(User.username == username))
                if user is not None:
                    user.subscription_status = "pro"
                    session.commit()
        return {"ok": True}

    return app


app = create_app()
