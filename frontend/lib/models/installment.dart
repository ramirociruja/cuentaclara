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
  final int? loanId; // 👈 NUEVO (opcional)

  Installment({
    required this.id,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.isPaid,
    required this.isOverdue,
    required this.number,
    required this.paidAmount,
    this.loanId, // 👈
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

    int? _parseLoanId(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      if (v is Map<String, dynamic>) {
        final cand = v['id'] ?? v['loan_id'];
        if (cand is num) return cand.toInt();
        if (cand is String) return int.tryParse(cand);
      }
      return null;
    }

    return Installment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: due,
      status: statusEs,
      isPaid: isPaid,
      isOverdue: isOverdue,
      number: (json['number'] as num?)?.toInt() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      loanId: _parseLoanId(json['loan_id'] ?? json['loan']),
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
      if (loanId != null) 'loan_id': loanId, // 👈 opcional
    };
  }
}
