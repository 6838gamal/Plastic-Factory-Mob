import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';

class ShiftHandoversAdminPage extends ConsumerStatefulWidget {
  const ShiftHandoversAdminPage({super.key});

  @override
  ConsumerState<ShiftHandoversAdminPage> createState() =>
      _ShiftHandoversAdminPageState();
}

class _ShiftHandoversAdminPageState
    extends ConsumerState<ShiftHandoversAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  List<Map<String, dynamic>> _handovers = [];
  List<Map<String, dynamic>> _debts = [];

  ApiDataSource get _ds => ref.read(dataSourceProvider);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _ds.getRaw('/api/shift-handover', query: {'limit': '100'}),
        _ds.getRaw('/api/shift-handover/custody-debts'),
      ]);
      setState(() {
        _handovers = List<Map<String, dynamic>>.from(results[0] as List);
        _debts     = List<Map<String, dynamic>>.from(results[1] as List);
      });
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resolveDebt(String debtId, String supervisorName) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسوية مديونية العهدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المشرف: $supervisorName'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المسوّي',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      try {
        await _ds.putRaw('/api/shift-handover/custody-debts/$debtId/resolve', {
          'resolved_by': ctrl.text.trim(),
        });
        _showSnack('تمت تسوية المديونية');
        _loadData();
      } catch (e) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    }
  }

  Future<void> _confirmHandover(String handoverId, String supervisorName) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد استلام العهدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('استلام وردية من: $supervisorName'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'اسم مشرف الوردية القادمة',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الاستلام',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      try {
        await _ds.postRaw('/api/shift-handover/$handoverId/confirm', {
          'next_supervisor_name': ctrl.text.trim(),
        });
        _showSnack('تم تأكيد استلام العهدة');
        _loadData();
      } catch (e) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed': return Colors.green;
      case 'closed':    return const Color(0xFF1565C0);
      case 'frozen':    return Colors.red;
      default:          return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed': return 'مؤكَّد ✓';
      case 'closed':    return 'مغلق';
      case 'frozen':    return '❄️ مجمَّد';
      default:          return 'مفتوح';
    }
  }

  Widget _statBubble(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );

  Widget _handoversList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_handovers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد عمليات تسليم بعد',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _handovers.length,
        itemBuilder: (ctx, i) {
          final h = _handovers[i];
          final status   = h['status'] as String? ?? 'open';
          final deficit  = (h['deficit_kg'] as num? ?? 0).toDouble();
          final scrapAdded = (h['scrap_added_kg'] as num? ?? 0).toDouble();
          final isFrozen = status == 'frozen';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                  color: isFrozen ? Colors.red.shade300 : Colors.transparent,
                  width: isFrozen ? 1.5 : 0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h['shift_name'] as String? ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(h['supervisor_name'] as String? ?? '',
                              style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _statusColor(status)),
                      ),
                      child: Text(_statusLabel(status),
                          style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ),
                  ]),
                  const Divider(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _statBubble('متوقع',
                          '${h['expected_stock_kg'] ?? 0} كجم',
                          Colors.blue),
                      _statBubble(
                          'فعلي',
                          h['actual_stock_kg'] != null
                              ? '${h['actual_stock_kg']} كجم'
                              : '---',
                          Colors.green),
                      if (deficit > 0.5)
                        _statBubble('عجز', '$deficit كجم', Colors.red),
                      if (scrapAdded > 0)
                        _statBubble(
                            '♻️ سكراب', '$scrapAdded كجم', Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(h['handover_date'] as String? ?? '',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  if (status == 'closed' || status == 'frozen') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('تأكيد استلام المشرف القادم'),
                        onPressed: () => _confirmHandover(
                            h['id'] as String,
                            h['supervisor_name'] as String? ?? ''),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _debtsList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_debts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('لا توجد مديونيات معلقة',
                style: TextStyle(color: Colors.green, fontSize: 16)),
          ],
        ),
      );
    }

    final pending  = _debts.where((d) => d['status'] == 'pending').toList();
    final resolved = _debts.where((d) => d['status'] != 'pending').toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (pending.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Text('مديونيات معلقة (${pending.length})',
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ]),
            ),
            ...pending.map((d) => _debtCard(d, isPending: true)),
          ],
          if (resolved.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('مديونيات مسوّاة',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
            ...resolved.map((d) => _debtCard(d, isPending: false)),
          ],
        ],
      ),
    );
  }

  Widget _debtCard(Map<String, dynamic> d, {required bool isPending}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: isPending ? Colors.red.shade200 : Colors.green.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isPending ? Icons.person_off : Icons.person_pin,
                  color: isPending ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['supervisor_name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(d['shift_name'] as String? ?? '',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red)),
                child: Text('${d['deficit_kg']} كجم',
                    style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(d['handover_date'] as String? ?? '',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            if (!isPending && d['resolved_by'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text('سوّى: ${d['resolved_by']}',
                    style:
                        const TextStyle(color: Colors.green, fontSize: 12)),
              ]),
            ],
            if (isPending) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('تسوية المديونية'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  onPressed: () => _resolveDebt(
                      d['id'] as String,
                      d['supervisor_name'] as String? ?? ''),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingDebts = _debts.where((d) => d['status'] == 'pending').length;
    final frozenShifts = _handovers.where((h) => h['status'] == 'frozen').length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Alert banner
          if (frozenShifts > 0 || pendingDebts > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      if (frozenShifts > 0) '$frozenShifts وردية مجمَّدة',
                      if (pendingDebts > 0) '$pendingDebts مديونية معلقة',
                    ].join(' • '),
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.red, size: 20),
                    onPressed: _loadData),
              ]),
            ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1565C0),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('سجل التسليم'),
                    if (frozenShifts > 0) ...[
                      const SizedBox(width: 6),
                      Badge(label: Text('$frozenShifts')),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('مديونيات العهدة'),
                    if (pendingDebts > 0) ...[
                      const SizedBox(width: 6),
                      Badge(
                          backgroundColor: Colors.red,
                          label: Text('$pendingDebts')),
                    ],
                  ],
                ),
              ),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_handoversList(), _debtsList()],
            ),
          ),
        ],
      ),
    );
  }
}
