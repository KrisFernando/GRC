# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

GigaChad GRC is a containerized, multi-service Governance, Risk, and Compliance (GRC) platform. It uses a monorepo managed by npm workspaces with seven backend NestJS services and one React frontend.

## Commands

All commands assume you are at the repo root unless noted.

### Infrastructure (Docker)
```bash
make up              # Start all containers
make down            # Stop all containers
make build           # Rebuild all service images
make logs s=controls # Tail logs for a specific service
make install         # Install all workspace dependencies
```

### Development
```bash
# Frontend (run inside frontend/)
npm run dev          # Vite dev server

# Backend service (run inside services/<name>/)
npm run start:dev    # NestJS watch mode

# Database
npm run prisma:generate   # Regenerate Prisma client after schema changes
npm run prisma:migrate    # Run pending migrations
```

### Testing
```bash
# Root — all workspaces
npm run test

# Frontend unit tests (Vitest)
cd frontend && npm run test

# Frontend E2E (Playwright)
cd frontend && npm run test:e2e
cd frontend && npm run test:e2e:ui   # interactive UI mode

# Backend service (Jest)
cd services/controls && npm run test
cd services/controls && npm run test:cov
```

### Linting & Formatting
```bash
npm run lint         # ESLint check across all workspaces (0 warnings allowed)
npm run lint:fix     # Auto-fix
npm run format       # Prettier format
```

### Production Validation
```bash
npm run validate:production   # Validate prod environment config
```

## Architecture

### Monorepo Layout
```
frontend/          React SPA (Vite, React Router v6, TanStack Query)
services/
  shared/          Shared Prisma schema, types, utilities (@gigachad-grc/shared)
  controls/        Primary backend service — all core GRC logic
  frameworks/      Compliance framework management
  policies/        Policies & procedures
  tprm/            Third-party risk management
  trust/           Trust center & vendor assessments
  audit/           External audit management
auth/              Keycloak realm configuration
gateway/           Traefik reverse proxy config
deploy/            Backup/restore scripts
```

### Backend Services (NestJS 11 + Prisma + PostgreSQL)

All backend services are NestJS apps sharing a single Prisma schema from `services/shared/`. The `controls` service is the primary service and contains most domain modules: AI/Risk Assistant, Auth (Keycloak), Controls, Evidence, Frameworks, Policies, Risk, TPRM, Trust, Audit, Integrations (Jira/ServiceNow), Workflows, Webhooks, SCIM, Custom Dashboards, Reports, Employee Compliance, and BCDR.

Guard stack per request: `DevAuthGuard` → `RolesGuard` → `PermissionsGuard` → `CustomThrottlerGuard`.

Multi-tenancy is workspace-scoped; workspace ID is injected as a header by the frontend Axios interceptor.

### Frontend (React 18 + Vite + TypeScript)

- **Routing:** React Router v6 with all pages lazy-loaded for code splitting.
- **State:** React Context handles auth, theme, branding, workspace, and module state. TanStack React Query manages all server state.
- **API client:** Axios with interceptors that auto-inject the auth token and org ID header, handle 401 redirects, and apply exponential-backoff retry only on transient errors (5xx, 408, 429, network errors).
- **Dev auth bypass:** Set `VITE_ENABLE_DEV_AUTH=true` to skip Keycloak in local development.
- **Path alias:** `@/` maps to `src/`.

### Auth (Keycloak)

Keycloak is the sole authentication provider. Realm is `gigachad-grc`. Client secrets must be provisioned for `grc-services` and `grc-mcp`. Default dev users (admin, compliance_manager, auditor) are seeded by the realm import in `auth/`.

### Infrastructure Services

| Service | Purpose |
|---------|---------|
| PostgreSQL | Primary database |
| Redis + BullMQ | Caching and job queues |
| MinIO ("rustfs") | S3-compatible object storage |
| Traefik | API gateway / reverse proxy |
| Grafana + Prometheus | Metrics and monitoring |
| Keycloak | SSO and identity |

### Shared Package

`services/shared/` is published as the `@gigachad-grc/shared` workspace package. It owns the single Prisma schema (`prisma/schema.prisma`) used by all services. After modifying it, run `npm run prisma:generate` from that package.

## Key Configuration Files

- `frontend/vite.config.ts` — dev server proxy, manual chunk splitting (vendor-xlsx, vendor-zod, vendor-recharts)
- `frontend/playwright.config.ts` — E2E base URL, browsers
- `services/shared/prisma/schema.prisma` — single source of truth for DB schema
- `gateway/traefik.yml` — routing rules between services
- `.env.example` — full list of required environment variables
- `Makefile` — authoritative reference for all Docker/make commands

## Environment Setup

Copy `.env.example` to `.env` and populate secrets. Critical variables:

- `ENCRYPTION_KEY` — 64-char hex (`openssl rand -hex 32`)
- `JWT_SECRET`, `SESSION_SECRET` — base64 (`openssl rand -base64 64`)
- `KEYCLOAK_ADMIN_CLIENT_SECRET` — must match realm import in `auth/`
- `VITE_ENABLE_DEV_AUTH=true` — enables dev auth bypass in frontend (never set in production)

Secrets can alternatively be managed via Infisical by setting `SECRETS_PROVIDER=infisical`.
