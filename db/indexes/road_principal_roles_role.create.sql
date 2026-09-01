-- ORA-955-tolerant, matching this index's own drop.sql (-1418 there) -- see road-atlas F-10.
begin
  execute immediate 'create index road_principal_roles_role_ix on road_principal_roles (role_name)';
exception
  when others then
    if sqlcode != -955 then
      raise;
    end if;
end;
/
