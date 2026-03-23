Place TLS certs in this directory:

- `fullchain.pem`
- `privkey.pem`

Example self-signed cert for wildcard + cme:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout privkey.pem \
  -out fullchain.pem \
  -days 365 \
  -subj "/CN=*.zlinebot-automos.local" \
  -addext "subjectAltName=DNS:*.zlinebot-automos.local,DNS:api.zlinebot-automos.local"
```
