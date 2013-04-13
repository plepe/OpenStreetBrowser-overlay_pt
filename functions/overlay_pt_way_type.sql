CREATE OR REPLACE FUNCTION overlay_pt_way_type(tags_list hstore[])
RETURNS text
AS $body$
DECLARE
  tags hstore;
  type_list text[]:=Array[]::text[];
BEGIN
  foreach tags in array tags_list loop
    type_list=array_append(type_list, tags->'route');
  end loop;

  if type_list @> '{train}' then
    return 'train';
  elsif type_list @> '{subway}' then
    return 'subway';
  elsif type_list @> '{monorail}' then
    return 'monorail';
  elsif type_list @> '{lightrail}' then
    return 'lightrail';
  elsif type_list @> '{tram}' and (type_list && '{bus,trolleybus}') then
    return 'tram/bus';
  elsif type_list @> '{tram}' then
    return 'tram';
  elsif type_list @> '{trolleybus}' then
    return 'trolleybus';
  elsif type_list @> '{bus}' then
    return 'bus';
  elsif type_list @> '{ferry}' then
    return 'ferry';
  elsif type_list @> '{aerialway}' then
    return 'aerialway';
  elsif type_list @> '{share_taxi}' then
    return 'share_taxi';
  else
    return null;
  end if;
END;
$body$ language plpgsql;
