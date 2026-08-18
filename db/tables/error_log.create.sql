create table error_log (
  id            number generated always as identity primary key,
  error_time    timestamp default systimestamp not null,
  sqlcode       number,
  sqlerrm       varchar2(4000 char),
  backtrace     clob,
  context       varchar2(500 char),
  session_user  varchar2(128 char) default sys_context('userenv', 'session_user')
);
