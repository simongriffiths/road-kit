create table road_api_log (
  log_id      raw(16) default sys_guid() primary key,
  issued_at   timestamp with time zone default systimestamp not null,
  caller_type varchar2(30 char) not null,
  caller_ref  varchar2(200 char),
  app_schema  varchar2(60 char) not null,
  endpoint    varchar2(200 char) not null,
  entity_type varchar2(60 char),
  entity_id   varchar2(60 char),
  outcome     varchar2(20 char)
);
