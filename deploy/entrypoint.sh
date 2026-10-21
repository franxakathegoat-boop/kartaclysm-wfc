#!/bin/sh
set -e
envsubst '${POSTGRES_PASSWORD} ${API_SECRET} ${ALLOW_DOLPHIN_KEYS}' < /app/config.xml.tmpl > /app/config.xml
exec /app/wwfc
