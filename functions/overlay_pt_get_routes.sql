CREATE OR REPLACE FUNCTION overlay_pt_get_routes (
  IN bbox       geometry,
  IN where_expr text default null::text,
  IN options    hstore default ''::hstore
) returns setof overlay_pt_route AS $body$
#variable_conflict use_variable
DECLARE
  r record;
BEGIN
  for r in select id from osm_rel(bbox, where_expr, options) loop
    select * into r from overlay_pt_get_route(bbox, r.id, options);
    return next r;
  end loop;

  return;
END;
$body$ language plpgsql;
