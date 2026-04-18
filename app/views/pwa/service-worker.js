// Gig Coordinator service worker
//
// HTML caching used to be stale-while-revalidate for faster cold starts, but
// it caused stale data across contexts (new users not appearing in lists,
// online dots out of sync between roster + feed, etc.). HTML now always
// hits the network. Only fingerprinted static assets (CSS/JS/icons/fonts)
// stay cached — those can't go stale.

const ASSET_CACHE = "gig-coordinator-assets-v1";

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop any stale buckets — including the old `gig-coordinator-html-v1` that
    // existing installs still have on disk from the previous SW version.
    const names = await caches.keys();
    const alive = new Set([ ASSET_CACHE ]);
    await Promise.all(names.filter((n) => !alive.has(n)).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

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

  // Only intercept same-origin GETs. Everything else (POSTs, third-party
  // Google Maps tiles, etc.) goes straight to the network untouched.
  if (url.origin !== self.location.origin) return;
  if (request.method !== "GET") return;

  // Static assets — cache-first with a background refresh. Digested paths
  // under /assets never change; other icons/manifest rarely do.
  if (isAssetPath(url.pathname)) {
    event.respondWith((async () => {
      const cache = await caches.open(ASSET_CACHE);
      const cached = await cache.match(request);
      if (cached) {
        fetch(request).then((r) => { if (r.ok) cache.put(request, r.clone()); }).catch(() => {});
        return cached;
      }
      const response = await fetch(request);
      if (response.ok) cache.put(request, response.clone());
      return response;
    })());
    return;
  }

  // HTML + everything else: pass through to the network. No SW caching, so
  // the page is always authoritative and Turbo Streams + presence dots stay
  // consistent with the server.
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
