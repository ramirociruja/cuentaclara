class Customer {
  final int id;
  final String firstName;
  final String lastName;
  final String dni;
  final String address;
  final String phone;
  final String province;
  final int companyId;
  final int employeeId;
  final DateTime? createdAt;
  final String email;

  Customer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.dni,
    required this.address,
    required this.phone,
    required this.province,
    required this.companyId,
    required this.employeeId,
    this.createdAt,
    required this.email,
  });

  String get fullName => ('$firstName $lastName').trim();

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'dni': dni,
      'address': address,
      'phone': phone,
      'province': province,
      'company_id': companyId,
      'employee_id': employeeId,
      'email': email,
      // no enviamos id/createdAt
    };
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int,
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      dni: (json['dni'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      province: (json['province'] ?? '').toString(),
      companyId: json['company_id'] as int,
      employeeId: json['employee_id'] as int,
      createdAt:
          (json['created_at'] != null &&
                  json['created_at'].toString().isNotEmpty)
              ? DateTime.parse(json['created_at'])
              : null,
      email: (json['email'] ?? '').toString(),
    );
  }
}
