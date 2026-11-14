-- One accepted decision per (action, principal, idempotency key). This is what makes a repeated
-- proposal unable to change state twice (GSC definition 0.1.0 section 6.5), even when two copies
-- race: the second insert waits for the first to commit, then fails ORA-00001, and the caller
-- answers with road_decision_api.prior_outcome.
--
-- Rejected rows are outside the index. A rejection never changes state, so a key may be rejected
-- any number of times before it is accepted once.
--
-- The key is scoped to the principal, so one consumer's key can never replay another consumer's
-- outcome. nvl(principal_id, 0) covers public actions, where there is no principal.
--
-- ORA-955-tolerant, matching this index's own drop.sql (-1418 there) -- see road-atlas F-10.
begin
  execute immediate q'[
    create unique index road_decisions_idempotency_ux on road_decisions (
      case when decision = 'accepted' and idempotency_key is not null
           then action_id end,
      case when decision = 'accepted' and idempotency_key is not null
           then nvl(principal_id, 0) end,
      case when decision = 'accepted' and idempotency_key is not null
           then idempotency_key end
    )
  ]';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
