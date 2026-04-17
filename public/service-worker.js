// Gig Coordinator service worker

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
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
