# Security Configuration

## Supabase API Keys - Environment Variables

This project has been updated to remove hardcoded Supabase anonymous API keys from the source code. All sensitive credentials must now be provided at build time via environment variables.

### Building with Required Environment Variables

The following environment variable **MUST** be provided when building the Flutter app:

- `SUPABASE_ANON_KEY` - Your Supabase anonymous API key (required)

Optionally, you can also override:

- `SUPABASE_URL` - Your Supabase project URL (defaults to `https://qimqakfjryptyhxmrjsj.supabase.co`)

### Build Commands

#### Development/Web Build

```bash
flutter build web \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

#### Android Release Build

```bash
flutter build apk --release \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

#### iOS Release Build

```bash
flutter build ios --release \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

#### With Custom Supabase URL

```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

### Security Best Practices

1. **Never commit API keys to version control** - The `.gitignore` file excludes `.env.local` files

2. **Use environment-specific builds**:
   - Development builds can use development API keys
   - Production builds should use production API keys with appropriate RLS (Row Level Security) policies

3. **Verify at runtime** - If the environment variable is not provided at build time, the app will throw a clear error message before initialization:
   ```
   SUPABASE_ANON_KEY environment variable is not set. 
   Please provide it at compile time: 
   flutter build ... --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
   ```

4. **CI/CD Integration** - Update your build pipelines to securely inject these variables:
   - GitHub Actions: Use secrets management
   - Vercel: Use environment variables in project settings
   - Other platforms: Follow their secrets management documentation

### Files Updated

The following files have been updated to remove hardcoded keys and implement validation:

- `lib/main.dart` - Removed hardcoded key, added `_validateSupabaseConfig()` function
- `lib/services/expense_service.dart` - Added runtime validation for missing key
- `lib/services/email_service.dart` - Added runtime validation for missing key
- `.worktrees/devlabel/lib/main.dart` - Updated worktree for consistency

### Key Changes

**Before:**
```dart
const _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIs...',  // ❌ Hardcoded key exposed
);
```

**After:**
```dart
const _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'MISSING_SUPABASE_ANON_KEY',
);

void _validateSupabaseConfig() {
  if (_kSupabaseAnonKey == 'MISSING_SUPABASE_ANON_KEY') {
    throw Exception(
      'SUPABASE_ANON_KEY environment variable is not set. '
      'Please provide it at compile time: '
      'flutter build ... --dart-define=SUPABASE_ANON_KEY=<your-anon-key>'
    );
  }
}
```

### Troubleshooting

If you see the error "SUPABASE_ANON_KEY environment variable is not set":

1. Ensure you're using `--dart-define=SUPABASE_ANON_KEY=<value>` in your build command
2. Check that your Supabase project still exists and the key is valid
3. If using CI/CD, verify that secrets are correctly configured and passed to the build step

### Questions?

Refer to:
- [Flutter Dart Environment Configuration](https://flutter.dev/docs/development/build-configuration)
- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Flutter Plugin](https://pub.dev/packages/supabase_flutter)
