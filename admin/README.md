# Admin Bootstrap Scripts

These scripts are for manual database bootstrap work and are intentionally separate from normal application deployment.

## Purpose

Use this folder for operations that require an admin-capable database account, especially before the ROAD application schema and normal `app_dev` / `app_test` / `app_prod` connections exist.

Current scripts:

- `create-schema-user.sql`
- `drop-schema-user.sql`
- `grant-schema-privileges.sql`

## How To Run

Run these scripts manually from SQLcl while connected as an admin-capable user.

Example:

```bash
sql admin@myadb_high
@admin/create-schema-user.sql
@admin/grant-schema-privileges.sql
```

## Important Rule

Do **not** run these scripts through `bin/run-sql.sh`.

`bin/run-sql.sh` is reserved for normal application-schema deployment and test execution through named app connections such as:

- `app_dev`
- `app_test`
- `app_prod`

The admin scripts are bootstrap operations and sit outside that contract.
