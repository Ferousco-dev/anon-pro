importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

const configRequest = fetch('/firebase-config.json', { cache: 'no-store' })
  .then((response) => (response.ok ? response.json() : null))
  .catch(() => null);

configRequest.then((config) => {
  if (!config) {
    return;
  }

  firebase.initializeApp(config);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const title = payload.notification?.title || 'AnonPro';
    const body = payload.notification?.body || '';
    const data = payload.data || {};

    self.registration.showNotification(title, {
      body,
      data,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
    });
  });
});
