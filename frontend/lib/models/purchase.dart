import 'package:frontend/models/installment.dart';

class Purchase {
  final int id;
  final int customerId;
  final String productName;
  final double amount;
  final double totalDue;
  final int installmentsCount;
  final double installmentAmount;
  final String frequency;
  final DateTime startDate;
  final String status;
  final int companyId;
  final List<Installment> installmentsList;

  Purchase({
    required this.id,
    required this.customerId,
    required this.productName,
    required this.amount,
    required this.totalDue,
    required this.installmentsCount,
    required this.installmentAmount,
    required this.frequency,
    required this.startDate,
    required this.status,
    required this.companyId,
    this.installmentsList =
        const [], // Inicializa como una lista vacía si no se proporciona
  });

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: json['id'],
    customerId: json['customer_id'],
    productName: json['product_name'],
    amount: json['amount'].toDouble(),
    totalDue: json['total_due'].toDouble(),
    installmentsCount: json['installments_count'],
    installmentAmount: json['installment_amount'].toDouble(),
    frequency: json['frequency'],
    startDate: DateTime.parse(json['start_date']),
    status: json['status'],
    companyId: json['company_id'],
    installmentsList:
        (json['installments_list'] as List)
            .map((i) => Installment.fromJson(i))
            .toList(),
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
    };
  }
}
