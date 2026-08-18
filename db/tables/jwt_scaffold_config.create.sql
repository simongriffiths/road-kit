-- Key columns are deliberately NULLABLE: the row is built in two phases by two different
-- owners. Config values are rendered from the environment (bin/render-auth-config.sh);
-- key material is generated once per environment and lives ONLY here, never on disk or in
-- git (bin/ensure-auth-key.sh). See planning/spec-patch-04-auth-config-derivation.md 5.4.
create table jwt_scaffold_config (
  config_id        number constraint jwt_scaffold_config_pk primary key,
  issuer           varchar2(1024 char) not null,
  audience         varchar2(1024 char) not null,
  scope_name       varchar2(4000 char) not null,
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
