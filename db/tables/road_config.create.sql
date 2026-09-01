-- Framework configuration that must outlive the JWT scaffold. road-cal's only existing settings
-- table is JWT_SCAFFOLD_CONFIG, which is scaffold-specific and goes when the scaffold does, so
-- default_principal_role and its successors need somewhere else to live (build plan 1.3).
--
-- Deliberately a narrow key/value table rather than a column-per-setting: the settings this holds
-- are read one at a time by name, and adding one should not be a schema change.
-- ORA-955-tolerant, matching this table's own drop.sql (-942 there) -- see road-atlas F-10.
begin
  execute immediate q'[
    create table road_config (
      config_key   varchar2(128 char) primary key,
      config_value varchar2(4000 char),
      description  varchar2(4000 char),
      updated_at   timestamp with time zone default systimestamp not null
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
