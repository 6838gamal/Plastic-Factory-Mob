---
name: FutureProvider.family Map key infinite loop
description: Map<String,dynamic> as a Riverpod family parameter has no structural equality — causes infinite rebuild/loading loop in Flutter web.
---

# Problem
`FutureProvider.family<T, Map<String, dynamic>>` with keys like `{'from': _from, 'to': _to}` creates a **new provider instance on every widget rebuild** because Dart Maps compare by reference. Each new instance starts in `loading` state → widget rebuilds → new Map → new provider → infinite loop. Symptoms: screens never leave shimmer/loading, and the server log shows the same API endpoint hammered every ~1 second.

# Fix
Replace `Map<String, dynamic>` with a typed `@immutable` class that implements `==` and `hashCode`:

```dart
@immutable
class BatchFilters {
  final DateTime? from;
  final DateTime? to;
  const BatchFilters({this.from, this.to});

  @override
  bool operator ==(Object other) =>
      other is BatchFilters && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
```

**Why:** Riverpod family caches provider instances by parameter equality. Without structural equality, every call creates a new uncached provider starting in loading state.

**How to apply:** Any time `FutureProvider.family` or `StateNotifierProvider.family` is used with a collection (Map, List) as the key, replace with a typed class. Dart records `(T1, T2)` also work since Dart 3 — they have structural equality built in.

# Files affected in this project
- `lib/presentation/providers/batch_provider.dart` — defines `BatchFilters`, `ProductionFilters`, `AlertFilters`
- `batches_admin_page.dart`, `production_page.dart`, `alerts_page.dart`, `admin_dashboard_page.dart`, `reports_page.dart` — updated to use typed filters
