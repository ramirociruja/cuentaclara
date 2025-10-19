import 'package:frontend/models/installment.dart';
import 'package:frontend/shared/status.dart';

class Loan {
  final int id;
  final int customerId;
  final double amount;
  final double totalDue;
  final int installmentsCount;
  final double installmentAmount;
  final String frequency; // "weekly" or "monthly"
  final String startDate; // podés migrar a DateTime si te sirve
  final String status; // etiqueta ES para UI: Activo/Pagado/...
  final int companyId;
  final List<Installment> installments;
  final String? description;
  final int? collectionDay; // 1..7 (ISO: 1=lunes … 7=domingo)

  Loan({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.totalDue,
    required this.installmentsCount,
    required this.installmentAmount,
    required this.frequency,
    required this.startDate,
    required this.status, // ES UI
    required this.companyId,
    this.installments = const [],
    this.description,
    this.collectionDay,
  });

  factory Loan.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    final statusEs = normalizeLoanStatus(rawStatus); // 👈 ES UI

    return Loan(
      id: (json['id'] as num).toInt(),
      customerId: (json['customer_id'] as num).toInt(),
      amount: (json['amount'] as num).toDouble(),
      totalDue: (json['total_due'] as num).toDouble(),
      installmentsCount: (json['installments_count'] as num).toInt(),
      installmentAmount: (json['installment_amount'] as num).toDouble(),
      frequency: json['frequency'] as String,
      startDate: (json['start_date'] as String),
      status: statusEs, // 👈 guardamos ES
      companyId: (json['company_id'] as num).toInt(),
      description: json['description'] as String?,
      collectionDay: (json['collection_day'] as num?)?.toInt(),
      installments:
          ((json['installments'] as List?) ?? const [])
              .map((i) => Installment.fromJson(i as Map<String, dynamic>))
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
      'status': toCanonicalLoanStatus(status), // 👈 EN canónico
      'company_id': companyId,
      'installments': [], // normalmente no se envían aquí
      if (description != null && description!.trim().isNotEmpty)
        'description': description,
      if (collectionDay != null) 'collection_day': collectionDay,
    };
  }
}
