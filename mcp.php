<?
// symbol are characters from the Unicode "Transport and Map Symbols" plane
// we use the font 'Symbola Regular' (from http://users.teilar.gr/~g1951d/) to
// display them
$overlay_pt_route_types=array(
  'train'       =>array(
    'color'     =>"000000",
    'symbol'    =>"🚆",
  ),
  'subway'       =>array(
    'color'     =>"0000AA",
    'symbol'    =>"🚇",
  ),
  'monorail'       =>array(
    'color'     =>"0000FF",
    'symbol'    =>"🚝",
  ),
  'lightrail'       =>array(
    'color'     =>"ff0000",
    'symbol'    =>"🚈",
  ),
  'tram/bus'       =>array(
    'color'     =>"ff3300",
    'symbol'    =>"🚋🚌",
  ),
  'tram'       =>array(
    'color'     =>"ff0000",
    'symbol'    =>"🚋",
  ),
  'trolleybus'       =>array(
    'color'     =>"000000",
    'symbol'    =>"🚎",
  ),
  'bus'       =>array(
    'color'     =>"ff5500",
    'symbol'    =>"🚌",
  ),
  'ferry'       =>array(
    'color'     =>"00ffff",
    'symbol'    =>"🚢",
  ),
  'aerialway'       =>array(
    'color'     =>"aa00ff",
    'symbol'    =>"🚡",
  ),
  'share_taxi'       =>array(
    'color'     =>"ffff00",
    'symbol'    =>"🚖",
  ),
);

function overlay_pt_replacement() {
  global $overlay_pt_route_types;
  global $tmp_dir;

  $ret=array();

  $ret['%ROUTE_TYPES_IN%']="('".implode("', '", array_keys($overlay_pt_route_types))."')";
  $ret['%TMP_DIR%']=$tmp_dir;

  return $ret;
}

function dom_tr($node, $repl) {
  if($node->nodeType==XML_TEXT_NODE) {
    $node->nodeValue=strtr($node->nodeValue, $repl);
  }
  elseif($node->nodeType==XML_ELEMENT_NODE && $node->attributes) {
    for($i=0; $i<$node->attributes->length; $i++) {
      $attribute=$node->attributes->item($i)->nodeName;

      $node->setAttribute(
        $attribute,
        strtr($node->getAttribute($attribute), $repl)
      );
    }
  }

  $curr=$node->firstChild;
  while($curr) {
    dom_tr($curr, $repl);

    $curr=$curr->nextSibling;
  }
}

function overlay_pt_compile($path) {
  $repl=overlay_pt_replacement();
  $content=file_get_contents("{$path}/overlay_pt.template");
  $dom=new DOMDocument();
  $dom->loadXML($content);

  $parameters=$dom->getElementsByTagName("Parameter");
  for($i=0; $i<$parameters->length; $i++) {
    $parameter=$parameters->item($i);

    if($parameter->getAttribute("name")=="table") {
      $text=$parameter->firstChild->textContent;
      $parameter->removeChild($parameter->firstChild);

      $text=strtr($text, $repl);

      $parameter->appendChild($dom->createTextNode($text));
    }
  }

  $rules=$dom->getElementsByTagName("Rule");
  $to_do=array();

  for($i=0; $i<$rules->length; $i++) {
    $rule=$rules->item($i);

    if($rule->getAttribute("template"))
      $to_do[]=$rule;
  }

  foreach($to_do as $rule) {
    $def=$rule->getAttribute("template");

    global $$def;

    $parent=$rule->parentNode;
    $parent->removeChild($rule);
    $rule_template=$rule;

    foreach($$def as $k=>$values) {
      print "* $k\n";
      $rule=$rule_template->cloneNode(true);

      $rule_repl=overlay_pt_replacement();
      $rule_repl["%KEY%"]=$k;
      foreach($values as $vk=>$vv)
        $rule_repl["%VALUE:{$vk}%"]=$vv;

      dom_tr($rule, $rule_repl);

      $parent->appendChild($rule);
    }
  }

  global $tmp_dir;
  $d=opendir("{$path}/img/");
  while($f=readdir($d)) {
    if(preg_match("/^(.*)\.(svg)$/", $f, $m)) {
      $file_name_base=$m[1];

      $content=file_get_contents("{$path}/img/{$f}");
      foreach($overlay_pt_route_types as $k=>$v) {
        $color=$v['color'];

        file_put_contents("{$tmp_dir}/{$file_name_base}_{$color}.svg",
          strtr($content, array("123456"=>$color)));
        system("convert -background none {$tmp_dir}/{$file_name_base}_{$color}.svg {$tmp_dir}/{$file_name_base}_{$color}.png");
      }
    }
  }
  closedir($d);

  file_put_contents("{$path}/overlay_pt.mapnik", $dom->saveXML());

  print "Compiled\n";
}

function overlay_pt_init($renderd) {
  $compile=false;
  global $db_central;
  global $overlay_pt_route_types;

  // check overlay_pt file
  $prefix=modulekit_file("overlay_pt", "overlay_pt", true);
  $path=modulekit_file("overlay_pt", "", true);

  if(!file_exists("$prefix.mapnik"))
    $compile=true;
  elseif(filesize("$prefix.mapnik")<1024)
    $compile=true;

  if($compile) {
    // re-populate overlay_pt_route_types table
    sql_query("delete from overlay_pt_route_types", $db_central);
    foreach($overlay_pt_route_types as $id=>$v) {
      $h=array_to_hstore($v);
      sql_query("insert into overlay_pt_route_types values ('{$id}', {$h})", $db_central);
    }

    // re-compile stylesheet
    print "Recompiling\n";
    overlay_pt_compile($path);
  }

  $renderd['overlay_pt']=array("file"=>"$prefix.mapnik");
}

register_hook("renderd_get_maps", "overlay_pt_init");
