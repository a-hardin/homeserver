<?php
$CONFIG = array (
  'htaccess.RewriteBase' => '/',
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'apps_paths' => 
  array (
    0 => 
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps',
      'writable' => false,
    ),
    1 => 
    array (
      'path' => '/var/www/html/custom_apps',
      'url' => '/custom_apps',
      'writable' => true,
    ),
  ),
  'upgrade.disable-web' => true,
  'instanceid' => 'ocfxooald6pl',
  'passwordsalt' => '6hIqfreriQv5oCx0T45JVJ50epcvPJ',
  'secret' => 'vHPpL/1B1OrXczbMW5ty0wxNmiATet8Ps28MQA5EuUfKhN4w',
  'trusted_domains' => 
  array (
    0 => '192.168.4.201:8082',
    1 => 'localhost',
    2 => '10.13.13.1',
  ),
  'datadirectory' => '/var/www/html/data',
  'dbtype' => 'mysql',
  'version' => '32.0.3.2',
  'overwrite.cli.url' => 'http://192.168.4.201:8082',
  'dbname' => 'nWPK5aNg1NbQRGWS6BRQ',
  'dbhost' => 'db:3306',
  'dbtableprefix' => 'oc_',
  'mysql.utf8mb4' => true,
  'dbuser' => 'lYwTUtjHThF8EBCwkjeB',
  'dbpassword' => 'mAXM2QuaTNKCmhDim9C6',
  'installed' => true,
  'maintenance' => false,
  'enabledPreviewProviders' => 
  array (
    'OC\Preview\Movie',
    'OC\Preview\PNG',
    'OC\Preview\JPEG',
    'OC\Preview\GIF',
    'OC\Preview\BMP',
    'OC\Preview\XBitmap',
    'OC\Preview\MP4',
    'OC\Preview\TXT',
    'OC\Preview\MarkDown'
  ),
);