// Gig Coordinator service worker
//
// HTML caching used to be stale-while-revalidate for faster cold starts, but
// it caused stale data across contexts (new users not appearing in lists,
// online dots out of sync between roster + feed, etc.). HTML now always
// hits the network. Only fingerprinted static assets (CSS/JS/icons/fonts)
// stay cached — those can't go stale.

const ASSET_CACHE = "chicken-assets-v1";

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop any stale buckets — including the old `chicken-html-v1` that
    // existing installs still have on disk from the previous SW version.
    const names = await caches.keys();
    const alive = new Set([ ASSET_CACHE ]);
    await Promise.all(names.filter((n) => !alive.has(n)).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

// Digestowane assety zmieniają nazwę przy każdym deployu, a starych wpisów
// nikt nie usuwa — bez limitu cache rośnie w nieskończoność. Cap + kasowanie
// od najstarszych (Cache API zwraca klucze w kolejności insertów).
const ASSET_CACHE_MAX_ENTRIES = 150;

async function trimCache(cache) {
  const keys = await cache.keys();
  if (keys.length <= ASSET_CACHE_MAX_ENTRIES) return;
  for (const key of keys.slice(0, keys.length - ASSET_CACHE_MAX_ENTRIES)) {
    await cache.delete(key);
  }
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
      if (response.ok) {
        await cache.put(request, response.clone());
        trimCache(cache).catch(() => {});
      }
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
  const { title, body, url, tag } = payload;
  event.waitUntil(
    self.registration.showNotification(title || "Gig Coordinator", {
      body: body || "",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      data: { url: url || "/" },
      // Payload z `tag` skleja powiadomienia: nowsze zastępuje starsze o tym
      // samym tagu (np. seria edycji zlecenia), `renotify` dalej daje sygnał.
      ...(tag ? { tag, renotify: true } : {})
    })
  );
});

// Push service zrotował subskrypcję (wygasła / odnowiona przez przeglądarkę).
// Rejestrujemy nową i od razu zgłaszamy ją serwerowi, a starą kasujemy —
// bez tego stary endpoint zostaje w bazie jako zombie (serwer wysyła z
// sukcesem, telefon nic nie pokazuje). Cookie sesji idzie z fetchem
// automatycznie (same-origin); bez zalogowanej sesji serwer odpowie 401
// i po prostu nic się nie zmieni.
self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil((async () => {
    const old = event.oldSubscription;
    const options = old?.options ?? { userVisibleOnly: true };
    const sub = await self.registration.pushManager.subscribe(options);
    const json = sub.toJSON();

    await fetch("/subskrypcje-push", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        push_subscription: {
          endpoint: sub.endpoint,
          p256dh_key: json.keys.p256dh,
          auth_key: json.keys.auth
        }
      })
    });

    if (old && old.endpoint !== sub.endpoint) {
      await fetch("/subskrypcje-push/rotated", {
        method: "DELETE",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ push_subscription: { endpoint: old.endpoint } })
      });
    }
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil((async () => {
    // Preferuj już otwarte okno apki: fokus + nawigacja do celu. openWindow
    // tylko gdy żadnego okna nie ma — inaczej Android potrafi otworzyć
    // drugą instancję zamiast użyć tej, w której user właśnie siedzi.
    // includeUncontrolled łapie też kartę załadowaną przed rejestracją SW.
    const clientsArr = await self.clients.matchAll({ type: "window", includeUncontrolled: true });

    const exact = clientsArr.find((c) => new URL(c.url).pathname === url);
    if (exact) return exact.focus();

    const open = clientsArr[0];
    if (open) {
      await open.focus();
      try { return await open.navigate(url); } catch (_) { return self.clients.openWindow(url); }
    }

    return self.clients.openWindow(url);
  })());
});
