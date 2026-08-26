create or replace trigger jwt_scaffold_credentials_updated_at_trg
before insert or update on jwt_scaffold_credentials
for each row
begin
  :new.updated_at := systimestamp;
end;
/
