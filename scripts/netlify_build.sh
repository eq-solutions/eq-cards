#!/bin/bash
# Netlify CI build script for EQ Cards (Flutter web).
#
# Netlify caches $HOME between builds, so Flutter is only cloned on the
# first build — subsequent builds reuse the cached SDK (~30s vs ~3min).
#
# Required Netlify environment variables (set in Site → Environment variables):
#   SUPABASE_URL         e.g. https://xyzxyz.supabase.co
#   SUPABASE_ANON_KEY    public anon key
#   SENTRY_DSN           https://...@sentry.io/...
#   POSTHOG_API_KEY      phc_...
#   POSTHOG_HOST         https://eu.i.posthog.com
set -euo pipefail

FLUTTER_DIR="$HOME/.flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "==> Flutter not cached — cloning stable..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
else
  echo "==> Flutter cached at $FLUTTER_DIR"
fi

export PATH="$PATH:$FLUTTER_DIR/bin"

flutter --version
flutter pub get
dart run build_runner build --delete-conflicting-outputs

flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=POSTHOG_API_KEY="$POSTHOG_API_KEY" \
  --dart-define=POSTHOG_HOST="$POSTHOG_HOST"

echo "==> Build complete: build/web"
