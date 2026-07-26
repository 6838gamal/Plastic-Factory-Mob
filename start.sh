#!/usr/bin/env bash
# Rebuild the Flutter web frontend on every start, then serve it via the backend.
# Only the build output (build/web) is removed — .dart_tool cache is preserved
# so incremental builds are faster and external builds are not affected.
set -e

cd "$(dirname "$0")"

echo "🔨 Rebuilding Flutter web app from source..."
flutter build web --release

echo "🚀 Starting backend server..."
cd backend
exec uv run uvicorn main:app --host 0.0.0.0 --port 5000
