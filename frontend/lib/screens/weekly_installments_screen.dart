import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/screens/installment_detail_screen.dart';
import 'package:frontend/shared/status.dart';

class WeeklyInstallmentsScreen extends StatefulWidget {
  const WeeklyInstallmentsScreen({super.key});

  @override
  State<WeeklyInstallmentsScreen> createState() =>
      _WeeklyInstallmentsScreenState();
}

class _WeeklyInstallmentsScreenState extends State<WeeklyInstallmentsScreen> {
  static const Color primaryColor = Color(0xFF3366CC);

  // ---- Estado base ----
  int? _employeeId;
  bool _loadingId = true;
  String? _idError;

  // Filtros
  int _selectedDay = 0; // 0=Todos, 1..7 = Lun..Dom
  bool _onlyPending = true; // Pendiente/Parcial (excluye vencidas del resumen)
  String _query = '';

  // Orden
  String _sort =
      'cliente_az'; // cliente_az | cliente_za | vencimiento_asc | monto_desc | saldo_desc | estado

  // Semana mostrada (sólo para rótulo)
  late DateTime _monday;
  late DateTime _sunday;

  bool _hideByStatus(InstallmentListItem r) {
    final st = r.installment.status.trim().toLowerCase();
    return st == 'cancelada' || st == 'refinanciada';
  }

  bool _isInCurrentWeek(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final lo = DateTime(_monday.year, _monday.month, _monday.day);
    final hi = DateTime(_sunday.year, _sunday.month, _sunday.day);
    return !dd.isBefore(lo) && !dd.isAfter(hi);
  }

  // Datos + scroll (para ocultar resumen al scrollear)
  Future<List<InstallmentListItem>>? _future;
  final ScrollController _scrollCtrl = ScrollController();
  bool _showSummary = true;

  // Buscar en AppBar
  bool _searchMode = false;
  final TextEditingController _searchCtrl = TextEditingController();

  // Formato dinero
  static final NumberFormat _moneyFmt = NumberFormat.currency(
    locale: 'es_AR',
    symbol: r'$',
  );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monday = _toMonday(now);
    _sunday = _monday.add(const Duration(days: 6));
    _scrollCtrl.addListener(_onScrollHideSummary);
    _loadEmployeeId();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScrollHideSummary);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScrollHideSummary() {
    if (_scrollCtrl.offset > 24 && _showSummary) {
      setState(() => _showSummary = false);
    } else if (_scrollCtrl.offset < 4 && !_showSummary) {
      setState(() => _showSummary = true);
    }
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
          _future = _loadData();
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

  Future<List<InstallmentListItem>> _loadData() async {
    final list = await ApiService.fetchInstallmentsEnriched(
      employeeId: _employeeId,
      dateFrom: _monday,
      dateTo: _sunday,
      statusFilter: _onlyPending ? 'pendientes' : 'todas',
    );

    // Nos quedamos SOLO con cuotas cuyo due_date cae en la semana
    return list.where((r) => _isInCurrentWeek(r.installment.dueDate)).toList();
  }

  DateTime _toMonday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
  String _fmtDMY(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // --------- Helpers de estado / filtros / summary ---------

  bool _isOverdue(InstallmentListItem row) {
    final it = row.installment;
    final s = (it.status).toLowerCase().trim();
    return (it.isOverdue == true) || s.contains('vencid');
  }

  String _statusOf(InstallmentListItem row) {
    final it = row.installment;
    final s = normalizeInstallmentStatus(
      it.status,
    ); // 👈 normalizador unificado
    if (s.toLowerCase().contains('vencid')) return kCuotaVencida;
    if (it.paidAmount >= it.amount - 1e-6) return kCuotaPagada;
    if (it.paidAmount > 0) return kCuotaParcial;
    return kCuotaPendiente;
  }

  int _collectionDay(InstallmentListItem row) => (row.collectionDay ?? 0);

  bool _passesDayFilter(InstallmentListItem row) =>
      _selectedDay == 0 || _collectionDay(row) == _selectedDay;

  bool _passesOnlyPending(InstallmentListItem row) {
    if (!_onlyPending) return true;

    final st = _statusOf(row);

    // Pendiente o Parcial → SIEMPRE pasan
    if (st == kCuotaPendiente || st == kCuotaParcial) return true;

    // Vencida → SOLO pasa si su due_date está dentro de ESTA semana
    if (_isOverdue(row) && _isInCurrentWeek(row.installment.dueDate)) {
      return true;
    }

    // Todo lo demás (Pagada, etc.) queda fuera
    return false;
  }

  bool _passesQuery(InstallmentListItem row) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    final name = (row.customerName ?? '').toLowerCase();
    final phone = (row.customerPhone ?? '').toLowerCase();
    return name.contains(q) || phone.contains(q);
  }

  List<InstallmentListItem> _applyFilters(List<InstallmentListItem> src) {
    return src
        .where((r) => !_hideByStatus(r)) // ⬅️ filtra Cancelada / Refinanciada
        .where((r) => _passesDayFilter(r))
        .where((r) => _passesOnlyPending(r))
        .where((r) => _passesQuery(r))
        .toList();
  }

  List<InstallmentListItem> _applySort(List<InstallmentListItem> items) {
    int sOrder(String s) {
      // usar constantes unificadas
      if (s == kCuotaPendiente) return 0;
      if (s == kCuotaParcial) return 1;
      if (s == kCuotaPagada) return 2;
      return 3;
    }

    items.sort((a, b) {
      final sa = _statusOf(a);
      final sb = _statusOf(b);
      final na = (a.customerName ?? '').toLowerCase();
      final nb = (b.customerName ?? '').toLowerCase();
      final da = a.installment.dueDate;
      final db = b.installment.dueDate;
      final ra = a.installment.amount - a.installment.paidAmount; // saldo
      final rb = b.installment.amount - b.installment.paidAmount;

      switch (_sort) {
        case 'cliente_az':
          return na.compareTo(nb);
        case 'cliente_za':
          return nb.compareTo(na);
        case 'vencimiento_asc':
          return da.compareTo(db);
        case 'monto_desc':
          return b.installment.amount.compareTo(a.installment.amount);
        case 'saldo_desc':
          return rb.compareTo(ra);
        case 'estado':
          final cmp = sOrder(sa).compareTo(sOrder(sb));
          if (cmp != 0) return cmp;
          return da.compareTo(db);
        default:
          return da.compareTo(db);
      }
    });
    return items;
  }

  Map<String, num> _deriveSummary(List<InstallmentListItem> items) {
    int pendParVen = 0, pagadas = 0;
    double cobrado = 0, pendiente = 0;

    for (final row in items) {
      final it = row.installment;
      final st = _statusOf(row);
      final bool esOverdue = _isOverdue(row);

      if (st == kCuotaPagada) {
        pagadas++;
      } else if (st == kCuotaPendiente || st == kCuotaParcial || esOverdue) {
        // ✅ Ahora contamos también las Vencidas dentro del bucket Pend/Par/Ven
        pendParVen++;
      }

      // Dinero
      cobrado += it.paidAmount;
      final saldo = it.amount - it.paidAmount;
      if (saldo > 0) pendiente += saldo;
    }

    return <String, num>{
      'count_total': pendParVen + pagadas,
      'count_pend_par_ven': pendParVen, // 👈 clave nueva
      'count_pagadas': pagadas,
      'amount_paid': cobrado,
      'amount_pending': pendiente,
    };
  }

  String _dayLabel(int? d) {
    if (d == null || d == 0) return 'Todos';
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    if (d < 1 || d > 7) return '-';
    return days[d - 1];
  }

  String _dayFull(int? d) {
    if (d == null || d == 0) return 'Todos';
    const days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    if (d < 1 || d > 7) return '-';
    return days[d - 1];
  }

  // ------------ Sort sheet ------------
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
              tile('vencimiento_asc', 'Vencimiento ↑', Icons.event),
              tile('cliente_az', 'Cliente A→Z', Icons.sort_by_alpha),
              tile('cliente_za', 'Cliente Z→A', Icons.sort_by_alpha),
              tile(
                'saldo_desc',
                'Saldo pendiente ↓',
                Icons.account_balance_wallet_outlined,
              ),
              tile('monto_desc', 'Monto de cuota ↓', Icons.attach_money),
              tile('estado', 'Estado', Icons.label_outline),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (sel != null) {
      setState(() => _sort = sel);
    }
  }

  // --------- AppBar título o búsqueda ---------
  Widget _buildAppBarTitle() {
    if (!_searchMode) {
      return const Text(
        'Agenda de cobranzas',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      );
    }
    return TextField(
      controller: _searchCtrl,
      autofocus: true,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      decoration: const InputDecoration(
        hintText: 'Buscar nombre o teléfono',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      onChanged: (v) => setState(() => _query = v),
    );
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
        appBar: AppBar(title: const Text('Agenda de cobranzas')),
        body: Center(child: Text(_idError!)),
      );
    }

    final weekLabel = 'Semana: ${_fmtDMY(_monday)} - ${_fmtDMY(_sunday)}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _buildAppBarTitle(),
        actions: [
          if (!_searchMode)
            IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.search),
              onPressed:
                  () => setState(() {
                    _searchMode = true;
                    _showSummary = false;
                  }),
            ),
          if (_searchMode)
            IconButton(
              tooltip: 'Cerrar búsqueda',
              icon: const Icon(Icons.close),
              onPressed:
                  () => setState(() {
                    _searchMode = false;
                    _query = '';
                    _searchCtrl.clear();
                  }),
            ),
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _loadData()),
          ),
        ],
      ),
      body:
          (_future == null)
              ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
              : FutureBuilder<List<InstallmentListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    );
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  final allWeek = snap.data ?? <InstallmentListItem>[];

                  var items = allWeek;
                  items = _applyFilters(items);
                  items = _applySort(items);

                  final summary = _deriveSummary(items);

                  return Column(
                    children: [
                      // Resumen compacto (se oculta al scrollear)
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState:
                            _showSummary
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                        firstChild: _TinySummaryBanner(
                          summary: summary,
                          dayLabel: _dayLabel(_selectedDay),
                          weekLabel: weekLabel,
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),

                      // Barra de filtros compacta (con dropdown de día)
                      _FiltersBar(
                        selectedDay: _selectedDay,
                        onlyPending: _onlyPending,
                        onDayChanged: (d) => setState(() => _selectedDay = d),
                        onOnlyPendingChanged:
                            (v) => setState(() {
                              _onlyPending = v;
                              _future = _loadData();
                            }),
                        onSortPressed: _openSortSheet,
                        dayLabelBuilder: _dayFull,
                      ),

                      // Lista
                      Expanded(
                        child: RefreshIndicator(
                          color: primaryColor,
                          onRefresh:
                              () async => setState(() => _future = _loadData()),
                          child:
                              items.isEmpty
                                  ? ListView(
                                    controller: _scrollCtrl,
                                    children: const [
                                      SizedBox(height: 80),
                                      Center(
                                        child: Text(
                                          'No hay cuotas para los filtros seleccionados',
                                        ),
                                      ),
                                    ],
                                  )
                                  : ListView.separated(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    itemCount: items.length,
                                    separatorBuilder:
                                        (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final row = items[i];
                                      final it = row.installment;
                                      final status = _statusOf(row);
                                      final saldo = (it.amount - it.paidAmount)
                                          .clamp(0, double.infinity);

                                      // Vencidas por préstamo en la semana (opcional)
                                      int overdueForLoan = 0;
                                      if (row.loanId != null) {
                                        overdueForLoan =
                                            allWeek
                                                .where(
                                                  (r) =>
                                                      r.loanId == row.loanId &&
                                                      _isOverdue(r),
                                                )
                                                .length;
                                      }

                                      final cardBorder =
                                          status.toLowerCase().contains(
                                                'vencid',
                                              )
                                              ? BorderSide(
                                                color: Colors.redAccent
                                                    .withValues(alpha: .35),
                                              )
                                              : BorderSide(
                                                color: Colors.grey.shade300,
                                              );

                                      return Card(
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: cardBorder,
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: () async {
                                            final refreshed = await Navigator.push<
                                              bool
                                            >(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        InstallmentDetailScreen(
                                                          installment: it,
                                                        ),
                                              ),
                                            );
                                            if (refreshed == true && mounted) {
                                              setState(
                                                () => _future = _loadData(),
                                              );
                                            }
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // ---- Fila principal ----
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // Avatar
                                                    Container(
                                                      width: 46,
                                                      height: 46,
                                                      decoration: BoxDecoration(
                                                        color: primaryColor
                                                            .withValues(
                                                              alpha: 0.1,
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

                                                    // Nombre + préstamo
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          // Nombre
                                                          Text(
                                                            row.customerName ??
                                                                'Cliente',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            'Préstamo #${row.loanId ?? '-'}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13.5,
                                                              color:
                                                                  Colors
                                                                      .grey
                                                                      .shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),

                                                    // Monto de cuota + estado
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          'Cuota ${_moneyFmt.format(it.amount)}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        _StatusPillCompact(
                                                          status: status,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),

                                                // ---- Meta row compacta (SIN fecha de vencimiento) ----
                                                const SizedBox(height: 8),
                                                _metaInline([
                                                  _metaItem(
                                                    Icons.tag,
                                                    '#${it.number}',
                                                  ),
                                                  if (_selectedDay == 0 &&
                                                      row.collectionDay != null)
                                                    _metaItem(
                                                      Icons.event_available,
                                                      _dayFull(
                                                        row.collectionDay,
                                                      ),
                                                    ),
                                                  if (saldo > 0)
                                                    _metaItem(
                                                      Icons
                                                          .account_balance_wallet_outlined,
                                                      'Saldo ${_moneyFmt.format(saldo)}',
                                                    ),
                                                  if (overdueForLoan > 0)
                                                    _metaItem(
                                                      Icons.warning_amber,
                                                      'Vencidas ${overdueForLoan.toString()}',
                                                    ),
                                                ]),
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

  // --------- Meta row helpers ---------
  Widget _metaInline(List<Widget> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  Widget _metaItem(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.black45),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: color ?? Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ----------------- Resumen compacto -----------------

class _TinySummaryBanner extends StatelessWidget {
  final Map<String, num> summary;
  final String dayLabel;
  final String weekLabel;
  const _TinySummaryBanner({
    required this.summary,
    required this.dayLabel,
    required this.weekLabel,
  });

  static const Color primaryColor = Color(0xFF3366CC);
  static const Color okColor = Color(0xFF00CC66);
  static const Color warnColor = Color(0xFFFFA000);

  @override
  Widget build(BuildContext context) {
    final countTotal = summary['count_total'] ?? 0;
    final countPendParVen =
        summary['count_pend_par_ven'] ?? 0; // 👈 nueva clave
    final countPagadas = summary['count_pagadas'] ?? 0;
    final amountPaid = (summary['amount_paid'] ?? 0).toDouble();
    final amountPending = (summary['amount_pending'] ?? 0).toDouble();

    final NumberFormat _fmt = NumberFormat.currency(
      locale: 'es_AR',
      symbol: r'$',
    );

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título sutil + semana + filtro día
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Resumen',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
                Text(
                  dayLabel == 'Todos' ? 'Día: Todos' : 'Día: $dayLabel',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              weekLabel,
              style: const TextStyle(color: Colors.black54, fontSize: 11.5),
            ),
            const SizedBox(height: 8),

            // Chips chiquitos: Total / Pend+Par+Ven / Pagadas
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _miniChip('Cuotas', '$countTotal', bg: primaryColor),
                _miniChip(
                  'Pend/Par/Ven',
                  '$countPendParVen',
                  bg: warnColor,
                ), // 👈 etiqueta actualizada
                _miniChip('Pagadas', '$countPagadas', bg: okColor),
              ],
            ),
            const SizedBox(height: 8),

            // Dinero: Cobrado | Pendiente
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _money('Cobrado', _fmt.format(amountPaid)),
                _money('Pendiente', _fmt.format(amountPending)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, String value, {required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          ),
          Text(
            value,
            style: TextStyle(
              color: bg.darken(0.25),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: bg.darken(0.10),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _money(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }
}

// ----------------- Barra de filtros compacta (con dropdown) -----------------

class _FiltersBar extends StatelessWidget {
  final int selectedDay; // 0..7
  final bool onlyPending;

  final ValueChanged<int> onDayChanged;
  final ValueChanged<bool> onOnlyPendingChanged;
  final VoidCallback onSortPressed;

  // construir etiqueta completa del día (p.ej., 0->Todos, 1->Lunes)
  final String Function(int?) dayLabelBuilder;

  static const Color primaryColor = Color(0xFF3366CC);

  const _FiltersBar({
    required this.selectedDay,
    required this.onlyPending,
    required this.onDayChanged,
    required this.onOnlyPendingChanged,
    required this.onSortPressed,
    required this.dayLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final dayItems = <DropdownMenuItem<int>>[
      for (int i = 0; i <= 7; i++)
        DropdownMenuItem<int>(value: i, child: Text(dayLabelBuilder(i))),
    ];

    return Material(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          children: [
            // Día (Dropdown)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: selectedDay,
                  items: dayItems,
                  onChanged: (v) {
                    if (v != null) onDayChanged(v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Ordenar
            IconButton(
              tooltip: 'Ordenar',
              icon: const Icon(Icons.sort),
              onPressed: onSortPressed,
            ),

            const Spacer(),

            // Solo pendientes (texto completo)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Solo pendientes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: onlyPending,
                  onChanged: onOnlyPendingChanged,
                  activeColor: primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------- Utiles -----------------

class _StatusPillCompact extends StatelessWidget {
  final String status;
  const _StatusPillCompact({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = installmentStatusColor(status); // 👈 color unificado
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: c.darken(0.25),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
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
