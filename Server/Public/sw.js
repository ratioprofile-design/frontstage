// Cache the public application shell only. Account/API traffic and project data are excluded.
const FRONTSTAGE_SHELL = 'frontstage-shell-__FRONTSTAGE_BUILD__';
const ASSETS = ["/", "/index.html", "/app.js", "/merge.js", "/board-operations.js", "/story-timeline.js", "/config.js", "/style.css", "/workspace-design.js", "/workspace-design.css", "/workspace-model.js", "/script-typography.js", "/script-annotations.js", "/script-context-menu.js", "/typography-preferences.js", "/feature-compatibility.js", "/dual-dialogue.js", "/screenplay-interchange.js", "/board-drawing.js", "/production-revision.js", "/workspaces.js", "/pagination.js", "/workspaces.css", "/screenplay-editor.js", "/dialogue-rules.js", "/scene-model.js", "/script-inclusion.js", "/continuous-script.js", "/live-markdown.js", "/write-panels.js", "/write-panel-model.js", "/script-filter.js", "/bamini.js", "/brand/apple-touch-icon.png", "/brand/favicon-16.png", "/brand/favicon-32.png", "/brand/icon-dark-192.png", "/brand/icon-dark-512.png", "/brand/icon-dark-64.png", "/brand/icon-light-192.png", "/brand/icon-light-512.png", "/brand/icon-light-64.png", "/brand/maskable-dark-512.png", "/brand/maskable-light-512.png", "/brand/wordmark-dark.png", "/brand/wordmark-light.png", "/brand/social-card.png", "/branding.css", "/branding.js", "/favicon.ico", "/manifest-dark.json", "/manifest-light.json", "/project-files.js"];
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
