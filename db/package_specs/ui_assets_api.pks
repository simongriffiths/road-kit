create or replace package ui_assets_api as
  procedure upsert_asset(
    p_app_name       in varchar2,
    p_relative_path  in varchar2,
    p_file_name      in varchar2,
    p_content_type   in varchar2,
    p_content_length in number,
    p_checksum       in varchar2,
    p_content        in blob
  );
end ui_assets_api;
/
