import os
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, HTTPException
from jose import jwt
from pydantic import BaseModel

app = FastAPI(title="ZEAZ Ultra API")

JWT_ALG = "HS256"
JWT_SECRET = os.getenv("JWT_SECRET_CURRENT", "dev-secret")


class AuthPayload(BaseModel):
    username: str
    password: str


class ChatPayload(BaseModel):
    message: str


@app.get("/health")
def health():
    return {"status": "ok", "service": "api"}


@app.post("/api/register")
def register(payload: AuthPayload):
    if len(payload.username.strip()) < 3:
        raise HTTPException(status_code=400, detail="username too short")
    return {"ok": True, "username": payload.username}


@app.post("/api/login")
def login(payload: AuthPayload):
    if not payload.username or not payload.password:
        raise HTTPException(status_code=400, detail="invalid credentials")
    exp = datetime.now(tz=timezone.utc) + timedelta(hours=12)
    token = jwt.encode({"sub": payload.username, "exp": exp}, JWT_SECRET, algorithm=JWT_ALG)
    return {"access_token": token, "token_type": "bearer"}


@app.post("/api/chat")
def chat(payload: ChatPayload):
    text = payload.message.strip()
    if not text:
        raise HTTPException(status_code=400, detail="message is required")
    return {"reply": f"Echo: {text}"}
