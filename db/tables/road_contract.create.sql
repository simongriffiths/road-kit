-- road_contract: the Governed Surface Contract document this deployment serves at GET /contract/
-- (definition 5.5; spec-patch-16 section 3.1). One row, written by deploy/create/generated/96_contract.sql,
-- which scripts/contract-to-sql.mjs generates from contract/<app>.gsc.json. Not application data.
-- road_surface_api reads the contract version from here, so the version the database serves, the
-- version on every response and the version in the file have one source.
-- ORA-955-tolerant, matching its drop script (road-atlas F-10).
begin
  execute immediate q'[
    create table road_contract (
      contract_id      number default 1 not null,
      contract_version varchar2(20 char) not null,
      document         clob not null,
      loaded_at        timestamp with time zone default systimestamp not null,
      constraint road_contract_pk primary key (contract_id),
      constraint road_contract_one_ck check (contract_id = 1),
      constraint road_contract_json_ck check (document is json)
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
