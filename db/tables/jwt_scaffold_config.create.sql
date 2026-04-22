create table jwt_scaffold_config (
  config_id        number constraint jwt_scaffold_config_pk primary key,
  issuer           varchar2(1024 char) not null,
  audience         varchar2(1024 char) not null,
  scope_name       varchar2(4000 char) not null,
  ttl_minutes      number not null,
  jwk_url          varchar2(1024 char) not null,
  kid              varchar2(255 char) not null,
  private_key_b64  varchar2(4000 char) not null,
  public_n         varchar2(4000 char) not null,
  public_e         varchar2(100 char) not null,
  created_at       timestamp with time zone default systimestamp not null,
  updated_at       timestamp with time zone default systimestamp not null,
  constraint jwt_scaffold_config_one_row_ck check (config_id = 1)
);
