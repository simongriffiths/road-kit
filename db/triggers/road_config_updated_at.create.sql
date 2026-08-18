create or replace trigger road_config_updated_at_trg
before insert or update on road_config
for each row
begin
  :new.updated_at := systimestamp;
end;
/
