create or replace package body health_api as
  function get_status return varchar2 is
  begin
    return 'ok';
  end get_status;
end health_api;
/
