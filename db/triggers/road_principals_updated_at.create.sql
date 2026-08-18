create or replace trigger road_principals_updated_at_trg
before insert or update on road_principals
for each row
begin
  :new.updated_at := systimestamp;
end;
/
