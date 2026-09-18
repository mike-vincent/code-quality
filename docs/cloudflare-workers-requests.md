# Cloudflare Workers request billing (guards)

Workers Static Assets are free when the asset layer answers without invoking
the Worker. `run_worker_first = true` (blanket) makes every asset hit a
Workers request and has driven real overages. Prefer `false`, or a selective
path array so only HTML/API run the Worker.

A second Worker that proxies www/apex to `app` (the retired
`radioindex-edge-shield` pattern) double-bills: the proxy request plus the
bound `app` fetch. Route public hosts only to `app`. Zone transform rules
may still set HSTS/XFO/etc.; CSP / Referrer-Policy / COOP belong on `app`
(or `_headers` for static), not on a front-door proxy.

Guards: `guard-cloudflare-assets.sh`, `guard-edge-shield.sh` (wired in
`hook-pre-tool.sh`).
