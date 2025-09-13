# FocusdBot AI Proxy (Cloudflare Workers)

Minimal proxy that accepts session payloads from the mac app, calls OpenAI, and stores a summary.

## Endpoints

- POST `/v1/summary` → `{ jobId }` (202). Body: compact session payload. Auth: optional `x-client-secret` header.
- GET `/v1/summary/:jobId` → `{ id, status, summary?, error? }`.

## Deploy

1. Install deps and wrangler

```
npm i --prefix proxy
npm i -g wrangler
```

2. Create KV

```
wrangler kv:namespace create SUMMARIES
# copy the id to wrangler.toml as KV_NAMESPACE_ID
```

3. Secrets

```
wrangler secret put OPENAI_API_KEY
wrangler secret put CLIENT_SECRET   # optional
```

4. Publish

```
cd proxy
wrangler publish
```

## Configure the app

Set environment variables on the Mac:

```
launchctl setenv FOCUSD_PROXY_URL "https://<your-worker>.workers.dev/v1/summary"
# If you set CLIENT_SECRET
launchctl setenv FOCUSD_CLIENT_SECRET "<same-secret>"
```

## Notes

- The Worker uses KV for job state and `waitUntil` to run the OpenAI call async.
- Add quotas and more auth as needed.


