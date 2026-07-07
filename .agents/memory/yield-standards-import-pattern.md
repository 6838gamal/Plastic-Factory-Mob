---
name: Yield Standards pages import pattern
description: dataSourceProvider is in auth_provider.dart; pages using ConsumerStatefulWidget must import auth_provider.dart to access it.
---

# dataSourceProvider import location

`dataSourceProvider` is defined in `lib/presentation/providers/auth_provider.dart`, NOT in api_datasource.dart or reference_data_provider.dart.

**Why:** New pages that call `ref.read(dataSourceProvider)` will fail to compile with "Undefined name 'dataSourceProvider'" if they only import `api_datasource.dart`. They must also import `auth_provider.dart`.

**How to apply:** Any new ConsumerStatefulWidget page that needs to call API methods directly via `ref.read(dataSourceProvider)` must import:
```dart
import '../../../providers/auth_provider.dart';
```

# production_standards.id UUID type cast

`production_standards.id` is UUID. `machine_production.standard_id` is VARCHAR. When querying by standard_id (passed as Python `str`), use explicit `$1::uuid` cast in asyncpg queries to avoid type binding errors.

**Why:** asyncpg does NOT auto-cast str→UUID for parameterized queries on UUID columns. Silent failure (exception caught and returns None) means yield stats and alerts silently don't trigger.

**How to apply:** `WHERE id=$1::uuid` whenever joining/filtering on UUID PK from a VARCHAR FK column passed as Python str.
