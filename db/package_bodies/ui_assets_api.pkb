create or replace package body ui_assets_api as
  procedure upsert_asset(
    p_app_name       in varchar2,
    p_relative_path  in varchar2,
    p_file_name      in varchar2,
    p_content_type   in varchar2,
    p_content_length in number,
    p_checksum       in varchar2,
    p_content        in blob
  ) as
  begin
    update ui_assets
       set file_name      = p_file_name,
           content_type   = p_content_type,
           content_length = p_content_length,
           checksum       = p_checksum,
           updated_at     = systimestamp,
           content        = p_content
     where app_name = p_app_name
       and relative_path = p_relative_path;

    if sql%rowcount = 0 then
      insert into ui_assets (
        app_name,
        relative_path,
        file_name,
        content_type,
        content_length,
        checksum,
        updated_at,
        content
      ) values (
        p_app_name,
        p_relative_path,
        p_file_name,
        p_content_type,
        p_content_length,
        p_checksum,
        systimestamp,
        p_content
      );
    end if;
  end upsert_asset;
end ui_assets_api;
/
