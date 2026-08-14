// lib/presentation/pages/worker/raw_material_receiving_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/api_datasource.dart';
import '../../../data/models/inventory_summary_model.dart';
import '../../../data/models/inventory_model.dart';
import '../../../data/models/voucher_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reference_data_provider.dart';
import '../../../core/constants/app_constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Providers
// ──────────────────────────────────────────────────────────────────────────────

final _receivingInventoryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'receiving').toList();
});

// ──────────────────────────────────────────────────────────────────────────────
// شاشة استلام المواد الخام
// ──────────────────────────────────────────────────────────────────────────────

class RawMaterialReceivingPage extends ConsumerStatefulWidget {
  final List<InventorySummaryModel>? preSelectedMaterials;
  final String? sourceWarehouse;
  final String? title;

  const RawMaterialReceivingPage({
    super.key,
    this.preSelectedMaterials,
    this.sourceWarehouse,
    this.title,
  });

  @override
  ConsumerState<RawMaterialReceivingPage> createState() => _RawMaterialReceivingPageState();
}

class _RawMaterialReceivingPageState extends ConsumerState<RawMaterialReceivingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<InventorySummaryModel> _incomingMaterials = [];
  List<String> _confirmedMaterialIds = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    
    if (widget.preSelectedMaterials != null && widget.preSelectedMaterials!.isNotEmpty) {
      _incomingMaterials = widget.preSelectedMaterials!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم استلام ${_incomingMaterials.length} مادة من مخزن الخلاط'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_receivingInventoryProvider);
    ref.invalidate(inventorySummaryProvider);
    setState(() {});
  }

  String get _operatorName {
    final auth = ref.read(authProvider);
    return auth.user?.name ?? auth.user?.email ?? 'مدير الاستلام';
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasIncomingFromMixer = _incomingMaterials.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'استلام المواد الخام'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'قيد الاستلام'),
            Tab(icon: Icon(Icons.check_circle_outline), text: 'جاهز للاستخدام'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (hasIncomingFromMixer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.green.shade200),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم استلام ${_incomingMaterials.length} مادة من مخزن الخلاط',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _showReceivedMaterialsDialog(context);
                    },
                    child: const Text('عرض التفاصيل'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ReceivingInventoryTab(
                  onRefresh: _refresh,
                  preLoadedMaterials: _incomingMaterials,
                  confirmedIds: _confirmedMaterialIds,
                  onMaterialConfirmed: (materialId) {
                    setState(() {
                      _confirmedMaterialIds.add(materialId);
                    });
                    _tabs.animateTo(1);
                  },
                  showError: _showErrorSnackBar,
                  showSuccess: _showSuccessSnackBar,
                  operatorName: _operatorName,
                ),
                _ReadyForUseTab(
                  onRefresh: _refresh,
                  confirmedIds: _confirmedMaterialIds,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReceivedMaterialsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('المواد المستلمة من مخزن الخلاط'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'إجمالي: ${_incomingMaterials.length} مادة',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LimitedBox(
                maxHeight: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _incomingMaterials.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade50,
                      child: Icon(
                        Icons.science_outlined,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                    title: Text(
                      _incomingMaterials[i].materialName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_incomingMaterials[i].currentBalance.toStringAsFixed(2)} ${_incomingMaterials[i].unit}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب قيد الاستلام
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingInventoryTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  final List<InventorySummaryModel> preLoadedMaterials;
  final List<String> confirmedIds;
  final Function(String) onMaterialConfirmed;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;
  final String operatorName;

  const _ReceivingInventoryTab({
    required this.onRefresh,
    this.preLoadedMaterials = const [],
    this.confirmedIds = const [],
    required this.onMaterialConfirmed,
    required this.showError,
    required this.showSuccess,
    required this.operatorName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingInventoryProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل المخزون', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Text(e.toString(), style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (items) {
        final allItems = [...items, ...preLoadedMaterials];
        final uniqueItems = allItems.fold<List<InventorySummaryModel>>([], (list, item) {
          if (!list.any((m) => m.materialId == item.materialId)) {
            list.add(item);
          }
          return list;
        });

        if (uniqueItems.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد قيد الاستلام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('المواد تصل هنا من مخزن الخلاط',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        final total = uniqueItems.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard(
              title: 'إجمالي المواد قيد الاستلام',
              total: total,
              color: Colors.deepPurple,
              badge: preLoadedMaterials.isNotEmpty 
                ? '(${preLoadedMaterials.length} من الخلاط)' 
                : null,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: uniqueItems.length,
                itemBuilder: (ctx, i) => _buildMaterialCard(
                  uniqueItems[i], 
                  Colors.deepPurple,
                  isFromMixer: preLoadedMaterials.any((m) => m.materialId == uniqueItems[i].materialId),
                  isConfirmed: confirmedIds.contains(uniqueItems[i].materialId),
                  showConfirmButton: true,
                  onConfirm: () {
                    _confirmReceiving(context, ref, uniqueItems[i]);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmReceiving(BuildContext context, WidgetRef ref, InventorySummaryModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد استلام المادة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المادة: ${item.materialName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'الكمية: ${item.currentBalance.toStringAsFixed(2)} ${item.unit}',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تأكيد الاستلام يعني أن المادة أصبحت جاهزة للاستخدام في الإنتاج.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الاستلام', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final ds = ref.read(dataSourceProvider);
      
      // استخدام addInventoryTransaction لتسجيل حركة التأكيد
      await ds.addInventoryTransaction(InventoryTransactionModel(
        id: '',
        materialId: item.materialId,
        warehouseType: 'receiving',
        transactionType: 'confirm_receiving',
        quantity: item.currentBalance,
        createdBy: operatorName,
        notes: 'تأكيد استلام المادة - جاهزة للاستخدام',
        createdAt: DateTime.now(),
      ));

      ref.invalidate(_receivingInventoryProvider);
      ref.invalidate(inventorySummaryProvider);
      
      if (context.mounted) {
        showSuccess(context, '✅ تم تأكيد استلام ${item.materialName} وأصبحت جاهزة للاستخدام');
        onMaterialConfirmed(item.materialId);
      }
    } catch (e) {
      if (context.mounted) {
        showError(context, '❌ فشل تأكيد الاستلام: ${e.toString()}');
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب جاهز للاستخدام
// ──────────────────────────────────────────────────────────────────────────────

class _ReadyForUseTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  final List<String> confirmedIds;

  const _ReadyForUseTab({
    required this.onRefresh,
    this.confirmedIds = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingInventoryProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل المواد الجاهزة', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (items) {
        final confirmedItems = items.where((m) => confirmedIds.contains(m.materialId)).toList();
        
        if (confirmedItems.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد جاهزة للاستخدام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('المواد تظهر هنا بعد تأكيد استلامها',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        final total = confirmedItems.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard(
              title: 'إجمالي المواد الجاهزة للاستخدام',
              total: total,
              color: Colors.green,
              badge: '(${confirmedItems.length} مادة)',
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: confirmedItems.length,
                itemBuilder: (ctx, i) => _buildMaterialCard(
                  confirmedItems[i], 
                  Colors.green,
                  showReadyBadge: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// مكونات مساعدة
// ──────────────────────────────────────────────────────────────────────────────

Widget _buildSummaryCard({
  required String title,
  required double total,
  required MaterialColor color,
  String? badge,
}) {
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      children: [
        Icon(Icons.assignment_outlined, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold)),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const Spacer(),
        Text(
          '${total.toStringAsFixed(1)} كجم',
          style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  );
}

Widget _buildMaterialCard(
  InventorySummaryModel item,
  MaterialColor color, {
  bool isFromMixer = false,
  bool isConfirmed = false,
  bool showConfirmButton = false,
  VoidCallback? onConfirm,
  bool showReadyBadge = false,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Container(
      decoration: BoxDecoration(
        border: isFromMixer 
            ? Border.all(color: Colors.orange.shade300, width: 2)
            : showReadyBadge || isConfirmed
                ? Border.all(color: Colors.green.shade700, width: 2)
                : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isFromMixer 
              ? Colors.orange.shade100 
              : showReadyBadge || isConfirmed
                  ? Colors.green.shade100
                  : color.shade50,
          child: Icon(
            isFromMixer ? Icons.send : 
            showReadyBadge || isConfirmed ? Icons.check_circle : Icons.science_outlined,
            color: isFromMixer 
                ? Colors.orange.shade700 
                : showReadyBadge || isConfirmed
                    ? Colors.green.shade700
                    : color.shade700,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.materialName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isFromMixer && !isConfirmed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'من الخلاط',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (showReadyBadge || isConfirmed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'جاهز',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.currentBalance.toStringAsFixed(2)} ${item.unit}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: item.currentBalance <= 0 ? Colors.red : color.shade700,
              ),
            ),
            if (showConfirmButton && !isConfirmed) ...[
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(60, 30),
                ),
                onPressed: onConfirm,
                child: const Text(
                  'تأكيد',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
