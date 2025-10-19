import 'package:frontend/shared/status.dart';

class Installment {
  final int id;
  final double amount;
  final DateTime dueDate;
  final String status; // etiqueta ES para UI
  final bool isPaid;
  final bool isOverdue;
  final int number;
  final double paidAmount;

  Installment({
    required this.id,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.isPaid,
    required this.isOverdue,
    required this.number,
    required this.paidAmount,
  });

  // ---- helpers seguros ----
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    final d = DateTime.tryParse(s);
    return d ?? DateTime.now();
  }

  factory Installment.fromJson(Map<String, dynamic> json) {
    final due = _parseDate(json['due_date']);
    final raw = json['status'] as String?;
    final statusEs = normalizeInstallmentStatus(raw); // 👈 ES UI

    final isPaid =
        (json['is_paid'] as bool?) ??
        (toCanonicalInstallmentStatus(raw) == 'paid');

    final isOverdue =
        (json['is_overdue'] as bool?) ??
        (toCanonicalInstallmentStatus(raw) == 'overdue');

    return Installment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: due,
      status: statusEs,
      isPaid: isPaid,
      isOverdue: isOverdue,
      number: (json['number'] as num?)?.toInt() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'status': toCanonicalInstallmentStatus(status), // 👈 EN canónico
      'is_paid': isPaid,
      'is_overdue': isOverdue,
      'number': number,
      'paid_amount': paidAmount,
    };
  }
}
