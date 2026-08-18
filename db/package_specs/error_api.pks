create or replace package error_api as

  -- Maps a raise_application_error in the reserved -20000..-20999 range to the flat
  -- {error, message, ora_code} envelope and an HTTP status, per
  -- spec/error-handling-contract-v1.md §4.2 and calendar-app-design-outline.md's error table.
  procedure handle_known(
    p_sqlcode     in number,
    p_sqlerrm     in varchar2,
    p_status_code out number,
    p_response    out clob
  );

  -- Logs full detail to error_log (autonomous transaction) and returns a generic 500 body.
  procedure handle_unknown(
    p_sqlerrm     in varchar2,
    p_backtrace   in varchar2,
    p_context     in varchar2 default null,
    p_status_code out number,
    p_response    out clob
  );

end error_api;
/
