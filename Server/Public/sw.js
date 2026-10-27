// Cache the public application shell only. Account/API traffic and project data are excluded.
const FRONTSTAGE_SHELL = 'frontstage-shell-__FRONTSTAGE_BUILD__';
const ASSETS = ['/', '/index.html', '/app.js', '/merge.js', '/board-operations.js', '/story-timeline.js', '/config.js', '/style.css', '/workspace-design.js', '/workspace-design.css', '/workspace-model.js', '/workspaces.js', '/pagination.js', '/workspaces.css', '/screenplay-editor.js', '/dialogue-rules.js', '/scene-model.js', '/script-inclusion.js', '/continuous-script.js', '/live-markdown.js', '/write-panels.js', '/write-panel-model.js', '/script-filter.js', '/bamini.js'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(FRONTSTAGE_SHELL).then(cache => cache.addAll(ASSETS.map(url => new Request(url, { cache: 'reload' })))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('frontstage-shell-') && key !== FRONTSTAGE_SHELL).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || !ASSETS.includes(url.pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(FRONTSTAGE_SHELL);
    try {
      const response = await fetch(event.request, { cache: 'no-cache' });
      if (response.ok) await cache.put(url.pathname, response.clone()).catch(() => {});
      if (response.ok || !(await cache.match(url.pathname))) return response;
    } catch {}
    return await cache.match(url.pathname) || Response.error();
  })());
});
