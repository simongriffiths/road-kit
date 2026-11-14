create or replace package error_api as

  -- Maps a raise_application_error in the reserved -20000..-20999 range to the flat
  -- {error, message, ora_code} envelope and a 4xx HTTP status, per
  -- spec/error-handling-contract-v1.md section 4. Wrong calls only: a business rejection is an
  -- outcome returned with 200 through road_decision_api, never an error (ledger D-05).
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
