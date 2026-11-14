begin
  execute immediate 'drop index road_decisions_idempotency_ux';
exception
  when others then
    if sqlcode != -1418 then
      raise;
    end if;
end;
/
