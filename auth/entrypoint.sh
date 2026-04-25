#!/bin/sh
set -e

# Substitute client secrets into the realm template.
# Only replaces ${GRC_SERVICES_SECRET} and ${GRC_MCP_SECRET} — leaves other
# ${...} patterns in the JSON untouched.
envsubst '${GRC_SERVICES_SECRET} ${GRC_MCP_SECRET}' \
  < /opt/keycloak/data/import/realm-template.json \
  > /opt/keycloak/data/import/realm.json

# Start Keycloak using the pre-built optimized server.
# --import-realm scans /opt/keycloak/data/import/ and imports any realm
# that does not already exist in the database (no-op on subsequent restarts).
exec /opt/keycloak/bin/kc.sh start \
  --optimized \
  --import-realm
