---
name: Stray precompiled artifacts in Flutter web/ source dir
description: Flutter web/ source folder had committed build OUTPUT files (main.dart.js, canvaskit/, assets/, etc.) that silently shadowed every fresh compile.
---

`flutter build web` copies everything under the source `web/` directory into `build/web/` in addition to compiling `lib/`. If a stale build artifact (e.g. `main.dart.js`, `.last_build_id`, `canvaskit/`, `assets/`, `version.json`, `flutter_service_worker.js`, `flutter.js`, `flutter_bootstrap.js`) is committed inside `web/` itself (not `build/web/`), it gets copied over the freshly compiled output — so code edits appear to have zero effect no matter how many times you rebuild, with no compiler error or warning.

**Why:** These got committed into `web/` at some point (likely an old build output copied into the wrong directory during project import), and every subsequent `flutter build web` silently re-shadowed the real compiled `main.dart.js` with that stale copy. Confirmed by editing distinct/unique marker strings and rebuilding repeatedly — they never appeared in the served bundle until the stray files were deleted.

**How to apply:** If Dart code changes don't seem to take effect after a clean `flutter build web` (verified via `flutter analyze` passing and file mtimes updating), check for build-output files committed directly under the source `web/` folder — only `index.html`, `manifest.json`, `favicon.png`, and `icons/` should normally be hand-maintained source there. Everything else Flutter regenerates and none of it belongs under version control in `web/`.
