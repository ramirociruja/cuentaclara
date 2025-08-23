class Customer {
  final int id;
  final String name;
  final String dni; // Campo DNI
  final String address;
  final String phone;
  final String province;
  final int companyId;
  final int employeeId;
  final DateTime? createdAt; // Ahora es opcional y de tipo DateTime
  final String email; // Agregado el campo email

  Customer({
    required this.id,
    required this.name,
    required this.dni, // Campo DNI
    required this.address,
    required this.phone,
    required this.province,
    required this.companyId,
    required this.employeeId,
    this.createdAt, // Opcional
    required this.email, // Agregado el campo email
  });

  // Método toJson actualizado
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dni': dni,
      'address': address,
      'phone': phone,
      'province': province,
      'company_id': companyId,
      'employee_id': employeeId,
      'email': email, // Incluido el campo email
      // No incluimos createdAt ni id
    };
  }

  // Método fromJson actualizado
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      name: json['name'],
      dni: json['dni'],
      address: json['address'],
      phone: json['phone'],
      province: json['province'],
      companyId: json['company_id'],
      employeeId: json['employee_id'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : null,
      email: json['email'], // Asegurando que se incluya el campo email
    );
  }
}
