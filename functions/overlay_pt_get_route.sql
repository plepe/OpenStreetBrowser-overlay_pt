CREATE OR REPLACE FUNCTION _overlay_pt_decide_direction(
  IN way_curr   geometry,
  IN way_prev   geometry,
  IN way_next   geometry,
  IN role       text,
  IN mode       int,
  OUT direction text,
  OUT valid     bool
) AS $body$
#variable_conflict use_variable
DECLARE
  w1 geometry;
  w2 geometry;
BEGIN
  if mode=0 then
    direction='';
  elsif mode=1 then
    if substr(role, 1, 7)='forward' then
      direction='F';
    elsif substr(role, 1, 8)='backward' then
      direction='B';
    else
      direction='X';
    end if;
    valid=true;
  elsif mode=2 then
    w1=ST_Line_Interpolate_Point(way_curr, 0);
    w2=ST_Line_Interpolate_Point(way_curr, 1);

    if    way_prev is not null and ST_Intersects(w1, way_prev) then
      direction='F';
    elsif way_prev is not null and ST_Intersects(w2, way_prev) then
      direction='B';
    elsif way_next is not null and ST_Intersects(w2, way_next) then
      direction='F';
    elsif way_next is not null and ST_Intersects(w1, way_next) then
      direction='B';
    else
      direction='';
    end if;
    valid=true; -- should return false for platforms, etc.
    -- TODO
  end if;
END;
$body$ language plpgsql;

-- for stops return:
-- direction|way_id|point on way|distance from way
-- e.g. F|W26576395|0101000020E6100000DA50DBFFF7403040A7DE0612061B4840|4.88234030285617e-05
-- 'point on way' is the closest point on the way to the stop
CREATE OR REPLACE FUNCTION overlay_pt_get_route(
  IN bbox       geometry,
  IN rel_id     text,
  OUT id        text,
  OUT tags      hstore,
  OUT way       geometry,
  OUT member_ids        text[],
  OUT member_roles      text[],
  OUT member_directions text[]
) AS $body$
#variable_conflict use_variable
DECLARE
  rel           osm_rel%rowtype;
  r             record;
  i             int;
  i_curr        int;
  member_id     text;
  way_prev      record;
  has_prev      bool:=false;
  way_next      record;
  way_curr      record;
  way_list      geometry[];
  has_curr      bool:=false;
  length        float:=0;
  importance    text;
  mode          int;
    -- 0.. unknown
    -- 1.. old PT scheme
    -- 2.. OXOMOA PT scheme
BEGIN
  -- get full relation
  rel:=osm_rel(bbox, 'id='||quote_nullable(rel_id));

  -- initialize return values
  id=rel.id;
  tags:=rel.tags;
  way:=rel.way;
  member_ids=rel.member_ids;
  member_roles=rel.member_roles;
  member_directions=array_fill(''::text, Array[array_upper(rel.member_ids, 1)]);
  way_list=array_fill(null::geometry, Array[array_upper(rel.member_ids, 1)]);

  -- check mode
  if tags?'from' or tags?'to' then
    mode=2;
    tags=tags || '#overlay_pt_mode=>oxomoa'::hstore;
  else
    mode=1;
    tags=tags || '#overlay_pt_mode=>public_transport'::hstore;
  end if;

  -- assess route
  length:=ST_Length(Geography(way));
  tags=tags||('#overlay_pt_importance=>'||(CASE
    WHEN length<=2500 THEN 'local'
    WHEN length<=10000 THEN 'suburban'
    WHEN length<=25000 THEN 'urban'
    WHEN length<=100000 THEN 'regional'
    WHEN length<=250000 THEN 'national'
    ELSE 'international'
    END))::hstore;

  -- iterate over all ways
  i:=0; -- the for always acquires the next way, i points to current
  i_curr:=0;
  foreach member_id in array rel.member_ids loop
    for way_next in -- returns only one row!
      select * from osm_linepoly(rel.way, 'id='||quote_nullable(member_id))
    loop
      i_curr=i+1;
      way_list[i+1]=way_next.way;
      -- call _overlay_pt_decide_direction always for the previous way
      if has_prev then
        r=_overlay_pt_decide_direction(
            way_curr.way,
            way_prev.way,
            way_next.way,
            rel.member_roles[i],
            mode
          );
        member_directions[i]=r.direction;

        if(r.valid) then
          way_prev=way_curr;
          way_curr=way_next;
        end if;
      elsif has_curr then
        r=_overlay_pt_decide_direction(
            way_curr.way,
            null,
            way_next.way,
            rel.member_roles[i],
            mode
          );
        member_directions[i]=r.direction;

        if(r.valid) then
          has_prev=true;
          way_prev=way_curr;
          way_curr=way_next;
        end if;
      else
        has_curr=true;
        way_curr=way_next;
      end if;
    end loop;

    i=i+1;
  end loop;

  -- also call _overlay_pt_decide_direction for the last member way
  if has_prev then
    r=_overlay_pt_decide_direction(
        way_curr.way,
        way_prev.way,
        null, 
        rel.member_roles[i_curr],
        mode
      );
    member_directions[i_curr]=r.direction;
  elsif has_curr then
    r=_overlay_pt_decide_direction(
        way_curr.way,
        null,
        null,
        rel.member_roles[i_curr],
        mode
      );
    member_directions[i_curr]=r.direction;
  end if;

  -- no iterate again for all stops to get their direction
  i:=0;
  foreach member_id in array rel.member_ids loop
    i=i+1;
    for way_curr in -- returns only one row!
      select * from osm_point(rel.way, 'id='||quote_nullable(member_id))
    loop

      select  ways.member_direction, ways.member_id, ST_Line_Interpolate_Point(ways.way, ST_Line_Locate_Point(ways.way, way_curr.way)) poi, ST_Distance(ways.way, way_curr.way) distance into r from
        (select unnest(member_ids) member_id, unnest(way_list) way, unnest(member_roles) member_role, unnest(member_directions) member_direction) ways
      where member_direction!='' order by distance asc limit 1;
      member_directions[i]=r.member_direction||'|'||r.member_id||'|'||cast(r.poi as text)||'|'||r.distance;
    end loop;
  end loop;

  return;
END;
$body$ language plpgsql;
