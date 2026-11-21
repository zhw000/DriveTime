# DriveTime AMap Cloudflare Worker

This Worker is the only component that knows the AMap **Web Service API Key**.
The iOS app calls the Worker and never stores or ships that key.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/health` | Proxy configuration health. Never returns secrets. |
| `GET` | `/v1/route/driving` | Proxies AMap Route Planning 2.0 driving; fixed `show_fields`. |
| `GET` | `/v1/places/text` | Proxies AMap POI 2.0 keyword search; returns a whitelist of POI fields. |

The route endpoint forwards the genuine AMap status/route payload so DriveTime
can parse the documented v5 field types. It does **not** invent routes, ETA,
tolls or traffic. Provider errors are returned as `{ error: { code, message } }`
with a non-2xx status. The app must display an error rather than a fabricated
route.

## 1. Prerequisites

- A Cloudflare account (free plan is enough for evaluation).
- An AMap **Web Service API** key. This is not the iOS SDK key.
  - https://console.amap.com/dev/key/app
  - Create an app, add a **Web 服务** key.
  - AMap may require real-name/enterprise verification depending on quota.
- Node.js 20+ and npm.

## 2. Install and deploy

```bash
cd backend/cloudflare-worker
npm install
npx wrangler login
npx wrangler secret put AMAP_KEY
# Strongly recommended: protect your proxy from unauthorised use.
npx wrangler secret put PROXY_ACCESS_TOKEN
npx wrangler deploy
```

Wrangler prints a URL such as:

```
https://drivetime-amap-proxy.<your-subdomain>.workers.dev
```

Enter this URL in **DriveTime → 设置 → 高德路线代理**, plus the same
`PROXY_ACCESS_TOKEN` if you set one. The token is stored in the iOS Keychain,
not in `UserDefaults` and not in this repository. It is a proxy access token,
not the AMap key.

Test the Worker directly:

```bash
curl -s "https://YOUR-WORKER.workers.dev/v1/health"
```

A configured Worker returns JSON with `"configured": true`. The health endpoint
deliberately does not consume AMap quota to probe the key; the first real route
query validates it. `provider_reachable` is therefore `false`/informational.

## 3. Optional persistent rate limiting

Without a KV binding the Worker uses a best-effort in-memory limiter per
Cloudflare isolate. For a more durable per-IP limit:

```bash
npx wrangler kv namespace create DRIVETIME_RATE_LIMIT
```

Uncomment the `[[kv_namespaces]]` block in `wrangler.toml` and fill in the
returned id, then redeploy. The default limit is 20 route/place calls per IP per
minute; change `RATE_LIMIT_PER_MINUTE` in `wrangler.toml` if needed.

The **only** correct place to store the AMap key is a Worker secret. Never put it
in `wrangler.toml`, a `.dev.vars` file committed to Git, the iOS app, or GitHub
Actions logs.

## 4. What the Worker does not do

- It does not use the AMap iOS SDK, so there is no Bundle ID ↔ SDK key binding
  for this integration. Changing the signed IPA's Bundle ID does not break the
  Web API proxy.
- It does not implement a proxy for Apple MapKit; that is called directly by
  iOS and requires no API key.
- It does not cache traffic results; stale ETA data must not be presented as
  live data.
- It does not claim future-departure traffic prediction. AMap's driving v5
  endpoint used here has no departure-time/prediction parameter.
