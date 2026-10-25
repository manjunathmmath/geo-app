import 'package:flutter/material.dart';

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

Color statusColor(String status) {
  switch (status) {
    case 'APPROVED':
      return Colors.green.shade700;
    case 'REJECTED':
      return Colors.red.shade700;
    default:
      return Colors.orange.shade800;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'APPROVED':
      return 'Published';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'In review';
  }
}
