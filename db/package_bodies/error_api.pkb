create or replace package body error_api as

  -- Never raises: a logging failure must not cause a secondary failure
  -- (spec/error-handling-contract-v1.md §5.2). Autonomous so the log entry survives even when
  -- the caller's transaction rolls back around this error.
  procedure write_error_log(
    p_sqlcode   in number,
    p_sqlerrm   in varchar2,
    p_backtrace in varchar2,
    p_context   in varchar2
  ) is
    pragma autonomous_transaction;
  begin
    insert into error_log (sqlcode, sqlerrm, backtrace, context)
    values (p_sqlcode, p_sqlerrm, p_backtrace, p_context);
    commit;
  exception
    when others then
      null;
  end write_error_log;

  procedure handle_known(
    p_sqlcode     in number,
    p_sqlerrm     in varchar2,
    p_status_code out number,
    p_response    out clob
  ) is
    l_error   varchar2(60);
    l_message varchar2(4000);
  begin
    -- Fixed mapping per calendar-app-design-outline.md §"Error signalling from EVENT_API to
    -- ORDS". Not a generic range-based scheme (e.g. 20000-20099 => 400): each code is a
    -- deliberately chosen business meaning, so it is listed explicitly rather than derived.
    case p_sqlcode
      when -20001 then
        l_error := 'VALIDATION_ERROR';
        p_status_code := 400;
      when -20003 then
        l_error := 'AGENDA_LOCKED';
        p_status_code := 422;
      when -20004 then
        l_error := 'NOT_FOUND';
        p_status_code := 404;
      when -20009 then
        l_error := 'CONFLICT';
        p_status_code := 409;
      when -20403 then
        -- road_ctx_pkg.c_forbidden. An AUTHENTICATED principal that lacks a required permission or
        -- role. Distinct from 401 by design: ORDS returns 401 for no token, a bad token or a
        -- missing scope, before any PL/SQL runs. Reaching here means the caller is who they say
        -- they are and still may not do this (spec-patch-06 section 6.4). Without the distinction
        -- a permission failure would surface as a 500 or as a 401 that misreports the cause.
        -- The code is mnemonic: -20403 -> 403.
        l_error := 'FORBIDDEN';
        p_status_code := 403;
      else
        -- A code inside the reserved range but outside the fixed mapping is a coding mistake,
        -- not a known business error — escalate rather than emit a response with a null
        -- error/status. Never silently return a malformed body (contract §2 principle 1).
        handle_unknown(
          p_sqlerrm     => p_sqlerrm,
          p_backtrace   => dbms_utility.format_error_backtrace,
          p_context     => 'error_api.handle_known: unmapped known-range sqlcode ' || p_sqlcode,
          p_status_code => p_status_code,
          p_response    => p_response
        );
        return;
    end case;

    -- raise_application_error(-20001, 'msg') surfaces as sqlerrm = 'ORA-20001: msg'; strip the
    -- code prefix so message carries only the user-safe text passed to raise_application_error.
    l_message := regexp_replace(p_sqlerrm, '^ORA-[0-9]+:\s*', '');

    select json_object(
             'error'    value l_error,
             'message'  value l_message,
             'ora_code' value 'ORA-' || to_char(-p_sqlcode, 'FM00000')
             returning clob
           )
      into p_response
      from dual;
  end handle_known;

  procedure handle_unknown(
    p_sqlerrm     in varchar2,
    p_backtrace   in varchar2,
    p_context     in varchar2 default null,
    p_status_code out number,
    p_response    out clob
  ) is
  begin
    write_error_log(
      p_sqlcode   => sqlcode,
      p_sqlerrm   => p_sqlerrm,
      p_backtrace => p_backtrace,
      p_context   => p_context
    );

    p_status_code := 500;

    -- Generic message only — never echo sqlerrm/backtrace to the client (contract §3.2).
    select json_object(
             'error'   value 'INTERNAL_ERROR',
             'message' value 'An unexpected error occurred'
             returning clob
           )
      into p_response
      from dual;
  end handle_unknown;

end error_api;
/
