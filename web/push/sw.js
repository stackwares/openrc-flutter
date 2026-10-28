// OpenRC push service worker. The web app registers it (as push/sw.js, so its
// scope stays clear of Flutter's own worker) to receive notifications from
// Firebase Cloud Messaging while no tab is open. It shows each one; the
// default tap opens the sale, and “Ask” jumps to Ask.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    // Not JSON: show a generic notification rather than none.
  }
  const notification = payload.notification || {};
  const data = payload.data || {};
  const transaction = data.transaction_id || null;
  event.waitUntil(
    self.registration.showNotification(notification.title || 'OpenRC', {
      body: notification.body || '',
      // The project's icon, when the notifier sent one, so a push reads as
      // belonging to that project rather than to OpenRC at large.
      icon: notification.image || '/icons/Icon-192.png',
      badge: '/icons/Icon-maskable-192.png',
      // A retried webhook replaces its notification instead of adding one.
      tag: data.event_id || payload.fcmMessageId || undefined,
      data: { transaction },
      actions: transaction
        ? [
            { action: 'open', title: 'Open' },
            { action: 'ask', title: 'Ask' },
          ]
        : [],
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const transaction = (event.notification.data || {}).transaction || null;
  const ask = event.action === 'ask';
  const url = new URL('/', self.location.origin);
  if (transaction) url.searchParams.set('transaction', transaction);
  if (ask) url.searchParams.set('ask', '1');
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      const open = windows.find((w) => new URL(w.url).origin === self.location.origin);
      if (open) {
        await open.focus();
        open.postMessage({ type: 'openrc-push-open', transaction, ask });
        return;
      }
      await self.clients.openWindow(url.href);
    })(),
  );
});
