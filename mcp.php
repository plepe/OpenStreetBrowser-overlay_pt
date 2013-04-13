<?
function overlay_pt_compile($path) {
  copy("{$path}/overlay_pt.template", "{$path}/overlay_pt.mapnik");

  print "Compiled\n";
}

function overlay_pt_init($renderd) {
  $compile=false;

  $prefix=modulekit_file("overlay_pt", "overlay_pt", true);
  $path=modulekit_file("overlay_pt", "", true);

  if(!file_exists("$prefix.mapnik"))
    $compile=true;
  elseif(filesize("$prefix.mapnik")<1024)
    $compile=true;

  if($compile) {
    print "Recompiling\n";
    overlay_pt_compile($path);
  }

  $renderd['overlay_pt']=array("file"=>"$prefix.mapnik");
}

register_hook("renderd_get_maps", "overlay_pt_init");
