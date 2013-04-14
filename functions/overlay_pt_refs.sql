DROP TYPE IF EXISTS overlay_pt_refs_return CASCADE;
CREATE TYPE overlay_pt_refs_return AS (
  ref_has_dir          text,
  ref1_type            text,
  ref1_color           text,
  ref1_both            text,
  ref1_forward         text,
  ref1_backward        text,
  ref2_type            text,
  ref2_color           text,
  ref2_both            text,
  ref2_forward         text,
  ref2_backward        text,
  ref3_type            text,
  ref3_color           text,
  ref3_both            text,
  ref3_forward         text,
  ref3_backward        text
);

CREATE OR REPLACE FUNCTION overlay_pt_refs(directions text[], relation_tags hstore[])
RETURNS SETOF overlay_pt_refs_return
AS $body$
DECLARE
  ref text;
  ref_parts text[];
  ref_types text[3]=Array[''::text, ''::text, ''::text];
  ret overlay_pt_refs_return;
  i int;
  route text:=''::text;
  d int;
  r record;
  has_dir bool[];
  needs_comma int;
BEGIN
  ref_parts=array_fill(''::text, Array[9]);
  has_dir=array_fill(false, Array[9]);

  i=0;
  for r in
    select t2.direction, array_agg(t2.ref) as ref, t2.route as route from (select t1.ref, overlay_pt_direction(array_agg(direction)) as direction, t1.route from (select unnest(directions) as direction, unnest(relation_tags)->'ref' as ref, unnest(relation_tags)->'route' as route) t1 group by t1.ref, t1.route) t2 group by t2.direction, t2.route order by t2.route, t2.direction desc
  loop
    if    r.direction='X' then d=1;
    elsif r.direction='F' then d=2;
    elsif r.direction='B' then d=3;
    else                       d=4; -- ignore
    end if;

    if r.route!=route then
      i=i+1;
      route=r.route;
      if i<4 then
        ref_types[i]=route;
      end if;
    end if;

    if i<4 and d<4 then
      has_dir[d]=true;
      ref_parts[(i-1)*3+d]=array_to_string(r.ref, ', ');
    end if;
  end loop;

  ret.ref_has_dir='';
  if has_dir[1] then ret.ref_has_dir=ret.ref_has_dir||'X'; end if;
  if has_dir[2] then ret.ref_has_dir=ret.ref_has_dir||'F'; end if;
  if has_dir[3] then ret.ref_has_dir=ret.ref_has_dir||'B'; end if;

  for d in 1..3 loop
    needs_comma=null;

    for i in 1..3 loop
      if ref_parts[(i-1)*3+d]!='' then
        if needs_comma is not null then
          ref_parts[(needs_comma-1)*3+d]=ref_parts[(needs_comma-1)*3+d]||', ';
        end if;
        needs_comma=i;
      end if;
    end loop;
  end loop;

  ret.ref1_type        =ref_types[1];
  ret.ref1_color       =(select '#'||(tags->'color') from overlay_pt_route_types where id=ref_types[1]);
  ret.ref1_both        =ref_parts[1];
  ret.ref1_forward     =ref_parts[2];
  ret.ref1_backward    =ref_parts[3];
  ret.ref2_type        =ref_types[2];
  ret.ref2_color       =(select '#'||(tags->'color') from overlay_pt_route_types where id=ref_types[2]);
  ret.ref2_both        =ref_parts[4];
  ret.ref2_forward     =ref_parts[5];
  ret.ref2_backward    =ref_parts[6];
  ret.ref3_type        =ref_types[3];
  ret.ref3_color       =(select '#'||(tags->'color') from overlay_pt_route_types where id=ref_types[3]);
  ret.ref3_both        =ref_parts[7];
  ret.ref3_forward     =ref_parts[8];
  ret.ref3_backward    =ref_parts[9];

  return next ret;
  return;
END;
$body$ language plpgsql;
