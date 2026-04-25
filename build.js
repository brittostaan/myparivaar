#!/usr/bin/env node

const fs = require('fs');
const { execSync } = require('child_process');

// Get environment variables
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const appEnv = process.env.APP_ENV;

console.log('Environment variables:');
console.log(`SUPABASE_ANON_KEY: ${supabaseAnonKey ? 'SET' : 'NOT SET'}`);
console.log(`APP_ENV: ${appEnv || 'NOT SET'}`);

if (!supabaseAnonKey) {
  console.error('ERROR: SUPABASE_ANON_KEY not set');
  process.exit(1);
}

// Build command
const buildCmd = `
git clone https://github.com/flutter/flutter.git --depth 1 -b stable /tmp/flutter && \
export PATH="/tmp/flutter/bin:$PATH" && \
flutter config --enable-web && \
flutter pub get && \
flutter build web --release \
  --dart-define=APP_ENV='${appEnv}' \
  --dart-define=SUPABASE_ANON_KEY='${supabaseAnonKey}'
`;

console.log('Running build...');
try {
  execSync(buildCmd, { stdio: 'inherit', shell: '/bin/bash' });
  console.log('Build completed successfully!');
} catch (error) {
  console.error('Build failed:', error.message);
  process.exit(1);
}
