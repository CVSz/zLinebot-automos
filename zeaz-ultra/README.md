# ZEAZ ULTRA BUILD 4 – Complete Production Package

## Full project structure
- Kubernetes manifests: `k8s/`
- Runtime services: `api/`, `worker/`, `billing/`, `ai-agent/`, `security/`
- Frontend: `frontend/`
- Monitoring: `monitoring/`
- Containerization: `docker/`
- Deployment scripts: `scripts/`

## 1-flow deploy
```bash
git clone <your-project>
cd zeaz-ultra
bash scripts/deploy.sh
```

Then open `https://zeaz.yourdomain.com`.

## Landing + Funnel endpoints
- `POST /api/register` → create free-trial token
- `POST /api/chat` → AI demo proxy endpoint (requires `Authorization` header)
- `GET /api/checkout?price_id=...` → Stripe Checkout redirect
- `GET /api/create-checkout` → legacy redirect to `/api/checkout`
