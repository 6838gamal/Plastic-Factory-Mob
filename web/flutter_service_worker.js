'use strict';
// Network-only service worker — no caching.
// On activate: delete ALL old caches so stale files are never served.
self.addEventListener('install', (e) => { self.skipWaiting(); });
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', (e) => {
  e.respondWith(fetch(e.request));
});
