import 'package:frontend/models/installment.dart';

class Loan {
  final int id;
  final int customerId;
  final double amount;
  final double totalDue;
  final int installmentsCount;
  final double installmentAmount;
  final String frequency; // "weekly" or "monthly"
  final String startDate;
  final String status; // "active", "paid", "defaulted"
  final int companyId;
  final List<Installment> installments;

  Loan({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.totalDue,
    required this.installmentsCount,
    required this.installmentAmount,
    required this.frequency,
    required this.startDate,
    required this.status,
    required this.companyId,
    this.installments = const [],
  });

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as int,
      customerId: json['customer_id'] as int,
      amount: (json['amount'] as num).toDouble(),
      totalDue: (json['total_due'] as num).toDouble(),
      installmentsCount: json['installments_count'] as int,
      installmentAmount: (json['installment_amount'] as num).toDouble(),
      frequency: json['frequency'] as String,
      startDate: (json['start_date'] as String),
      status: json['status'] as String,
      companyId: json['company_id'] as int,
      installments:
          (json['installments'] as List)
              .map((i) => Installment.fromJson(i))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'amount': amount,
      'total_due': totalDue,
      'installments_count': installmentsCount,
      'installment_amount': installmentAmount,
      'frequency': frequency,
      'start_date': startDate,
      'status': status,
      'company_id': companyId,
      'installments': [],
    };
  }
}
