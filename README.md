# myparivaar

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Building the App

### Prerequisites

Before building, ensure you have the Supabase API key and URL:

1. Go to your [Supabase project settings](https://app.supabase.com)
2. Get your project's:
   - `SUPABASE_URL` (e.g., `https://your-project.supabase.co`)
   - `SUPABASE_ANON_KEY` (your anonymous API key)

### Build Commands

The app requires the `SUPABASE_ANON_KEY` environment variable to be set at build time:

```bash
flutter build web \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

For more details and build options, see [SECURITY.md](./SECURITY.md).
