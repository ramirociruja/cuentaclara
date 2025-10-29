import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/models/purchase.dart';
import 'package:frontend/models/api_result.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/services/token_storage.dart';
// 👇 NUEVO: helpers para normalizar/canonizar estados
import 'package:frontend/shared/status.dart' as st;

/// Excepción específica cuando la sesión expiró y el refresh no pudo renovarla.
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = 'Sesión expirada']);
  @override
  String toString() => message;
}

class PayInstallmentResult {
  final Installment installment;
  final int? paymentId;
  PayInstallmentResult({required this.installment, this.paymentId});
}

/// Eventos de autenticación para reaccionar globalmente desde la app (main.dart).
class AuthEvents {
  static const loggedIn = 'loggedIn';
  static const sessionExpired = 'sessionExpired';
  static const loggedOut = 'loggedOut';
}

class ApiService {
  // Ahora soporta --dart-define=API_BASE_URL=http://IP:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://cuentaclara-production.up.railway.app',
    //defaultValue: 'http://192.168.100.5:8000',
  );

  static void _assertHttpsInRelease() {
    // Permite http:// solo en debug/profile. En release exige https://
    const url = baseUrl;
    if (kReleaseMode && url.startsWith('http://')) {
      throw StateError(
        'API_BASE_URL debe usar HTTPS en release. Valor actual: $url',
      );
    }
  }

  static const String kTZ = 'America/Argentina/Buenos_Aires';

  // ----------------- Event bus (auth) -----------------
  static final _authEvents = StreamController<String>.broadcast();
  static Stream<String> get authEvents => _authEvents.stream;

  // ----------------- Auth (secure) -----------------
  static String? _accessToken; // cache en memoria
  static String? _refreshToken; // cache en memoria
  static Completer<bool>? _refreshing;
  static bool _initDone = false;
  static String? _cachedEmployeeName;

  /// (Opcional) Llamá en main(): await ApiService.init();
  static Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    _assertHttpsInRelease();
    // Migra tokens de SharedPreferences → SecureStorage si aplica
    await TokenStorage.migrateFromPrefsIfNeeded();
    _accessToken ??= await TokenStorage.readAccess();
    _refreshToken ??= await TokenStorage.readRefresh();
  }

  static Future<String?> getEmployeeName() async {
    if (_cachedEmployeeName != null) return _cachedEmployeeName;

    // Helper para extraer un nombre legible desde distintos esquemas
    String? _pickName(dynamic raw) {
      if (raw == null) return null;
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is Map<String, dynamic>) {
        final m = raw;
        final full =
            (m['name'] ?? m['full_name'] ?? m['fullName'] ?? m['username'])
                ?.toString();
        if (full != null && full.trim().isNotEmpty) return full.trim();

        final first = (m['first_name'] ?? m['firstName'])?.toString().trim();
        final last = (m['last_name'] ?? m['lastName'])?.toString().trim();
        final joined = [
          first,
          last,
        ].where((s) => s != null && s.isNotEmpty).join(' ');
        if (joined.trim().isNotEmpty) return joined.trim();
      }
      return null;
    }

    try {
      final id = await getEmployeeId();
      // 1) /employees/{id}
      if (id != null) {
        final uri1 = Uri.parse('$baseUrl/employees/$id');
        final r1 = await _get(uri1);
        if (r1.statusCode == 200) {
          final name = _pickName(_json(r1));
          if (name != null && name.isNotEmpty) {
            _cachedEmployeeName = name;
            return _cachedEmployeeName;
          }
        }
        // 2) /employee/{id} (por si tu backend usa singular)
        final uri2 = Uri.parse('$baseUrl/employee/$id');
        final r2 = await _get(uri2);
        if (r2.statusCode == 200) {
          final name = _pickName(_json(r2));
          if (name != null && name.isNotEmpty) {
            _cachedEmployeeName = name;
            return _cachedEmployeeName;
          }
        }
        // 3) /users/{id} (algunos backends lo exponen así)
        final uri3 = Uri.parse('$baseUrl/users/$id');
        final r3 = await _get(uri3);
        if (r3.statusCode == 200) {
          final name = _pickName(_json(r3));
          if (name != null && name.isNotEmpty) {
            _cachedEmployeeName = name;
            return _cachedEmployeeName;
          }
        }
      }

      // 4) /me (si tu backend expone el usuario actual)
      final meUri = Uri.parse('$baseUrl/me');
      final meRes = await _get(meUri);
      if (meRes.statusCode == 200) {
        final name = _pickName(_json(meRes));
        if (name != null && name.isNotEmpty) {
          _cachedEmployeeName = name;
          return _cachedEmployeeName;
        }
      }
    } catch (_) {
      // silenciamos errores de red / parse y devolvemos null abajo
    }

    return null;
  }

  // ----------------- Helpers de IDs (Prefs) -----------------
  static Future<void> saveCompanyId(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('company_id', companyId);
  }

  static Future<int?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('company_id');
  }

  // ApiService.dart
  static String? _cachedCompanyName;

  static Future<String?> getCompanyName() async {
    if (_cachedCompanyName != null) return _cachedCompanyName;

    try {
      final cid = await getCompanyId(); // ya lo tenés en prefs
      if (cid != null) {
        final res = await _get(Uri.parse('$baseUrl/companies/$cid'));
        if (res.statusCode == 200) {
          final j = _json(res);
          final name = (j['name'] ?? j['company_name'])?.toString();
          final trimmed = name?.trim();
          if (trimmed != null && trimmed.isNotEmpty) {
            _cachedCompanyName = trimmed;
            return _cachedCompanyName;
          }
        }
      }
    } catch (_) {}

    // Fallback: intentar /me
    try {
      final res = await _get(Uri.parse('$baseUrl/me'));
      if (res.statusCode == 200) {
        final j = _json(res);
        final name = (j['company']?['name'] ?? j['company_name'])?.toString();
        final trimmed = name?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          _cachedCompanyName = trimmed;
          return _cachedCompanyName;
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<void> saveEmployeeId(int employeeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('employee_id', employeeId);
  }

  static Future<int?> getEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('employee_id');
  }

  // ----------------- Tokens (SecureStorage) -----------------

  /// Guarda access y refresh (ambos) + cachea en memoria
  static Future<void> _setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    await TokenStorage.writeTokens(access: access, refresh: refresh);
  }

  /// Persiste un access token nuevo conservando el refresh actual.
  static Future<void> _persistAccessOnly(String access) async {
    _accessToken = access;
    final currentRefresh =
        _refreshToken ?? (await TokenStorage.readRefresh()) ?? '';
    await TokenStorage.writeTokens(access: access, refresh: currentRefresh);
  }

  static Future<String?> getToken() async {
    if (_accessToken != null) return _accessToken;
    _accessToken = await TokenStorage.readAccess();
    return _accessToken;
  }

  static Future<String?> getRefreshToken() async {
    if (_refreshToken != null) return _refreshToken;
    _refreshToken = await TokenStorage.readRefresh();
    return _refreshToken;
  }

  /// Limpia sesión (tokens seguros e IDs en prefs)
  static Future<void> clearAuth() async {
    _accessToken = null;
    _refreshToken = null;
    await TokenStorage.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('employee_id');
    await prefs.remove('company_id');

    // Avisar globalmente que se cerró sesión (manualmente o por cleanup)
    _authEvents.add(AuthEvents.loggedOut);
  }

  /// Intenta decodificar employee_id / company_id del JWT para guardarlos.
  static Future<void> _persistIdsFromToken(String jwt) async {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return;

      String normalize(String s) => s
          .padRight(s.length + (4 - s.length % 4) % 4, '=')
          .replaceAll('-', '+')
          .replaceAll('_', '/');

      final Uint8List payloadBytes = base64Url.decode(normalize(parts[1]));
      final payload = utf8.decode(payloadBytes);
      final map = jsonDecode(payload);

      final emp = map['employee_id'];
      final comp = map['company_id'];

      if (emp != null) {
        final v = (emp is String) ? int.tryParse(emp) : (emp as num).toInt();
        if (v != null) await saveEmployeeId(v);
      }
      if (comp != null) {
        final v = (comp is String) ? int.tryParse(comp) : (comp as num).toInt();
        if (v != null) await saveCompanyId(v);
      }
    } catch (_) {
      // ignorar errores de decode, no rompe el flujo
    }
  }

  // ----------------- Headers & JSON robusto -----------------

  // Headers con Bearer (lee de cache; si no hay, consulta SecureStorage)
  static Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!withAuth) return headers;

    _accessToken ??= await getToken();
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Decodifica siempre desde bytes → UTF8. Si falla, intenta latin1.
  static dynamic _json(http.Response resp) {
    final bytes = resp.bodyBytes;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      try {
        return jsonDecode(latin1.decode(bytes));
      } catch (e) {
        throw Exception('JSON decode error: $e');
      }
    }
  }

  // ----------------- Auto-refresh en 401 -----------------

  /// Intenta renovar el access token usando el refresh token.
  /// Retorna true si pudo renovar; si no, limpia sesión y emite `sessionExpired`.
  static Future<bool> _tryRefresh() async {
    // Si ya hay un refresh en curso, me cuelgo de ese.
    if (_refreshing != null) {
      try {
        return await _refreshing!.future;
      } catch (_) {
        return false;
      }
    }

    final startedWith = await getRefreshToken();
    if (startedWith == null || startedWith.isEmpty) return false;

    _refreshing = Completer<bool>();

    try {
      final url = Uri.parse('$baseUrl/refresh');
      final res = await http.post(
        url,
        headers: await _headers(withAuth: false),
        body: jsonEncode({'refresh_token': startedWith}),
      );

      if (res.statusCode == 200) {
        final j = _json(res) as Map<String, dynamic>;
        final String newAccess = j['access_token'] as String;
        final String? maybeNewRefresh = j['refresh_token'] as String?;

        // Persistir tokens
        if (maybeNewRefresh != null && maybeNewRefresh.isNotEmpty) {
          await _setTokens(newAccess, maybeNewRefresh);
        } else {
          await _persistAccessOnly(newAccess);
        }

        _accessToken = newAccess;
        if (maybeNewRefresh != null && maybeNewRefresh.isNotEmpty) {
          _refreshToken = maybeNewRefresh;
        }

        await _persistIdsFromToken(newAccess);

        if (j['employee_id'] != null) await saveEmployeeId(j['employee_id']);
        if (j['company_id'] != null) await saveCompanyId(j['company_id']);

        _refreshing!.complete(true);
        return true;
      }

      // Si falló con el refresh con el que empezamos, puede ser porque
      // OTRO refresh paralelo lo rotó y ya guardó uno nuevo.
      final current = await TokenStorage.readRefresh();
      if (current != null && current.isNotEmpty && current != startedWith) {
        _refreshing!.complete(true);
        return true;
      }

      // Falló y no hay refresh nuevo → expiró de verdad
      _refreshing!.complete(false);
      await clearAuth(); // emite loggedOut
      _authEvents.add(AuthEvents.sessionExpired);
      return false;
    } catch (_) {
      // Error de red u otro: no limpiar sesión por esto
      _refreshing!.complete(false);
      return false;
    } finally {
      _refreshing = null; // libera para futuros refresh
    }
  }

  // ---------- GET ----------
  static Future<http.Response> _get(Uri url) async {
    var resp = await http.get(url, headers: await _headers());
    if (resp.statusCode != 401) return resp;

    // intenta una sola vez renovar token
    if (await _tryRefresh()) {
      return await http.get(url, headers: await _headers());
    }

    throw SessionExpiredException();
  }

  // ---------- POST ----------
  static Future<http.Response> _post(
    Uri url, {
    Object? body,
    bool withAuth = true,
  }) async {
    var resp = await http.post(
      url,
      headers: await _headers(withAuth: withAuth),
      body: body,
    );

    // si no es auth o no hay 401 → devolvemos respuesta normal
    if (!withAuth || resp.statusCode != 401) return resp;

    // intenta renovar tokens
    if (await _tryRefresh()) {
      return await http.post(url, headers: await _headers(), body: body);
    }

    throw SessionExpiredException();
  }

  // ---------- PUT ----------
  static Future<http.Response> _put(Uri url, {Object? body}) async {
    var resp = await http.put(url, headers: await _headers(), body: body);
    if (resp.statusCode != 401) return resp;

    // reintenta solo una vez si se logró refrescar correctamente
    if (await _tryRefresh()) {
      return await http.put(url, headers: await _headers(), body: body);
    }

    throw SessionExpiredException();
  }

  /// Intento de login silencioso al abrir la app.
  /// Si el refresh sigue siendo válido, renueva el access y retorna true.
  static Future<bool> trySilentLogin() async {
    final rt = await getRefreshToken();
    if (rt == null || rt.isEmpty) return false;
    return await _tryRefresh();
  }

  // Formatea fecha como YYYY-MM-DD
  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ----------------- Auth -----------------

  // Servicio de login
  static Future<bool> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');

    try {
      final response = await http.post(
        url,
        headers: await _headers(withAuth: false),
        body: jsonEncode({'username': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = _json(response) as Map<String, dynamic>;
        final String access = data['access_token'];
        final String refresh = data['refresh_token'];
        final employeeId = data['employee_id'];
        final companyId = data['company_id'];

        await _setTokens(access, refresh);
        await _persistIdsFromToken(access);
        if (employeeId != null) await saveEmployeeId(employeeId);
        if (companyId != null) await saveCompanyId(companyId);

        // Aviso global: hay sesión activa
        _authEvents.add(AuthEvents.loggedIn);
        return true;
      } else {
        // ignore: avoid_print
        print('Error de login: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      // ignore: avoid_print
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
      final response = await _get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = _json(response) as List<dynamic>;
        return data.map((customer) => Customer.fromJson(customer)).toList();
      } else {
        // ignore: avoid_print
        print('Error al obtener los clientes: ${response.statusCode}');
        throw Exception('Failed to load customers');
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // ignore: avoid_print
      print('Error de red: $e');
      throw Exception('Failed to load customers');
    }
  }

  // Crear cliente
  static Future<ApiResult<Customer>> createCustomer(Customer customer) async {
    final url = Uri.parse('$baseUrl/customers/');

    try {
      final response = await _post(url, body: jsonEncode(customer.toJson()));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return ApiResult.success(Customer.fromJson(_json(response)));
      } else {
        // Intentar extraer el detalle del backend FastAPI: {"detail": "..."}
        String message = 'No se pudo crear el cliente';
        try {
          final jsonMap = _json(response);
          if (jsonMap is Map && jsonMap['detail'] != null) {
            message = jsonMap['detail'].toString();
          }
        } catch (_) {
          message =
              'Error ${response.statusCode}: ${response.reasonPhrase ?? 'Servidor'}';
        }
        return ApiResult.failure(message);
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      return ApiResult.failure('Error de conexión: $e');
    }
  }

  // Número de cuotas vencidas por cliente
  static Future<int> fetchOverdueInstallmentCount(int customerId) async {
    final url = Uri.parse(
      '$baseUrl/installments/by-customer/$customerId/overdue-count',
    );

    try {
      final response = await _get(url);
      if (response.statusCode == 200) {
        final v = _json(response);
        if (v is num) return v.toInt();
        return int.parse(v.toString());
      } else {
        // ignore: avoid_print
        print('Error al obtener cuotas vencidas: ${response.statusCode}');
        throw Exception('Failed to load overdue installments count');
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // ignore: avoid_print
      print('Error de red: $e');
      throw Exception('Failed to load overdue installments count');
    }
  }

  static Future<Customer> fetchCustomerById(int customerId) async {
    final url = Uri.parse('$baseUrl/customers/$customerId');
    final response = await _get(url);

    if (response.statusCode == 200) {
      final jsonData = _json(response) as Map<String, dynamic>;
      return Customer.fromJson(jsonData);
    } else if (response.statusCode == 404) {
      throw Exception('Cliente no encontrado');
    } else {
      throw Exception('Error al cargar el cliente (${response.statusCode})');
    }
  }

  static Future<Customer> updateCustomer(Customer customer) async {
    final url = Uri.parse('$baseUrl/customers/${customer.id}');
    final response = await _put(
      url,
      body: jsonEncode({
        'first_name': customer.firstName,
        'last_name': customer.lastName,
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
      final data = _json(response) as Map<String, dynamic>;
      return Customer.fromJson(data);
    } else {
      throw Exception(
        'Error al actualizar el cliente: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }

  // ----------------- Loans & Purchases -----------------

  static Future<List<Loan>> fetchLoansByCustomer(int customerId) async {
    final response = await _get(
      Uri.parse('$baseUrl/loans/customer/$customerId'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = _json(response) as List<dynamic>;
      return data.map((json) => Loan.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load loans');
    }
  }

  static Future<List<Purchase>> fetchPurchasesByCustomer(int customerId) async {
    final response = await _get(
      Uri.parse('$baseUrl/purchases/customer/$customerId'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = _json(response) as List<dynamic>;
      return data.map((item) => Purchase.fromJson(item)).toList();
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception('Error al cargar las compras: ${response.statusCode}');
    }
  }

  static Future<List<Installment>> fetchInstallmentsByLoan(int loanId) async {
    final response = await _get(
      Uri.parse('$baseUrl/loans/$loanId/installments'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = _json(response) as List<dynamic>;
      return data.map((json) => Installment.fromJson(json)).toList();
    } else {
      throw Exception('No se pudieron obtener las cuotas');
    }
  }

  static Future<Loan?> createLoan(Loan loan) async {
    final url = Uri.parse('$baseUrl/loans/createLoan/');

    try {
      final response = await _post(url, body: jsonEncode(loan.toJson()));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Loan.fromJson(_json(response) as Map<String, dynamic>);
      } else {
        // ignore: avoid_print
        print('Error del servidor: ${response.statusCode}');
        // ignore: avoid_print
        print('Respuesta: ${utf8.decode(response.bodyBytes)}');
        return null;
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // ignore: avoid_print
      print('Error de conexión: $e');
      return null;
    }
  }

  static Future<Purchase?> createPurchase(Purchase purchase) async {
    final url = Uri.parse('$baseUrl/purchases/');

    try {
      final response = await _post(url, body: jsonEncode(purchase.toJson()));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Purchase.fromJson(_json(response) as Map<String, dynamic>);
      } else {
        // ignore: avoid_print
        print('Error del servidor: ${response.statusCode}');
        // ignore: avoid_print
        print('Respuesta: ${utf8.decode(response.bodyBytes)}');
        return null;
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // ignore: avoid_print
      print('Error de conexión: $e');
      return null;
    }
  }

  static Future<int?> registerPayment(
    int loanId,
    double amount, {
    String? paymentType, // 'cash' | 'transfer' | 'other'
    String? description, // requerido sólo si paymentType == 'other'
  }) async {
    final payload = <String, dynamic>{'amount_paid': amount};
    if (paymentType != null && paymentType.isNotEmpty) {
      payload['payment_type'] = paymentType;
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }

    final response = await _post(
      Uri.parse('$baseUrl/loans/$loanId/pay'),
      body: json.encode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error al registrar el pago');
    }

    final data = _json(response);
    if (data is Map) {
      // si el backend envía { payment_id, ... }
      if (data.containsKey('payment_id')) {
        final pid = data['payment_id'];
        if (pid is num) return pid.toInt();
        if (pid is String) return int.tryParse(pid);
      }
      // opcional: imprimir mensaje si viene
      if (data.containsKey('message')) {
        // ignore: avoid_print
        print(data['message']);
      }
    }
    return null; // backend legacy que no devuelve payment_id
  }

  static Future<bool> createPayment({
    required double amount,
    int? loanId,
    int? purchaseId,
    String? description,
  }) async {
    final url = Uri.parse('$baseUrl/payments/');

    final body = {
      'amount': amount,
      if (loanId != null) 'loan_id': loanId,
      if (purchaseId != null) 'purchase_id': purchaseId,
      if (description != null && description.trim().isNotEmpty)
        'description': description,
    };

    final resp = await _post(url, body: jsonEncode(body));

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return true;
    }
    // levantamos mensaje legible si vino {"detail": "..."}
    try {
      final m = _json(resp) as Map<String, dynamic>;
      throw Exception(m['detail'] ?? 'No se pudo registrar el pago');
    } catch (_) {
      throw Exception('No se pudo registrar el pago (HTTP ${resp.statusCode})');
    }
  }

  static Future<Loan> fetchLoanDetails(int loanId) async {
    try {
      final response = await _get(Uri.parse('$baseUrl/loans/$loanId'));

      if (response.statusCode == 200) {
        final jsonData = _json(response) as Map<String, dynamic>;
        return Loan.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw Exception('Préstamo no encontrado');
      } else {
        throw Exception('Error al cargar el préstamo: ${response.statusCode}');
      }
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // ignore: avoid_print
      print('Error en fetchLoanDetails: $e');
      throw Exception('No se pudo obtener el préstamo: $e');
    }
  }

  static Future<Map<String, dynamic>> getPayment(int id) async {
    final uri = Uri.parse('$baseUrl/payments/$id');
    final resp = await _get(uri);

    if (resp.statusCode == 200) {
      final data = _json(resp);
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(
      'GET /payments/$id -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  // ----------------- Installments (Nuevo) -----------------

  /// Lista de cuotas con filtros para la pantalla "Cuotas de la semana".
  /// Backend: GET /installments/
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
    // 👇 NORMALIZACIÓN: si viene 'Pagada' o 'paid', mandamos 'paid'
    if (status != null && status.trim().isNotEmpty) {
      qp['status'] = st.toCanonicalInstallmentStatus(status);
    }

    final uri = Uri.parse(
      '$baseUrl/installments/',
    ).replace(queryParameters: qp);
    final resp = await _get(uri);

    if (resp.statusCode == 200) {
      final List data = _json(resp) as List;
      return data.map((e) => Installment.fromJson(e)).toList();
    }
    throw Exception(
      'GET /installments/ -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  /// KPIs para la pantalla (pendientes, cobradas, vencidas, totales).
  /// Backend: GET /installments/summary
  /// KPIs para la pantalla (pendientes, cobradas, vencidas, totales).
  /// Backend: GET /installments/summary
  static Future<Map<String, dynamic>> fetchInstallmentsSummary({
    int? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? province, // <- NUEVO
    bool byDay = false, // <- NUEVO
  }) async {
    final qp = <String, String>{};
    if (employeeId != null) qp['employee_id'] = '$employeeId';
    if (dateFrom != null) qp['date_from'] = _fmtDate(dateFrom);
    if (dateTo != null) qp['date_to'] = _fmtDate(dateTo);
    if (province != null && province.isNotEmpty) qp['province'] = province;
    if (byDay) qp['by_day'] = 'true';

    final uri = Uri.parse(
      '$baseUrl/installments/summary',
    ).replace(queryParameters: qp);
    final resp = await _get(uri);

    if (resp.statusCode == 200) {
      return _json(resp) as Map<String, dynamic>;
    }
    throw Exception(
      'GET /installments/summary -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  /// Resumen de pagos (total + by_day opcional).
  /// Backend: GET /payments/summary
  static Future<Map<String, dynamic>> fetchPaymentsSummary({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? province, // <- opcional
    bool byDay = true, // <- por defecto queremos la serie diaria
  }) async {
    final qp = <String, String>{
      'employee_id': '$employeeId',
      'date_from': dateFrom.toUtc().toIso8601String(),
      'date_to': dateTo.toUtc().toIso8601String(),
    };
    if (province != null && province.isNotEmpty) qp['province'] = province;
    if (byDay) qp['by_day'] = 'true';
    qp['tz'] = kTZ;

    final uri = Uri.parse(
      '$baseUrl/payments/summary',
    ).replace(queryParameters: qp);
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      return _json(resp)
          as Map<String, dynamic>; // { total_amount, by_day: [...] }
    }
    throw Exception('No se pudo obtener el summary de pagos');
  }

  /// Marcar cuota como pagada. Intenta POST moderna y retrocede a PUT legacy.
  static Future<PayInstallmentResult> payInstallment({
    required int installmentId,
    required double amount,
    String? paymentType, // 'cash' | 'transfer' | 'other'
    String? description, // texto libre (usado si 'other' o notas adicionales)
  }) async {
    final body = json.encode({
      'amount': amount,
      if (paymentType != null) 'payment_type': paymentType,
      if (description != null && description.isNotEmpty)
        'description': description,
    });

    // POST moderna
    final resp = await _post(
      Uri.parse('$baseUrl/installments/$installmentId/pay'),
      body: body,
    );

    if (resp.statusCode == 200) {
      final data = _json(resp);

      if (data is Map &&
          data.containsKey('payment_id') &&
          data['installment'] is Map) {
        final inst = Installment.fromJson(
          Map<String, dynamic>.from(data['installment']),
        );
        final pid = (data['payment_id'] as num?)?.toInt();
        return PayInstallmentResult(installment: inst, paymentId: pid);
      }

      // Soporte legado: el backend devolvía directamente la cuota
      if (data is Map<String, dynamic>) {
        final inst = Installment.fromJson(data);
        return PayInstallmentResult(installment: inst, paymentId: null);
      }

      throw Exception(
        'Formato inesperado en la respuesta de /installments/{id}/pay',
      );
    }

    // Error HTTP: intentar decodificar detalle
    try {
      final err = _json(resp) as Map<String, dynamic>;
      throw Exception(err['detail'] ?? 'Error al registrar el pago');
    } catch (_) {
      throw Exception('Error al registrar el pago: HTTP ${resp.statusCode}');
    }
  }

  // ignore: unused_field
  static const String _kPendiente = 'Pendiente';
  // ignore: unused_field
  static const String _kParcial = 'Parcialmente Pagada';

  /// Lista enriquecida (con customer_name / debt_type / loan_id)
  static Future<List<InstallmentListItem>> fetchInstallmentsEnriched({
    int? employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
    // 'pendientes' | 'pagadas' | 'vencidas' | 'todas'
    String statusFilter = 'pendientes',
  }) async {
    final qp = <String, String>{};
    if (employeeId != null) qp['employee_id'] = '$employeeId';
    if (dateFrom != null) qp['date_from'] = _fmtDate(dateFrom);
    if (dateTo != null) qp['date_to'] = _fmtDate(dateTo);

    // Hint para backend (si no filtra, igual filtramos en cliente)
    if (statusFilter == 'pendientes') {
      qp['only_pending'] = 'true'; // incluye Pendiente + Parcial
    } else if (statusFilter == 'pagadas') {
      // 👇 canónico EN para backend
      qp['status'] = st.toCanonicalInstallmentStatus('Pagada'); // 'paid'
    } else if (statusFilter == 'vencidas') {
      qp['status'] = st.toCanonicalInstallmentStatus('Vencida'); // 'overdue'
    }

    final url = Uri.parse(
      '$baseUrl/installments/',
    ).replace(queryParameters: qp);
    final resp = await _get(url);

    if (resp.statusCode == 204 || resp.bodyBytes.isEmpty) {
      return <InstallmentListItem>[];
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'GET ${url.path} -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
      );
    }

    // Parseo seguro
    List<dynamic> data;
    try {
      final raw = _json(resp);
      if (raw == null) return <InstallmentListItem>[];
      if (raw is! List) {
        throw Exception('Se esperaba una lista, llegó: ${raw.runtimeType}');
      }
      data = raw;
    } catch (e) {
      throw Exception('JSON parse error en ${url.path}: $e');
    }

    var items =
        data
            .map((e) => InstallmentListItem.fromJson(e as Map<String, dynamic>))
            .toList();

    // ⛔ Excluir siempre cuotas canceladas/refinanciadas (según etiqueta ES normalizada)
    items =
        items.where((x) {
          final label = st.normalizeInstallmentStatus(x.installment.status);
          return label != st.kCuotaCancelada && label != st.kCuotaRefinanciada;
        }).toList();

    // ✅ Filtros por estado (en ES para UI)
    if (statusFilter == 'pendientes') {
      items =
          items.where((x) {
            final label = st.normalizeInstallmentStatus(x.installment.status);
            return label == st.kCuotaPendiente ||
                label == st.kCuotaParcial ||
                (x.installment.isPaid == false);
          }).toList();
    } else if (statusFilter == 'pagadas') {
      items =
          items.where((x) {
            final label = st.normalizeInstallmentStatus(x.installment.status);
            return label == st.kCuotaPagada || (x.installment.isPaid == true);
          }).toList();
    } else if (statusFilter == 'vencidas') {
      items =
          items.where((x) {
            final label = st.normalizeInstallmentStatus(x.installment.status);
            final bool isOverdue = x.installment.isOverdue == true;
            return label == st.kCuotaVencida || isOverdue;
          }).toList();
    }
    // 'todas' => sin filtro adicional

    return items;
  }

  static Future<List<dynamic>> fetchPayments({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final url = Uri.parse(
      '$baseUrl/payments/?employee_id=$employeeId'
      '&date_from=${dateFrom.toUtc().toIso8601String()}'
      '&date_to=${dateTo.toUtc().toIso8601String()}',
    );
    final resp = await _get(url);
    if (resp.statusCode == 200) {
      final data = _json(resp) as List<dynamic>;
      return data;
    }
    throw Exception('No se pudo obtener la lista de pagos');
  }

  // LISTADO de créditos por empleado y rango (si existe en tu backend)
  // Espera: GET /loans/by-employee?employee_id=&date_from=&date_to=
  static Future<List<Loan>> fetchLoansByEmployeeRange({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/loans/by-employee'
      '?employee_id=$employeeId'
      '&date_from=${dateFrom.toUtc().toIso8601String()}'
      '&date_to=${dateTo.toUtc().toIso8601String()}',
    );
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
      return data.map((e) => Loan.fromJson(e)).toList();
    } else if (resp.statusCode == 404) {
      return <Loan>[];
    }
    throw Exception('No se pudo obtener el listado de créditos');
  }

  static Future<CreditsSummary> fetchCreditsSummary({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? province, // <- NUEVO
    bool byDay = false, // <- NUEVO (si querés serie diaria)
  }) async {
    final qp = <String, String>{
      'employee_id': '$employeeId',
      'date_from': dateFrom.toUtc().toIso8601String(),
      'date_to': dateTo.toUtc().toIso8601String(),
    };
    if (province != null && province.isNotEmpty) qp['province'] = province;
    if (byDay) qp['by_day'] = 'true';

    final uri = Uri.parse(
      '$baseUrl/loans/summary',
    ).replace(queryParameters: qp);
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      final data = _json(resp) as Map<String, dynamic>;
      // Soporta salida con o sin by_day
      return CreditsSummary(
        (data['count'] ?? 0) as int,
        (data['amount'] ?? data['originated_amount'] ?? 0).toDouble(),
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
      '&date_from=${dateFrom.toUtc().toIso8601String()}'
      '&date_to=${dateTo.toUtc().toIso8601String()}',
    );
    final resp = await _get(url);
    if (resp.statusCode == 200) {
      final data = _json(resp) as Map<String, dynamic>;
      return (data['total_amount'] ?? 0).toDouble();
    }
    throw Exception('No se pudo obtener el summary de pagos');
  }

  /// Lista de cuotas para el rango, filtrable por paid/pending y provincia.
  static Future<List<Map<String, dynamic>>> fetchInstallmentsList({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? province,
    required bool isPaid,
  }) async {
    final qp = <String, String>{
      'employee_id': '$employeeId',
      'date_from': _fmtDate(dateFrom),
      'date_to': _fmtDate(dateTo),
      'is_paid': isPaid ? 'true' : 'false',
    };
    if (province != null && province.isNotEmpty) qp['province'] = province;

    final uri = Uri.parse(
      '$baseUrl/installments/',
    ).replace(queryParameters: qp);
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      final data = _json(resp);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return const [];
    }
    throw Exception('GET /installments -> ${resp.statusCode}');
  }

  /// Lista de préstamos originados en el rango, filtrable por provincia.
  static Future<List<Map<String, dynamic>>> fetchLoansList({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? province,
  }) async {
    final qp = <String, String>{
      'employee_id': '$employeeId',
      'date_from': dateFrom.toUtc().toIso8601String(),
      'date_to': dateTo.toUtc().toIso8601String(),
    };
    if (province != null && province.isNotEmpty) qp['province'] = province;

    final uri = Uri.parse('$baseUrl/loans/').replace(queryParameters: qp);
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      final data = _json(resp);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return const [];
    }
    throw Exception('GET /loans/ -> ${resp.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> fetchPaymentsList({
    required int employeeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? province,
    int limit = 200,
    int offset = 0,
  }) async {
    final qp = <String, String>{
      'employee_id': '$employeeId',
      'date_from': dateFrom.toUtc().toIso8601String(),
      'date_to': dateTo.toUtc().toIso8601String(),
      'limit': '$limit',
      'offset': '$offset',
    };
    if (province != null && province.isNotEmpty) qp['province'] = province;

    final uri = Uri.parse('$baseUrl/payments/').replace(queryParameters: qp);
    final resp = await _get(uri);
    if (resp.statusCode == 200) {
      final data = _json(resp);
      if (data is List) return data.cast<Map<String, dynamic>>();
      return const [];
    }
    throw Exception('GET /payments -> ${resp.statusCode}');
  }

  // ====== DETALLE / EDICIÓN DE PAYMENTS ======

  static Future<Map<String, dynamic>> updatePayment(
    int id, {
    String? paymentType,
    String? description,
  }) async {
    final uri = Uri.parse('$baseUrl/payments/$id');
    final body = <String, dynamic>{
      if (paymentType != null) 'payment_type': paymentType,
      if (description != null) 'description': description,
    };

    final resp = await _put(uri, body: jsonEncode(body));

    if (resp.statusCode == 200) {
      final data = _json(resp);
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(
      'PUT /payments/$id -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  // ======================= Admin Payments =======================
  static Future<bool> voidPayment(int paymentId, {String? reason}) async {
    final url = Uri.parse('$baseUrl/payments/void/$paymentId');
    final body = reason != null ? jsonEncode({'reason': reason}) : '{}';
    final response = await http.post(
      url,
      headers: await _headers(),
      body: body,
    );
    if (response.statusCode == 200) return true;
    throw Exception(
      'No se pudo anular el pago ($paymentId): ${response.statusCode} ${response.body}',
    );
  }

  // ======================= Loans mgmt =======================
  static Future<bool> cancelLoan(int loanId, {String? reason}) async {
    final url = Uri.parse('$baseUrl/loans/$loanId/cancel');
    final body = reason != null ? jsonEncode({'reason': reason}) : '{}';
    final response = await http.post(
      url,
      headers: await _headers(),
      body: body,
    );
    if (response.statusCode == 200) return true;
    throw Exception(
      'No se pudo cancelar el préstamo ($loanId): ${response.statusCode} ${response.body}',
    );
  }

  static Future<double> refinanceLoan(int loanId) async {
    final url = Uri.parse('$baseUrl/loans/$loanId/refinance');
    final response = await http.post(url, headers: await _headers());
    if (response.statusCode == 200) {
      final data = _json(response) as Map<String, dynamic>;
      return (data['remaining_due'] as num).toDouble();
    }
    throw Exception(
      'No se pudo refinanciar el préstamo ($loanId): ${response.statusCode} ${response.body}',
    );
  }

  // ----------------- Payments by Loan -----------------
  static Future<List<Map<String, dynamic>>> fetchPaymentsByLoan(
    int loanId,
  ) async {
    final uri = Uri.parse('$baseUrl/loans/$loanId/payments');
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = _json(resp);
      final list = (data as List).cast<dynamic>();
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(
      'GET /loans/$loanId/payments -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  // ---------- Payments for ONE installment ----------
  static Future<List<Map<String, dynamic>>> fetchPaymentsByInstallment(
    int installmentId,
  ) async {
    final uri = Uri.parse('$baseUrl/installments/$installmentId/payments');
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = _json(resp);
      final list = (data as List).cast<dynamic>();
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(
      'GET /installments/$installmentId/payments -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  // ---------- Allocations for ONE payment ----------
  static Future<List<Map<String, dynamic>>> getPaymentAllocations(
    int paymentId,
  ) async {
    final uri = Uri.parse('$baseUrl/payments/$paymentId/allocations');
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = _json(resp);
      final list = (data as List).cast<dynamic>();
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(
      'GET /payments/$paymentId/allocations -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }

  // ====== Perfil / Datos básicos ======

  /// Devuelve el empleado por ID (mapa simple con campos del backend).
  static Future<Map<String, dynamic>?> fetchEmployeeById(int employeeId) async {
    final uri = Uri.parse('$baseUrl/employees/$employeeId');
    final res = await _get(uri);
    if (res.statusCode == 200) {
      final j = _json(res);
      if (j is Map<String, dynamic>) return j;
    }
    return null;
  }

  /// Devuelve la empresa por ID (mapa simple).
  static Future<Map<String, dynamic>?> fetchCompanyById(int companyId) async {
    final uri = Uri.parse('$baseUrl/companies/$companyId');
    final res = await _get(uri);
    if (res.statusCode == 200) {
      final j = _json(res);
      if (j is Map<String, dynamic>) return j;
    }
    return null;
  }

  // Pagos por cliente (opcionalmente con rango de fechas ISO 8601)
  static Future<List<Map<String, dynamic>>> fetchPaymentsByCustomer(
    int customerId, {
    String? startDate,
    String? endDate,
  }) async {
    var uri = Uri.parse('$baseUrl/payments/by-customer/$customerId');

    final qp = <String, String>{};
    if (startDate != null && startDate.isNotEmpty) qp['start_date'] = startDate;
    if (endDate != null && endDate.isNotEmpty) qp['end_date'] = endDate;
    if (qp.isNotEmpty) {
      uri = uri.replace(queryParameters: qp);
    }

    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode == 200) {
      final data = _json(resp);
      final list = (data as List).cast<dynamic>();
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(
      'GET /payments/by-customer/$customerId -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}',
    );
  }
}

class InstallmentListItem {
  final Installment installment;
  final String? customerName;
  final String? debtType; // "loan" | "purchase"
  final int? loanId;
  final int? customerId;
  final String? customerPhone;
  final int? collectionDay; // 1..7, viene del LOAN

  InstallmentListItem({
    required this.installment,
    this.customerName,
    this.debtType,
    this.loanId,
    this.customerId,
    this.customerPhone,
    this.collectionDay,
  });

  factory InstallmentListItem.fromJson(Map<String, dynamic> json) {
    return InstallmentListItem(
      installment: Installment.fromJson(json),
      customerName: json['customer_name'] as String?,
      debtType: json['debt_type'] as String?,
      loanId: (json['loan_id'] as num?)?.toInt(),
      customerId: (json['customer_id'] as num?)?.toInt(),
      customerPhone: json['customer_phone'] as String?,
      collectionDay: (json['collection_day'] as num?)?.toInt(),
    );
  }
}

class CreditsSummary {
  final int count;
  final double amount;
  CreditsSummary(this.count, this.amount);
}
