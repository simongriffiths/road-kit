-- ORA-955-tolerant, matching this index's own drop.sql (-1418 there) -- see road-atlas F-10.
begin
  execute immediate 'create index road_principals_email_ix on road_principals (email)';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
