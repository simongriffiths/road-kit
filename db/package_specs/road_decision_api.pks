create or replace package road_decision_api as

  -- Decision records and outcomes for governed actions (spec-patch-12; GSC definition 0.1.0
  -- sections 6.3 to 6.7).
  --
  -- A governed action's decision code returns an OUTCOME, never raises a business rejection. Its
  -- handler sends the outcome with HTTP 200 (ledger D-05). This package writes the decision record
  -- and builds the outcome, so every governed action in every adopter returns the same shape:
  --
  --   accepted: { "contract_version", "decision": "accepted", "result",     "audit_id" }
  --   rejected: { "contract_version", "decision": "rejected", "rejections", "audit_id" }
  --
  -- Each rejection is { "rule_id", "message", "retryable", "ids"? }. audit_id is the decision
  -- record's id.
  --
  -- The principal is always taken from road_ctx_pkg, never from a parameter, so a caller cannot
  -- misattribute a decision. It is null for an action the contract declares public.
  --
  -- The shape of a governed action, in its package:
  --
  --   function request_x(p_request in json) return json is
  --     l_prior json;
  --   begin
  --     l_prior := road_decision_api.prior_outcome(c_action, l_key);   -- step 3: idempotency
  --     if l_prior is not null then return l_prior; end if;
  --     savepoint request_x;
  --     ... re-read current state, test the rules ...                    -- steps 4 and 5
  --     if <a rule rejects> then
  --       rollback to savepoint request_x;                               -- step 6, rejected
  --       return road_decision_api.reject(c_action, c_version,
  --                road_decision_api.rejection('RULE_ID', 'Why.', false));
  --     end if;
  --     ... apply the change, record events ...                          -- step 6, accepted
  --     return road_decision_api.accept(c_action, c_version, l_result, p_idempotency_key => l_key);
  --   exception
  --     when dup_val_on_index then
  --       -- Only if the action's own tables have no unique keys of their own; otherwise test
  --       -- which constraint fired. A copy of this proposal won the race and committed first.
  --       rollback to savepoint request_x;
  --       return road_decision_api.prior_outcome(c_action, l_key);
  --   end request_x;
  --
  -- Never commits the caller's transaction. ORDS commits when the handler completes.

  c_accepted constant varchar2(8) := 'accepted';
  c_rejected constant varchar2(8) := 'rejected';

  -- Raised for a call that breaks this package's own rules: a rejection with no rule_id, a reject
  -- with no rejections. Outside error_api's fixed mapping on purpose, so it surfaces as a logged
  -- 500. It is a coding mistake in the action, not something a consumer did.
  c_misuse constant number := -20090;

  -- One rejection object. p_ids, where disclosing them is permitted, is a JSON array of the
  -- identifiers of the records involved, for example json('[42]').
  function rejection(
    p_rule_id   in varchar2,
    p_message   in varchar2,
    p_retryable in boolean,
    p_ids       in json default null
  ) return json;

  -- Records an accepted decision IN THE CALLER'S TRANSACTION and returns the outcome. If the
  -- change is later rolled back, so is this record: an audit record can never claim a success
  -- whose change did not commit.
  --
  -- With p_idempotency_key, a second accepted decision for the same action, principal and key
  -- raises DUP_VAL_ON_INDEX (index road_decisions_idempotency_ux).
  function accept(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_result           in json default null,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json;

  -- Records a rejected decision IN AN AUTONOMOUS TRANSACTION and returns the outcome. The record
  -- survives the rollback of the rejected change.
  --
  -- The caller rolls back its own changes first (rollback to savepoint). This package cannot do it
  -- for the caller, and an autonomous write cannot see whether it was done.
  --
  -- p_rejections is one rejection object, or a JSON array of them.
  function reject(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_rejections       in json,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json;

  -- A non-disclosing rejection (GSC definition section 6.4.4). The record holds the true decision,
  -- rejected, with its rejections. The consumer receives an accepted outcome carrying
  -- p_reported_result. Use only for an action whose contract declares its accepted outcome
  -- non-disclosing.
  function reject_undisclosed(
    p_action_id        in varchar2,
    p_contract_version in varchar2,
    p_rejections       in json,
    p_reported_result  in json default null,
    p_record_ids       in json default null,
    p_idempotency_key  in varchar2 default null
  ) return json;

  -- The earlier outcome for this action, principal and key, or null if there is none. Step 3 of
  -- the decision procedure: a repeated proposal returns this and changes nothing.
  --
  -- By default only an accepted outcome is replayed, so a rejected proposal does not use up its
  -- key and a retryable rejection can still succeed later with the same key. This reading of GSC
  -- definition section 6.5 is not yet settled there (spec-patch-12 section 4.4). Pass
  -- p_replay_rejections => true to replay the latest decision of either kind.
  function prior_outcome(
    p_action_id         in varchar2,
    p_idempotency_key   in varchar2,
    p_replay_rejections in boolean default false
  ) return json;

end road_decision_api;
/
