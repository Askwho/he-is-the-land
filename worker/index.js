// he-is-the-land worker
// - Serves the Quartz site from static assets (everything not matched below).
// - /audio/<key>   : streams podcast MP3s from R2 with HTTP Range support.
// - /upload/<key>  : PUT with "Authorization: Bearer <UPLOAD_TOKEN>" stores a new
//                    episode in R2 (used by publish.ps1 when a new session lands).

const AUDIO_TYPES = { mp3: "audio/mpeg", m4a: "audio/mp4" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/audio/")) {
      return serveAudio(request, env, decodeURIComponent(url.pathname.slice("/audio/".length)));
    }

    if (url.pathname.startsWith("/upload/")) {
      return handleUpload(request, env, decodeURIComponent(url.pathname.slice("/upload/".length)));
    }

    return env.ASSETS.fetch(request);
  },
};

function audioHeaders(object, key) {
  const ext = key.split(".").pop().toLowerCase();
  const headers = new Headers();
  headers.set("Content-Type", AUDIO_TYPES[ext] || "application/octet-stream");
  headers.set("Accept-Ranges", "bytes");
  headers.set("ETag", object.httpEtag);
  headers.set("Cache-Control", "public, max-age=86400");
  headers.set("Access-Control-Allow-Origin", "*");
  return headers;
}

async function serveAudio(request, env, key) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  if (!key) return new Response("Not found", { status: 404 });

  // HEAD: metadata only.
  if (request.method === "HEAD") {
    const head = await env.MEDIA.head(key);
    if (!head) return new Response("Not found", { status: 404 });
    const headers = audioHeaders(head, key);
    headers.set("Content-Length", String(head.size));
    return new Response(null, { status: 200, headers });
  }

  const rangeHeader = request.headers.get("range");
  let object;
  try {
    object = await env.MEDIA.get(key, rangeHeader ? { range: request.headers } : undefined);
  } catch {
    // Unsatisfiable/malformed range.
    const head = await env.MEDIA.head(key);
    if (!head) return new Response("Not found", { status: 404 });
    return new Response("Range not satisfiable", {
      status: 416,
      headers: { "Content-Range": `bytes */${head.size}` },
    });
  }
  if (!object) return new Response("Not found", { status: 404 });

  const headers = audioHeaders(object, key);

  if (object.range) {
    const start = object.range.offset ?? 0;
    const length = object.range.length ?? object.size - start;
    const end = start + length - 1;
    headers.set("Content-Range", `bytes ${start}-${end}/${object.size}`);
    headers.set("Content-Length", String(length));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { status: 200, headers });
}

async function handleUpload(request, env, key) {
  if (request.method !== "PUT") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "PUT" } });
  }
  const auth = request.headers.get("authorization") || "";
  if (!env.UPLOAD_TOKEN || auth !== `Bearer ${env.UPLOAD_TOKEN}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  if (!key) return new Response("Missing key", { status: 400 });
  const object = await env.MEDIA.put(key, request.body);
  return Response.json({ ok: true, key: object.key, size: object.size, etag: object.httpEtag });
}
