# =============================================================================
# GigaChad GRC - Keycloak Identity Provider
# Multi-stage build: pre-optimizes Keycloak for PostgreSQL + /auth base path.
# Client secrets are substituted into the realm template at container startup.
# =============================================================================

FROM quay.io/keycloak/keycloak:25.0 AS builder

ENV KC_DB=postgres
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_HEALTH_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

# -----------------------------------------------------------------------

FROM quay.io/keycloak/keycloak:25.0

USER root

# Install gettext (envsubst) and curl (health check)
RUN microdnf install -y gettext curl && \
    microdnf clean all && \
    mkdir -p /opt/keycloak/data/import

# Copy pre-built optimized server
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Realm template — ${GRC_SERVICES_SECRET} and ${GRC_MCP_SECRET} are substituted at startup
COPY auth/realm-export.json /opt/keycloak/data/import/realm-template.json

COPY auth/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER 1000

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
