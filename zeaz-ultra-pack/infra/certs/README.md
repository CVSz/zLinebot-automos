Place TLS files here for local testing:
- fullchain.pem
- privkey.pem

You can generate a self-signed cert for local use with:
openssl req -x509 -nodes -newkey rsa:2048 -keyout privkey.pem -out fullchain.pem -days 365 -subj "/CN=cme.zeaz.dev"
