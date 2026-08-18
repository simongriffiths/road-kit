begin
  execute immediate 'drop index road_principals_email_ix';
exception
  when others then
    if sqlcode != -1418 then
      raise;
    end if;
end;
/
