# Cloudflared tunnel for `app.<domain>` and `api.<domain>`

1. Create a named tunnel in Cloudflare Zero Trust.
2. Download the tunnel credential JSON file and place it at:

```text
infra/cloudflared/credentials.json
```

3. Create DNS routes in Cloudflare for:
   - `app.<domain>`
   - `api.<domain>`
4. Set `CLOUDFLARED_TUNNEL_ID` in `.env` (the tunnel UUID).
5. Set `APP_HOST` and `API_HOST` in `.env` if you want to override the defaults (`app.${DOMAIN}` and `api.${DOMAIN}`).
6. Start with the Cloudflare profile:

```bash
cd infra
docker compose --env-file ../.env --profile cloudflare up -d cloudflared
```

The service renders `infra/cloudflared/config.tmpl.yml` with your tunnel ID and hostnames and routes full stack traffic via:

- `https://app.<domain>` -> `https://nginx:443`
- `https://api.<domain>` -> `https://nginx:443`

(`noTLSVerify: true` is enabled because nginx uses self-signed TLS by default.)

## Documentation Refresh — 2026-03-26 (UTC)

- Revalidated Cloudflared setup sequence and expected env variables for tunnel operation.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

