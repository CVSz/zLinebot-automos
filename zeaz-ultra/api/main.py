import os
import sys
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from billing.stripe import create_checkout  # noqa: E402

app = FastAPI(title="ZEAZ Ultra API")


class RegisterResponse(BaseModel):
    token: str
    message: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1000)


class ChatResponse(BaseModel):
    reply: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/register", response_model=RegisterResponse)
def register():
    token = f"trial_{uuid.uuid4().hex}"
    return {
        "token": token,
        "message": "สมัครสำเร็จ! คุณเริ่มใช้งาน Free Trial ได้ทันที",
    }


@app.post("/api/chat", response_model=ChatResponse)
def chat(payload: ChatRequest, authorization: Optional[str] = Header(default=None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    prompt = payload.message.strip()
    return {
        "reply": (
            "[AI Demo] รับข้อความแล้ว: "
            f"'{prompt}'. ระบบพร้อมอัปเกรดเป็นแพลน Pro เมื่อคุณเชื่อมต่อโมเดลจริง"
        )
    }


@app.get("/api/checkout")
def checkout(price_id: Optional[str] = None):
    selected_price_id = price_id or os.getenv("STRIPE_PRICE_ID")
    if not selected_price_id:
        raise HTTPException(status_code=400, detail="Missing Stripe price_id")

    public_base_url = os.getenv("PUBLIC_BASE_URL", "http://localhost:5173")
    success_url = f"{public_base_url}/?payment=success"
    cancel_url = f"{public_base_url}/?payment=cancel"

    try:
        session = create_checkout(
            price_id=selected_price_id,
            success_url=success_url,
            cancel_url=cancel_url,
        )
        return RedirectResponse(url=session.url, status_code=303)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"Stripe checkout failed: {exc}") from exc


@app.get("/api/create-checkout")
def legacy_checkout_redirect():
    return RedirectResponse(url="/api/checkout", status_code=307)
