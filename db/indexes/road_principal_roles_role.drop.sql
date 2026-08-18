begin
  execute immediate 'drop index road_principal_roles_role_ix';
exception
  when others then
    if sqlcode != -1418 then
      raise;
    end if;
end;
/
