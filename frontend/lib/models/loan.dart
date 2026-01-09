import 'package:frontend/models/installment.dart';
import 'package:frontend/shared/status.dart';

class Loan {
  final int id;
  final int customerId;
  final double amount;
  final double totalDue;
  final int installmentsCount;
  final double installmentAmount;
  final String? frequency; // "weekly" or "monthly"
  final String startDate; // podés migrar a DateTime si te sirve
  final String status; // etiqueta ES para UI: Activo/Pagado/...
  final int? companyId;
  final List<Installment> installments;
  final String? description;
  final int? collectionDay; // 1..7 (ISO: 1=lunes … 7=domingo)
  final int? installmentIntervalDays;

  /// 👇 NUEVO: cobrador dueño del préstamo (employee_id en backend)
  final int? employeeId;

  final String? employeeName;

  Loan({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.totalDue,
    required this.installmentsCount,
    required this.installmentAmount,
    this.frequency,
    required this.startDate,
    required this.status, // ES UI
    this.companyId,
    this.installments = const [],
    this.description,
    this.collectionDay,
    this.employeeId, // 👈 nuevo param opcional
    this.employeeName,
    this.installmentIntervalDays,
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
      frequency: json['frequency']?.toString(),
      startDate: (json['start_date'] as String),
      status: statusEs, // 👈 guardamos ES
      companyId: (json['company_id'] as num?)?.toInt(),
      description: json['description'] as String?,
      collectionDay: (json['collection_day'] as num?)?.toInt(),
      installments:
          ((json['installments'] as List?) ?? const [])
              .map((i) => Installment.fromJson(i as Map<String, dynamic>))
              .toList(),

      /// 👇 NUEVO: lo tomamos si viene del backend (puede venir null en datos viejos)
      employeeId: (json['employee_id'] as num?)?.toInt(),
      employeeName: json['employee_name'] as String?,
      installmentIntervalDays:
          (json['installment_interval_days'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'amount': amount,
      'installments_count': installmentsCount,
      'installment_amount': installmentAmount,
      'start_date': startDate,
      if (description != null && description!.trim().isNotEmpty)
        'description': description,
      if (collectionDay != null) 'collection_day': collectionDay,

      /// 👇 NUEVO: solo lo mandamos si está seteado
      if (employeeId != null) 'employee_id': employeeId,
      if (installmentIntervalDays != null)
        "installment_interval_days": installmentIntervalDays,
    };
  }
}
