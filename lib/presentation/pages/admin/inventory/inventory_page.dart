import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/inventory_model.dart';
import '../../../../data/models/inventory_summary_model.dart';
import '../../../../data/models/voucher_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/reference_data_provider.dart'
    show inventorySummaryProvider, allRawMaterialsAsSummaryProvider, rawMaterialsProvider;
import '../../../../core/constants/app_constants.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';
import '../../worker/raw_material_receiving_page.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _txProvider = FutureProvider.autoDispose.family<List<InventoryTransactionModel>, String>(
  (ref, materialId) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getInventoryTransactions(
        materialId: materialId.isEmpty ? null : materialId);
  },
);

final _stagingIncomingVouchersProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'main_to_staging');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

final _stagingOutgoingVouchersProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'staging_to_mixer');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

// ── Main Page ─────────────────────────────────────────────────────────────────

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  static const _tabMain = 0;
  static const _tabMixer = 1;
  static const _tabStaging = 2;
  static const _tabTx = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _activeWarehouse {
    if (_tabController.index == _tabMixer) return AppConstants.warehouseMixer;
    if (_tabController.index == _tabStaging) return 'staging';
    return AppConstants.warehouseMain;
  }

  @override
  Widget build(BuildContext context) {
    final isTransactionsTab = _tabController.index == _tabTx;
    final isStagingTab = _tabController.index == _tabStaging;

    final pendingIncoming = ref
            .watch(_stagingIncomingVouchersProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(icon: Icon(Icons.warehouse_outlined), text: 'الرئيسي'),
              const Tab(icon: Icon(Icons.blender_outlined), text: 'الخلاط'),
              Tab(
                icon: Badge(
                  isLabelVisible: pendingIncoming > 0,
                  label: Text('$pendingIncoming'),
                  child: const Icon(Icons.swap_horiz),
                ),
                text: 'المرحلي',
              ),
              const Tab(icon: Icon(Icons.history), text: 'الحركات'),
            ],
          ),

          if (!isTransactionsTab)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SearchBar(
                hintText: 'بحث عن مادة...',
                leading: const Icon(Icons.search),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _WarehouseTab(
                  warehouse: AppConstants.warehouseMain,
                  search: _search,
                  color: Colors.blue,
                  icon: Icons.warehouse_outlined,
                  label: 'المخزن الرئيسي',
                ),
                _WarehouseTab(
                  warehouse: AppConstants.warehouseMixer,
                  search: _search,
                  color: Colors.teal,
                  icon: Icons.blender_outlined,
                  label: 'مخزن الخلاط',
                ),
                _StagingTab(
                  search: _search,
                  onRefresh: () {
                    ref.invalidate(_stagingIncomingVouchersProvider);
                    ref.invalidate(_stagingOutgoingVouchersProvider);
                    ref.invalidate(inventorySummaryProvider);
                  },
                ),
                _TransactionsTab(search: _search),
              ],
            ),
          ),
        ],
      ),

      floatingActionButton: isTransactionsTab
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showActionDialog(context),
              icon: const Icon(Icons.add),
              label: Text(
                _tabController.index == _tabMixer
                    ? 'حركة — الخلاط'
                    : _tabController.index == _tabStaging
                        ? 'إجراء — المرحلي'
                        : 'حركة — رئيسي',
              ),
              backgroundColor: _tabController.index == _tabMixer
                  ? Colors.teal
                  : _tabController.index == _tabStaging
                      ? Colors.deepOrange
                      : Colors.blue,
            ),
    );
  }

  // ── Action bottom sheet ──────────────────────────────────────────────────

  void _showActionDialog(BuildContext context) {
    final isMain    = _tabController.index == _tabMain;
    final isMixer   = _tabController.index == _tabMixer;
    final isStaging = _tabController.index == _tabStaging;

    if (isStaging) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, color: Colors.deepOrange, size: 20),
                  const SizedBox(width: 8),
                  const Text('إجراءات المخزن المرحلي',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.deepOrange)),
                ],
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.deepOrange.shade300, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'الرئيسي  →  المرحلي  →  الخلاط',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.arrow_downward, color: Colors.white)),
                title: const Text('طلب تحويل من الرئيسي'),
                subtitle: const Text('إنشاء سند نقل مواد من المخزن الرئيسي إلى المرحلي'),
                onTap: () {
                  Navigator.pop(context);
                  _openStagingVoucherDialog(context, 'main_to_staging');
                },
              ),
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: const Icon(Icons.arrow_upward, color: Colors.white)),
                title: const Text('إرسال للخلاط'),
                subtitle: const Text('إنشاء سند نقل مواد من المرحلي إلى مخزن الخلاط'),
                onTap: () {
                  Navigator.pop(context);
                  _openStagingVoucherDialog(context, 'staging_to_mixer');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    final color = isMain ? Colors.blue : Colors.teal;
    final warehouseLabel = isMain ? 'المخزن الرئيسي' : 'مخزن الخلاط';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text('إضافة حركة — $warehouseLabel',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: color)),
                ],
              ),
              const Divider(),
              
              if (isMain) ...[
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.add_circle_outline, color: Colors.white)),
                  title: const Text('استلام وارد'),
                  subtitle: const Text('إضافة مواد خام جديدة للمخزون'),
                  onTap: () {
                    Navigator.pop(context);
                    _showInventoryDialog(context,
                        title: 'استلام وارد',
                        transactionType: 'in',
                        positiveOnly: true,
                        icon: Icons.add_circle_outline,
                        iconColor: Colors.green,
                        defaultWarehouse: _activeWarehouse);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: const Icon(Icons.tune, color: Colors.white)),
                  title: const Text('تسوية يدوية'),
                  subtitle: const Text('تعديل الرصيد يدوياً (زيادة أو نقصان)'),
                  onTap: () {
                    Navigator.pop(context);
                    _showInventoryDialog(context,
                        title: 'تسوية يدوية',
                        transactionType: 'adjustment',
                        positiveOnly: false,
                        icon: Icons.tune,
                        iconColor: Colors.orange,
                        defaultWarehouse: _activeWarehouse);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.playlist_add_check, color: Colors.white)),
                  title: const Text('رصيد افتتاحي'),
                  subtitle: const Text('تسجيل الرصيد الافتتاحي لمادة'),
                  onTap: () {
                    Navigator.pop(context);
                    _showOpeningBalanceDialog(context,
                        defaultWarehouse: _activeWarehouse);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      child: const Icon(Icons.swap_horiz, color: Colors.white)),
                  title: const Text('تحويل للمرحلي'),
                  subtitle: const Text('إنشاء سند نقل مواد من الرئيسي إلى المخزن المرحلي'),
                  onTap: () {
                    Navigator.pop(context);
                    _openStagingVoucherDialog(context, 'main_to_staging');
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple,
                      child: const Icon(Icons.undo, color: Colors.white)),
                  title: const Text('إلغاء تحويل من المرحلي'),
                  subtitle: const Text('إرجاع مواد من المخزن المرحلي إلى الرئيسي'),
                  onTap: () {
                    Navigator.pop(context);
                    _showTransferDialog(context,
                        fromWarehouse: 'staging',
                        toWarehouse: AppConstants.warehouseMain);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.red.shade700,
                      child: const Icon(Icons.exposure_zero, color: Colors.white)),
                  title: const Text('تصفير بيانات مادة'),
                  subtitle: const Text('إعادة كل تفاصيل المادة إلى صفر'),
                  onTap: () {
                    Navigator.pop(context);
                    _showResetBalanceDialog(context, defaultWarehouse: _activeWarehouse);
                  },
                ),
              ] 
              
              else if (isMixer) ...[
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.send, color: Colors.white)),
                  title: const Text('استلام وارد'),
                  subtitle: const Text('إنشاء سند استلام من مخزن الخلاط'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateReceivingVoucherDialog(context);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: const Icon(Icons.tune, color: Colors.white)),
                  title: const Text('تسوية يدوية'),
                  subtitle: const Text('تعديل الرصيد يدوياً (زيادة أو نقصان)'),
                  onTap: () {
                    Navigator.pop(context);
                    _showInventoryDialog(context,
                        title: 'تسوية يدوية',
                        transactionType: 'adjustment',
                        positiveOnly: false,
                        icon: Icons.tune,
                        iconColor: Colors.orange,
                        defaultWarehouse: _activeWarehouse);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.playlist_add_check, color: Colors.white)),
                  title: const Text('رصيد افتتاحي'),
                  subtitle: const Text('تسجيل الرصيد الافتتاحي لمادة'),
                  onTap: () {
                    Navigator.pop(context);
                    _showOpeningBalanceDialog(context,
                        defaultWarehouse: _activeWarehouse);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: const Icon(Icons.arrow_upward, color: Colors.white)),
                  title: const Text('سحب من المرحلي'),
                  subtitle: const Text('نقل مواد من المخزن المرحلي إلى الخلاط'),
                  onTap: () {
                    Navigator.pop(context);
                    _openStagingVoucherDialog(context, 'staging_to_mixer');
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Colors.red.shade700,
                      child: const Icon(Icons.exposure_zero, color: Colors.white)),
                  title: const Text('تصفير بيانات مادة'),
                  subtitle: const Text('إعادة كل تفاصيل المادة إلى صفر'),
                  onTap: () {
                    Navigator.pop(context);
                    _showResetBalanceDialog(context, defaultWarehouse: _activeWarehouse);
                  },
                ),
              ],
              
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── حوار إنشاء سند استلام من مخزن الخلاط (مثل بقية النوافذ - مادة واحدة) ──
  void _showCreateReceivingVoucherDialog(BuildContext context) {
    final summaryAsync = ref.read(inventorySummaryProvider);
    final allItems = summaryAsync.value ?? [];
    
    final mixerMaterials = allItems
        .where((item) => item.warehouseType == AppConstants.warehouseMixer)
        .toList();

    if (mixerMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد مواد في مخزن الخلاط لإرسالها'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _CreateReceivingVoucherDialog(
        materials: mixerMaterials,
        onConfirm: (selectedMaterial, quantity) async {
          try {
            final ds = ref.read(dataSourceProvider);
            final authState = ref.read(authProvider);
            final operatorName = authState.user?.name ?? authState.user?.email ?? 'مدير';

            await ds.createTransferVoucher({
              'notes': 'طلب استلام من مخزن الخلاط',
              'created_by': operatorName,
              'transfer_type': 'mixer_to_receiving',
              'items': [
                {
                  'material_name': selectedMaterial.materialName,
                  'unit': selectedMaterial.unit,
                  'requested_qty': quantity,
                  'material_id': selectedMaterial.materialId,
                }
              ],
            });

            ref.invalidate(inventorySummaryProvider);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ تم إنشاء سند الاستلام بنجاح (بانتظار الاستلام)'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ فشل إنشاء السند: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  // ── Open staging voucher dialog ───────────────────────────────

  Future<void> _openStagingVoucherDialog(
      BuildContext context, String transferType) async {
    final authState = ref.read(authProvider);
    final operatorName =
        authState.user?.name ?? authState.user?.email ?? 'مدير';
    await showDialog(
      context: context,
      builder: (_) => _StagingVoucherDialog(
        transferType: transferType,
        createdBy: operatorName,
        onSaved: () {
          ref.invalidate(_stagingIncomingVouchersProvider);
          ref.invalidate(_stagingOutgoingVouchersProvider);
          ref.invalidate(inventorySummaryProvider);
        },
      ),
    );
  }

  // ── Reset Balance Dialog ─────────────────────────────────────────────────

  Future<void> _showResetBalanceDialog(BuildContext context,
      {required String defaultWarehouse}) async {
    final summaryAsync = ref.read(inventorySummaryProvider);
    final all = summaryAsync.value ?? [];
    final seen = <String>{};
    final materials = all
        .where((m) => seen.add(m.materialId))
        .toList();

    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد مواد في المخزن.')));
      return;
    }

    InventorySummaryModel? selected = materials.first;
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(children: [
            Icon(Icons.exposure_zero, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('تصفير بيانات مادة'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<InventorySummaryModel>(
                value: selected,
                decoration: const InputDecoration(labelText: 'المادة الخام'),
                items: materials
                    .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text('${m.materialName} — ${Helpers.formatQuantityInKg(m.currentBalance, m.unit)}')))
                    .toList(),
                onChanged: (v) => ss(() => selected = v),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم تصفير كل تفاصيل هذه المادة في المخزن الرئيسي والمخزن المرحلي ومخزن الخلاط معاً إلى صفر: الرصيد الحالي، إجمالي الوارد، إجمالي المنصرف، التحويلات، التسويات، والرصيد الافتتاحي. هذا الإجراء لا يمكن التراجع عنه.',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: confirmed,
                title: const Text('أؤكد تصفير كل بيانات هذه المادة', style: TextStyle(fontSize: 13)),
                onChanged: (v) => ss(() => confirmed = v ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: !confirmed || selected == null ? null : () async {
                try {
                  final ds = ref.read(dataSourceProvider);
                  final authState = ref.read(authProvider);
                  final email = authState.user?.email ?? 'admin';
                  await ds.resetMaterialBothWarehouses(
                    selected!.materialId,
                    createdBy: email,
                  );
                  ref.invalidate(inventorySummaryProvider);
                  ref.invalidate(_txProvider(''));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('تم تصفير كل بيانات ${selected!.materialName} في المخازن الثلاثة (الرئيسي، المرحلي، الخلاط)'),
                        backgroundColor: Colors.red.shade700));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('تصفير', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Receive / Adjustment Dialog ──────────────────────────────────────────

  Future<void> _showInventoryDialog(
    BuildContext context, {
    required String title,
    required String transactionType,
    required bool positiveOnly,
    required IconData icon,
    required Color iconColor,
    required String defaultWarehouse,
  }) async {
    final summaryAsync = ref.read(allRawMaterialsAsSummaryProvider);
    final all = summaryAsync.value ?? [];
    final materials = all.where((m) => m.warehouseType == defaultWarehouse).toList();

    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'لا توجد مواد خام. أضف مواداً من صفحة المواد الخام أولاً.')));
      return;
    }

    InventorySummaryModel? selected = materials.first;
    String warehouse = defaultWarehouse;
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isPositive = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Text(title),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventorySummaryModel>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'المادة الخام'),
                  items: materials
                      .map((m) => DropdownMenuItem(
                          value: m,
                          child: Row(
                            children: [
                              Expanded(child: Text(m.materialName)),
                              Text(
                                Helpers.formatQuantityInKg(m.currentBalance, m.unit),
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 11),
                              ),
                            ],
                          )))
                      .toList(),
                  onChanged: (v) => ss(() => selected = v),
                ),
                const SizedBox(height: 12),
                if (!positiveOnly) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('زيادة (+)'),
                          selected: isPositive,
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) => ss(() => isPositive = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('نقصان (-)'),
                          selected: !isPositive,
                          selectedColor: Colors.red.shade100,
                          onSelected: (_) => ss(() => isPositive = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => ss(() {}),
                  decoration: InputDecoration(
                    labelText: 'الكمية (${selected?.unit ?? 'كجم'})',
                    prefixIcon: Icon(
                      positiveOnly || isPositive ? Icons.add : Icons.remove,
                      color:
                          positiveOnly || isPositive ? Colors.green : Colors.red,
                    ),
                    helperText: selected != null
                        ? 'الرصيد الحالي: ${Helpers.formatQuantityInKg(selected!.currentBalance, selected!.unit)}'
                            '${positiveOnly && (double.tryParse(qtyCtrl.text) ?? 0) > 0 ? '  ←  بعد الاستلام: ${Helpers.formatQuantityInKg(selected!.currentBalance + (double.tryParse(qtyCtrl.text) ?? 0), selected!.unit)}' : ''}'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: iconColor),
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text);
                if (qty == null || qty <= 0 || selected == null) return;
                final ds = ref.read(dataSourceProvider);
                try {
                  await ds.addInventoryTransaction(InventoryTransactionModel(
                    id: '',
                    materialId: selected!.materialId,
                    warehouseType: warehouse,
                    transactionType: transactionType,
                    quantity: qty,
                    createdBy: 'admin',
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    createdAt: DateTime.now(),
                  ));
                  ref.invalidate(inventorySummaryProvider);
                  ref.invalidate(_txProvider(''));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('تم تسجيل $title بنجاح')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Transfer Dialog ──────────────────────────────────────────────────────

  Future<void> _showTransferDialog(BuildContext context,
      {required String fromWarehouse, required String toWarehouse}) async {
    final summaryAsync = ref.read(inventorySummaryProvider);
    final all = summaryAsync.value ?? [];
    final materials = all.where((m) => m.warehouseType == fromWarehouse).toList();

    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد مواد خام في المخزن المصدر.')));
      return;
    }

    String _whLabel(String w) => w == 'main'
        ? 'المخزن الرئيسي'
        : w == 'mixer'
            ? 'مخزن الخلاط'
            : 'المخزن المرحلي';
    final fromLabel = _whLabel(fromWarehouse);
    final toLabel   = _whLabel(toWarehouse);

    InventorySummaryModel? selected = materials.first;
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.compare_arrows, color: Colors.purple),
            SizedBox(width: 8),
            Text('تحويل بين المخازن'),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(fromLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 16,
                          color: Colors.purple),
                      const SizedBox(width: 8),
                      Text(toLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InventorySummaryModel>(
                  value: selected,
                  decoration: const InputDecoration(
                    labelText: 'المادة الخام',
                    prefixIcon: Icon(Icons.science_outlined),
                  ),
                  items: materials
                      .map((m) => DropdownMenuItem(
                          value: m,
                          child: Row(
                            children: [
                              Expanded(child: Text(m.materialName)),
                              Text(
                                Helpers.formatQuantityInKg(m.currentBalance, m.unit),
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 11),
                              ),
                            ],
                          )))
                      .toList(),
                  onChanged: (v) => ss(() => selected = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية المحوّلة (${selected?.unit ?? 'كجم'})',
                    prefixIcon: const Icon(Icons.compare_arrows,
                        color: Colors.purple),
                    helperText: selected != null
                        ? 'المتاح: ${Helpers.formatQuantityInKg(selected!.currentBalance, selected!.unit)}'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton.icon(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              icon: const Icon(Icons.compare_arrows, color: Colors.white),
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text);
                if (qty == null || qty <= 0 || selected == null) return;
                if (qty > selected!.currentBalance) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content:
                          Text('الكمية أكبر من الرصيد المتاح'),
                      backgroundColor: Colors.red));
                  return;
                }
                final ds = ref.read(dataSourceProvider);
                final authState = ref.read(authProvider);
                try {
                  await ds.transferInventory(
                    materialId: selected!.materialId,
                    quantity: qty,
                    fromWarehouse: fromWarehouse,
                    toWarehouse: toWarehouse,
                    notes: notesCtrl.text.trim().isEmpty
                        ? 'تحويل من $fromLabel إلى $toLabel'
                        : notesCtrl.text.trim(),
                    createdBy: authState.user?.email ?? 'admin',
                  );
                  ref.invalidate(inventorySummaryProvider);
                  ref.invalidate(_txProvider(''));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'تم تحويل ${Helpers.formatQuantityInKg(qty, selected!.unit)} من $fromLabel إلى $toLabel'),
                        backgroundColor: Colors.purple));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: Colors.red));
                  }
                }
              },
              label: const Text('تحويل',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Opening Balance Dialog ───────────────────────────────────────────────

  Future<void> _showOpeningBalanceDialog(BuildContext context,
      {required String defaultWarehouse}) async {
    final summaryAsync = ref.read(allRawMaterialsAsSummaryProvider);
    final all = summaryAsync.value ?? [];
    final uniqueMaterials = <String, InventorySummaryModel>{};
    for (final m in all) {
      uniqueMaterials.putIfAbsent(m.materialId, () => m);
    }
    final materials = uniqueMaterials.values.toList();

    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد مواد خام. أضف مواداً من صفحة المواد الخام أولاً.')));
      return;
    }

    InventorySummaryModel? selected = materials.first;
    String warehouse = defaultWarehouse;
    final balCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.playlist_add_check, color: Colors.blue),
            SizedBox(width: 8),
            Text('رصيد افتتاحي'),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventorySummaryModel>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'المادة الخام'),
                  items: materials
                      .map((m) => DropdownMenuItem(
                          value: m, child: Text(m.materialName)))
                      .toList(),
                  onChanged: (v) => ss(() => selected = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: warehouse,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: const [
                    DropdownMenuItem(
                        value: 'main', child: Text('المخزن الرئيسي')),
                    DropdownMenuItem(
                        value: 'staging', child: Text('المخزن المرحلي')),
                    DropdownMenuItem(
                        value: 'mixer', child: Text('مخزن الخلاط')),
                  ],
                  onChanged: (v) => ss(() => warehouse = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: balCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          'الرصيد الافتتاحي (${selected?.unit ?? 'كجم'})'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  decoration:
                      const InputDecoration(labelText: 'السبب / الملاحظة'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final bal = double.tryParse(balCtrl.text);
                if (bal == null || selected == null) return;
                final ds = ref.read(dataSourceProvider);
                try {
                  await ds.addOpeningBalance({
                    'material_id': selected!.materialId,
                    'warehouse_type': warehouse,
                    'balance': bal,
                    'reason': reasonCtrl.text.trim().isEmpty
                        ? null
                        : reasonCtrl.text.trim(),
                    'created_by': 'admin',
                  });
                  ref.invalidate(inventorySummaryProvider);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('تم حفظ الرصيد الافتتاحي')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// كلاس حوار إنشاء سند استلام من الخلاط (مثل بقية النوافذ - مادة واحدة)
// ══════════════════════════════════════════════════════════════════════════════

class _CreateReceivingVoucherDialog extends StatefulWidget {
  final List<InventorySummaryModel> materials;
  final Function(InventorySummaryModel, double) onConfirm;

  const _CreateReceivingVoucherDialog({
    required this.materials,
    required this.onConfirm,
  });

  @override
  State<_CreateReceivingVoucherDialog> createState() => _CreateReceivingVoucherDialogState();
}

class _CreateReceivingVoucherDialogState extends State<_CreateReceivingVoucherDialog> {
  String _selectedMaterialId = '';
  String _selectedMaterialName = '';
  String _selectedUnit = 'كجم';
  double _quantity = 0;
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final materials = widget.materials;

    if (_selectedMaterialId.isEmpty && materials.isNotEmpty) {
      _selectedMaterialId = materials.first.materialId;
      _selectedMaterialName = materials.first.materialName;
      _selectedUnit = materials.first.unit;
    }

    InventorySummaryModel? selectedMaterial;
    if (_selectedMaterialId.isNotEmpty) {
      try {
        selectedMaterial = materials.firstWhere((m) => m.materialId == _selectedMaterialId);
      } catch (_) {
        selectedMaterial = materials.isNotEmpty ? materials.first : null;
      }
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.send, color: Colors.teal),
          const SizedBox(width: 8),
          const Text('إنشاء سند استلام من الخلاط'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مؤشر التدفق
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.teal, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'مخزن الخلاط ← شاشة الاستلام',
                        style: TextStyle(color: Colors.teal, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // اختيار المادة (Dropdown)
              DropdownButtonFormField<String>(
                value: _selectedMaterialId.isNotEmpty ? _selectedMaterialId : null,
                decoration: const InputDecoration(
                  labelText: 'المادة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.science_outlined),
                ),
                items: materials
                    .map((m) => DropdownMenuItem(
                          value: m.materialId,
                          child: Text(
                            '${m.materialName} (${m.currentBalance.toStringAsFixed(1)} ${m.unit})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    final mat = materials.firstWhere((m) => m.materialId == v);
                    setState(() {
                      _selectedMaterialId = v;
                      _selectedMaterialName = mat.materialName;
                      _selectedUnit = mat.unit;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // الكمية
              TextFormField(
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الكمية (${selectedMaterial?.unit ?? 'كجم'})',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.scale_outlined),
                  helperText: selectedMaterial != null
                      ? 'المتاح: ${selectedMaterial.currentBalance.toStringAsFixed(2)} ${selectedMaterial.unit}'
                      : null,
                  helperStyle: const TextStyle(color: Colors.grey),
                ),
                onChanged: (v) {
                  _quantity = double.tryParse(v) ?? 0;
                },
              ),
              const SizedBox(height: 16),
              
              // ملاحظات
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_add_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
          ),
          onPressed: _selectedMaterialId.isEmpty || _quantity <= 0
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onConfirm(selectedMaterial!, _quantity);
                },
          child: const Text(
            'إنشاء سند',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Warehouse Tab
// ══════════════════════════════════════════════════════════════════════════════

class _WarehouseTab extends ConsumerWidget {
  final String warehouse;
  final String search;
  final Color color;
  final IconData icon;
  final String label;

  const _WarehouseTab({
    required this.warehouse,
    required this.search,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(inventorySummaryProvider);

    return summary.when(
      data: (all) {
        final list = all.where((m) => m.warehouseType == warehouse).toList();
        final filtered = search.isEmpty
            ? list
            : list
                .where((s) => s.materialName
                    .toLowerCase()
                    .contains(search.toLowerCase()))
                .toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(inventorySummaryProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _WarehouseSummaryPanel(
                    items: list, color: color, label: label),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 64, color: color.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        Text(
                          list.isEmpty
                              ? 'لا توجد مواد مسجّلة في $label بعد'
                              : 'لا نتائج للبحث',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 14),
                        ),
                        if (list.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'أضف رصيداً افتتاحياً لبدء التشغيل',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _SummaryCard(
                          item: filtered[i], accentColor: color),
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(inventorySummaryProvider),
      ),
    );
  }
}

// ── Warehouse Summary Panel ──────────────────────────────────────────────────

class _WarehouseSummaryPanel extends StatelessWidget {
  final List<InventorySummaryModel> items;
  final Color color;
  final String label;

  const _WarehouseSummaryPanel(
      {required this.items, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final totalMaterials = items.length;
    final lowCount =
        items.where((m) => m.isLow && !m.isCritical && !m.isOutOfStock).length;
    final criticalCount = items.where((m) => m.isCritical).length;
    final outOfStockCount = items.where((m) => m.isOutOfStock).length;
    final totalKg = items.fold<double>(0, (s, m) => s + m.currentBalance);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.9), color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalMaterials مادة',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatChip(
                  label: 'إجمالي المخزون',
                  value: '${totalKg.toStringAsFixed(1)} كجم',
                  icon: Icons.scale_outlined),
              const SizedBox(width: 8),
              if (outOfStockCount > 0)
                _StatChip(
                    label: 'نافد',
                    value: '$outOfStockCount',
                    icon: Icons.remove_circle_outline,
                    danger: true),
              if (criticalCount > 0) ...[
                const SizedBox(width: 8),
                _StatChip(
                    label: 'حرج',
                    value: '$criticalCount',
                    icon: Icons.warning_amber_outlined,
                    warn: true),
              ],
              if (lowCount > 0) ...[
                const SizedBox(width: 8),
                _StatChip(
                    label: 'منخفض',
                    value: '$lowCount',
                    icon: Icons.trending_down_outlined),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;
  final bool warn;
  const _StatChip(
      {required this.label,
      required this.value,
      required this.icon,
      this.danger = false,
      this.warn = false});

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? Colors.red.withOpacity(0.3)
        : warn
            ? Colors.orange.withOpacity(0.3)
            : Colors.white.withOpacity(0.2);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ── Material Summary Card ────────────────────────────────────────────────────

class _SummaryCard extends ConsumerWidget {
  final InventorySummaryModel item;
  final Color accentColor;
  const _SummaryCard({required this.item, required this.accentColor});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    bool confirmed = false;
    final ds = ref.read(dataSourceProvider);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(children: [
            Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('حذف المادة نهائياً'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(ctx).style,
                  children: [
                    const TextSpan(text: 'سيتم حذف المادة '),
                    TextSpan(
                      text: '"${item.materialName}"',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: ' من المخزن الرئيسي ومخزن الخلاط معاً:\n\n'
                          '• جميع حركات المخزون\n'
                          '• الأرصدة الافتتاحية\n'
                          '• صفوف المخزون\n'
                          '• المادة نفسها من قائمة المواد الخام\n\n'
                          'هذا الإجراء لا يمكن التراجع عنه.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: CheckboxListTile(
                  value: confirmed,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'أؤكد حذف هذه المادة نهائياً',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onChanged: (v) => ss(() => confirmed = v ?? false),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
              child: const Text('حذف نهائياً', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await ds.deleteInventoryMaterialFully(item.materialId);
      ref.invalidate(inventorySummaryProvider);
      ref.invalidate(rawMaterialsProvider);
      ref.invalidate(allRawMaterialsAsSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم حذف "${item.materialName}" نهائياً'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ أثناء الحذف: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color statusColor = item.isOutOfStock
        ? Colors.red
        : item.isCritical
            ? Colors.red
            : item.isLow
                ? Colors.orange
                : Colors.green;

    final String statusLabel = item.isOutOfStock
        ? 'نافد'
        : item.isCritical
            ? 'حرج'
            : item.isLow
                ? 'منخفض'
                : 'طبيعي';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.25), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.materialName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (item.code != null && item.code!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(item.code!,
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: 'خيارات',
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_forever_outlined,
                            color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text('حذف نهائي',
                            style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'delete') _confirmDelete(context, ref);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('الرصيد الحالي: ',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13)),
                  Text(
                    Helpers.formatQuantityInKg(item.currentBalance, item.unit),
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                _BalanceChip(
                    'افتتاحي', item.openingBalance, item.unit, Colors.blue),
                const SizedBox(width: 6),
                _BalanceChip('وارد', item.totalIn, item.unit, Colors.green),
                const SizedBox(width: 6),
                _BalanceChip(
                    'منصرف', item.totalOut, item.unit, Colors.red),
                const SizedBox(width: 6),
                _BalanceChip(
                    'تسويات', item.netAdjustments, item.unit, Colors.purple),
              ],
            ),
            if (item.minStock > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.bar_chart_outlined,
                      size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                      'الحد الأدنى: ${Helpers.formatQuantityInKg(item.minStock, item.unit)}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (item.currentBalance / (item.minStock * 2))
                            .clamp(0, 1),
                        backgroundColor: statusColor.withOpacity(0.15),
                        color: statusColor,
                        minHeight: 5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  const _BalanceChip(this.label, this.value, this.unit, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              Helpers.formatQuantityInKgCompact(value, unit),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Staging Warehouse Tab
// ══════════════════════════════════════════════════════════════════════════════

enum _StagingSection { inventory, incoming, outgoing }

class _StagingTab extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  final String search;
  const _StagingTab({required this.onRefresh, required this.search});

  @override
  ConsumerState<_StagingTab> createState() => _StagingTabState();
}

class _StagingTabState extends ConsumerState<_StagingTab> {
  _StagingSection _section = _StagingSection.inventory;

  String get _operatorName {
    final auth = ref.read(authProvider);
    return auth.user?.name ?? auth.user?.email ?? 'مدير الإنتاج';
  }

  void _refresh() {
    ref.invalidate(_stagingIncomingVouchersProvider);
    ref.invalidate(_stagingOutgoingVouchersProvider);
    ref.invalidate(inventorySummaryProvider);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final pendingIncoming = ref
            .watch(_stagingIncomingVouchersProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    return Column(
      children: [
        Container(
          color: Colors.deepOrange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _StagingChip(
                label: 'المخزون',
                icon: Icons.inventory_2_outlined,
                selected: _section == _StagingSection.inventory,
                color: Colors.deepOrange,
                onTap: () => setState(() => _section = _StagingSection.inventory),
              ),
              const SizedBox(width: 8),
              _StagingChip(
                label: 'وارد من الرئيسي',
                icon: Icons.arrow_downward,
                selected: _section == _StagingSection.incoming,
                color: Colors.deepOrange,
                badgeCount: pendingIncoming,
                onTap: () => setState(() => _section = _StagingSection.incoming),
              ),
              const SizedBox(width: 8),
              _StagingChip(
                label: 'صادر للخلاط',
                icon: Icons.arrow_upward,
                selected: _section == _StagingSection.outgoing,
                color: Colors.deepOrange,
                onTap: () => setState(() => _section = _StagingSection.outgoing),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _section.index,
            children: [
              _StagingInventorySection(search: widget.search, onRefresh: _refresh),
              _StagingVouchersSection(
                provider: _stagingIncomingVouchersProvider,
                emptyLabel: 'لا توجد طلبات واردة من المخزن الرئيسي',
                emptyHint: 'استخدم زر + لإنشاء طلب تحويل من الرئيسي',
                role: 'incoming',
                operatorName: _operatorName,
                onAction: _refresh,
              ),
              _StagingVouchersSection(
                provider: _stagingOutgoingVouchersProvider,
                emptyLabel: 'لا توجد سندات صادرة للخلاط',
                emptyHint: 'استخدم زر + لإنشاء سند تحويل للخلاط',
                role: 'outgoing',
                operatorName: _operatorName,
                onAction: _refresh,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StagingChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final int badgeCount;
  final VoidCallback onTap;
  const _StagingChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(selected ? 0 : 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                label: Text('$badgeCount'),
                child: Icon(icon, size: 16,
                    color: selected ? Colors.white : color),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StagingInventorySection extends ConsumerWidget {
  final VoidCallback onRefresh;
  final String search;
  const _StagingInventorySection(
      {required this.onRefresh, required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(inventorySummaryProvider);
    return summary.when(
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(inventorySummaryProvider),
      ),
      data: (all) {
        final items = all.where((m) => m.warehouseType == 'staging').toList();
        final filtered = search.isEmpty
            ? items
            : items
                .where((m) => m.materialName
                    .toLowerCase()
                    .contains(search.toLowerCase()))
                .toList();

        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _WarehouseSummaryPanel(
                  items: items,
                  color: Colors.deepOrange,
                  label: 'المخزن المرحلي',
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 64,
                            color: Colors.deepOrange.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        Text(
                          items.isEmpty
                              ? 'لا توجد مواد في المخزن المرحلي بعد'
                              : 'لا نتائج للبحث',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 14),
                        ),
                        if (items.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'اضغط + لإنشاء طلب تحويل من المخزن الرئيسي',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _SummaryCard(
                          item: filtered[i], accentColor: Colors.deepOrange),
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StagingVouchersSection extends ConsumerWidget {
  final ProviderBase<AsyncValue<List<TransferVoucherModel>>> provider;
  final String emptyLabel;
  final String emptyHint;
  final String role;
  final String operatorName;
  final VoidCallback onAction;

  const _StagingVouchersSection({
    required this.provider,
    required this.emptyLabel,
    required this.emptyHint,
    required this.role,
    required this.operatorName,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const ShimmerList(),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  role == 'incoming' ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(emptyLabel, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 6),
                Text(emptyHint,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 80),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => onAction(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: vouchers.length,
            itemBuilder: (ctx, i) => _StagingVoucherCard(
              voucher: vouchers[i],
              operatorName: operatorName,
              onAction: onAction,
              role: role,
            ),
          ),
        );
      },
    );
  }
}

class _StagingVoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final String operatorName;
  final VoidCallback onAction;
  final String role;
  const _StagingVoucherCard({
    required this.voucher,
    required this.operatorName,
    required this.onAction,
    required this.role,
  });

  Color get _statusColor {
    return switch (voucher.status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange,
      'cancelled' => Colors.red,
      _ => Colors.grey,
    };
  }

  String get _statusLabel {
    return switch (voucher.status) {
      'confirmed' => 'مُنفَّذ',
      'pending' => 'قيد الانتظار',
      'cancelled' => 'ملغي',
      _ => 'مسودة',
    };
  }

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، تأكيد')),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.read(dataSourceProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(_statusLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _statusColor,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                Text(voucher.voucherNumber ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (voucher.createdAt != null)
                  Text(
                    voucher.createdAt!.split('T').first,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (voucher.itemNames.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: voucher.itemNames.take(4).map((name) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepOrange.shade100),
                    ),
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepOrange.shade800)),
                  );
                }).toList(),
              ),
            if (voucher.itemNames.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${voucher.itemNames.length - 4} مواد أخرى',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 11)),
              ),
            if (voucher.notes?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('ملاحظات: ${voucher.notes}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            if (!voucher.isConfirmed && !voucher.isCancelled) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined,
                        color: Colors.red, size: 16),
                    label: const Text('إلغاء',
                        style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final ok = await _confirm(context, 'تأكيد الإلغاء',
                          'هل تريد إلغاء سند ${voucher.voucherNumber}؟');
                      if (ok) {
                        try {
                          await ds.cancelTransferVoucher(voucher.id!);
                          onAction();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('خطأ: $e'),
                                backgroundColor: Colors.red));
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  if (voucher.isDraft)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('إرسال للمراجعة'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange),
                      onPressed: () async {
                        try {
                          await ds.submitTransferVoucher(voucher.id!);
                          onAction();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('خطأ: $e'),
                                backgroundColor: Colors.red));
                          }
                        }
                      },
                    ),
                  if (role == 'incoming' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد الاستلام'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد الاستلام',
                          'هل تأكد استلام المواد من المخزن الرئيسي؟\nسيتم نقل المواد للمخزن المرحلي.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(
                                voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم تأكيد الاستلام ونقل المواد للمخزن المرحلي'),
                                      backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('خطأ: $e'),
                                  backgroundColor: Colors.red));
                            }
                          }
                        }
                      },
                    ),
                  if (role == 'outgoing' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد استلام الخلاط'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد استلام مخزن الخلاط',
                          'هل تأكد استلام المواد من المخزن المرحلي؟\nسيتم نقل المواد لمخزن الخلطات.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(
                                voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'تم تأكيد الاستلام ونقل المواد لمخزن الخلطات'),
                                      backgroundColor: Colors.teal));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('خطأ: $e'),
                                  backgroundColor: Colors.red));
                            }
                          }
                        }
                      },
                    ),
                ],
              ),
            ],
            if (voucher.isConfirmed && voucher.confirmedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text('تم التنفيذ بواسطة: ${voucher.confirmedBy}',
                        style: const TextStyle(
                            color: Colors.green, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Staging voucher creation dialog ─────────────────────────────────────────

class _StagingVItemEntry {
  String name = '';
  String unit = 'كجم';
  double qty = 0;
  String? materialId;
}

class _StagingVoucherDialog extends ConsumerStatefulWidget {
  final String transferType;
  final String? createdBy;
  final VoidCallback onSaved;

  const _StagingVoucherDialog({
    required this.transferType,
    required this.onSaved,
    this.createdBy,
  });

  @override
  ConsumerState<_StagingVoucherDialog> createState() =>
      _StagingVoucherDialogState();
}

class _StagingVoucherDialogState extends ConsumerState<_StagingVoucherDialog> {
  final _notesCtrl = TextEditingController();
  final List<_StagingVItemEntry> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _fromWarehouse =>
      widget.transferType == 'main_to_staging' ? 'main' : 'staging';

  String get _title => widget.transferType == 'main_to_staging'
      ? 'طلب تحويل من المخزن الرئيسي'
      : 'سند صادر للخلاط';

  String get _flowLabel => widget.transferType == 'main_to_staging'
      ? 'المخزن الرئيسي ← المخزن المرحلي'
      : 'المخزن المرحلي ← مخزن الخلطات';

  void _addItem() => setState(() => _items.add(_StagingVItemEntry()));
  void _removeItem(int i) => setState(() => _items.removeAt(i));

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أضف بنداً واحداً على الأقل'),
            backgroundColor: Colors.red),
      );
      return;
    }
    final incomplete = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.isEmpty || _items[i].qty <= 0) i + 1,
    ];
    if (incomplete.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'أكمل بيانات البند رقم ${incomplete.join("، ")} قبل الحفظ'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.createTransferVoucher({
        'notes': _notesCtrl.text.trim(),
        'created_by': widget.createdBy ?? 'مدير الإنتاج',
        'transfer_type': widget.transferType,
        'items': _items
            .map((e) => {
                  'material_name': e.name,
                  'unit': e.unit,
                  'requested_qty': e.qty,
                  if (e.materialId != null) 'material_id': e.materialId,
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(inventorySummaryProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == _fromWarehouse)
            .toList() ??
        [];

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz,
                        color: Colors.deepOrange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _flowLabel,
                        style: const TextStyle(
                            color: Colors.deepOrange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('المواد',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('إضافة بند'),
                    onPressed: _addItem,
                  ),
                ],
              ),
              const Divider(),
              ..._items.asMap().entries.map((e) => _StagingVItemRow(
                    index: e.key,
                    entry: e.value,
                    materials: materials,
                    onRemove: () => _removeItem(e.key),
                    onChanged: () => setState(() {}),
                  )),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text('اضغط "إضافة بند" لإضافة مادة',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('حفظ', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _StagingVItemRow extends StatelessWidget {
  final int index;
  final _StagingVItemEntry entry;
  final List<InventorySummaryModel> materials;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _StagingVItemRow({
    required this.index,
    required this.entry,
    required this.materials,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final itemNo = index + 1;
    final selected = entry.name.isNotEmpty
        ? materials
            .where((m) => entry.materialId != null && entry.materialId!.isNotEmpty
                ? m.materialId == entry.materialId
                : m.materialName == entry.name)
            .firstOrNull
        : null;
    final available = selected?.currentBalance ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('البند $itemNo',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.deepOrange)),
              const Spacer(),
              InkWell(
                  onTap: onRemove,
                  child: const Icon(Icons.remove_circle_outline,
                      color: Colors.red, size: 20)),
            ],
          ),
          const SizedBox(height: 8),
          materials.isEmpty
              ? TextField(
                  decoration: const InputDecoration(
                      labelText: 'اسم المادة',
                      border: OutlineInputBorder()),
                  onChanged: (v) {
                    entry.name = v;
                    onChanged();
                  },
                )
              : DropdownButtonFormField<String>(
                  value: entry.name.isNotEmpty ? entry.name : null,
                  decoration: const InputDecoration(
                      labelText: 'المادة', border: OutlineInputBorder()),
                  items: materials
                      .map((m) => DropdownMenuItem(
                            value: m.materialName,
                            child: Text(
                              '${m.materialName} (${m.currentBalance.toStringAsFixed(1)} ${m.unit})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    entry.name = v ?? '';
                    final mat = materials.firstWhere(
                        (m) => m.materialName == v,
                        orElse: () => materials.first);
                    entry.materialId = mat.materialId;
                    entry.unit = mat.unit;
                    onChanged();
                  },
                ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: entry.qty > 0 ? entry.qty.toString() : '',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية',
                    border: const OutlineInputBorder(),
                    helperText: available > 0
                        ? 'متاح: ${available.toStringAsFixed(2)}'
                        : null,
                    helperStyle: const TextStyle(color: Colors.grey),
                  ),
                  onChanged: (v) {
                    entry.qty = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<String>(
                  value: entry.unit,
                  decoration: const InputDecoration(
                      labelText: 'الوحدة', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'كجم', child: Text('كجم')),
                    DropdownMenuItem(value: 'جرام', child: Text('جرام')),
                    DropdownMenuItem(value: 'لتر', child: Text('لتر')),
                  ],
                  onChanged: (v) {
                    entry.unit = v ?? 'كجم';
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Transactions Tab
// ══════════════════════════════════════════════════════════════════════════════

class _TransactionsTab extends ConsumerStatefulWidget {
  final String search;
  const _TransactionsTab({required this.search});

  @override
  ConsumerState<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<_TransactionsTab> {
  String _warehouseFilter = 'all';
  String _typeFilter = 'all';

  Future<void> _deleteTx(BuildContext context, WidgetRef ref,
      InventoryTransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف الحركة'),
        content: Text(
          'حذف حركة "${tx.materialName}" بقيمة ${tx.quantity.toStringAsFixed(2)}؟\n\n'
          'سيتم عكس أثرها على رصيد المخزون تلقائياً.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.deleteInventoryTransaction(tx.id);
      ref.invalidate(_txProvider(''));
      ref.invalidate(inventorySummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الحركة'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(_txProvider(''));

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _FilterChip2(
                  label: 'الكل',
                  selected: _warehouseFilter == 'all',
                  onTap: () => setState(() => _warehouseFilter = 'all')),
              const SizedBox(width: 6),
              _FilterChip2(
                  label: 'الرئيسي',
                  selected: _warehouseFilter == 'main',
                  color: Colors.blue,
                  onTap: () => setState(() => _warehouseFilter = 'main')),
              const SizedBox(width: 6),
              _FilterChip2(
                  label: 'الخلاط',
                  selected: _warehouseFilter == 'mixer',
                  color: Colors.teal,
                  onTap: () => setState(() => _warehouseFilter = 'mixer')),
              const SizedBox(width: 16),
              _FilterChip2(
                  label: 'وارد',
                  selected: _typeFilter == 'in',
                  color: Colors.green,
                  onTap: () => setState(
                      () => _typeFilter = _typeFilter == 'in' ? 'all' : 'in')),
              const SizedBox(width: 6),
              _FilterChip2(
                  label: 'منصرف',
                  selected: _typeFilter == 'out',
                  color: Colors.red,
                  onTap: () => setState(() =>
                      _typeFilter = _typeFilter == 'out' ? 'all' : 'out')),
              const SizedBox(width: 6),
              _FilterChip2(
                  label: 'تحويل',
                  selected: _typeFilter == 'transfer',
                  color: Colors.purple,
                  onTap: () => setState(() => _typeFilter =
                      _typeFilter == 'transfer' ? 'all' : 'transfer')),
              const SizedBox(width: 6),
              _FilterChip2(
                  label: 'تسوية',
                  selected: _typeFilter == 'adjustment',
                  color: Colors.orange,
                  onTap: () => setState(() => _typeFilter =
                      _typeFilter == 'adjustment' ? 'all' : 'adjustment')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: txs.when(
            data: (list) {
              var filtered = list;

              if (_warehouseFilter != 'all') {
                filtered = filtered
                    .where((t) => t.warehouseType == _warehouseFilter)
                    .toList();
              }
              if (_typeFilter != 'all') {
                filtered = filtered
                    .where((t) => _typeFilter == 'transfer'
                        ? t.transactionType.startsWith('transfer')
                        : t.transactionType == _typeFilter)
                    .toList();
              }
              if (widget.search.isNotEmpty) {
                filtered = filtered
                    .where((t) =>
                        (t.notes?.contains(widget.search) ?? false))
                    .toList();
              }

              if (filtered.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horiz,
                          size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('لا توجد حركات مطابقة',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(_txProvider('')),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _TxCard(
                    tx: filtered[i],
                    onDelete: () => _deleteTx(context, ref, filtered[i]),
                  ),
                ),
              );
            },
            loading: () => const ShimmerList(),
            error: (e, _) => ErrorWidget2(
              message: Helpers.friendlyError(e),
              onRetry: () => ref.invalidate(_txProvider('')),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip2(
      {required this.label,
      required this.selected,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withOpacity(selected ? 0 : 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : c,
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Transaction Card
// ══════════════════════════════════════════════════════════════════════════════

class _TxCard extends StatelessWidget {
  final InventoryTransactionModel tx;
  final VoidCallback onDelete;
  const _TxCard({required this.tx, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final typeInfo = _txTypeInfo(tx.transactionType);
    final isMain = tx.warehouseType == AppConstants.warehouseMain;
    final warehouseLabel = isMain ? 'رئيسي' : 'خلاط';
    final warehouseColor = isMain ? Colors.blue : Colors.teal;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeInfo.$2.withOpacity(0.15),
          child: Icon(typeInfo.$1, color: typeInfo.$2, size: 20),
        ),
        title: Row(
          children: [
            Text(typeInfo.$3,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: warehouseColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(warehouseLabel,
                  style: TextStyle(
                      color: warehouseColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx.materialName.isNotEmpty)
              Text(
                tx.materialName,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            Text(
              '${tx.createdAt.toLocal().toString().substring(0, 16)}  •  ${tx.createdBy}',
              style: const TextStyle(fontSize: 11),
            ),
            if (tx.notes != null && tx.notes!.isNotEmpty)
              Text(tx.notes!,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_isNegative(tx.transactionType) ? '-' : '+'}${tx.quantity.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: _isNegative(tx.transactionType)
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              tooltip: 'حذف',
              onPressed: onDelete,
            ),
          ],
        ),
        isThreeLine: tx.materialName.isNotEmpty || (tx.notes != null && tx.notes!.isNotEmpty),
      ),
    );
  }

  bool _isNegative(String type) =>
      type == 'out' || type == 'transfer_out';

  (IconData, Color, String) _txTypeInfo(String type) {
    return switch (type) {
      'in' => (Icons.arrow_downward, Colors.green, 'وارد'),
      'out' => (Icons.arrow_upward, Colors.red, 'منصرف'),
      'transfer_in' => (Icons.swap_horiz, Colors.blue, 'تحويل وارد'),
      'transfer_out' => (Icons.swap_horiz, Colors.purple, 'تحويل صادر'),
      'transfer' => (Icons.swap_horiz, Colors.blue, 'تحويل'),
      'adjustment' => (Icons.tune, Colors.orange, 'تسوية'),
      'opening' => (Icons.playlist_add_check, Colors.teal, 'افتتاحي'),
      _ => (Icons.circle, Colors.grey, type),
    };
  }
}
