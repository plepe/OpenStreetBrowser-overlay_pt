DROP TYPE IF EXISTS overlay_pt_refs_return CASCADE;
CREATE TYPE overlay_pt_refs_return AS (
  text_right    text,
  text_left     text
);

CREATE OR REPLACE FUNCTION overlay_pt_refs(directions text[], relation_tags hstore[])
RETURNS SETOF overlay_pt_refs_return
AS $body$
DECLARE
  ref text;
  ref_parts text[]=Array[''::text, ''::text, ''::text, ''::text];
  ret overlay_pt_refs_return;
  i int;
  d int;
  r record;
BEGIN
  ret.text_right=''::text;
  ret.text_left=''::text;

  for r in
    select t2.direction, array_agg(t2.ref) as ref from (select t1.ref, overlay_pt_direction(array_agg(direction)) as direction from (select unnest(directions) as direction, unnest(relation_tags)->'ref' as ref) t1 group by t1.ref) t2 group by t2.direction order by t2.direction desc
  loop
    if    r.direction='X' then d=1;
    elsif r.direction='F' then d=2;
    elsif r.direction='B' then d=3;
    else                       d=4; -- ignore
    end if;

    ref_parts[d]=array_to_string(r.ref, ', ');
  end loop;
  
  ret.text_right=ref_parts[1];
  ret.text_left =ref_parts[1];

  if ref_parts[2]!='' then
    ret.text_right=ret.text_right||
      (CASE WHEN ret.text_right!='' THEN ' ' ELSE '' END)||'→ '||ref_parts[2];
  end if;

  if ref_parts[3]!='' then
    ret.text_left =ret.text_left||
      (CASE WHEN ret.text_left!='' THEN ' ' ELSE '' END)||'→ '||ref_parts[3];
  end if;

  if ref_parts[3]!='' then
    ret.text_right=ret.text_right||
      (CASE WHEN ret.text_right!='' THEN ' ' ELSE '' END)||'← '||ref_parts[3];
  end if;

  if ref_parts[2]!='' then
    ret.text_left =ret.text_left||
      (CASE WHEN ret.text_left!='' THEN ' ' ELSE '' END)||'← '||ref_parts[2];
  end if;

  return next ret;
  return;
END;
$body$ language plpgsql;


select overlay_pt_refs(Array['F', 'F', 'F', 'B', 'X', 'X'], Array['ref=>1'::hstore, 'ref=>49'::hstore, 'ref=>46'::hstore, 'ref=>49'::hstore, 'ref=>46'::hstore, 'ref=>VRT'::hstore]);
