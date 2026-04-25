// Cloudflare Worker: proxy bar-rts demo storage with CORS headers, so the
// browser viewer can `fetch()` a .sdfz directly without OVH CORS support.
//
// Deploy:
//   wrangler init bar-demo-proxy
//   (paste this as src/index.js)
//   wrangler deploy
// Then point the viewer at https://<your-worker>.workers.dev/<demoFileName>
//
// 100k requests/day on the free tier is plenty for hobby use.

const STORAGE = "https://storage.uk.cloud.ovh.net/v1/AUTH_10286efc0d334efd917d476d7183232e/BAR/demos/";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Range, Content-Type",
  "Access-Control-Expose-Headers": "Content-Length, Content-Range, ETag, Last-Modified",
};

export default {
  async fetch(req) {
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(req.url);
    // Strip leading slash, treat the rest as the demo filename.
    const fname = decodeURIComponent(url.pathname.replace(/^\//, ""));
    if (!fname.endsWith(".sdfz")) {
      return new Response("only .sdfz under /<filename>", { status: 400, headers: CORS });
    }

    const upstream = STORAGE + encodeURIComponent(fname);
    const upstreamReq = new Request(upstream, {
      method:  req.method,
      headers: { "Range": req.headers.get("Range") || "" },
    });
    const r = await fetch(upstreamReq);
    const h = new Headers(r.headers);
    Object.entries(CORS).forEach(([k, v]) => h.set(k, v));
    return new Response(r.body, { status: r.status, headers: h });
  },
};
