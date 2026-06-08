#!/bin/bash
# Build Flutter web app with Supabase credentials
# This script is called by the deployment workflow

set -e

echo "Building Flutter web app..."

# Build with Supabase env vars if available
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

echo "Build complete! Output: build/web"
