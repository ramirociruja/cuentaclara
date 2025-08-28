import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/screens/installment_detail_screen.dart';

/// Nueva versión enfocada en:
/// - Resumen *muy* alto nivel (cuotas de la semana + breakdown por estado)
/// - Sin selector de rango (siempre semana actual Lun–Dom)
/// - Filtros como pestañas (TabBar) para una distribución prolija
/// - UI consistente con el resto (tipografía, colores, cards)
class WeeklyInstallmentsScreen extends StatefulWidget {
  const WeeklyInstallmentsScreen({super.key});

  @override
  State<WeeklyInstallmentsScreen> createState() =>
      _WeeklyInstallmentsScreenState();
}

class _WeeklyInstallmentsScreenState extends State<WeeklyInstallmentsScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF3366CC);

  late final TabController _tabController;

  // Filtros visibles
  // 0: Todas | 1: Pendientes | 2: Parcialmente | 3: Pagadas
  int _tabIndex = 0;

  late DateTime _monday;
  late DateTime _sunday;

  int? _employeeId;
  bool _loadingId = true;
  String? _idError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monday = _toMonday(now);
    _sunday = _monday.add(const Duration(days: 6));

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabIndex != _tabController.index) {
        setState(() => _tabIndex = _tabController.index);
      }
    });

    _loadEmployeeId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeId() async {
    try {
      final id = await ApiService.getEmployeeId();
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _idError = 'No se encontró el empleado logueado';
          _loadingId = false;
        });
      } else {
        setState(() {
          _employeeId = id;
          _loadingId = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _idError = 'Error cargando empleado: $e';
        _loadingId = false;
      });
    }
  }

  DateTime _toMonday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  String _fmtDMY(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<_ScreenData> _load() async {
    final id = _employeeId!;

    // Siempre semana actual por due_date
    final list = await ApiService.fetchInstallmentsEnriched(
      employeeId: id,
      dateFrom: _monday,
      dateTo: _sunday,
      statusFilter: '', // traigo todas y filtro client-side por tab
    );

    // Derivamos el resumen en el cliente para no depender del shape del backend
    final derived = _deriveSummary(list);

    return _ScreenData(list: list, summary: derived);
  }

  Map<String, num> _deriveSummary(List<InstallmentListItem> items) {
    int total = items.length;
    int pendientes = 0;
    int parciales = 0;
    int pagadas = 0;

    double totalAmount = 0;
    double paidSoFar = 0;

    for (final row in items) {
      final it = row.installment;
      final s = (it.status).toLowerCase().trim();

      totalAmount += it.amount;
      paidSoFar += (it.paidAmount);

      if (it.isPaid == true || s == 'pagada') {
        pagadas++;
      } else if (s == 'parcialmente pagada') {
        parciales++;
      } else {
        pendientes++;
      }
    }

    return {
      'total_count': total,
      'pending_count': pendientes,
      'partial_count': parciales,
      'paid_count': pagadas,
      'total_amount': totalAmount,
      'paid_amount': paidSoFar,
    };
  }

  List<InstallmentListItem> _applyTabFilter(List<InstallmentListItem> items) {
    if (_tabIndex == 0) return items; // Todas
    return items.where((row) {
      final it = row.installment;
      final s = (it.status).toLowerCase().trim();
      final isPaid = (it.isPaid == true) || s == 'pagada';
      final isPend = s == 'pendiente';
      final isParc = s == 'parcialmente pagada';
      switch (_tabIndex) {
        case 1:
          return isPend; // Pendientes
        case 2:
          return isPaid || isParc; // Pagadas (incluye Parciales)
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingId) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }
    if (_idError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cuotas de la semana')),
        body: Center(child: Text(_idError!)),
      );
    }

    final subtitle = 'Semana ${_fmtDMY(_monday)} – ${_fmtDMY(_sunday)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cuotas de la Semana',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<_ScreenData>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final data = snap.data!;
          final items = data.list;
          final visibleItems = _applyTabFilter(items);

          return Column(
            children: [
              _SummaryCompact(summary: data.summary, subtitle: subtitle),

              // TabBar de estados
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    labelColor: primaryColor,
                    unselectedLabelColor: Colors.black54,
                    tabs: const [
                      Tab(text: 'Todas'),
                      Tab(text: 'Pendientes'),
                      Tab(text: 'Pagadas'),
                    ],
                    onTap: (_) => setState(() {}),
                  ),
                ),
              ),

              Expanded(
                child: RefreshIndicator(
                  color: primaryColor,
                  onRefresh: () async => setState(() {}),
                  child:
                      visibleItems.isEmpty
                          ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(child: Text('No hay cuotas esta semana')),
                            ],
                          )
                          : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: visibleItems.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final row = visibleItems[i];
                              final it = row.installment;

                              final isPaid = it.isPaid;
                              final amount = it.amount;
                              final number = it.number;
                              final due = _fmtDMY(it.dueDate);
                              final status = it.status;
                              final cust =
                                  row.customerName ?? 'Cliente desconocido';
                              final loanId = row.loanId;

                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 0,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    final refreshed =
                                        await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => InstallmentDetailScreen(
                                                  installment: it,
                                                ),
                                          ),
                                        );
                                    if (refreshed == true && mounted)
                                      setState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: primaryColor.withOpacity(
                                              0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.person,
                                            color: primaryColor,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                cust,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Préstamo #${loanId ?? '-'} • Cuota #$number • Vence: $due',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${amount.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _StatusPill(
                                              status: status,
                                              isPaid: isPaid,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCompact extends StatelessWidget {
  final Map<String, num> summary;
  final String subtitle;
  const _SummaryCompact({required this.summary, required this.subtitle});

  static const Color primaryColor = Color(0xFF3366CC);
  static const Color successColor = Color(0xFF00CC66);
  static const Color warningColor = Color(0xFFFFA000);
  static const Color infoColor = Color(0xFF607D8B);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Resumen semanal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipMetric('Cuotas', summary['total_count'] ?? 0),
                _chipMetric(
                  'Pendientes',
                  summary['pending_count'] ?? 0,
                  bg: warningColor,
                ),
                _chipMetric(
                  'Parciales',
                  summary['partial_count'] ?? 0,
                  bg: infoColor,
                ),
                _chipMetric(
                  'Pagadas',
                  summary['paid_count'] ?? 0,
                  bg: successColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _money('Monto semanal', summary['total_amount'] ?? 0),
                _money('Cobrado hasta ahora', summary['paid_amount'] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipMetric(String label, num value, {Color bg = primaryColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          ),
          Text(
            '$value',
            style: TextStyle(color: bg.darken(), fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: bg.darken())),
        ],
      ),
    );
  }

  Widget _money(String label, num value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final bool isPaid;
  const _StatusPill({required this.status, required this.isPaid});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;

    final s = status.toLowerCase().trim();
    if (isPaid || s == 'pagada') {
      bg = Colors.green.withOpacity(0.12);
      fg = Colors.green.shade700;
    } else if (s == 'pendiente') {
      bg = Colors.orange.withOpacity(0.12);
      fg = Colors.orange.shade700;
    } else if (s == 'parcialmente pagada') {
      bg = Colors.blueGrey.withOpacity(0.12);
      fg = Colors.blueGrey.shade700;
    } else {
      bg = Colors.grey.withOpacity(0.12);
      fg = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

extension on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

class _ScreenData {
  final List<InstallmentListItem> list;
  final Map<String, num> summary;
  _ScreenData({required this.list, required this.summary});
}
