# Local Development Environment
**Version:** 1.0  
**Status:** Approved

---

## 1. Purpose

This document defines the standard development environment for building and deploying applications in this framework. It covers Oracle ADB connectivity, SQLcl configuration, React build and deployment, and the conventions an LLM agent must follow to operate correctly in this environment.

---

## 2. Core Principles

1. **No local runtime servers in production.** Production deployments must not depend on any local ORDS instance, local React server, or proxy in the application runtime path. Development and test may use local runtime tooling when needed.
2. **Standard ROAD deployments are same-origin.** When deployed through the standard ROAD model, React static files are served directly from ADB ORDS and the app and API share the same host. This is mandatory for production and the default for development and test.
3. **Wallet at a fixed path.** The ADB wallet lives at a standardised absolute path outside the project directory. The project never contains credentials.
4. **Agent-operated.** The development workflow is designed for an LLM agent, not a human team. Setup steps must be explicit, deterministic, and scriptable.

---

## 3. Architecture Overview

```
Developer machine / Agent environment
│
├── Project directory (source code, specs, SQL artifacts)
│
├── Wallet directory (absolute path, outside project)
│   └── /opt/oracle/wallet/<app_name>-<env>/
│       ├── cwallet.sso
│       ├── ewallet.p12
│       ├── tnsnames.ora
│       └── sqlnet.ora
│
└── SQLcl (installed, available via $SQLCL_BIN)

         │  SQL*Net / TCPS
         ▼
Oracle Autonomous Database (OCI)
├── ORDS (built-in, serves both protected APIs and public UI delivery routes)
├── Application schema
└── UI asset storage (`UI_ASSETS` and related delivery objects)
```

---

## 4. Prerequisites

The following must be present before any framework tooling is used:

| Prerequisite | Requirement |
|---|---|
| SQLcl | Installed, available on PATH or via `$SQLCL_BIN` |
| ADB wallet | Downloaded from OCI console, extracted to wallet path |
| SQLcl saved connections | Provisioned for each target environment |
| Node.js + npm | Installed for React builds |
| Bash | Available (Mac/Linux only — Windows not supported in v1) |

---

## 5. Project Identity Configuration

### 5.1 Bootstrap Prompt

`app_name` is a mandatory user-supplied project identity. It must be captured when a new ROAD application is created or scaffolded.

The framework may prompt the user for this value during bootstrap, but it must not prompt again during normal build or deploy operations.

### 5.2 Canonical Storage

The canonical persisted source of project identity is the repo-root file:

```text
road.config
```

At minimum, this file must contain:

```bash
APP_NAME=<app_name>
```

Where:

- `APP_NAME` is the canonical deployment identity for the application
- the value is user-chosen and stable for the life of the project unless an intentional rename is performed

### 5.3 Usage

All framework tooling that needs the application identity must read it from `road.config` or receive the same value derived from `road.config`.

This includes at minimum:

- wallet naming conventions that embed `<app_name>`
- `bin/deploy-react.sh`
- React build configuration that maps `APP_NAME` to `VITE_APP_NAME`
- ORDS UI delivery paths under `/ords/<ui_base_path>/ui/<app_name>/`

---

## 6. Wallet Configuration

### 6.1 Wallet Location

Each environment-specific ADB wallet must be placed at:

```
/opt/oracle/wallet/<app_name>-<env>/
```

Where:

- `<app_name>` identifies the application
- `<env>` is `dev`, `test`, or `prod`

This path is fixed and absolute. It must not be inside the project directory. It must not be committed to source control.

### 6.2 TNS_ADMIN

SQLcl must be pointed at the wallet directory via the `TNS_ADMIN` environment variable:

```bash
export TNS_ADMIN=/opt/oracle/wallet/<app_name>-<env>
```

This must be set to the target environment's wallet path before invoking `run-sql.sh` or any SQLcl command. For agent environments, it must be set at the start of every session or switched explicitly before targeting a different environment.

### 6.3 sqlnet.ora

The wallet's `sqlnet.ora` must contain:

```
WALLET_LOCATION = (SOURCE = (METHOD = file) (METHOD_DATA = (DIRECTORY="/opt/oracle/wallet/<app_name>-<env>")))
SSL_SERVER_DN_MATCH=yes
```

This is standard for ADB wallet connectivity and should be present in the downloaded wallet unchanged.

### 6.4 Wallet Security

- The wallet directory must have permissions `700` (owner read/write/execute only)
- Wallet files must have permissions `600`
- The wallet path must never appear in logs, source control, or error messages

---

## 7. SQLcl Saved Connection Setup

### 7.1 Connection Provisioning

Before using the framework, SQLcl saved connections must be created for each environment:

```bash
export TNS_ADMIN=/opt/oracle/wallet/<app_name>-dev

sql /nolog <<EOF
connect -save app_dev \
  --url "jdbc:oracle:thin:@<tns_alias>?TNS_ADMIN=/opt/oracle/wallet/<app_name>-dev" \
  --username <schema_user>
EOF
```

Equivalent named saved connections must be created for `test` and `prod`, each pointing at that environment's wallet path.

Where `<tns_alias>` matches an entry in the selected wallet's `tnsnames.ora`.

Admin/bootstrap scripts that create or drop schema users are outside the `run-sql.sh` contract. They must be run manually from SQLcl using an admin-capable connection, not through the application connection mapping.

### 7.2 Verifying Connectivity

After provisioning, verify the connection:

```bash
run-sql.sh --env dev --script bin/verify-connection.sql
```

`bin/verify-connection.sql` contains:

```sql
select 'connected' as status from dual;
```

A successful run confirms SQLcl, the wallet, and the saved connection are all correctly configured.

---

## 8. React Build and Deployment

### 8.1 Standard Hosted Dev Runtime

The standard ROAD development workflow builds the React application, uploads it into Oracle-backed UI asset storage, and serves it through ORDS. In that standard hosted model, the app and API share the same host.

Local React servers or proxies may be used in development or test when explicitly chosen, but they are optional tooling outside the production runtime model.

### 8.2 Build

React apps are built using the standard Vite build:

```bash
cd <app_name>
npm install
npm run build -- --mode development
```

Output is written to `dist/`.

### 8.3 Deployment to ORDS

Built React files are uploaded into the ROAD UI delivery layer using SQLcl-backed deployment tooling. A deploy script handles this:

```bash
bin/deploy-react.sh --env dev --app <app_name>
```

This script:

1. Runs the Vite build in the app directory using the mode that matches the target environment (`development`, `test`, or `production`)
2. Uploads all files from `dist/` into the database-backed UI asset store for the target environment
3. Logs the result

The `--app` argument must match `APP_NAME` from `road.config`.

The upload mechanism is defined by `file-upload-and-ui-delivery-spec-v1.md`, which standardises database-backed UI asset upload and public ORDS delivery.

### 8.4 ORDS UI Delivery

ORDS serves the React app's `index.html` and assets from the database-backed UI asset store. The React app is reachable at:

```
https://<adb-host>/ords/<ui_base_path>/ui/<app_name>/
```

Protected API calls from the React app still go to the same ORDS host, typically under:

```text
https://<adb-host>/ords/<api_base_path>/api/v1/
```

In the default same-host ROAD deployment model, no CORS configuration is required.

### 8.5 Environment Variables at Build Time

Since there is no runtime environment variable injection, all configuration is baked into the React build via Vite's `.env` files.

For each environment, the correct `.env` file must be active at build time:

```bash
npm run build -- --mode development   # uses .env.development
npm run build -- --mode test          # uses .env.test
npm run build -- --mode production    # uses .env.production
```

`VITE_APP_NAME` must be derived from `APP_NAME` in `road.config`:

```text
<app_name>
```

`VITE_ORDS_BASE_URL` must point to the correct protected API base path for the target environment, typically:

```text
https://<adb-host>/ords/<api_base_path>/api/v1
```

`VITE_UI_BASE_PATH` must point to the public ORDS UI base path for the target environment:

```text
<ui_base_path>
```

The React router basename and Vite `base` must resolve to:

```text
https://<adb-host>/ords/<ui_base_path>/ui/<app_name>/
```

---

## 9. Development Workflow

### 9.1 Standard Cycle

The standard development cycle for an LLM agent is:

```
1. Write or modify SQL artifact(s)
2. run-sql.sh --env dev --script <artifact>
3. Write or modify React component(s)
4. bin/deploy-react.sh --env dev --app <app_name>
5. Verify via ORDS URL
6. run-sql.sh --env dev --script test/smoke/<test>.test.sql
```

### 9.2 Full Deploy from Scratch

To deploy a fresh environment:

```bash
# 1. Deploy database objects
run-sql.sh --env dev --script deploy/create/00_full.sql

# 2. Deploy test utilities (dev/test environments only)
run-sql.sh --env dev --script deploy/test/00_test_setup.sql

# 3. Build and deploy React app
bin/deploy-react.sh --env dev --app <app_name>

# 4. Run smoke tests
run-sql.sh --env dev --script test/smoke/00_smoke.sql
```

### 9.3 Teardown

```bash
run-sql.sh --env dev --script deploy/drop/00_full.sql
```

---

## 10. Project Environment Files

Each project must include:

| File | Purpose | Committed? |
|---|---|---|
| `road.config` | Canonical project identity such as `APP_NAME` | Yes |
| `.env.development` | Dev ORDS base URL | Yes |
| `.env.test` | Test ORDS base URL | Yes |
| `.env.production` | Prod ORDS base URL | Yes |
| `.env.example` | Documents all required variables | Yes |
| `bin/deploy-react.sh` | React build and upload script | Yes |
| `bin/verify-connection.sql` | Connection smoke test | Yes |

Wallet files, credentials, and CONNMGR configuration are never committed.

---

## 11. Agent Environment Requirements

When operating as an LLM agent, the following must be true at the start of every session:

- `TNS_ADMIN` is set to the wallet path
- `SQLCL_BIN` is set if SQLcl is not on PATH as `sql`
- Node.js and npm are available
- The project root is the working directory for all relative paths
- `run-sql.sh` is executable (`chmod +x bin/run-sql.sh`)

---

## 12. What This Spec Does Not Cover

- Wallet download and OCI console setup (manual prerequisite)
- ORDS static file storage mechanism and UI asset delivery internals (see `file-upload-and-ui-delivery-spec-v1.md`)
- CI/CD pipeline configuration (see CI/CD Pipeline Spec)
- Multi-developer or team workflows (out of scope — agent-operated only in v1)
