importScripts('https://www.gstatic.com/firebasejs/10.11.0/firebase-app.js');
importScripts('https://www.gstatic.com/firebasejs/10.11.0/firebase-messaging.js');

// Initialize Firebase
firebase.initializeApp({
  apiKey: 'AIzaSyBEbmn_0exN-9rbmzMISDdJDFrSzxL7Zy0',
  authDomain: 'vision-mate-9793c.firebaseapp.com',
  projectId: 'vision-mate-9793c',
  storageBucket: 'vision-mate-9793c.firebasestorage.app',
  messagingSenderId: '56982087061',
  appId: '1:56982087061:web:c49f521b2431693eec029c',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = 'Background Message Title';
  const notificationOptions = {
    body: 'Background Message body.',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});