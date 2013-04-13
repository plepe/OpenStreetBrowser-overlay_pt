drop type overlay_pt_member cascade;
create type overlay_pt_member as (
  id                 text,
  tags               hstore,
  way                geometry,
  relation_id        text,
  relation_tags      hstore,
  relation_role      text,
  direction          text
);

CREATE OR REPLACE FUNCTION overlay_pt_get_members(
  IN bbox       geometry,
  IN where_expr text,
  IN options    hstore default ''::hstore
)
RETURNS SETOF overlay_pt_member
AS $body$
#variable_conflict use_variable
DECLARE
 all_member_ids text[]:=Array[]::text[];
 r    record;
 id      text;
 i      int;
BEGIN
  for r in select member_ids from overlay_pt_get_routes(bbox, where_expr, options) loop
    all_member_ids=array_cat(all_member_ids, r.member_ids);
  end loop;

  select array_agg(member_id) into all_member_ids from (select unnest(all_member_ids) member_id group by member_id) t;

  for r in
    select
      member.id as id,
      member.tags as tags,
      member.way as way,
      routes.id as relation_id,
      routes.tags as relation_tags,
      routes.member_ids as relation_member_ids,
      routes.member_roles as relation_member_roles,
      routes.member_directions as relation_member_directions
       from
    (select * from overlay_pt_get_routes(bbox, where_expr, options)) routes,
    (select * from osm_all(bbox, 'id=any('||quote_nullable(cast(all_member_ids as text))||')')) member where member.id=any(routes.member_ids)
  loop
    i=0;
    foreach id in array r.relation_member_ids loop
      i=i+1;

      if id=r.id then
        return query select r.id, r.tags, r.way, r.relation_id, r.relation_tags, r.relation_member_roles[i], r.relation_member_directions[i];
      end if;
    end loop;
  end loop;
  
  return;
END;
$body$ language plpgsql;
