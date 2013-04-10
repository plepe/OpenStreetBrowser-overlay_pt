<?
function overlay_pt_init($renderd) {
  $prefix=modulekit_file("overlay_pt", "overlay_pt", true);

  $renderd['overlay_pt']=array("file"=>"$prefix.mapnik");
}

register_hook("renderd_get_maps", "overlay_pt_init");
