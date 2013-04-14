create table overlay_pt_route_types (
  id            text    not null,
  tags          hstore  not null default ''::hstore,
  primary key(id)
);
