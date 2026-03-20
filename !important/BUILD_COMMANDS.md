# Build Commands

## Android (release APK)

```
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
  --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
  --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=anon-pro \
  --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
  --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
  --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
  --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
  --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
  --dart-define=ENABLE_ADMIN_TOOLS=false
```

## Android (release AAB)

```
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
  --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
  --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=anon-pro \
  --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
  --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
  --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
  --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
  --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
  --dart-define=ENABLE_ADMIN_TOOLS=false
```

## Web (release)

```
flutter build web --release \
  --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
  --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
  --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=anon-pro \
  --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
  --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
  --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
  --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
  --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
  --dart-define=ENABLE_ADMIN_TOOLS=false
```

## iOS (release, device)

```
flutter build ios --release \
  --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
  --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
  --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=anon-pro \
  --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
  --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
  --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
  --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
  --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
  --dart-define=ENABLE_ADMIN_TOOLS=false
```

## run

flutter run \
 --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
 --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
 --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
 --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
 --dart-define=FIREBASE_PROJECT_ID=anon-pro \
 --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
 --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
 --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
 --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
 --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
 --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
 --dart-define=ENABLE_ADMIN_TOOLS=false \
--dart-define=ADMIN_TERMINAL_PASSKEY=190308

flutter build apk --release \
 --dart-define=SUPABASE_URL=https://mnfbdrdmqromgfnqetzh.supabase.co \
 --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg \
 --dart-define=FIREBASE_API_KEY=AIzaSyAbYibHGg14y8A8Ag7ylsgR91PmMOooyHQ \
 --dart-define=FIREBASE_AUTH_DOMAIN=anon-pro.firebaseapp.com \
 --dart-define=FIREBASE_PROJECT_ID=anon-pro \
 --dart-define=FIREBASE_STORAGE_BUCKET=anon-pro.firebasestorage.app \
 --dart-define=FIREBASE_MESSAGING_SENDER_ID=616821146393 \
 --dart-define=FIREBASE_APP_ID=1:616821146393:web:22dd80de6f4e13fad63b88 \
 --dart-define=FIREBASE_WEB_VAPID_KEY=BDMT3Mz2SzdzwckTbxAo4VZ41DVyttT0-0SNDh8Lxu54ZVm2-aeyUKxm0d3jLz2XV6clx5i1gUyeC2aP43Ax9z0 \
 --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/bchbwqir6 \
 --dart-define=IMAGEKIT_PUBLIC_KEY=public_CdhxhG0EaHMaE5SkujBFCRzgRbA= \
 --dart-define=ENABLE_ADMIN_TOOLS=true \
 --dart-define=ADMIN_TERMINAL_PASSKEY=190308
