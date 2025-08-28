import 'dart:convert';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/models/puchase.dart';
import 'package:frontend/models/api_result.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Ahora soporta --dart-define=API_BASE_URL=http://IP:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'http://192.168.100.5:8000', // <-- podés cambiarlo con --dart-define
  );

  // ----------------- Auth & storage -----------------

  static Future<void> saveCompanyId(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('company_id', companyId);
  }

  static Future<int?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('company_id');
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

  // Helper para headers (si después querés usar token, descomentá Authorization)
  static Future<Map<String, String>> _headers() async {
    final h = <String, String>{'Content-Type': 'application/json'};
    // final token = await getToken();
    // if (token != null && token.isNotEmpty) {
    //   h['Authorization'] = 'Bearer $token';
    // }
    return h;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ----------------- Auth -----------------

  // Servicio de login
  static Future<bool> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');

    try {
      final response = await http.post(
        url,
        headers: await _headers(),
        body: jsonEncode({'username': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        final employeeId = data['employee_id'];
        final companyId = data['company_id'];

        await saveToken(token);
        await saveEmployeeId(employeeId);
        await saveCompanyId(companyId);
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

  // ----------------- Customers -----------------

  // Obtener clientes del empleado logueado
  static Future<List<Customer>> fetchCustomersByEmployee() async {
    final employeeId = await getEmployeeId();
    if (employeeId == null) {
      throw Exception("Employee ID no encontrado.");
    }

    final url = Uri.parse('$baseUrl/customers/employees/$employeeId');

    try {
      final response = await http.get(url, headers: await _headers());
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

  // Crear cliente
  static Future<ApiResult<Customer>> createCustomer(Customer customer) async {
    final url = Uri.parse('$baseUrl/customers/');

    try {
      final response = await http.post(
        url,
        headers: await _headers(),
        body: jsonEncode(customer.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return ApiResult.success(Customer.fromJson(jsonDecode(response.body)));
      } else {
        // Intentar extraer el detalle del backend FastAPI: {"detail": "..."}
        String message = 'No se pudo crear el cliente';
        try {
          final decodedBody = utf8.decode(response.bodyBytes);
          final json = jsonDecode(decodedBody);
          if (json is Map && json['detail'] != null) {
            message = json['detail'].toString();
          }
        } catch (_) {
          // Si el body no es JSON, dejar el genérico pero con código
          message =
              'Error ${response.statusCode}: ${response.reasonPhrase ?? 'Servidor'}';
        }
        return ApiResult.failure(message);
      }
    } catch (e) {
      return ApiResult.failure('Error de conexión: $e');
    }
  }

  // Número de cuotas vencidas por cliente
  static Future<int> fetchOverdueInstallmentCount(int customerId) async {
    final url = Uri.parse(
      '$baseUrl/installments/by-customer/$customerId/overdue-count',
    );

    try {
      final response = await http.get(url, headers: await _headers());
      if (response.statusCode == 200 || response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error al obtener cuotas vencidas: ${response.statusCode}');
        throw Exception('Failed to load overdue installments count');
      }
    } catch (e) {
      print('Error de red: $e');
      throw Exception('Failed to load overdue installments count');
    }
  }

  static Future<Customer> fetchCustomerById(int customerId) async {
    final url = Uri.parse('$baseUrl/customers/$customerId');
    final response = await http.get(url, headers: await _headers());

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
    final url = Uri.parse('$baseUrl/customers/${customer.id}');
    final response = await http.put(
      url,
      headers: await _headers(),
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

  // ----------------- Loans & Purchases -----------------

  static Future<List<Loan>> fetchLoansByCustomer(int customerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/loans/customer/$customerId'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Loan.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load loans');
    }
  }

  static Future<List<Purchase>> fetchPurchasesByCustomer(int customerId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/purchases/customer/$customerId'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => Purchase.fromJson(item)).toList();
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception('Error al cargar las compras: ${response.statusCode}');
    }
  }

  static Future<List<Installment>> fetchInstallmentsByLoan(int loanId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/loans/$loanId/installments'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Installment.fromJson(json)).toList();
    } else {
      throw Exception('No se pudieron obtener las cuotas');
    }
  }

  static Future<Loan?> createLoan(Loan loan) async {
    final url = Uri.parse('$baseUrl/loans/createLoan/');

    try {
      final response = await http.post(
        url,
        headers: await _headers(),
        body: jsonEncode(loan.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Loan.fromJson(jsonDecode(response.body));
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

  static Future<Purchase?> createPurchase(Purchase purchase) async {
    final url = Uri.parse('$baseUrl/purchases/');

    try {
      final response = await http.post(
        url,
        headers: await _headers(),
        body: jsonEncode(purchase.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Purchase.fromJson(jsonDecode(response.body));
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

  static Future<void> registerPayment(int loanId, double amount) async {
    final response = await http.post(
      Uri.parse('$baseUrl/loans/$loanId/pay'),
      headers: await _headers(),
      body: json.encode({'amount_paid': amount}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error al registrar el pago');
    }

    final data = json.decode(response.body);
    print(data['message']);
  }

  static Future<Loan> fetchLoanDetails(int loanId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/loans/loans/$loanId'),
        headers: await _headers(),
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

  // ----------------- Installments (Nuevo) -----------------

  /// Lista de cuotas con filtros para la pantalla "Cuotas de la semana".
  /// Backend: GET /installment/
  static Future<List<Installment>> fetchInstallments({
    int? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool onlyPending = true,
    String? status,
  }) async {
    final qp = <String, String>{};
    if (employeeId != null) qp['employee_id'] = '$employeeId';
    if (dateFrom != null) qp['date_from'] = _fmtDate(dateFrom);
    if (dateTo != null) qp['date_to'] = _fmtDate(dateTo);
    if (onlyPending) qp['only_pending'] = 'true';
    if (status != null) qp['status'] = status;

    final uri = Uri.parse(
      '$baseUrl/installments/',
    ).replace(queryParameters: qp);
    final resp = await http.get(uri, headers: await _headers());

    if (resp.statusCode == 200) {
      final List data = jsonDecode(resp.body) as List;
      return data.map((e) => Installment.fromJson(e)).toList();
    }
    throw Exception('GET /installment/ -> ${resp.statusCode}: ${resp.body}');
  }

  /// KPIs para la pantalla (pendientes, cobradas, vencidas, totales).
  /// Backend: GET /installment/summary
  static Future<Map<String, dynamic>> fetchInstallmentsSummary({
    int? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final qp = <String, String>{};
    if (employeeId != null) qp['employee_id'] = '$employeeId';
    if (dateFrom != null) qp['date_from'] = _fmtDate(dateFrom);
    if (dateTo != null) qp['date_to'] = _fmtDate(dateTo);

    final uri = Uri.parse(
      '$baseUrl/installments/summary',
    ).replace(queryParameters: qp);
    final resp = await http.get(uri, headers: await _headers());

    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception(
      'GET /installment/summary -> ${resp.statusCode}: ${resp.body}',
    );
  }

  /// Marcar cuota como pagada. Intenta POST moderna y retrocede a PUT legacy.
  static Future<Installment> payInstallment({
    required int installmentId,
    required double amount,
    String? notes,
  }) async {
    final body = json.encode({
      'amount': amount,
      if (notes != null) 'notes': notes,
    });

    // 1) Intento moderno: POST /installments/{id}/pay
    var resp = await http.post(
      Uri.parse('$baseUrl/installments/$installmentId/pay'),
      headers: await _headers(),
      body: body,
    );

    if (resp.statusCode == 200) {
      return Installment.fromJson(json.decode(resp.body));
    }

    // 2) Fallback legacy: PUT /installment/{id}/pay
    if (resp.statusCode == 404 || resp.statusCode == 405) {
      resp = await http.put(
        Uri.parse('$baseUrl/installment/$installmentId/pay'),
        headers: await _headers(),
        body: body,
      );
      if (resp.statusCode == 200) {
        return Installment.fromJson(json.decode(resp.body));
      }
    }

    try {
      final errorData = json.decode(resp.body);
      throw Exception(errorData['detail'] ?? 'Error al registrar el pago');
    } catch (_) {
      throw Exception('Error al registrar el pago: HTTP ${resp.statusCode}');
    }
  }

  /// Estados que usás en DB
  static const String _kPagada = 'Pagada';
  static const String _kPendiente = 'Pendiente';
  static const String _kParcial = 'Parcialmente Pagada';

  /// Lista enriquecida (con customer_name / debt_type / loan_id)
  static Future<List<InstallmentListItem>> fetchInstallmentsEnriched({
    int? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
    // 'pendientes' | 'pagadas' | 'todas'
    String statusFilter = 'pendientes',
  }) async {
    final qp = <String, String>{};
    if (employeeId != null) qp['employee_id'] = '$employeeId';
    if (dateFrom != null) qp['date_from'] = _fmtDate(dateFrom);
    if (dateTo != null) qp['date_to'] = _fmtDate(dateTo);

    // Hint para backend (si no filtra igual filtramos en cliente)
    if (statusFilter == 'pendientes') {
      qp['only_pending'] = 'true'; // incluye Pendiente + Parcial
    } else if (statusFilter == 'pagadas') {
      qp['status'] = _kPagada; // ⚠️ en español
    }

    // barra final para evitar 307
    final primary = Uri.parse(
      '$baseUrl/installments/',
    ).replace(queryParameters: qp);
    final alt = Uri.parse('$baseUrl/installment/').replace(queryParameters: qp);

    var resp = await http.get(primary, headers: await _headers());
    if (resp.statusCode == 404 || resp.statusCode == 405) {
      resp = await http.get(alt, headers: await _headers());
    }

    if (resp.statusCode == 200) {
      final List data = jsonDecode(resp.body) as List;
      var items =
          data
              .map(
                (e) => InstallmentListItem.fromJson(e as Map<String, dynamic>),
              )
              .toList();

      // ✅ Filtro de seguridad del lado cliente (por si el backend no filtró)
      if (statusFilter == 'pendientes') {
        items =
            items.where((x) {
              final st = (x.installment.status).trim();
              return st == _kPendiente ||
                  st == _kParcial ||
                  x.installment.isPaid == false;
            }).toList();
      } else if (statusFilter == 'pagadas') {
        items =
            items.where((x) {
              final st = (x.installment.status).trim();
              return st == _kPagada || x.installment.isPaid == true;
            }).toList();
      }
      return items;
    }
    throw Exception('GET ${primary.path} -> ${resp.statusCode}: ${resp.body}');
  }

  static Future<List<dynamic>> fetchPayments({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final url = Uri.parse(
      '$baseUrl/payments?employee_id=$employeeId'
      '&date_from=${dateFrom.toIso8601String()}'
      '&date_to=${dateTo.toIso8601String()}',
    );
    final resp = await http.get(url, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return (data as List);
    }
    throw Exception('No se pudo obtener la lista de pagos');
  }

  static Future<CreditsSummary> fetchCreditsSummary({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final url = Uri.parse(
      '$baseUrl/loans/summary?employee_id=$employeeId'
      '&date_from=${dateFrom.toIso8601String()}'
      '&date_to=${dateTo.toIso8601String()}',
    );
    final resp = await http.get(url, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return CreditsSummary(
        (data['count'] ?? 0) as int,
        (data['amount'] ?? 0).toDouble(),
      );
    }
    throw Exception('No se pudo obtener el summary de créditos');
  }

  static Future<double> fetchPaymentsTotal({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final url = Uri.parse(
      '$baseUrl/payments/summary?employee_id=$employeeId'
      '&date_from=${dateFrom.toIso8601String()}'
      '&date_to=${dateTo.toIso8601String()}',
    );
    final resp = await http.get(url, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return (data['total_amount'] ?? 0).toDouble();
    }
    throw Exception('No se pudo obtener el summary de pagos');
  }
}

class InstallmentListItem {
  final Installment installment;
  final String? customerName;
  final String? debtType; // "loan"|"purchase"
  final int? loanId; // 👈 nuevo

  InstallmentListItem({
    required this.installment,
    this.customerName,
    this.debtType,
    this.loanId,
  });

  factory InstallmentListItem.fromJson(Map<String, dynamic> json) {
    return InstallmentListItem(
      installment: Installment.fromJson(json),
      customerName: json['customer_name'] as String?,
      debtType: json['debt_type'] as String?,
      loanId: json['loan_id'] as int?, // 👈
    );
  }
}

class CreditsSummary {
  final int count;
  final double amount;
  CreditsSummary(this.count, this.amount);
}
