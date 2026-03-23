FROM node:20-alpine AS frontend_builder
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

FROM nginx:alpine
RUN apk add --no-cache openssl
COPY infra/nginx.conf /etc/nginx/nginx.conf
COPY infra/panels/admin /usr/share/nginx/html/admin
COPY infra/panels/user /usr/share/nginx/html/user
COPY infra/panels/devops /usr/share/nginx/html/devops
COPY --from=frontend_builder /app/frontend/dist/ /usr/share/nginx/html/
RUN mkdir -p /etc/nginx/certs
COPY infra/certs/ /tmp/certs/
RUN if [ -f /tmp/certs/fullchain.pem ] && [ -f /tmp/certs/privkey.pem ]; then \
      cp /tmp/certs/fullchain.pem /etc/nginx/certs/fullchain.pem && \
      cp /tmp/certs/privkey.pem /etc/nginx/certs/privkey.pem ; \
    else \
      openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj "/CN=localhost/O=zLineBot-automos/C=US" \
      -keyout /etc/nginx/certs/privkey.pem \
      -out /etc/nginx/certs/fullchain.pem ; \
    fi
