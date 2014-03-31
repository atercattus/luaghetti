luaghetti
=========

Spaghetti html+lua code templater inside nginx

Example:
```html
<?lml tmpl:include('sugar') ?>
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>Now <?lml print(ngx.utctime()) ?></title>
</head>
<body>
<?lml local alc = require('lib.alc') ?>
Hi, <?lml print(esc(req:get('name', 'traveler')), '/', ngx.var.remote_addr) ?>.
It has <?lml print(alc:inc('cnt')) ?>th request since the server is restarted.

<?lml
    local hdrs = {}
    for k,v in pairs(ngx.req.get_headers()) do
        table.insert(hdrs, '<tr><td style="font-weight:bold;">'..esc(k)..'</td><td>'..esc(v)..'</td></tr>')
    end
?>

<h3>Headers of <?lml print(ngx.req.get_method()) ?>th request to <?lml print(esc(ngx.var.request_uri)) ?></h3>
<table><?lml print(hdrs) ?></table>

<?lml include('footer') ?>
```

Enjoy :)
