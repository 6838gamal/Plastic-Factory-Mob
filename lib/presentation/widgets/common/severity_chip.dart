import 'package:flutter/material.dart';
import '../../../core/utils/helpers.dart';

class SeverityChip extends StatelessWidget {
  final String severity;
  const SeverityChip({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = Helpers.getSeverityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        Helpers.getSeverityText(severity),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'acknowledged':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'saved':
        return Colors.green;
      case 'pending_sync':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String get _label {
    switch (status) {
      case 'pending':
        return 'معلق';
      case 'acknowledged':
        return 'تم التأكيد';
      case 'resolved':
        return 'تم الحل';
      case 'saved':
        return 'محفوظ';
      case 'pending_sync':
        return 'في انتظار المزامنة';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        _label,
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
