<?
$route_types_way=array(
  'train'       =>array(
    'color'     =>"#000000",
  ),
  'subway'       =>array(
    'color'     =>"#0000AA",
  ),
  'monorail'       =>array(
    'color'     =>"#0000FF",
  ),
  'lightrail'       =>array(
    'color'     =>"#ff0000",
  ),
  'tram/bus'       =>array(
    'color'     =>"#ff3300",
  ),
  'tram'       =>array(
    'color'     =>"#ff0000",
  ),
  'trolleybus'       =>array(
    'color'     =>"#000000",
  ),
  'bus'       =>array(
    'color'     =>"#ff5500",
  ),
  'ferry'       =>array(
    'color'     =>"#00ffff",
  ),
  'aerialway'       =>array(
    'color'     =>"#aa00ff",
  ),
  'share_taxi'       =>array(
    'color'     =>"#ffff00",
  ),
);

function overlay_pt_replacement() {
  global $route_types_way;

  $ret=array();

  $ret['%ROUTE_TYPES_IN%']="('".implode("', '", array_keys($route_types_way))."')";

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

      $rule_repl=array();
      $rule_repl["%KEY%"]=$k;
      foreach($values as $vk=>$vv)
        $rule_repl["%VALUE:{$vk}%"]=$vv;

      dom_tr($rule, $rule_repl);

      $parent->appendChild($rule);
    }
  }

  file_put_contents("{$path}/overlay_pt.mapnik", $dom->saveXML());

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
