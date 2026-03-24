#!/bin/sh
set -eu

APP_HOST="${APP_HOST:-app.localhost}"
API_HOST="${API_HOST:-api.localhost}"
WILDCARD_HOST="${WILDCARD_HOST:-}"
SERVER_NAMES="${APP_HOST} ${API_HOST} _"

if [ -n "$WILDCARD_HOST" ]; then
  SERVER_NAMES="$WILDCARD_HOST $SERVER_NAMES"
fi

export NGINX_SERVER_NAMES="$SERVER_NAMES"
envsubst '${NGINX_SERVER_NAMES}' < /etc/nginx/nginx.conf.tmpl > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
