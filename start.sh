#!/usr/bin/env bash
# Always wipe any cached Flutter build artifacts and rebuild the web
# frontend from scratch before starting the backend server.
set -e

cd "$(dirname "$0")"

echo "🧹 Cleaning old Flutter build cache..."
flutter clean
rm -rf build/web .dart_tool

echo "🔨 Rebuilding Flutter web app from source..."
flutter build web --release --dart-define=API_BASE_URL=https://plastic-factory-api-backend.onrender.com

echo "🚀 Starting backend server..."
cd backend
exec uv run uvicorn main:app --host 0.0.0.0 --port 5000
