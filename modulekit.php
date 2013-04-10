<?
$name="OpenStreetBrowser - Public Transport Overlay";

$id="overlay_pt";

$depend=array("hooks");

$default_include=array(
  "pgsql-functions"=>array("functions/*.sql", "functions.sql"),
  "pgsql-init"=>array("init.sql"),
  "pgsql-after-import"=>array("after-import.sql"),
  "php"=>array("inc/*.php", "backend.php"),
  "mcp"=>array("inc/*.php", "mcp.php"),
);

$include=$default_include;
