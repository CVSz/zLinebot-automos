# ZEAZ Ultra Landing – Full Ultra Pack

Production-ready starter ที่รวม Landing Page, Live Demo API, Stripe Funnel และ Viral Content templates ไว้ในแพ็กเดียว

## Project Structure

```text
zeaz-ultra/
├─ frontend/
│  ├─ public/
│  │  └─ index.html
│  └─ src/
│     ├─ App.jsx
│     ├─ main.jsx
│     ├─ components/
│     │  ├─ Hero.jsx
│     │  ├─ Features.jsx
│     │  ├─ CTAButton.jsx
│     │  └─ DemoChat.jsx
│     └─ styles/
│        └─ tailwind.css
├─ backend/
│  ├─ server.js
│  └─ webhook.js
├─ viral-content/
│  └─ tiktok-scripts.md
├─ package.json
├─ postcss.config.js
└─ tailwind.config.js
```

## Quick Start

```bash
cd zeaz-ultra
npm install
npm run dev
```

Frontend จะรันผ่าน Vite สำหรับหน้า Landing Page + Live Demo UI

## Backend (Stripe + Demo API)

1. ตั้งค่า environment variables:
   - `STRIPE_SECRET_KEY`
   - `STRIPE_PRICE_ID`
   - `STRIPE_WEBHOOK_SECRET`
2. รัน backend:

```bash
npm run backend
```

3. รัน webhook listener:

```bash
npm run webhook
```

## Funnel Flow

1. User เข้า Landing Page
2. ทดลองฟรีผ่าน Live Demo Chat (`/api/chat`)
3. กด Upgrade (`/api/create-checkout`)
4. Stripe webhook อัปเดตสถานะผู้ใช้เป็น paid
5. ทำ Upsell ผ่าน email/automation ภายหลัง

## Viral Content

ใช้สคริปต์พร้อมใช้งานได้ที่ `viral-content/tiktok-scripts.md`

## Deployment Notes

- Build frontend: `npm run build`
- Serve frontend ผ่าน NGINX หรือ static host
- Deploy backend บน Docker/VM เดียวกับ stack หลัก
- เปิด webhook endpoint ให้ Stripe เข้าถึงได้จากภายนอก
