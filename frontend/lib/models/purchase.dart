import 'package:frontend/models/installment.dart';

class Purchase {
  final int id;
  final int customerId;
  final String productName;
  final double amount;
  final double totalDue;
  final int installmentsCount;
  final double installmentAmount;
  final String? frequency;
  final DateTime startDate;
  final String status;
  final List<Installment> installmentsList;
  final int? installmentIntervalDays;

  Purchase({
    required this.id,
    required this.customerId,
    required this.productName,
    required this.amount,
    required this.totalDue,
    required this.installmentsCount,
    required this.installmentAmount,
    this.frequency,
    required this.startDate,
    required this.status,
    this.installmentsList =
        const [], // Inicializa como una lista vacía si no se proporciona
    this.installmentIntervalDays,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: json['id'],
    customerId: json['customer_id'],
    productName: json['product_name'],
    amount: json['amount'].toDouble(),
    totalDue: json['total_due'].toDouble(),
    installmentsCount: json['installments_count'],
    installmentAmount: json['installment_amount'].toDouble(),
    frequency: json['frequency']?.toString(),
    startDate: DateTime.parse(json['start_date']),
    status: json['status'],
    installmentsList:
        (json['installments_list'] as List)
            .map((i) => Installment.fromJson(i))
            .toList(),
    installmentIntervalDays:
        (json['installment_interval_days'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'total_due': totalDue,
      'installments_count': installmentsCount,
      'installment_amount': installmentAmount,
      'frequency': frequency,
      'start_date': startDate,
      'status': status,
      'customer_id': customerId,
      "installment_interval_days": installmentIntervalDays,
    };
  }
}
