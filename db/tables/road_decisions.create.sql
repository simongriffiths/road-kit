-- The decision record for governed actions (spec-patch-12 section 4; GSC definition 0.1.0
-- section 6.7). One row per proposal that reached a decision, accepted or rejected.
--
-- Written only through road_decision_api: accepted rows in the caller's transaction, rejected rows
-- in an autonomous transaction so they survive the rollback of the rejected change.
--
-- No foreign key to road_principals, deliberately: a decision outlives the principal that made it.
-- principal_id is null for an action the contract declares public.
--
-- Never purged by the framework. The rows double as the idempotency store, so purging them also
-- ends replay for the keys they hold.
--
-- ORA-955-tolerant, matching this table's own drop.sql -- see road-atlas F-10.
begin
  execute immediate q'[
    create table road_decisions (
      decision_id      number generated always as identity primary key,
      decided_at       timestamp with time zone default systimestamp not null,
      principal_id     number,
      action_id        varchar2(200 char) not null,
      contract_version varchar2(40 char) not null,
      decision         varchar2(8 char) not null,
      disclosed        boolean default true not null,
      idempotency_key  varchar2(400 char),
      record_ids       json,
      result           json,
      rejections       json,
      constraint road_decisions_decision_ck
        check (decision in ('accepted', 'rejected')),
      constraint road_decisions_rejections_ck
        check (decision = 'accepted' or rejections is not null),
      constraint road_decisions_disclosed_ck
        check (decision = 'rejected' or disclosed)
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
