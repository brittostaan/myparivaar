#!/bin/bash
set -e

echo "Starting Flutter build..."
echo "SUPABASE_ANON_KEY is set: ${SUPABASE_ANON_KEY:+yes}"
echo "APP_ENV is set: ${APP_ENV:+yes}"

git clone https://github.com/flutter/flutter.git --depth 1 -b stable /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"
flutter config --enable-web
flutter pub get

echo "Building Flutter web..."
flutter build web --release \
  --dart-define=APP_ENV=${APP_ENV} \
  --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}

echo "Build completed successfully!"

