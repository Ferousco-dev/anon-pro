importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ',
  authDomain: 'anon-pro.firebaseapp.com',
  projectId: 'anon-pro',
  storageBucket: 'anon-pro.firebasestorage.app',
  messagingSenderId: '616821146393',
  appId: '1:616821146393:web:22dd80de6f4e13fad63b88',
  measurementId: 'G-H77B61HXYS',
});

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
