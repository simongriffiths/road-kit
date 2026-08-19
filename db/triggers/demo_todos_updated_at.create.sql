create or replace trigger demo_todos_updated_at_trg
before insert or update on demo_todos
for each row
begin
  :new.updated_at := systimestamp;
end;
/
