# Cloudflared tunnel for `*.zlinebot-automos.local` and `api.zlinebot-automos.local`

1. Create a named tunnel in Cloudflare Zero Trust.
2. Download the tunnel credential JSON file and place it at:

```text
infra/cloudflared/credentials.json
```

3. Create DNS routes in Cloudflare for:
   - `*.zlinebot-automos.local`
   - `api.zlinebot-automos.local`
4. Set `CLOUDFLARED_TUNNEL_ID` in `.env` (the tunnel UUID).
5. Start with the Cloudflare profile:

```bash
cd infra
docker compose --env-file ../.env --profile cloudflare up -d cloudflared
```

The service renders `infra/cloudflared/config.tmpl.yml` with your tunnel ID and routes full stack traffic via:

- `https://*.zlinebot-automos.local` -> `https://nginx:443`
- `https://api.zlinebot-automos.local` -> `https://nginx:443`

(`noTLSVerify: true` is enabled because nginx uses self-signed TLS by default.)
