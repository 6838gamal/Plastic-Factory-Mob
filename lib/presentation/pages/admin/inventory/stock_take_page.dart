import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';

// ── providers ───────────────────────────────────────────────────────────────
final _sessionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getStockTakeSessions();
});

// ── page ─────────────────────────────────────────────────────────────────────
class StockTakePage extends ConsumerStatefulWidget {
  const StockTakePage({super.key});
  @override
  ConsumerState<StockTakePage> createState() => _StockTakePageState();
}

class _StockTakePageState extends ConsumerState<StockTakePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _items = [];
  bool _loadingSession = false;
  bool _saving = false;
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  String _fmtDt(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
          '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ── create new session ───────────────────────────────────────────────────
  Future<void> _startNewSession() async {
    final nameCtrl = TextEditingController(
      text: 'جرد ${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} - ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء جرد دوري جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم الجرد'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بدء')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loadingSession = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final session = await ds.createStockTakeSession({
        'session_name': nameCtrl.text.trim(),
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'warehouse_type': 'main',
        'created_by': 'admin',
      });
      final full = await ds.getStockTakeSession(session['id']);
      _loadSession(full);
      _tabs.animateTo(0);
      ref.invalidate(_sessionsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  void _loadSession(Map<String, dynamic> full) {
    for (final c in _ctrls.values) c.dispose();
    _ctrls.clear();
    final items = List<Map<String, dynamic>>.from(full['items'] ?? []);
    for (final it in items) {
      final id = it['id'] as String;
      final actual = it['actual_qty'];
      _ctrls[id] = TextEditingController(
        text: actual != null ? actual.toString() : '',
      );
    }
    setState(() {
      _activeSession = Map<String, dynamic>.from(full)..remove('items');
      _items = items;
    });
  }

  Future<void> _openSession(String sessionId) async {
    setState(() => _loadingSession = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final full = await ds.getStockTakeSession(sessionId);
      _loadSession(full);
      _tabs.animateTo(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSession = false);
    }
  }

  // ── save one item ─────────────────────────────────────────────────────────
  Future<void> _saveItem(String sessionId, Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final text = _ctrls[id]?.text.trim() ?? '';
    final qty = double.tryParse(text);
    if (qty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقماً صحيحاً'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final updated = await ds.updateStockTakeItem(sessionId, id, qty);
      final idx = _items.indexWhere((e) => e['id'] == id);
      if (idx >= 0) setState(() => _items[idx] = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── close session ─────────────────────────────────────────────────────────
  Future<void> _closeSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق الجرد'),
        content: const Text('بعد الإغلاق لن تتمكن من تعديل الأرقام.\nهل تريد إغلاق الجرد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إغلاق', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.closeStockTakeSession(_activeSession!['id']);
      final updated = await ds.getStockTakeSession(_activeSession!['id']);
      _loadSession(updated);
      ref.invalidate(_sessionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إغلاق الجرد بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── color for difference ──────────────────────────────────────────────────
  Color _diffColor(dynamic diff) {
    if (diff == null) return Colors.grey.shade300;
    final d = (diff is num) ? diff.toDouble() : double.tryParse(diff.toString()) ?? 0;
    if (d.abs() <= 0.01) return Colors.green.shade100;
    if (d.abs() <= 2.0) return Colors.yellow.shade100;
    return Colors.red.shade100;
  }

  Color _diffTextColor(dynamic diff) {
    if (diff == null) return Colors.grey;
    final d = (diff is num) ? diff.toDouble() : double.tryParse(diff.toString()) ?? 0;
    if (d.abs() <= 0.01) return Colors.green.shade800;
    if (d > 0) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── header bar ──────────────────────────────────────────────────
          Material(
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 10),
                  const Text('الجرد الدوري',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_saving) const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text('جرد جديد'),
                    onPressed: _loadingSession ? null : _startNewSession,
                  ),
                ],
              ),
            ),
          ),
          // ── tabs ────────────────────────────────────────────────────────
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'الجرد الحالي'),
              Tab(icon: Icon(Icons.history_outlined), text: 'السجل'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CurrentSessionTab(
                  session: _activeSession,
                  items: _items,
                  ctrls: _ctrls,
                  loading: _loadingSession,
                  saving: _saving,
                  fmtDt: _fmtDt,
                  diffColor: _diffColor,
                  diffTextColor: _diffTextColor,
                  onSaveItem: _saveItem,
                  onClose: _closeSession,
                ),
                _HistoryTab(
                  fmtDt: _fmtDt,
                  onOpen: _openSession,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current Session Tab
// ─────────────────────────────────────────────────────────────────────────────
class _CurrentSessionTab extends StatelessWidget {
  final Map<String, dynamic>? session;
  final List<Map<String, dynamic>> items;
  final Map<String, TextEditingController> ctrls;
  final bool loading;
  final bool saving;
  final String Function(String?) fmtDt;
  final Color Function(dynamic) diffColor;
  final Color Function(dynamic) diffTextColor;
  final Future<void> Function(String, Map<String, dynamic>) onSaveItem;
  final Future<void> Function() onClose;

  const _CurrentSessionTab({
    required this.session,
    required this.items,
    required this.ctrls,
    required this.loading,
    required this.saving,
    required this.fmtDt,
    required this.diffColor,
    required this.diffTextColor,
    required this.onSaveItem,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (session == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('لا يوجد جرد مفتوح',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            const Text('اضغط "جرد جديد" لبدء جرد دوري',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final isClosed = session!['status'] == 'closed';
    final counted  = items.where((e) => e['actual_qty'] != null).length;
    final diffs    = items.where((e) {
      final d = e['actual_qty'];
      final s = e['system_qty'];
      if (d == null || s == null) return false;
      return ((d is num ? d : double.tryParse(d.toString()) ?? 0) -
              (s is num ? s : double.tryParse(s.toString()) ?? 0)).abs() > 0.01;
    }).length;

    return Column(
      children: [
        // Session info card
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(session!['session_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isClosed ? Colors.grey.shade200 : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isClosed ? 'مغلق' : 'مفتوح',
                        style: TextStyle(
                          color: isClosed ? Colors.grey.shade700 : Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('بدأ: ${fmtDt(session!['created_at'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                if (session!['closed_at'] != null)
                  Row(children: [
                    const Icon(Icons.lock_clock, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('أُغلق: ${fmtDt(session!['closed_at'])}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _StatChip(label: 'الأصناف', value: '${items.length}', color: Colors.blue),
                  _StatChip(label: 'تم الجرد', value: '$counted', color: Colors.green),
                  _StatChip(label: 'فروقات', value: '$diffs', color: diffs > 0 ? Colors.red : Colors.green),
                ]),
              ],
            ),
          ),
        ),

        // Items list
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: items.map((item) => _ItemRow(
                item: item,
                ctrl: ctrls[item['id']]!,
                isClosed: isClosed,
                fmtDt: fmtDt,
                diffColor: diffColor,
                diffTextColor: diffTextColor,
                onSave: () => onSaveItem(session!['id'], item),
              )).toList(),
            ),
          ),
        ),

        // Close button
        if (!isClosed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.lock_outline, color: Colors.white),
                label: const Text('إغلاق الجرد', style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: saving ? null : onClose,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Item row ──────────────────────────────────────────────────────────────────
class _ItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final TextEditingController ctrl;
  final bool isClosed;
  final String Function(String?) fmtDt;
  final Color Function(dynamic) diffColor;
  final Color Function(dynamic) diffTextColor;
  final VoidCallback onSave;

  const _ItemRow({
    required this.item,
    required this.ctrl,
    required this.isClosed,
    required this.fmtDt,
    required this.diffColor,
    required this.diffTextColor,
    required this.onSave,
  });

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final sysQty  = (item['system_qty'] as num?)?.toDouble() ?? 0.0;
    final actQty  = item['actual_qty'];
    final diff    = item['difference'];
    final diffPct = item['diff_pct'];
    final unit    = item['unit'] ?? 'كجم';
    final countedAt = item['counted_at'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: diff != null ? widget.diffColor(diff) : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(item['material_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text(unit, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _QtyBox(label: 'رصيد النظام', value: sysQty, unit: unit)),
              const SizedBox(width: 8),
              Expanded(
                child: widget.isClosed
                    ? _QtyBox(
                        label: 'الرصيد الفعلي',
                        value: actQty != null ? (actQty as num).toDouble() : null,
                        unit: unit,
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('الرصيد الفعلي',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: widget.ctrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: const OutlineInputBorder(),
                                hintText: '0.0',
                                suffixText: unit,
                              ),
                              onChanged: (_) => setState(() => _editing = true),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            tooltip: 'حفظ',
                            onPressed: widget.onSave,
                            iconSize: 22,
                          ),
                        ]),
                      ]),
              ),
              const SizedBox(width: 8),
              if (diff != null) ...[
                _DiffBox(
                  diff: (diff as num).toDouble(),
                  pct: diffPct != null ? (diffPct as num).toDouble() : null,
                  textColor: widget.diffTextColor(diff),
                ),
              ] else
                const SizedBox(width: 64),
            ]),
            if (countedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.schedule, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('جُرد: ${widget.fmtDt(countedAt)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _QtyBox extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  const _QtyBox({required this.label, required this.value, required this.unit});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      const SizedBox(height: 2),
      Text(
        value != null ? Helpers.formatQuantityInKg(value!, unit) : '—',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ]);
  }
}

class _DiffBox extends StatelessWidget {
  final double diff;
  final double? pct;
  final Color textColor;
  const _DiffBox({required this.diff, required this.pct, required this.textColor});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('الفرق', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Text(
        '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
      ),
      if (pct != null)
        Text('${pct! >= 0 ? '+' : ''}${pct!.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, color: textColor)),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History Tab
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryTab extends ConsumerWidget {
  final String Function(String?) fmtDt;
  final Future<void> Function(String) onOpen;
  const _HistoryTab({required this.fmtDt, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessAsync = ref.watch(_sessionsProvider);
    return sessAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(_sessionsProvider),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('لا توجد جلسات جرد سابقة', style: TextStyle(color: Colors.grey)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sessions.length,
          itemBuilder: (_, i) {
            final s = sessions[i];
            final isClosed = s['status'] == 'closed';
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isClosed ? Colors.grey.shade200 : Colors.green.shade100,
                  child: Icon(
                    isClosed ? Icons.lock_outline : Icons.lock_open,
                    color: isClosed ? Colors.grey : Colors.green,
                  ),
                ),
                title: Text(s['session_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.access_time, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(fmtDt(s['created_at']), style: const TextStyle(fontSize: 12)),
                  ]),
                  Text(
                    '${s['counted_items'] ?? 0} / ${s['total_items'] ?? 0} صنف | '
                    '${s['diff_items'] ?? 0} فروقات',
                    style: const TextStyle(fontSize: 12),
                  ),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isClosed ? Colors.grey.shade200 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isClosed ? 'مغلق' : 'مفتوح',
                      style: TextStyle(
                        fontSize: 11,
                        color: isClosed ? Colors.grey.shade700 : Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.open_in_full, size: 18),
                    tooltip: 'فتح',
                    onPressed: () => onOpen(s['id']),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
