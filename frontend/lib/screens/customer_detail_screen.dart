import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/screens/edit_customer_screen.dart';
import 'package:frontend/screens/loan_detail_screen.dart';
import 'package:frontend/screens/payment_detail_screen.dart';
import 'package:frontend/screens/create_loan_or_purchase_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';

// Estados centralizados
import 'package:frontend/shared/status.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  // Paleta local
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color warningColor = Color(0xFFFFA000);

  Customer? customer;
  List<Loan> loans = [];
  bool isLoading = true;

  // estados de expansión (por UX: activos abierto, resto cerrado)
  bool showActive = true;
  bool showCompleted = false;
  bool showRefinanced = false;
  bool showCanceled = false;
  bool showPayments = false;

  // pagos
  List<Map<String, dynamic>> payments = [];

  final DateFormat dateFormat = DateFormat('dd/MM/yyyy');
  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: r'$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => isLoading = true);
      final fetchedCustomer = await ApiService.fetchCustomerById(
        widget.customerId,
      );
      final fetchedLoans = await ApiService.fetchLoansByCustomer(
        widget.customerId,
      );

      // intentar cargar historial de pagos
      final loadedPayments = await _tryLoadPayments(
        customerId: widget.customerId,
        loans: fetchedLoans,
      );

      setState(() {
        customer = fetchedCustomer;
        loans = fetchedLoans;
        payments = loadedPayments;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al cargar los datos del cliente'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  /// Intenta cargar pagos:
  /// 1) Usa ApiService.fetchPaymentsByCustomer si existe
  /// 2) Si no, usa ApiService.fetchPaymentsByLoan por cada préstamo
  Future<List<Map<String, dynamic>>> _tryLoadPayments({
    required int customerId,
    required List<Loan> loans,
  }) async {
    // Opción directa por cliente
    try {
      final list = await ApiService.fetchPaymentsByCustomer(customerId);
      list.sort((a, b) {
        final da =
            _extractDateTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db =
            _extractDateTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return list;
    } catch (_) {
      // Si no existe el endpoint por cliente, juntamos por préstamo
    }

    final out = <Map<String, dynamic>>[];
    for (final loan in loans) {
      try {
        final byLoan = await ApiService.fetchPaymentsByLoan(loan.id);
        out.addAll(
          byLoan.map<Map<String, dynamic>>(
            (p) => {
              ...Map<String, dynamic>.from(p),
              'loanId': p['loanId'] ?? p['loan_id'] ?? loan.id,
            },
          ),
        );
      } catch (_) {
        // seguimos con el resto
      }
    }

    out.sort((a, b) {
      final da = _extractDateTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = _extractDateTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return out;
  }

  void _navigateToEditCustomer() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCustomerScreen(customer: customer!),
      ),
    );
    if (result == true) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente editado exitosamente'),
          backgroundColor: secondaryColor,
        ),
      );
    }
  }

  // ---------- Helpers de datos ----------

  // Fix rápido para textos con acentos mal decodificados (mojibake)
  String _fixEncoding(String? s) {
    final v = s ?? '';
    if (v.contains('Ã') ||
        v.contains('Â') ||
        v.contains('â') ||
        v.contains('€') ||
        v.contains('™')) {
      try {
        final bytes = latin1.encode(v);
        return utf8.decode(bytes);
      } catch (_) {
        return v;
      }
    }
    return v;
  }

  DateTime? _extractDateTime(Map<String, dynamic> p) {
    final v =
        p['payment_date'] ??
        p['paymentDate'] ??
        p['date'] ??
        p['created_at'] ??
        p['createdAt'];
    if (v == null) return null;

    if (v is String && v.isNotEmpty) {
      final candidates = <String>[v, v.replaceAll('Z', ''), v.split('.').first];
      for (final c in candidates) {
        final dt = DateTime.tryParse(c);
        if (dt != null) return dt.toLocal();
      }
    } else if (v is int) {
      final isSeconds = v < 20000000000;
      final dt =
          isSeconds
              ? DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
              : DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      return dt.toLocal();
    }
    return null;
  }

  String _formatMaybeDate(Map<String, dynamic> p) {
    final dt = _extractDateTime(p);
    if (dt == null) return '-';
    return dateFormat.format(dt);
  }

  String _translateMethod(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'cash':
        return 'Efectivo';
      case 'transfer':
      case 'bank_transfer':
      case 'wire':
        return 'Transferencia';
      case 'card':
      case 'debit':
      case 'credit':
        return 'Tarjeta';
      case 'other':
      default:
        return s.isEmpty ? '-' : 'Otro';
    }
  }

  // Normaliza el objeto del pago para PaymentDetailScreen(payment: ...)
  Map<String, dynamic> _normalizePayment(Map<String, dynamic> p) {
    final id = p['id'] ?? p['payment_id'];
    final amount = p['amount'];
    final dt = _extractDateTime(p);
    final loanId = p['loanId'] ?? p['loan_id'];
    final purchaseId = p['purchaseId'] ?? p['purchase_id'];
    final paymentType = p['payment_type'] ?? p['paymentType'] ?? p['method'];
    final description = p['description'];

    return {
      'id': id,
      'amount': amount,
      'paymentDate': dt?.toIso8601String(),
      'loanId': loanId,
      'purchaseId': purchaseId,
      'paymentType': paymentType,
      'description': description,
    };
  }

  // ---------- Helpers de UI ----------

  Widget _buildInfoPill(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 2),
              Text(
                _fixEncoding(value),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Caja del cliente en DOS columnas (responsivo)
  Widget _buildCustomerInfoBox() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth > 360;

            Expanded col(Widget child) => Expanded(child: child);

            return Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: primaryColor.withValues(alpha: 0.10),
                      radius: 30,
                      child: Icon(Icons.person, size: 30, color: primaryColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _fixEncoding(customer!.fullName),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (twoCols) ...[
                  Row(
                    children: [
                      col(
                        _buildInfoPill(Icons.credit_card, 'DNI', customer!.dni),
                      ),
                      const SizedBox(width: 12),
                      col(
                        _buildInfoPill(
                          Icons.phone,
                          'Teléfono',
                          customer!.phone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      col(
                        _buildInfoPill(
                          Icons.location_on,
                          'Provincia',
                          customer!.province,
                        ),
                      ),
                      const SizedBox(width: 12),
                      col(
                        _buildInfoPill(
                          Icons.home,
                          'Dirección',
                          customer!.address,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildInfoPill(Icons.credit_card, 'DNI', customer!.dni),
                  const SizedBox(height: 8),
                  _buildInfoPill(Icons.phone, 'Teléfono', customer!.phone),
                  const SizedBox(height: 8),
                  _buildInfoPill(
                    Icons.location_on,
                    'Provincia',
                    customer!.province,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoPill(Icons.home, 'Dirección', customer!.address),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoanCard(Loan loan) {
    // Normalizar estado de PRÉSTAMO con helper correcto
    final displayStatus = normalizeLoanStatus(loan.status);
    Color chipColor = loanStatusColor(displayStatus);

    // Mantener tus overrides de matiz (opcional)
    final statusLower = displayStatus.toLowerCase();
    if (statusLower.contains('refinanci')) chipColor = warningColor; // amarillo
    if (statusLower.contains('cancel')) chipColor = dangerColor; // rojo

    // Progreso seguro
    final total = loan.amount;
    final due = loan.totalDue;
    double progress = 0;
    if (total > 0) {
      progress = ((total - due) / total).clamp(0.0, 1.0);
    }

    // Fecha segura
    DateTime? startDt;
    final v = loan.startDate;
    if (v is DateTime) {
      startDt = v as DateTime?;
    } else {
      startDt = DateTime.tryParse(v.toString());
    }

    final isPaid = displayStatus.toLowerCase() == 'pagado';
    final intervalDays = loan.installmentIntervalDays;

    // Helpers de “badges” (cobrador / intervalo)
    Widget badge({
      required IconData icon,
      required String text,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              _fixEncoding(text),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final hasEmployee =
        loan.employeeName != null && loan.employeeName!.trim().isNotEmpty;

    final hasInterval = intervalDays != null && intervalDays > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LoanDetailScreen(loanId: loan.id),
            ),
          ).then((value) {
            if (value == true) _loadData();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: ID + Estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Préstamo #${loan.id}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      fontSize: 16,
                    ),
                  ),
                  Chip(
                    label: Text(
                      displayStatus,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: chipColor,
                  ),
                ],
              ),

              // Badges secundarios: Cobrador + Intervalo
              if (hasEmployee || hasInterval) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasEmployee)
                      badge(
                        icon: Icons.person,
                        text: loan.employeeName!,
                        color: primaryColor,
                      ),
                    if (hasInterval)
                      badge(
                        icon: Icons.calendar_month,
                        text:
                            'Cada $intervalDays día${intervalDays == 1 ? '' : 's'}',
                        color: Colors.grey.shade700,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Económico con jerarquía: Saldo grande + monto secundario
              Text(
                'Saldo',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                currencyFormatter.format(loan.totalDue),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isPaid ? secondaryColor : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Monto total: ',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  Text(
                    currencyFormatter.format(loan.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Fecha (operativo)
              Row(
                children: [
                  Icon(Icons.event, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Inicio: ',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  Text(
                    startDt != null ? dateFormat.format(startDt) : '-',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Progreso / Pagado
              if (!isPaid) ...[
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade200,
                  color: progress >= 0.999 ? secondaryColor : primaryColor,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}% Pagado',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: secondaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '100% Pagado',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Sección Expandible Reutilizable ----------
  Widget _buildExpandableLoansSection({
    required String title,
    required IconData icon,
    required Color accent,
    required List<Loan> data,
    required bool initiallyExpanded,
    required ValueChanged<bool> onChanged,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: accent.withValues(alpha: 0.08),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8.0),
        childrenPadding: const EdgeInsets.only(
          left: 8.0,
          right: 8.0,
          bottom: 8.0,
        ),
        onExpansionChanged: onChanged,
        title: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Badge(label: Text(data.length.toString()), backgroundColor: accent),
          ],
        ),
        children: data.map(_buildLoanCard).toList(),
      ),
    );
  }

  // ---------- Historial de Pagos (expandible) ----------
  Widget _buildPaymentsSection() {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: primaryColor.withValues(alpha: 0.06),
      ),
      child: ExpansionTile(
        initiallyExpanded: showPayments,
        onExpansionChanged: (v) => setState(() => showPayments = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8.0),
        childrenPadding: const EdgeInsets.only(
          left: 8.0,
          right: 8.0,
          bottom: 8.0,
        ),
        title: Row(
          children: [
            const Icon(Icons.receipt_long, size: 18, color: primaryColor),
            const SizedBox(width: 8),
            const Text(
              'Historial de pagos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Badge(
              label: Text(payments.length.toString()),
              backgroundColor: primaryColor,
            ),
          ],
        ),
        children: [
          if (payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No hay pagos para mostrar aún.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            )
          else
            ...payments.map((p) {
              final loanId = p['loanId'] ?? p['loan_id'];
              final amount = p['amount'];
              final method = _translateMethod(
                p['payment_type'] ?? p['paymentType'] ?? p['method'],
              );
              final desc = (p['description'] ?? '').toString();
              final niceDate = _formatMaybeDate(p);

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.payments),
                  title: Text(
                    amount is num
                        ? currencyFormatter.format(amount)
                        : (amount?.toString() ?? '-'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text('Fecha: $niceDate'),
                      if (loanId != null) Text('Préstamo: #$loanId'),
                      if (method.isNotEmpty) Text('Método: $method'),
                      if (desc.isNotEmpty) Text('Detalle: $desc'),
                    ],
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade600,
                  ),
                  onTap: () {
                    final normalized = _normalizePayment(p);
                    if (normalized['id'] != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) =>
                                  PaymentDetailScreen(payment: normalized),
                        ),
                      );
                    } else if (loanId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) =>
                                  LoanDetailScreen(loanId: loanId as int),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  // --------- Predicados usando el status centralizado ---------
  // Activos: lo que está en curso (tu taxonomía canónica: Activo / Incumplido)
  bool _loanIsActive(String? raw) {
    final n = normalizeLoanStatus(raw).toLowerCase();
    return n == 'activo' || n == 'incumplido';
  }

  bool _loanIsCompleted(String? raw) {
    final n = normalizeLoanStatus(raw).toLowerCase();
    return n == 'pagado';
  }

  bool _loanIsRefinanced(String? raw) {
    final n = normalizeLoanStatus(raw).toLowerCase();
    return n.contains('refinanciado');
  }

  bool _loanIsCanceled(String? raw) {
    final n = normalizeLoanStatus(raw).toLowerCase();
    return n.contains('cancelado');
  }

  @override
  Widget build(BuildContext context) {
    final activeLoans = loans.where((l) => _loanIsActive(l.status)).toList();
    final completedLoans =
        loans.where((l) => _loanIsCompleted(l.status)).toList();
    final refinancedLoans =
        loans.where((l) => _loanIsRefinanced(l.status)).toList();
    final canceledLoans =
        loans.where((l) => _loanIsCanceled(l.status)).toList();

    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryColor),
              SizedBox(height: 16),
              Text('Cargando información...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cliente no encontrado'),
          backgroundColor: primaryColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: dangerColor),
              const SizedBox(height: 16),
              const Text(
                'No se encontró el cliente solicitado',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('Volver atrás'),
              ),
            ],
          ),
        ),
      );
    }

    final noLoans =
        activeLoans.isEmpty &&
        completedLoans.isEmpty &&
        refinancedLoans.isEmpty &&
        canceledLoans.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _fixEncoding(customer!.fullName),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar cliente',
              onPressed: _navigateToEditCustomer,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: _loadData,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: primaryColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCustomerInfoBox(),
                if (noLoans) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.credit_card_off,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay préstamos registrados',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  // Activos
                  _buildExpandableLoansSection(
                    title: 'Préstamos Activos',
                    icon: Icons.playlist_add_check,
                    accent: primaryColor,
                    data: activeLoans,
                    initiallyExpanded: showActive,
                    onChanged: (v) => setState(() => showActive = v),
                  ),

                  // Completados
                  _buildExpandableLoansSection(
                    title: 'Préstamos Completados',
                    icon: Icons.done_all,
                    accent: secondaryColor,
                    data: completedLoans,
                    initiallyExpanded: showCompleted,
                    onChanged: (v) => setState(() => showCompleted = v),
                  ),

                  // Refinanciados (amarillo)
                  _buildExpandableLoansSection(
                    title: 'Préstamos Refinanciados',
                    icon: Icons.autorenew,
                    accent: warningColor,
                    data: refinancedLoans,
                    initiallyExpanded: showRefinanced,
                    onChanged: (v) => setState(() => showRefinanced = v),
                  ),

                  // Cancelados (rojo)
                  _buildExpandableLoansSection(
                    title: 'Préstamos Cancelados',
                    icon: Icons.cancel,
                    accent: dangerColor,
                    data: canceledLoans,
                    initiallyExpanded: showCanceled,
                    onChanged: (v) => setState(() => showCanceled = v),
                  ),

                  const SizedBox(height: 8),

                  // Historial de pagos (expandible)
                  _buildPaymentsSection(),
                ],
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateLoanOrPurchaseScreen(),
              ),
            );
            if (created == true) {
              await _loadData(); // refresca al volver
            }
          },
          backgroundColor: primaryColor,
          tooltip: 'Agregar préstamo',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
