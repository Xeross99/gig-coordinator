// Gig Coordinator service worker

const HTML_CACHE  = "gig-coordinator-html-v1";
const ASSET_CACHE = "gig-coordinator-assets-v1";

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop any stale cache buckets from previous SW versions.
    const names = await caches.keys();
    const alive = new Set([ HTML_CACHE, ASSET_CACHE ]);
    await Promise.all(names.filter((n) => !alive.has(n)).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

async function invalidateHtml() {
  await caches.delete(HTML_CACHE);
}

// Decide whether a response is safe to cache as HTML. We skip redirects so that
// the signed-in → signed-out boundary doesn't poison the cache with a login
// redirect cached under `/`.
function isCacheableHtml(response) {
  return response.ok &&
         !response.redirected &&
         (response.headers.get("content-type") || "").includes("text/html");
}

function isAssetPath(pathname) {
  return pathname.startsWith("/assets/") ||
         pathname === "/manifest" ||
         pathname.startsWith("/icon") ||
         pathname.startsWith("/favicon") ||
         pathname.startsWith("/apple-touch-icon") ||
         /\.(png|jpg|jpeg|webp|svg|ico|woff2?|css|js)$/.test(pathname);
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);

  // Only intercept same-origin traffic. Third-party (Google Maps tiles, fonts)
  // passes straight to the network.
  if (url.origin !== self.location.origin) return;

  // Session-mutating endpoints: let the request through, but wipe the HTML
  // cache on success so the next navigation fetches fresh, auth-aware pages.
  const mutatesSession = request.method === "POST" && (
    url.pathname === "/sesja" ||
    url.pathname.startsWith("/logowanie") ||
    url.pathname === "/kody-logowania"
  );
  if (mutatesSession || (request.method === "DELETE" && url.pathname === "/sesja")) {
    event.respondWith((async () => {
      const response = await fetch(request);
      if (response.ok || response.redirected) await invalidateHtml();
      return response;
    })());
    return;
  }

  // Everything below is GET-only.
  if (request.method !== "GET") return;

  // Static assets — cache-first, refresh in the background. Digest-fingerprinted
  // paths under /assets never go stale; other icons/manifest rarely change.
  if (isAssetPath(url.pathname)) {
    event.respondWith((async () => {
      const cache = await caches.open(ASSET_CACHE);
      const cached = await cache.match(request);
      if (cached) {
        // Kick a background refresh. Swallow errors — we still have the cached copy.
        fetch(request).then((r) => { if (r.ok) cache.put(request, r.clone()); }).catch(() => {});
        return cached;
      }
      const response = await fetch(request);
      if (response.ok) cache.put(request, response.clone());
      return response;
    })());
    return;
  }

  // HTML navigations — stale-while-revalidate. Serve cached shell instantly
  // (makes the app feel "native" on cold starts), then update cache in the
  // background. Turbo Streams over the cable deliver live data over the top.
  const acceptsHtml = (request.headers.get("accept") || "").includes("text/html");
  if (request.mode === "navigate" || acceptsHtml) {
    event.respondWith((async () => {
      const cache = await caches.open(HTML_CACHE);
      const cached = await cache.match(request);
      const networkPromise = fetch(request).then((response) => {
        if (isCacheableHtml(response)) cache.put(request, response.clone());
        return response;
      }).catch(() => cached);
      return cached || networkPromise;
    })());
  }
});

self.addEventListener("push", (event) => {
  let payload = { title: "Gig Coordinator", body: "" };
  try { payload = event.data ? event.data.json() : payload; } catch (_) {
    payload.body = event.data ? event.data.text() : "";
  }
  const { title, body, url } = payload;
  event.waitUntil(
    self.registration.showNotification(title || "Gig Coordinator", {
      body: body || "",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      data: { url: url || "/" }
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window" }).then((clientsArr) => {
      for (const c of clientsArr) {
        if (c.url.includes(url)) { return c.focus(); }
      }
      return self.clients.openWindow(url);
    })
  );
});
