import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../admin/warehouse/warehouse_manager_page.dart';

class WarehouseHomePage extends ConsumerWidget {
  const WarehouseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final keeperName =
        (auth.user?.name != null && auth.user!.name!.isNotEmpty)
            ? auth.user!.name!
            : auth.user?.email ?? 'أمين المخزن';

    return WarehouseManagerPage(keeperName: keeperName);
  }
}
