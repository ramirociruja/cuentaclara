import 'dart:convert';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/models/puchase.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.100.5:8000'; // <-- cambiar esto

  // Servicio de login
  static Future<bool> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        final employeeId = data['employee_id'];
        final companyId = data['company_id']; // Obtener company_id

        await saveToken(token);
        await saveEmployeeId(employeeId);
        await saveCompanyId(companyId); // Guardar company_id

        return true;
      } else {
        print('Error de login: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error de red: $e');
      return false;
    }
  }

  static Future<void> saveCompanyId(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('company_id', companyId); // Guardar el company_id
  }

  static Future<int?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('company_id'); // Recuperar el company_id
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<void> saveEmployeeId(int employeeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('employee_id', employeeId);
  }

  static Future<int?> getEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('employee_id');
  }

  // Servicio para obtener los clientes de un empleado específico
  static Future<List<Customer>> fetchCustomersByEmployee() async {
    final employeeId = await getEmployeeId(); // Recuperamos el employeeId

    if (employeeId == null) {
      throw Exception("Employee ID no encontrado.");
    }

    final url = Uri.parse('$baseUrl/customers/employees/$employeeId/customers');

    try {
      final response = await http.get(url); // No necesitamos pasar el token

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((customer) => Customer.fromJson(customer)).toList();
      } else {
        print('Error al obtener los clientes: ${response.statusCode}');
        throw Exception('Failed to load customers');
      }
    } catch (e) {
      print('Error de red: $e');
      throw Exception('Failed to load customers');
    }
  }

  // Servicio para crear un nuevo cliente
  static Future<Customer?> createCustomer(Customer customer) async {
    final url = Uri.parse('$baseUrl/customers/createCustomers/');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(customer.toJson()),
      );

      if (response.statusCode == 201) {
        return Customer.fromJson(jsonDecode(response.body));
      } else {
        print('Error del servidor: ${response.statusCode}');
        print('Respuesta: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error de conexión: $e');
      return null;
    }
  }

  // Método para obtener el número de cuotas vencidas de un cliente
  static Future<int> fetchOverdueInstallmentCount(int customerId) async {
    final url = Uri.parse(
      '$baseUrl/installments/by-customer/$customerId/overdue-count',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(
          response.body,
        ); // Retorna el número de cuotas vencidas
      } else {
        print('Error al obtener las cuotas vencidas: ${response.statusCode}');
        throw Exception('Failed to load overdue installments count');
      }
    } catch (e) {
      print('Error de red: $e');
      throw Exception('Failed to load overdue installments count');
    }
  }

  static Future<List<Loan>> fetchLoansByCustomer(int customerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/loans/customer/$customerId'),
    );

    if (response.statusCode == 200) {
      // Si la solicitud fue exitosa, parseamos el JSON
      List<dynamic> data = json.decode(response.body);

      // Convertimos el JSON en una lista de objetos Loan
      List<Loan> loans = data.map((json) => Loan.fromJson(json)).toList();
      return loans;
    } else {
      // Si hubo un error, lanzamos una excepción
      throw Exception('Failed to load loans');
    }
  }

  static Future<List<Purchase>> fetchPurchasesByCustomer(int customerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/purchases/customer/$customerId'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => Purchase.fromJson(item)).toList();
    } else if (response.statusCode == 404) {
      // Si no hay compras para este cliente
      return [];
    } else {
      throw Exception('Error al cargar las compras: ${response.statusCode}');
    }
  }

  static Future<List<Installment>> fetchInstallmentsByLoan(int loanId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/loans/$loanId/installments'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Installment.fromJson(json)).toList();
    } else {
      throw Exception('No se pudieron obtener las cuotas');
    }
  }
  /*
  static Future<List<Installment>> fetchInstallmentsByPurchase(
    int purchaseId,
  ) async {
    final response = await http.get(
      Uri.parse('your-api-url/installments?purchase_id=$purchaseId'),
    );
    // Implementación del manejo de respuesta y mapeo de datos
  }*/

  static Future<Loan?> createLoan(Loan loan) async {
    final url = Uri.parse(
      '$baseUrl/loans/createLoan/',
    ); // Ajusta la URL según corresponda

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          loan.toJson(),
        ), // Suponiendo que 'toJson' está implementado en la clase Loan
      );

      if (response.statusCode == 201) {
        return Loan.fromJson(
          jsonDecode(response.body),
        ); // Devuelve el objeto Loan creado
      } else {
        print('Error del servidor: ${response.statusCode}');
        print('Respuesta: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error de conexión: $e');
      return null;
    }
  }

  // Servicio para crear un nuevo Purchase
  static Future<Purchase?> createPurchase(Purchase purchase) async {
    final url = Uri.parse(
      '$baseUrl/purchases/createPurchase/',
    ); // Ajusta la URL según corresponda

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          purchase.toJson(),
        ), // Suponiendo que 'toJson' está implementado en la clase Purchase
      );

      if (response.statusCode == 201) {
        return Purchase.fromJson(
          jsonDecode(response.body),
        ); // Devuelve el objeto Purchase creado
      } else {
        print('Error del servidor: ${response.statusCode}');
        print('Respuesta: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error de conexión: $e');
      return null;
    }
  }

  static Future<Customer> fetchCustomerById(int customerId) async {
    final url = Uri.parse('$baseUrl/customers/$customerId');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      return Customer.fromJson(jsonData);
    } else if (response.statusCode == 404) {
      throw Exception('Cliente no encontrado');
    } else {
      throw Exception('Error al cargar el cliente (${response.statusCode})');
    }
  }

  static Future<Customer> updateCustomer(Customer customer) async {
    final url = Uri.parse('$baseUrl/customers/edit/${customer.id}');

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': customer.name,
        'dni': customer.dni,
        'address': customer.address,
        'phone': customer.phone,
        'province': customer.province,
        'email': customer.email,
        'company_id': customer.companyId,
        'employee_id': customer.employeeId,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Customer.fromJson(data);
    } else {
      throw Exception('Error al actualizar el cliente: ${response.body}');
    }
  }

  static Future<void> registerPayment(int loanId, double amount) async {
    final response = await http.post(
      Uri.parse('$baseUrl/loans/$loanId/pay'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'amount_paid': amount}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error al registrar el pago');
    }

    // Opcional: podrías leer el mensaje si querés mostrarlo
    final data = json.decode(response.body);
    print(data['message']); // o simplemente ignorarlo si no lo usás
  }

  static Future<Loan> fetchLoanDetails(int loanId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/loans/loans/$loanId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return Loan.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw Exception('Préstamo no encontrado');
      } else {
        throw Exception('Error al cargar el préstamo: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en fetchLoanDetails: $e');
      throw Exception('No se pudo obtener el préstamo: $e');
    }
  }

  static Future<Installment> payInstallment({
    required int installmentId,
    required double amount,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installments/$installmentId/pay'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'amount': amount, 'notes': notes}),
      );

      if (response.statusCode == 200) {
        return Installment.fromJson(json.decode(response.body));
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Error al registrar el pago');
      }
    } on http.ClientException catch (e) {
      throw Exception('Error de conexión: ${e.message}');
    } catch (e) {
      throw Exception('Error al procesar el pago: $e');
    }
  }
}
