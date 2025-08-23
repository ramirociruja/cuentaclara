class Installment {
  final int id;
  final double amount;
  final DateTime dueDate;
  final String status;
  final bool isPaid;
  final bool isOverdue;
  final int number;
  final double paidAmount; // Agregar el campo paidAmount

  Installment({
    required this.id,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.isPaid,
    required this.isOverdue,
    required this.number,
    required this.paidAmount, // Agregar al constructor
  });

  factory Installment.fromJson(Map<String, dynamic> json) {
    return Installment(
      id: json['id'],
      amount: json['amount'],
      dueDate: DateTime.parse(json['due_date']),
      status: json['status'],
      isPaid: json['is_paid'],
      isOverdue: json['is_overdue'],
      number: json['number'],
      paidAmount: json['paid_amount'], // Mapear el campo paid_amount
    );
  }
}
