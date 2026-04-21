# File Upload and UI Delivery
**Version:** 1.0  
**Status:** Draft

---

## 1. Purpose

This document defines how ROAD applications upload built UI assets into Oracle Database and serve them publicly through ORDS.

It covers the deployment and delivery contract for static browser assets, including:

- database-backed asset storage
- upload tooling behaviour
- public ORDS delivery paths
- content-type handling
- SPA fallback to `index.html`

This spec is the missing delivery boundary between the React build output and the runtime UI served by ORDS.

---

## 2. Core Principles

1. **UI assets are static deployment artifacts.** React source is built before upload. ORDS serves only the resulting static files.
2. **No runtime middleware.** There is no Node, Express, or custom file server in the runtime path.
3. **Oracle stores the deployed assets.** UI files are stored in Oracle as BLOB-backed assets with metadata.
4. **ORDS serves the public UI.** UI assets are delivered through public ORDS routes, separate from protected API routes.
5. **SPA routing is a delivery concern.** Client-side routes must resolve through ORDS fallback to `index.html`.
6. **Upload is a deployment operation, not a public API.** Asset upload is performed by trusted tooling and must not be exposed as a browser-facing endpoint in v1.

---

## 3. Scope

This spec covers:

- uploaded static build artifacts
- database asset storage model
- upload modes and path normalization
- public ORDS asset delivery
- SPA route fallback
- response headers for asset delivery

This spec does not cover:

- React source compilation details (see `react-project-structure-conventions-v1.md`)
- protected JSON API design (see `ords-api-design-standards-v1.md`)
- bearer token auth for protected APIs (see `authentication-spec-v1.md`)
- ORDS privilege protection for protected APIs (see `ords-security-configuration-v1.md`)

---

## 4. Build Artifact Contract

The upload and delivery layer consumes the static build artifact produced by the UI build.

### 4.1 Required Input Shape

The input artifact must satisfy:

- root directory containing `index.html`
- static assets beneath relative subpaths such as `assets/...`
- no required rewrite or transformation before upload

### 4.2 Expected Source Directory

For ROAD React applications, the default build output directory is:

```text
dist/
```

### 4.3 Deployment Identity

Each uploaded UI is identified by:

- `app_name`
- relative asset path within the build

`app_name` is a bootstrap-time user-supplied project identity. Its canonical persisted source is `APP_NAME` in the repo-root `road.config`.

Multiple applications may coexist in the same delivery system as long as their `app_name` values differ.

---

## 5. Public URL Model

UI assets are served publicly under:

```text
/ords/<ui_base_path>/ui/<app_name>/<relative_path>
```

Examples:

```text
/ords/road-ui/ui/road-app/index.html
/ords/road-ui/ui/road-app/assets/main-abc123.js
/ords/road-ui/ui/road-app/dashboard
```

### 5.1 Path Rules

- `<app-name>` is part of the public deployment identity
- relative paths must be preserved exactly as uploaded
- public UI delivery remains unversioned in v1
- protected APIs remain separate and versioned under `/api/v1/`

---

## 6. Data Model

### 6.1 Table: `UI_ASSETS`

The delivery layer stores uploaded assets in a table with at least these fields:

| Field | Purpose |
|---|---|
| `asset_id` | Primary key |
| `app_name` | Logical UI application identifier |
| `relative_path` | Relative path within the uploaded build |
| `file_name` | Final file name |
| `content_type` | MIME type |
| `content_length` | File size |
| `checksum` | Optional integrity / change-detection value |
| `updated_at` | Last update timestamp |
| `content` | File content as BLOB |

### 6.2 Uniqueness

The unique key must be:

```text
(app_name, relative_path)
```

### 6.3 LOB Storage

The `content` column should use `SECUREFILE` BLOB storage in v1.

---

## 7. Upload Contract

### 7.1 Entry Point

In ROAD, the standard upload entry point is the React deployment script:

```bash
bin/deploy-react.sh --env <env> --app <app_name>
```

This script is the framework wrapper around the upload contract defined here.

The `--app` value must match `APP_NAME` in `road.config`.

### 7.2 Upload Behaviour

The uploader must:

- accept a built root directory
- walk the directory recursively
- normalize paths to forward-slash relative paths
- detect MIME type
- read binary content safely
- upsert assets by `app_name` and `relative_path`

### 7.3 Upload Modes

The underlying upload logic must support:

- `upsert`
- `sync`

#### `upsert`

- inserts missing assets
- updates existing assets for the same `app_name` and `relative_path`
- leaves unrelated existing assets unchanged

#### `sync`

- performs `upsert`
- deletes stored assets for the same `app_name` that are not present in the current build artifact

### 7.4 Trusted Execution Only

Upload is restricted to deployment tooling, CI, or trusted operators. It is not exposed as a public browser-facing REST endpoint in v1.

---

## 8. ORDS Delivery Behaviour

### 8.1 Asset Lookup

The ORDS delivery module must:

1. extract `app_name` and requested relative path
2. normalize the path
3. reject traversal or malformed paths
4. look up the asset by `app_name` and `relative_path`
5. return the stored BLOB and `Content-Type` if found

### 8.2 Implementation Style

Asset responses must use ORDS media-style BLOB delivery.

### 8.3 Public Access

UI asset routes are public in v1. They must be separate from protected API routes.

---

## 9. SPA Fallback Rules

### 9.1 Fallback Behaviour

If the requested path is not found:

- if the request appears to be a client-side SPA route, return that app's `index.html`
- if the request clearly targets a missing static asset, return `404`

### 9.2 Suggested Rule

The default ROAD rule is:

- paths with a file extension are treated as asset requests
- paths without a file extension are treated as SPA routes

### 9.3 Examples

| Request | Behaviour |
|---|---|
| `/ui/road-app/assets/main.js` | Return stored asset or `404` |
| `/ui/road-app/dashboard` | Return `index.html` |
| `/ui/road-app/admin/users` | Return `index.html` |

---

## 10. Response Headers

For successful asset responses in v1:

- `Content-Type: <stored type>`
- `Cache-Control: no-store`

The `no-store` rule is intentional in v1 to minimise stale asset issues during iterative deployment.

Future versions may add:

- `ETag`
- `Last-Modified`
- selective cache behaviour for immutable hashed assets

---

## 11. Error Handling

| Condition | HTTP Status |
|---|---|
| Invalid path or traversal attempt | 400 |
| Missing asset with no SPA fallback | 404 |
| Unexpected database or ORDS failure | 500 |

UI asset delivery errors are separate from protected API auth failures and must not reuse bearer-token error semantics.

---

## 12. Security Model

### 12.1 Public UI, Protected API

ROAD separates:

- public UI asset delivery
- protected JSON API delivery

The UI route namespace must not be used to expose protected API handlers.

### 12.2 Path Safety

Path normalization must reject:

- traversal attempts
- malformed relative paths
- ambiguous path variants

### 12.3 Schema Separation

Where practical, UI asset storage should live in a dedicated UI schema, separate from protected API schemas.

### 12.4 CORS

Public UI routes do not require CORS headers in the default same-origin ROAD deployment model.

---

## 13. Relationship to Other Specs

### 13.1 Local Development Environment

`local-dev-environment-v1.md` defines the build-and-deploy workflow. This spec defines what `bin/deploy-react.sh` must upload and how ORDS serves it.

### 13.2 React Project Structure

`react-project-structure-conventions-v1.md` defines the UI application structure and build output expectations. This spec defines how that output is deployed and delivered.

### 13.3 ORDS API Design Standards

`ords-api-design-standards-v1.md` governs protected APIs. This spec governs public UI asset delivery. They are separate route families.

### 13.4 CI/CD Pipeline

`cicd-pipeline-v1.md` invokes React deployment as a stage. This spec defines the delivery semantics behind that deployment stage.

---

## 14. ROAD Implementation Mapping

In ROAD v1:

- React build output is produced in the app directory
- `bin/deploy-react.sh` is the standard deployment wrapper
- the uploader writes asset rows into Oracle
- ORDS serves the uploaded asset rows from the public UI path

This allows `road-kit` to remain a single repository while still using the same database-backed delivery architecture originally modeled in the separate `road1` delivery specs.

---

## 15. What This Spec Does Not Cover

- React source compilation internals
- protected API auth and privilege enforcement
- runtime config injection strategy beyond the build artifact contract
- advanced caching, release versioning, rollback orchestration, or CDN integration

---

## 16. Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-04-21 | Initial draft integrated from the separate ROAD asset-delivery design into the main framework suite |
