Place TLS certs in this directory:

- `fullchain.pem`
- `privkey.pem`

Example self-signed cert for `app.zeaz.dev` + `api.zeaz.dev`:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout privkey.pem \
  -out fullchain.pem \
  -days 365 \
  -subj "/CN=app.zeaz.dev" \
  -addext "subjectAltName=DNS:app.zeaz.dev,DNS:api.zeaz.dev"
```

For a real public wildcard such as `*.zeaz.dev`, terminate TLS at an external edge or use a DNS challenge-based certificate flow; the built-in installer does not mint public wildcard certificates automatically.
