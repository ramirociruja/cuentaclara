import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/screens/payment_detail_screen.dart';
import 'package:frontend/screens/loan_detail_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF3366CC);

  late final TabController _tabs;

  int? _employeeId;
  bool _loading = true;
  String? _err;

  // ========= Semana (Lun..Dom) =========
  late DateTime _from; // lunes 00:00
  late DateTime _to; // domingo 23:59:59.999

  // ========= Filtros =========
  bool _searchMode = false; // búsqueda en AppBar
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _sort = 'reciente'; // reciente|monto_desc|monto_asc|cliente_az

  // ========= Datos =========
  List<Map<String, dynamic>> _payments = [];
  double _paymentsTotal = 0;

  int _creditsCount = 0;
  double _creditsAmount = 0;
  List<Loan> _loans = [];
  bool _loansTried = false;

  // Paginación simple en memoria (Pagos)
  int _paymentsVisibleCount = 10;

  final _moneyFmt = NumberFormat.currency(locale: 'es_AR', symbol: r'$');
  final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _dateShort = DateFormat('dd/MM'); // sin año

  // ---------- helpers semana ----------
  static DateTime _toMonday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static DateTime _weekStart(DateTime d) => _toMonday(d);

  static DateTime _weekEnd(DateTime d) {
    final start = _weekStart(d);
    final sunday = start.add(const Duration(days: 6));
    return DateTime(
      sunday.year,
      sunday.month,
      sunday.day,
      23,
      59,
      59,
      999,
      999,
    );
  }

  String _weekLabelShort() =>
      '${_dateShort.format(_from)} – ${_dateShort.format(_to)}'; // sin "Semana" ni año

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _from = _weekStart(now);
    _to = _weekEnd(now);
    _boot();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final id = await ApiService.getEmployeeId();
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _err = 'No se encontró el empleado logueado';
          _loading = false;
        });
        return;
      }
      _employeeId = id;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_employeeId == null) return;
    setState(() => _loading = true);
    try {
      // Pagos (lista + total)
      final payments = await ApiService.fetchPayments(
        employeeId: _employeeId!,
        dateFrom: _from,
        dateTo: _to,
      );
      final pTotal = await ApiService.fetchPaymentsTotal(
        employeeId: _employeeId!,
        dateFrom: _from,
        dateTo: _to,
      );

      // Créditos (resumen)
      final credits = await ApiService.fetchCreditsSummary(
        employeeId: _employeeId!,
        dateFrom: _from,
        dateTo: _to,
      );

      // (opcional) listado de créditos si existe en backend
      List<Loan> loans = _loans;
      try {
        loans = await ApiService.fetchLoansByEmployeeRange(
          employeeId: _employeeId!,
          dateFrom: _from,
          dateTo: _to,
        );
        _loansTried = true;
      } catch (_) {
        _loansTried = true;
        loans = const [];
      }

      // ordenar pagos recientes primero
      payments.sort((a, b) {
        final da =
            DateTime.tryParse('${a['payment_date'] ?? ''}') ?? DateTime(1970);
        final db =
            DateTime.tryParse('${b['payment_date'] ?? ''}') ?? DateTime(1970);
        return db.compareTo(da);
      });

      if (!mounted) return;
      setState(() {
        _payments = payments.cast<Map<String, dynamic>>();
        _paymentsTotal = pTotal;
        _creditsCount = credits.count;
        _creditsAmount = credits.amount;
        _loans = loans;
        _loading = false;
        _paymentsVisibleCount = 10; // reset paginación al refrescar
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  // ======== Sort: bottom sheet ========
  Future<void> _openSortSheet() async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        Widget tile(String v, String label, IconData icon) {
          final selected = _sort == v;
          return ListTile(
            leading: Icon(
              icon,
              color: selected ? primaryColor : Colors.black54,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? primaryColor : null,
              ),
            ),
            trailing:
                selected ? const Icon(Icons.check, color: primaryColor) : null,
            onTap: () => Navigator.pop(context, v),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile('reciente', 'Recientes', Icons.schedule),
              tile('cliente_az', 'Cliente A→Z', Icons.sort_by_alpha),
              tile('monto_desc', 'Monto ↓', Icons.attach_money),
              tile('monto_asc', 'Monto ↑', Icons.attach_money),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (sel != null) setState(() => _sort = sel);
  }

  // ======== Búsqueda en AppBar ========
  Widget _buildAppBarTitle() {
    if (!_searchMode) {
      return const Text(
        'Actividad',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      );
    }
    return TextField(
      controller: _searchCtrl,
      autofocus: true,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: const InputDecoration(
        hintText: 'Buscar (cliente, método, descripción, #ref, estado)',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      onChanged: (v) => setState(() => _search = v),
    );
  }

  // ======== DatePicker robusto (clamp para evitar crash) ========
  DateTime _clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }

  Future<void> _pickWeek() async {
    // Rango amplio y clamp de initialDate para evitar asserts
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 2, 1, 1);
    final lastDate = DateTime(now.year + 2, 12, 31);
    final initial = _clampDate(_from, firstDate, lastDate);

    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: 'Elegí un día',
        cancelText: 'Cancelar',
        confirmText: 'Aceptar',
        // builder para controlar densidad (evita texto “apretado” en algunos temas)
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.95)),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
      if (picked != null) {
        setState(() {
          _from = _weekStart(picked);
          _to = _weekEnd(picked);
        });
        await _refresh();
      }
    } catch (_) {
      // si algo raro pasa, no rompemos la pantalla
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el selector de fecha')),
      );
    }
  }

  Future<void> _shiftWeek(int deltaWeeks) async {
    setState(() {
      _from = _from.add(Duration(days: 7 * deltaWeeks));
      _to = _weekEnd(_from);
    });
    await _refresh();
  }

  bool _isWithinWeek(DateTime dt) => !dt.isBefore(_from) && !dt.isAfter(_to);

  // ---------------- filtros en memoria ----------------
  List<Map<String, dynamic>> _filteredPaymentsAll() {
    final q = _search.trim().toLowerCase();

    final filtered =
        _payments.where((p) {
          // filtro por búsqueda
          if (q.isNotEmpty) {
            final name = (p['customer_name'] ?? '').toString().toLowerCase();
            final desc = (p['description'] ?? '').toString().toLowerCase();
            final meth = (p['payment_type'] ?? '').toString().toLowerCase();
            final refLoan = p['loan_id']?.toString() ?? '';
            final refPur = p['purchase_id']?.toString() ?? '';
            final hits =
                name.contains(q) ||
                desc.contains(q) ||
                meth.contains(q) ||
                ('prestamo #$refLoan').toLowerCase().contains(q) ||
                ('compra #$refPur').toLowerCase().contains(q);
            if (!hits) return false;
          }

          // filtro por semana (aunque el backend falle)
          final dt = DateTime.tryParse('${p['payment_date'] ?? ''}');
          if (dt == null) return false;
          return _isWithinWeek(dt.toLocal());
        }).toList();

    // orden
    switch (_sort) {
      case 'monto_desc':
        filtered.sort(
          (a, b) => (b['amount'] ?? 0).toDouble().compareTo(
            (a['amount'] ?? 0).toDouble(),
          ),
        );
        break;
      case 'monto_asc':
        filtered.sort(
          (a, b) => (a['amount'] ?? 0).toDouble().compareTo(
            (b['amount'] ?? 0).toDouble(),
          ),
        );
        break;
      case 'cliente_az':
        filtered.sort((a, b) {
          final aa = (a['customer_name'] ?? '').toString().toLowerCase();
          final bb = (b['customer_name'] ?? '').toString().toLowerCase();
          return aa.compareTo(bb);
        });
        break;
      default: // reciente
        filtered.sort((a, b) {
          final da =
              DateTime.tryParse('${a['payment_date'] ?? ''}') ?? DateTime(1970);
          final db =
              DateTime.tryParse('${b['payment_date'] ?? ''}') ?? DateTime(1970);
          return db.compareTo(da);
        });
    }
    return filtered;
  }

  List<Map<String, dynamic>> _filteredPaymentsPaged() {
    final all = _filteredPaymentsAll();
    final end = _paymentsVisibleCount.clamp(0, all.length);
    return all.sublist(0, end);
  }

  List<Loan> _filteredLoans() {
    final q = _search.trim().toLowerCase();

    final filtered =
        _loans.where((l) {
          // week filter
          final start = DateTime.tryParse(l.startDate);
          if (start == null || !_isWithinWeek(start)) return false;

          // search
          if (q.isEmpty) return true;
          final idStr = 'prestamo #${l.id}'.toLowerCase();
          final st = (l.status).toLowerCase();
          return idStr.contains(q) || st.contains(q);
        }).toList();

    switch (_sort) {
      case 'monto_desc':
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'monto_asc':
        filtered.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      default: // reciente por startDate
        filtered.sort((a, b) {
          final da = DateTime.tryParse(a.startDate) ?? DateTime(1970);
          final db = DateTime.tryParse(b.startDate) ?? DateTime(1970);
          return db.compareTo(da);
        });
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }
    if (_err != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Actividad', style: TextStyle(color: Colors.white)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(child: Text(_err!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _buildAppBarTitle(),
        actions: [
          if (!_searchMode)
            IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed:
                  () => setState(() {
                    _searchMode = true;
                    _searchCtrl.text = _search;
                  }),
            ),
          if (_searchMode)
            IconButton(
              tooltip: 'Cerrar búsqueda',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed:
                  () => setState(() {
                    _searchMode = false;
                    _search = '';
                    _searchCtrl.clear();
                  }),
            ),
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.insights), text: 'Resumen'),
            Tab(icon: Icon(Icons.payments), text: 'Pagos'),
            Tab(icon: Icon(Icons.topic), text: 'Créditos'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ====== Barra de semana + ordenar (texto corto) ======
          _WeekAndSortBar(
            weekLabel: _weekLabelShort(),
            onPrevWeek: () => _shiftWeek(-1),
            onNextWeek: () => _shiftWeek(1),
            onPickWeek: _pickWeek,
            onSortPressed: _openSortSheet,
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SummaryTab(
                  paymentsTotal: _paymentsTotal,
                  paymentsCount:
                      _filteredPaymentsAll().length, // conteo real de la semana
                  creditsCount: _filteredLoans().length, // idem
                  creditsAmount: _creditsAmount,
                  fmt: _moneyFmt,
                  rangeShortLabel: _weekLabelShort(),
                  onRefresh: _refresh,
                ),
                _PaymentsTab(
                  payments: _filteredPaymentsPaged(),
                  totalCount: _filteredPaymentsAll().length,
                  paymentsTotal: _paymentsTotal,
                  rangeShortLabel: _weekLabelShort(),
                  df: _dateTimeFmt,
                  fmt: _moneyFmt,
                  onRefresh: _refresh,
                  onLoadMore:
                      () => setState(() {
                        _paymentsVisibleCount += 10;
                      }),
                ),
                _CreditsTab(
                  loans: _filteredLoans(),
                  haveListEndpoint: _loansTried,
                  creditsCount: _creditsCount,
                  creditsAmount: _creditsAmount,
                  fmt: _moneyFmt,
                  rangeShortLabel: _weekLabelShort(),
                  onRefresh: _refresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================== UI widgets ==================

class _WeekAndSortBar extends StatelessWidget {
  final String weekLabel; // ya sin "Semana" ni año
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPickWeek;
  final VoidCallback onSortPressed;

  const _WeekAndSortBar({
    required this.weekLabel,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onPickWeek,
    required this.onSortPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Anterior',
              onPressed: onPrevWeek,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickWeek,
                icon: const Icon(Icons.calendar_month),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Del $weekLabel', // compacto
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  foregroundColor: Colors.black87,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Siguiente',
              onPressed: onNextWeek,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Ordenar',
              onPressed: onSortPressed,
              icon: const Icon(Icons.sort),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final int paymentsCount;
  final double paymentsTotal;
  final int creditsCount;
  final double creditsAmount;
  final NumberFormat fmt;
  final String rangeShortLabel; // compacto
  final Future<void> Function()? onRefresh;

  const _SummaryTab({
    required this.paymentsCount,
    required this.paymentsTotal,
    required this.creditsCount,
    required this.creditsAmount,
    required this.fmt,
    required this.rangeShortLabel,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _ActivityScreenState.primaryColor,
      onRefresh: onRefresh ?? () async {},
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _summaryBar(title: 'Resumen', subtitle: 'Del $rangeShortLabel'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  icon: Icons.payments,
                  title: 'Pagos',
                  value: '$paymentsCount',
                  subtitle: fmt.format(paymentsTotal),
                  center: true, // centrado
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(
                  icon: Icons.request_page,
                  title: 'Créditos',
                  value: '$creditsCount',
                  subtitle: fmt.format(creditsAmount),
                  center: true, // centrado
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1.5,
            child: ListTile(
              leading: const Icon(
                Icons.lightbulb,
                color: _ActivityScreenState.primaryColor,
              ),
              title: const Text('Vista rápida'),
              subtitle: const Text(
                'Usá las pestañas para ver Pagos y Créditos de la semana.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar({required String title, required String subtitle}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.summarize,
              color: _ActivityScreenState.primaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _ActivityScreenState.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(subtitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool center;

  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final textAlign = center ? TextAlign.center : TextAlign.start;
    final cross = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _ActivityScreenState.primaryColor.withAlpha(
                (0.1 * 255).round(),
              ),
              child: Icon(icon, color: _ActivityScreenState.primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: cross,
                children: [
                  Text(
                    title,
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: textAlign,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  final List<Map<String, dynamic>> payments; // ya filtrados y paginados
  final int totalCount; // total filtrado (semana)
  final double paymentsTotal;
  final String rangeShortLabel;
  final DateFormat df;
  final NumberFormat fmt;
  final Future<void> Function()? onRefresh;
  final VoidCallback onLoadMore;

  const _PaymentsTab({
    required this.payments,
    required this.totalCount,
    required this.paymentsTotal,
    required this.rangeShortLabel,
    required this.df,
    required this.fmt,
    this.onRefresh,
    required this.onLoadMore,
  });

  String _methodLabel(String? m) {
    switch ((m ?? '').toLowerCase()) {
      case 'cash':
        return 'Efectivo';
      case 'transfer':
        return 'Transferencia';
      case 'other':
        return 'Otro';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _ActivityScreenState.primaryColor,
      onRefresh: onRefresh ?? () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: payments.length + 2, // + resumen + (posible) cargar más
        itemBuilder: (context, i) {
          if (i == 0) {
            return _summaryBar(
              leftLabel: 'Pagos ($totalCount)',
              leftValue: fmt.format(paymentsTotal),
              rightLabel: 'Del $rangeShortLabel',
            );
          }
          if (i == payments.length + 1) {
            // botón "Cargar más" si corresponde
            final hasMore = payments.length < totalCount;
            if (!hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: OutlinedButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('Cargar más'),
              ),
            );
          }

          final p = payments[i - 1];
          final amount = (p['amount'] ?? 0).toDouble();
          final desc = (p['description'] ?? '').toString().trim();
          final loanId = p['loan_id'];
          final purchaseId = p['purchase_id'];
          final dt = DateTime.tryParse('${p['payment_date'] ?? ''}');
          final dateTxt =
              dt == null ? '-' : df.format(dt.toLocal()); // <- toLocal()
          final method = _methodLabel(p['payment_type']);
          final customer = (p['customer_name'] ?? '').toString().trim();

          final ref =
              loanId != null
                  ? 'Préstamo #$loanId'
                  : purchaseId != null
                  ? 'Compra #$purchaseId'
                  : 'Sin referencia';

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentDetailScreen(payment: p),
                  ),
                );
              },
              leading: CircleAvatar(
                backgroundColor: _ActivityScreenState.primaryColor.withAlpha(
                  (0.1 * 255).round(),
                ),
                child: const Icon(
                  Icons.attach_money,
                  color: _ActivityScreenState.primaryColor,
                ),
              ),
              title: Text(
                fmt.format(amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  if (customer.isNotEmpty) customer,
                  ref,
                  'Método: $method · $dateTxt',
                  if (desc.isNotEmpty) desc,
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryBar({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.summarize,
              color: _ActivityScreenState.primaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                leftLabel,
                style: const TextStyle(
                  color: _ActivityScreenState.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  leftValue,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  rightLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditsTab extends StatelessWidget {
  final List<Loan> loans; // ya filtrados por semana
  final bool haveListEndpoint;
  final int creditsCount;
  final double creditsAmount;
  final NumberFormat fmt;
  final String rangeShortLabel;
  final Future<void> Function()? onRefresh;

  const _CreditsTab({
    required this.loans,
    required this.haveListEndpoint,
    required this.creditsCount,
    required this.creditsAmount,
    required this.fmt,
    required this.rangeShortLabel,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _ActivityScreenState.primaryColor,
      onRefresh: onRefresh ?? () async {},
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _summaryBar(
            leftLabel: 'Créditos: $creditsCount',
            leftValue: fmt.format(creditsAmount),
            rightLabel: 'Del $rangeShortLabel',
          ),
          const SizedBox(height: 8),

          // Si hay lista, la mostramos SIEMPRE (prioridad al contenido real)
          if (loans.isNotEmpty)
            ...loans.map((l) {
              final start = DateTime.tryParse(l.startDate);
              final startTxt =
                  start == null ? '-' : DateFormat('dd/MM/yyyy').format(start);
              final saldo = (l.totalDue).toDouble();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoanDetailScreen(loanId: l.id),
                      ),
                    );
                  },
                  leading: CircleAvatar(
                    backgroundColor: _ActivityScreenState.primaryColor
                        .withAlpha((0.1 * 255).round()),
                    child: const Icon(
                      Icons.account_balance,
                      color: _ActivityScreenState.primaryColor,
                    ),
                  ),
                  title: Text(
                    'Préstamo #${l.id} · ${fmt.format(l.amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Inicio: $startTxt · Saldo: ${fmt.format(saldo)} · Estado: ${l.status}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            }),

          // Si no hay lista pero hay endpoint, mostramos vacío amigable
          if (loans.isEmpty && haveListEndpoint)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay créditos para el rango seleccionado'),
              ),
            ),

          // Solo si no hay endpoint y además no hay lista
          if (loans.isEmpty && !haveListEndpoint)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: _ActivityScreenState.primaryColor,
                ),
                title: Text('Listado de créditos'),
                subtitle: Text(
                  'Aún no está disponible el endpoint de listado. Cuando lo agregues en el backend, aparecerá acá.',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryBar({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.summarize,
              color: _ActivityScreenState.primaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                leftLabel,
                style: const TextStyle(
                  color: _ActivityScreenState.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  leftValue,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  rightLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
