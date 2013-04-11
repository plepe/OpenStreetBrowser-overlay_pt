CREATE OR REPLACE FUNCTION _overlay_pt_decide_direction(
  IN way        geometry,
  IN way_prev   geometry,
  IN way_next   geometry,
  IN role       text,
  IN mode       int,
  OUT direction text,
  OUT valid     bool
) AS $body$
#variable_conflict use_variable
DECLARE
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
    -- TODO
  end if;
END;
$body$ language plpgsql;

CREATE OR REPLACE FUNCTION overlay_pt_get_route(
  IN bbox       geometry,
  IN rel_id     text,
  OUT tags      hstore,
  OUT member_directions text[]
) AS $body$
#variable_conflict use_variable
DECLARE
  rel           osm_rel%rowtype;
  r             record;
  i             int;
  member_id     text;
  way_prev      record;
  has_prev      bool:=false;
  way_next      record;
  way           record;
  has_way       bool:=false;
  length        float:=0;
  mode          int;
    -- 0.. unknown
    -- 1.. old PT scheme
    -- 2.. OXOMOA PT scheme
BEGIN
  -- get full reltion
  rel:=osm_rel(bbox, 'id='||quote_nullable(rel_id));

  -- initialize return values
  tags:=rel.tags;
  member_directions=array_fill(''::text, Array[array_upper(rel.member_ids, 1)]);

  -- check mode
  if tags?'from' or tags?'to' then
    mode=2;
    tags=tags || '#overlay_pt_mode=>oxomoa'::hstore;
  else
    mode=1;
    tags=tags || '#overlay_pt_mode=>public_transport'::hstore;
  end if;

  -- iterate over all ways
  i:=0; -- the for always acquires the next way, i points to current
  foreach member_id in array rel.member_ids loop
    for way_next in -- returns only one row!
      select * from osm_linepoly(rel.way, 'id='||quote_nullable(member_id))
    loop
      -- call _overlay_pt_decide_direction always for the previous way
      if has_prev then
        r=_overlay_pt_decide_direction(
            way.way,
            way_prev.way,
            way_next.way,
            rel.member_roles[i],
            mode
          );
        member_directions[i]=r.direction;

        if(r.valid) then
          way_prev=way;
          way=way_next;
        end if;
      elsif has_way then
        r=_overlay_pt_decide_direction(
            way.way,
            null,
            way_next.way,
            rel.member_roles[i],
            mode
          );
        member_directions[i]=r.direction;

        if(r.valid) then
          has_prev=true;
          way_prev=way;
          way=way_next;
        end if;
      else
        has_way=true;
        way=way_next;
      end if;
    end loop;

    i=i+1;
  end loop;

  -- also call _overlay_pt_decide_direction for the last member way
  if has_prev then
    r=_overlay_pt_decide_direction(
        way.way,
        way_prev.way,
        null, 
        rel.member_roles[i],
        mode
      );
    member_directions[i]=r.direction;
  elsif has_way then
    r=_overlay_pt_decide_direction(
        way.way,
        null,
        null,
        rel.member_roles[i],
        mode
      );
    member_directions[i]=r.direction;
  end if;

  return;
END;
$body$ language plpgsql;
