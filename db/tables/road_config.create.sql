-- Framework configuration that must outlive the JWT scaffold. road-cal's only existing settings
-- table is JWT_SCAFFOLD_CONFIG, which is scaffold-specific and goes when the scaffold does, so
-- default_principal_role and its successors need somewhere else to live (build plan 1.3).
--
-- Deliberately a narrow key/value table rather than a column-per-setting: the settings this holds
-- are read one at a time by name, and adding one should not be a schema change.
create table road_config (
  config_key   varchar2(128 char) primary key,
  config_value varchar2(4000 char),
  description  varchar2(4000 char),
  updated_at   timestamp with time zone default systimestamp not null
);
