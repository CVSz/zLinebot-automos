# ZEAZ Ultra Pack (Deploy-ready for `cme.zeaz.dev`)

Full stack starter with frontend, FastAPI backend, worker, Kafka, Redis, Postgres, NGINX TLS reverse proxy, backup, and health checks.

## Structure

```text
zeaz-ultra-pack/
├─ .env.example
├─ gen-secrets.sh
├─ frontend/
├─ backend/
└─ infra/
```

## Quick Start

1. Generate secrets and runtime environment.

```bash
cd zeaz-ultra-pack
./gen-secrets.sh cme.zeaz.dev admin@cme.zeaz.dev
```

2. Add TLS cert files in `infra/certs` (`fullchain.pem` and `privkey.pem`).

3. Start stack.

```bash
cd infra
docker compose --env-file ../.env up -d --build
```

4. Verify health.

```bash
./monitor/health.sh
```

## Endpoints

- `https://cme.zeaz.dev/api/health`
- `https://cme.zeaz.dev/admin/`
- `https://cme.zeaz.dev/user/`
- `https://cme.zeaz.dev/devops/`

## Backup

Run encrypted database backup:

```bash
cd infra
source ../.env
./backup/backup.sh /tmp/zeaz-backups
```
