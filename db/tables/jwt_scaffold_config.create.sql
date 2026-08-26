-- Key columns are deliberately NULLABLE: the row is built in two phases by two different
-- owners. Config values are rendered from the environment (bin/render-auth-config.sh);
-- key material is generated once per environment and lives ONLY here, never on disk or in
-- git (bin/ensure-auth-key.sh). See planning/spec-patch-04-auth-config-derivation.md 5.4.
create table jwt_scaffold_config (
  config_id        number constraint jwt_scaffold_config_pk primary key,
  issuer           varchar2(1024 char) not null,
  audience         varchar2(1024 char) not null,
  -- NULLABLE, not NOT NULL -- spec-patch-09 phase 4. Was NOT NULL when this column held a
  -- fixed scope list issued to every user; it now falls back INTO issue_token's NVL only for a
  -- principal entitled to nothing, and NULL is the only value that means that. An empty-string
  -- attempt at the same intent fails anyway -- Oracle stores '' as NULL for VARCHAR2, so a
  -- NOT NULL column simply refuses it (ORA-01407), found deploying this phase.
  scope_name       varchar2(4000 char),
  ttl_minutes      number not null,
  jwk_url          varchar2(1024 char) not null,
  kid              varchar2(255 char),
  private_key_b64  varchar2(4000 char),
  public_n         varchar2(4000 char),
  public_e         varchar2(100 char),
  created_at       timestamp with time zone default systimestamp not null,
  updated_at       timestamp with time zone default systimestamp not null,
  constraint jwt_scaffold_config_one_row_ck check (config_id = 1)
);
