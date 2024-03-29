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

create type overlay_pt_route as (
  id        text,
  tags      hstore,
  way       geometry,
  member_ids        text[],
  member_roles      text[],
  member_directions text[]
);
-- for stops return:
-- direction|way_id|point on way|distance from way
-- e.g. F|W26576395|0101000020E6100000DA50DBFFF7403040A7DE0612061B4840|4.88234030285617e-05
-- 'point on way' is the closest point on the way to the stop
CREATE OR REPLACE FUNCTION overlay_pt_get_route(
  IN bbox       geometry,
  IN rel_id     text,
  IN options    hstore default ''::hstore
)
RETURNS SETOF overlay_pt_route
AS $body$
#variable_conflict use_variable
DECLARE
  rel           osm_rel%rowtype;
  ret           overlay_pt_route;
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
  angle         float;
  angle_p       float;
  angle_n       float;
  line_900913   geometry;
  poi_900913    geometry;
  pos_900913    float;
  pos_p_900913  float;
  pos_n_900913  float;
  mode          int;
    -- 0.. unknown
    -- 1.. old PT scheme
    -- 2.. OXOMOA PT scheme
BEGIN
  -- raise notice 'overlay_pt_get_route(%)', rel_id;
  ret:=cast(cache_search(rel_id, 'overlay_pt_get_route') as overlay_pt_route);
  if ret is not null then
    return next ret;
    return;
  end if;

  -- get full relation
  rel:=osm_rel(bbox, 'id='||quote_nullable(rel_id));

  -- initialize return values
  ret.id=rel.id;
  ret.tags:=rel.tags;
  ret.way:=rel.way;
  ret.member_ids=rel.member_ids;
  ret.member_roles=rel.member_roles;
  ret.member_directions=array_fill(''::text, Array[array_upper(rel.member_ids, 1)]);
  way_list=array_fill(null::geometry, Array[array_upper(rel.member_ids, 1)]);

  -- check mode
  if ret.tags?'from' or ret.tags?'to' then
    mode=2;
    ret.tags=ret.tags || '#overlay_pt_mode=>oxomoa'::hstore;
  else
    mode=1;
    ret.tags=ret.tags || '#overlay_pt_mode=>public_transport'::hstore;
  end if;

  -- assess route
  length:=ST_Length(Geography(ret.way));
  ret.tags=ret.tags||('#overlay_pt_importance=>'||(CASE
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
      select * from osm_line(rel.way, 'id='||quote_nullable(member_id))
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
        ret.member_directions[i]=r.direction;

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
        ret.member_directions[i]=r.direction;

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
    ret.member_directions[i_curr]=r.direction;
  elsif has_curr then
    r=_overlay_pt_decide_direction(
        way_curr.way,
        null,
        null,
        rel.member_roles[i_curr],
        mode
      );
    ret.member_directions[i_curr]=r.direction;
  end if;

  -- no iterate again for all stops to get their direction
  i:=0;
  foreach member_id in array rel.member_ids loop
    i=i+1;
    for way_curr in -- returns only one row!
      select * from osm_point(rel.way, 'id='||quote_nullable(member_id))
    loop

      select  ways.member_direction, ways.member_id, ST_Line_Interpolate_Point(ways.way, ST_Line_Locate_Point(ways.way, way_curr.way)) poi, ST_Distance(ways.way, way_curr.way) distance, ways.way into r from
        (select unnest(ret.member_ids) member_id, unnest(way_list) way, unnest(ret.member_roles) member_role, unnest(ret.member_directions) member_direction) ways
      where member_direction!='' order by distance asc limit 1;

      -- find angle of stop
      line_900913=ST_Transform(r.way, 900913);
      poi_900913=ST_Transform(r.poi, 900913);
      pos_900913=ST_Line_Locate_Point(line_900913, poi_900913);
      poi_900913=ST_Line_Interpolate_Point(line_900913, pos_900913);
      length:=ST_Length(line_900913);
      pos_p_900913:=pos_900913-0.001/length;

      angle_p:=null;
      if pos_p_900913>=0 then
        angle_p:=ST_Azimuth(line_interpolate_point(line_900913, pos_p_900913), poi_900913);
      end if;

      angle_n:=null;
      pos_n_900913:=pos_900913+0.001/length;
      if pos_n_900913<=1 then
        angle_n:=ST_Azimuth(poi_900913, line_interpolate_point(line_900913, pos_n_900913));
      end if;

      if angle_p is not null and angle_n is not null then
        angle=angle_p+(angle_n-angle_p)/2;
      elsif angle_p is not null then
        angle=angle_p;
      elsif angle_n is not null then
        angle=angle_n;
      else
        angle=0;
      end if;

      ret.member_directions[i]=r.member_direction||'|'||r.member_id||'|'||cast(r.poi as text)||'|'||r.distance||'|'||angle;
    end loop;
  end loop;

  perform cache_insert(rel_id, 'overlay_pt_get_route', cast(ret as text), rel.member_ids);
  return next ret;
  return;
END;
$body$ language plpgsql;
