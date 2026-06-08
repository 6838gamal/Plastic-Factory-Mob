---
name: GoRouter + Riverpod auth redirect
description: How to make GoRouter re-evaluate its redirect when Riverpod auth state changes, without recreating the router instance.
---

## The rule

Never use `ref.watch(authProvider)` inside `routerProvider` and return a new `GoRouter(...)` — recreating the router resets navigation to `initialLocation` and the redirect doesn't fire reliably.

**Why:** When `MaterialApp.router(routerConfig: router)` receives a new GoRouter instance, Flutter disposes the old one and mounts the fresh one starting from `initialLocation`. The redirect may not fire on the initial route of the new instance, leaving the user stuck on the wrong screen.

## How to apply

Use a `ChangeNotifier` + `refreshListenable` pattern:

```dart
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final _authRefreshProvider = ChangeNotifierProvider<_AuthRefreshNotifier>(
  (ref) => _AuthRefreshNotifier(ref),
);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authRefreshProvider); // keeps it alive
  return GoRouter(
    initialLocation: '/worker',
    refreshListenable: notifier,           // triggers redirect on auth change
    redirect: (context, state) {
      final isAdmin = ref.read(authProvider).isAdmin; // ref.read — not watch
      ...
    },
    routes: [...],
  );
});
```

The GoRouter is created **once**. When auth changes, `notifier.notifyListeners()` fires, GoRouter re-runs `redirect`, and routes to the correct destination without resetting navigation history.
