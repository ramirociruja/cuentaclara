// lib/utils/utils.dart
import 'package:flutter/material.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/receipt_service.dart';

Future<void> shareReceiptByPaymentId(
  BuildContext context,
  int paymentId,
) async {
  await ReceiptService.shareReceiptByPaymentId(context, paymentId);
}

DateTime dateOnlyLocal(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime startOfDayLocal(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime endOfDayLocal(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Si el string tiene “Z” u offset, lo parsea y lo pasa a local.
/// Si viene sin zona (naive), lo toma como local.
DateTime? parseToLocal(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.isUtc ? v.toLocal() : v;
  try {
    final dt = DateTime.parse(v.toString());
    return dt.isUtc ? dt.toLocal() : dt;
  } catch (_) {
    return null;
  }
}

/// Devuelve el lunes y domingo (local) de la semana de `d`, con horas normalizadas.
({DateTime monday, DateTime sunday}) weekRangeLocal(DateTime d) {
  final base = startOfDayLocal(d);
  final monday = base.subtract(Duration(days: base.weekday - 1));
  final sunday = endOfDayLocal(monday.add(const Duration(days: 6)));
  return (monday: monday, sunday: sunday);
}

DateTime instDueLocal(Installment it) {
  final d = it.dueDate;
  return d.isUtc ? d.toLocal() : d;
}
