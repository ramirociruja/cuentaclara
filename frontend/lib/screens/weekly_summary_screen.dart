import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/api_service.dart';

// Detalles
import 'package:frontend/screens/payment_detail_screen.dart';
import 'package:frontend/screens/installment_detail_screen.dart';
import 'package:frontend/screens/loan_detail_screen.dart';

// Modelo
import 'package:frontend/models/installment.dart';
import 'package:frontend/utils/utils.dart';

class WeeklySummaryScreen extends StatefulWidget {
  final DateTime initialFrom;
  final DateTime initialTo;
  final String? initialProvince;

  const WeeklySummaryScreen({
    super.key,
    required this.initialFrom,
    required this.initialTo,
    this.initialProvince,
  });

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color successColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color warningColor = Color(0xFFFFA000);

  late DateTime _from;
  late DateTime _to;
  String? _province;

  bool _loading = true;
  String? _error;

  late TabController _tab;

  // Provincias
  static const List<String> _provinces = [
    'Buenos Aires',
    'Catamarca',
    'Chaco',
    'Chubut',
    'CABA',
    'Córdoba',
    'Corrientes',
    'Entre Ríos',
    'Formosa',
    'Jujuy',
    'La Pampa',
    'La Rioja',
    'Mendoza',
    'Misiones',
    'Neuquén',
    'Río Negro',
    'Salta',
    'San Juan',
    'San Luis',
    'Santa Cruz',
    'Santa Fe',
    'Santiago del Estero',
    'Tierra del Fuego',
    'Tucumán',
  ];

  // Formats
  final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$');
  final _dfDate = DateFormat('dd/MM/yyyy');
  final _df = DateFormat('dd/MM');
  final _dfTime = DateFormat('HH:mm');

  // Datos – pestaña Cuotas
  double _paymentsTotal = 0.0;
  List<Map<String, dynamic>> _paymentsList = const [];

  double _instTotalAmount = 0.0;
  List<Map<String, dynamic>> _instListPaid = const [];
  List<Map<String, dynamic>> _instListPendingAll =
      const []; // pendientes (+ parciales)

  // Datos – pestaña Créditos
  int _loansCount = 0;
  double _loansAmount = 0.0;
  List<Map<String, dynamic>> _loansList = const [];

  int? _employeeId;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
    _province = widget.initialProvince;
    _tab = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ----------------- Helpers base -----------------
  DateTime? _parseDate(dynamic v) => parseToLocal(v);

  // (2) Traducción del método
  String _methodEs(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'transfer' || s == 'transferencia') return 'Transferencia';
    if (s == 'cash' || s == 'efectivo') return 'Efectivo';
    if (s == 'other' || s == 'otro' || s == 'others') return 'Otro';
    // fallback: capitaliza primera letra
    return raw.isEmpty ? '-' : raw[0].toUpperCase() + raw.substring(1);
  }

  // Excluir loans cancelados/refinanciados (refuerzo en cliente)
  bool _isActiveLoanStatus(dynamic statusRaw) {
    final s = (statusRaw ?? '').toString().toLowerCase().trim();
    if (s.isEmpty) return true;
    const blocked = <String>[
      'canceled',
      'cancelled',
      'refinanced',
      'cancelado',
      'refinanciado',
    ];
    for (final b in blocked) {
      if (s == b || s.contains(b)) return false;
    }
    return true;
  }

  bool _isActiveInstallment(Map<String, dynamic> it) {
    if (it['loan_id'] != null) {
      if (it['loan_is_canceled'] == true || it['loan_is_cancelled'] == true) {
        return false;
      }
      if (it['loan_is_refinanced'] == true) return false;
      if (!_isActiveLoanStatus(it['loan_status'])) return false;
    }
    return true;
  }

  double _numToDouble(dynamic n) {
    if (n == null) return 0.0;
    if (n is num) return n.toDouble();
    return double.tryParse(n.toString().replaceAll(',', '.')) ?? 0.0;
  }

  String _niceDate(dynamic iso) {
    final dt = _parseDate(iso);
    if (dt == null) return (iso?.toString() ?? '-');
    return '${_df.format(dt)} ${_dfTime.format(dt)}';
  }

  // ---------- Status de cuotas: normalización a ES ----------
  String _statusEs(Map<String, dynamic> it) {
    final raw =
        (it['status'] ?? it['installment_status'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
    final isPaidBool = it['is_paid'] == true || it['paid'] == true;
    final amount = _numToDouble(it['amount']);
    final paidAmount = _numToDouble(
      it['paid_amount'] ?? it['paidAmount'] ?? it['amount_paid'],
    );
    final due = _parseDate(it['due_date']);
    final isOverdueNow =
        (due != null) && due.isBefore(DateTime.now()) && paidAmount < amount;

    if (raw.contains('pagad') || raw == 'paid') return 'Pagada';
    if (raw.contains('parcial') || raw == 'partial') return 'Parcial';
    if (raw.contains('vencid') || raw == 'overdue') return 'Vencida';
    if (raw.contains('pend') || raw == 'pending') return 'Pendiente';

    if (isPaidBool || paidAmount >= amount - 0.0001) return 'Pagada';
    if (paidAmount > 0 && paidAmount < amount) {
      return isOverdueNow ? 'Vencida' : 'Parcial';
    }
    return isOverdueNow ? 'Vencida' : 'Pendiente';
  }

  Color _statusColorEs(String es) {
    switch (es) {
      case 'Pagada':
        return successColor;
      case 'Parcial':
        return warningColor;
      case 'Vencida':
        return dangerColor;
      case 'Pendiente':
      default:
        return primaryColor;
    }
  }

  // ----------------- Carga -----------------
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _employeeId = await ApiService.getEmployeeId();
      await _loadAll();
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAll() async {
    if (_employeeId == null) throw Exception('Empleado no encontrado');

    // PAGOS
    final paySummary = await ApiService.fetchPaymentsSummary(
      employeeId: _employeeId!,
      dateFrom: startOfDayLocal(_from).toUtc(),
      dateTo: endOfDayLocal(_to).toUtc(),
      province: _province,
      byDay: true,
    );
    _paymentsTotal = (paySummary['total_amount'] ?? 0).toDouble();

    _paymentsList = await ApiService.fetchPaymentsList(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
      limit: 200,
    );

    // CUOTAS
    final instSummary = await ApiService.fetchInstallmentsSummary(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
      byDay: false,
    );
    _instTotalAmount = (instSummary['total_amount'] ?? 0).toDouble();

    _instListPaid = await ApiService.fetchInstallmentsList(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
      isPaid: true,
    );
    _instListPendingAll = await ApiService.fetchInstallmentsList(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
      isPaid: false,
    );

    // CRÉDITOS
    final credits = await ApiService.fetchCreditsSummary(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
      byDay: false,
    );
    _loansCount = credits.count;
    _loansAmount = credits.amount;

    _loansList = await ApiService.fetchLoansList(
      employeeId: _employeeId!,
      dateFrom: _from,
      dateTo: _to,
      province: _province,
    );

    // --------- Sin doble filtro para cuotas; sólo dedupe y activos ---------
    List<Map<String, dynamic>> dedupe(List<Map<String, dynamic>> src) {
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final it in src) {
        final id =
            (it['id'] ?? it['installment_id'] ?? it['uuid'] ?? '${it.hashCode}')
                .toString();
        if (seen.add(id)) out.add(it);
      }
      return out;
    }

    // (1) Filtrado por fecha de PAGOS (además de dedupe)
    _paymentsList = dedupe(_paymentsList);
    final start = startOfDayLocal(_from);
    final end = endOfDayLocal(_to);
    _paymentsList =
        _paymentsList.where((p) {
          final dt = _parseDate(
            p['payment_date'] ?? p['date'] ?? p['created_at'],
          );
          if (dt == null) return false;
          return !dt.isBefore(start) && !dt.isAfter(end);
        }).toList();

    List<Map<String, dynamic>> keepActiveInstallments(
      List<Map<String, dynamic>> src,
    ) {
      final filtered = <Map<String, dynamic>>[];
      for (final it in src) {
        if (_isActiveInstallment(it)) filtered.add(it);
      }
      return dedupe(filtered);
    }

    _instListPaid = keepActiveInstallments(_instListPaid);
    _instListPendingAll = keepActiveInstallments(_instListPendingAll);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      saveText: 'Aplicar',
      helpText: 'Seleccioná el rango',
      builder:
          (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(
                ctx,
              ).colorScheme.copyWith(primary: primaryColor),
            ),
            child: child!,
          ),
    );
    if (picked == null) return;

    setState(() {
      _from = startOfDayLocal(picked.start);
      _to = endOfDayLocal(picked.end);
      _loading = true;
    });
    await _loadAll();
    if (mounted) setState(() => _loading = false);
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final rangeText = 'Del ${_dfDate.format(_from)} al ${_dfDate.format(_to)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Resumen semanal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Cuotas'), Tab(text: 'Créditos')],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Rango',
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _pickRange,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                controller: _tab,
                children: [
                  // ------- TAB CUOTAS -------
                  RefreshIndicator(
                    onRefresh: _bootstrap,
                    color: primaryColor,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _filterBar(rangeText),
                        const SizedBox(height: 12),
                        _cuotasSummaryCard(),
                        const SizedBox(height: 12),
                        _expPaymentsList(),
                        const SizedBox(height: 12),
                        _expInstallmentsLists(),
                      ],
                    ),
                  ),
                  // ------- TAB CRÉDITOS -------
                  RefreshIndicator(
                    onRefresh: _bootstrap,
                    color: primaryColor,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _filterBar(rangeText),
                        const SizedBox(height: 12),
                        _loansSummaryCard(),
                        const SizedBox(height: 12),
                        _expLoansList(),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _filterBar(String rangeText) {
    return Row(
      children: [
        Expanded(
          child: _FilterField(
            label: 'Provincia',
            icon: Icons.map_outlined,
            value: _province,
            items: const [null, ..._provinces],
            display: (v) => v ?? 'Todas',
            onChanged: (v) async {
              setState(() {
                _province = v;
                _loading = true;
              });
              await _loadAll();
              if (mounted) setState(() => _loading = false);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RangeField(
            label: 'Rango',
            icon: Icons.date_range,
            text: rangeText,
            onTap: _pickRange,
          ),
        ),
      ],
    );
  }

  // ---------- Cards resumen ----------
  Widget _cuotasSummaryCard() {
    final goal = _instTotalAmount;
    final achieved = _paymentsTotal;
    final pending = (goal - achieved) <= 0 ? 0.0 : (goal - achieved);
    final progress = goal == 0 ? 0.0 : (achieved / goal).clamp(0.0, 1.0);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kpi('A cobrar', _money.format(goal), color: primaryColor),
                  const SizedBox(height: 8),
                  _kpi('Cobrado', _money.format(achieved), color: successColor),
                  const SizedBox(height: 8),
                  _kpi('Pendiente', _money.format(pending), color: dangerColor),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _donut(progress),
          ],
        ),
      ),
    );
  }

  Widget _loansSummaryCard() {
    final avg = _loansCount > 0 ? (_loansAmount / _loansCount) : 0.0;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _kpi('Créditos', '$_loansCount', color: primaryColor),
            _kpi('Otorgado', _money.format(_loansAmount), color: successColor),
            _kpi('Ticket promedio', _money.format(avg), color: warningColor),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, {required Color color}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }

  Widget _donut(double progress) {
    final size = 64.0;
    final thickness = 6.0;
    final v = progress.clamp(0.0, 1.0);
    final fontSize = size * 0.22;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: thickness,
              color: Colors.grey.shade200,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: v,
              strokeWidth: thickness,
              color: primaryColor,
              backgroundColor: Colors.transparent,
            ),
          ),
          Text(
            '${(v * 100).round()}%',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  // ---------- Expandibles ----------
  Widget _expPaymentsList() {
    return _expCard(
      icon: Icons.payments_outlined,
      title: 'Pagos registrados',
      initiallyExpanded: false,
      child:
          _paymentsList.isEmpty
              ? const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'No hay pagos registrados en el período',
                  style: TextStyle(color: Colors.black54),
                ),
              )
              : Column(children: _paymentsList.map(_paymentCard).toList()),
    );
  }

  Widget _expInstallmentsLists() {
    final combined = <Map<String, dynamic>>[];
    final seen = <String>{};
    void addUnique(Iterable<Map<String, dynamic>> src) {
      for (final it in src) {
        final id =
            (it['id'] ?? it['installment_id'] ?? it['uuid'] ?? '${it.hashCode}')
                .toString();
        if (seen.add(id)) combined.add(it);
      }
    }

    addUnique(_instListPaid);
    addUnique(_instListPendingAll);

    combined.sort((a, b) {
      final da =
          _parseDate(a['due_date']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db =
          _parseDate(b['due_date']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });

    final pagadas = <Map<String, dynamic>>[];
    final pendientes = <Map<String, dynamic>>[];

    for (final it in combined) {
      final es = _statusEs(it);
      if (es == 'Pagada') {
        pagadas.add(it);
      } else {
        pendientes.add(it);
      }
    }

    return _expCard(
      icon: Icons.event_note,
      title: 'Cuotas del período',
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subHeader('Pagadas (${pagadas.length})'),
          if (pagadas.isEmpty)
            _empty('Sin cuotas pagadas')
          else
            ...pagadas.map(_installmentCard),

          const SizedBox(height: 12),
          _subHeader('Pendientes (${pendientes.length})'),
          if (pendientes.isEmpty)
            _empty('Sin cuotas pendientes')
          else
            ...pendientes.map(_installmentCard),
        ],
      ),
    );
  }

  Widget _expLoansList() {
    return _expCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Créditos otorgados',
      initiallyExpanded: false,
      child:
          _loansList.isEmpty
              ? const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'No hay créditos en el período',
                  style: TextStyle(color: Colors.black54),
                ),
              )
              : Column(children: _loansList.map(_loanTile).toList()),
    );
  }

  Widget _expCard({
    required IconData icon,
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE9ECF5)),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(icon, color: primaryColor),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          children: [child],
        ),
      ),
    );
  }

  // ---------- Tiles estilo "customer_detail_screen" ----------
  // PAGOS
  Widget _paymentCard(Map<String, dynamic> p) {
    final amountDynamic = p['amount'];
    final amountText =
        (amountDynamic is num)
            ? _money.format(amountDynamic)
            : (amountDynamic?.toString() ?? '-');

    final niceDate = _niceDate(p['payment_date']);
    final loanId = p['loan_id'] ?? p['loanId'];
    final method = (p['payment_type'] ?? p['method'] ?? '').toString();
    final methodEs = _methodEs(method); // (2) traducción
    final desc = (p['description'] ?? p['detail'] ?? '').toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: const Icon(Icons.payments),
        title: Text(
          amountText,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('Fecha: $niceDate'),
            if (loanId != null) Text('Préstamo: #$loanId'),
            if (methodEs.isNotEmpty) Text('Método: $methodEs'), // (2)
            if (desc.isNotEmpty) Text('Detalle: $desc'),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade600),
        onTap: () {
          final normalized = _normalizePayment(p);
          final id = normalized['id'];
          if (id != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentDetailScreen(payment: normalized),
              ),
            );
          } else if (loanId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LoanDetailScreen(loanId: loanId as int),
              ),
            );
          }
        },
      ),
    );
  }

  Map<String, dynamic> _normalizePayment(Map<String, dynamic> p) {
    return {
      'id': p['id'] ?? p['payment_id'],
      'amount': p['amount'],
      'payment_date': p['payment_date'] ?? p['date'] ?? p['created_at'],
      'payment_type': p['payment_type'] ?? p['method'],
      'description': p['description'] ?? p['detail'],
      'loan_id': p['loan_id'] ?? p['loanId'],
      'customer_name': p['customer_name'] ?? p['customerName'],
      ...p,
    };
  }

  // CUOTAS
  Widget _installmentCard(Map<String, dynamic> it) {
    final customer = (it['customer_name'] ?? '-').toString();
    final number = (it['number'] ?? it['installment_number'] ?? '-').toString();
    final dueTxt = _dfDate.format(
      _parseDate(it['due_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    final statusEs = _statusEs(it);
    final color = _statusColorEs(statusEs);
    final amount = _numToDouble(it['amount']);
    final amountText = _money.format(amount);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: const Icon(Icons.event_note),
        title: Text(
          'Cuota $number — $customer',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('Vence: $dueTxt'),
            Text('Estado: $statusEs', style: TextStyle(color: color)),
            Text('Monto: $amountText'),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade600),
        onTap: () {
          try {
            final inst = Installment.fromJson(Map<String, dynamic>.from(it));
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InstallmentDetailScreen(installment: inst),
              ),
            );
          } catch (_) {}
        },
      ),
    );
  }

  // ---------- Otros tiles ----------
  Widget _loanTile(Map<String, dynamic> l) {
    final customer = (l['customer_name'] ?? '-').toString();
    final amount = _money.format(((l['amount'] ?? 0) as num).toDouble());
    final sd = _parseDate(l['start_date']);
    final when =
        sd != null ? _dfDate.format(sd) : (l['start_date']?.toString() ?? '-');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 0),
      leading: CircleAvatar(
        backgroundColor: primaryColor.withValues(alpha: 0.10), // preferencia
        child: const Icon(Icons.account_balance_wallet, color: primaryColor),
      ),
      title: Text(
        customer,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('Fecha: $when\nMonto: $amount'),
      isThreeLine: true,
    );
  }

  // ---------- Util UI ----------
  Widget _subHeader(String t) {
    return Row(
      children: [
        const Icon(Icons.segment, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _empty(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.black45),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _FilterField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<T?> items;
  final String Function(T?) display;
  final ValueChanged<T?> onChanged;

  const _FilterField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });

  static const Color border = Color(0xFFE0E4F2);
  static const Color primaryColor = Color(0xFF3366CC);

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF6F8FF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryColor, width: 1.4),
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          isExpanded: true,
          value: value,
          items:
              items
                  .map(
                    (e) =>
                        DropdownMenuItem<T?>(value: e, child: Text(display(e))),
                  )
                  .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _RangeField({
    required this.label,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  static const Color border = Color(0xFFE0E4F2);
  static const Color primaryColor = Color(0xFF3366CC);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: const Color(0xFFF6F8FF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: primaryColor, width: 1.4),
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
