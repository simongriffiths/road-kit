begin
  execute immediate 'drop trigger jwt_scaffold_credentials_updated_at_trg';
exception
  when others then
    if sqlcode != -4080 then
      raise;
    end if;
end;
/
