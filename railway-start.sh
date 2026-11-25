#!/bin/sh
set -eu

# Railway injects PORT for the public HTTP service.
# Nginx listens on that public port, while the Node API listens internally on 3000.
export NGINX_PORT="${PORT:-8080}"
export PORT="3000"
export BACKEND="127.0.0.1"
export RESOLVER="${RESOLVER:-127.0.0.11}"
export CF_CONNECTING_IP="${CF_CONNECTING_IP:-}"
export BASE_PATH="${BASE_PATH:-}"
export MEDIA_UPLOAD_MAX="${MEDIA_UPLOAD_MAX:-112m}"
export MCP_BACKEND="${MCP_BACKEND:-127.0.0.1}"
export MCP_PORT="${MCP_PORT:-3100}"
export DATA_DIR="${DATA_DIR:-/data}"
export TRUST_PROXY="${TRUST_PROXY:-1}"

mkdir -p "$DATA_DIR" /etc/nginx/http.d /run/nginx

# Render nginx site config from openGym's template
envsubst '${NGINX_PORT} ${BACKEND} ${PORT} ${RESOLVER} ${CF_CONNECTING_IP} ${BASE_PATH} ${MEDIA_UPLOAD_MAX} ${MCP_BACKEND} ${MCP_PORT} ${CONTENT_SECURITY_POLICY}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/http.d/default.conf

# Start Node API in background
cd /app/api
node server.js &
API_PID=$!

# Forward termination signals
trap 'kill -TERM "$API_PID" 2>/dev/null || true; exit 0' TERM INT

# Wait briefly for API health before starting nginx
i=0
while [ "$i" -lt 30 ]; do
  if wget -q --spider "http://127.0.0.1:3000/api/health" 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 0.5
done

# Run nginx in foreground; if it exits, stop API too
nginx -g 'daemon off;' &
NGINX_PID=$!

wait "$NGINX_PID"
kill -TERM "$API_PID" 2>/dev/null || true
