import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/api_service.dart';
import 'customer_overdue_detail_screen.dart';

enum _SortMode { amount, days, name }

class OverdueScreen extends StatefulWidget {
  const OverdueScreen({super.key});
  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  static const primary = Color(0xFF3366CC);

  bool _loading = true;
  String? _error;
  _SortMode _sort = _SortMode.amount;
  final _searchCtl = TextEditingController();
  String _search = '';

  // resumen
  int clientsWithOverdue = 0;
  int loansWithOverdue = 0;
  int installmentsOverdue = 0;
  double totalOverdue = 0;

  // listado agrupado
  List<CustomerAgg> groups = [];

  late final NumberFormat _moneyFmtDec = NumberFormat.decimalPattern('es_AR');
  String _money(num v, {bool symbol = true}) {
    final s = _moneyFmtDec.format(v);
    return symbol ? '\$$s' : s; // sin espacio para evitar saltos de línea
  }

  final TextStyle _subtitleStyle = const TextStyle(
    color: Colors.black54,
    fontSize: 13,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final employeeId = await ApiService.getEmployeeId();

      // Traé directamente VENCIDAS desde el service
      final items = await ApiService.fetchInstallmentsEnriched(
        employeeId: employeeId!,
        dateFrom: null,
        dateTo: null,
        statusFilter: 'vencidas',
      );

      final today = DateTime.now();
      final Map<String, CustomerAgg> map = {};

      for (final row in items) {
        final it = row.installment;
        final st = (it.status).toLowerCase().trim();

        // Seguridad extra: asegurate que sea Vencida y no Pagada
        final bool isOverdueFlag = (it as dynamic).isOverdue == true;
        final bool isVencida = st == 'vencida' || isOverdueFlag;
        final bool isPagada = (it.isPaid == true) || st == 'pagada';
        if (!isVencida || isPagada) continue;

        final key = (row.customerId?.toString() ?? row.customerName ?? 'N/D');

        map.putIfAbsent(
          key,
          () => CustomerAgg(
            customerKey: key,
            customerId: row.customerId,
            name: row.customerName ?? 'Cliente',
            phone: row.customerPhone,
          ),
        );

        final g = map[key]!;

        // paidAmount robusto
        double paid = 0.0;
        try {
          final dynamicPaid = (it as dynamic).paidAmount;
          if (dynamicPaid is num) paid = dynamicPaid.toDouble();
        } catch (_) {}
        final remaining = (it.amount - paid).clamp(0, it.amount);

        final loanId = row.loanId ?? -1;
        g.loans.putIfAbsent(loanId, () => LoanAgg(loanId: loanId));
        final la = g.loans[loanId]!;

        // due_date (para días de mora)
        final dueOnly = DateTime(
          it.dueDate.year,
          it.dueDate.month,
          it.dueDate.day,
        );
        final todayOnly = DateTime(today.year, today.month, today.day);

        la.amountOverdue += remaining;
        la.count += 1;
        la.oldestDue =
            (la.oldestDue == null || dueOnly.isBefore(la.oldestDue!))
                ? dueOnly
                : la.oldestDue;

        g.totalInstallments += 1;
        g.totalOverdue += remaining;
        final days = todayOnly.difference(dueOnly).inDays;
        if (days > g.maxDaysOverdue) g.maxDaysOverdue = days;
      }

      groups = map.values.toList();

      // resumen global
      clientsWithOverdue = groups.length;
      loansWithOverdue = groups.fold(0, (acc, g) => acc + g.loans.length);
      installmentsOverdue = groups.fold(
        0,
        (acc, g) => acc + g.totalInstallments,
      );
      totalOverdue = groups.fold(0.0, (acc, g) => acc + g.totalOverdue);

      _applySort();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  void _applySort() {
    switch (_sort) {
      case _SortMode.amount:
        groups.sort((a, b) => b.totalOverdue.compareTo(a.totalOverdue));
        break;
      case _SortMode.days:
        groups.sort((a, b) => b.maxDaysOverdue.compareTo(a.maxDaysOverdue));
        break;
      case _SortMode.name:
        groups.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
    }
  }

  List<CustomerAgg> get _visibleGroups {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return groups.where((g) => g.name.toLowerCase().contains(q)).toList();
  }

  Color _overdueColor(int days) {
    if (days >= 60) return Colors.redAccent;
    if (days >= 30) return Colors.orange;
    if (days >= 7) return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext ctx) {
    // Header fijo, un poco más alto para que entren bien los chips
    const double headerHeight = 160;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cuotas vencidas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: primary))
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                color: primary,
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _summaryCard(),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SearchSortHeader(
                        searchCtl: _searchCtl,
                        sort: _sort,
                        onSearchChanged: (v) => setState(() => _search = v),
                        onSortChanged: (m) {
                          setState(() {
                            _sort = m;
                            _applySort();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Ordenado por ${m == _SortMode.amount
                                    ? 'monto vencido'
                                    : m == _SortMode.days
                                    ? 'días de mora'
                                    : 'nombre'}',
                              ),
                              duration: const Duration(milliseconds: 1200),
                            ),
                          );
                        },
                        height: headerHeight,
                      ),
                    ),
                    if (_visibleGroups.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _emptyStateCard(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _customerTile(_visibleGroups[i]),
                            childCount: _visibleGroups.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }

  // === UI helpers ===

  Widget _summaryCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen de mora',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Clientes con deuda activa: $clientsWithOverdue',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    _kpiCell(
                      Icons.people_alt,
                      clientsWithOverdue.toString(),
                      'Clientes',
                    ),
                    _kpiCell(
                      Icons.assignment,
                      loansWithOverdue.toString(),
                      'Créditos',
                    ),
                  ],
                ),
                const TableRow(
                  children: [SizedBox(height: 12), SizedBox(height: 12)],
                ),
                TableRow(
                  children: [
                    _kpiCell(
                      Icons.event_busy,
                      installmentsOverdue.toString(),
                      'Cuotas',
                    ),
                    _kpiCell(
                      Icons.payments_rounded,
                      _money(totalOverdue, symbol: true),
                      'Total vencido',
                      emphasize: true,
                      valueColor: Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCell(
    IconData icon,
    String value,
    String label, {
    bool emphasize = false,
    bool alignRight = false,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment:
          alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment:
                alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                value,
                softWrap: true,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: emphasize ? 18 : 16,
                  color: valueColor ?? Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: _subtitleStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _customerTile(CustomerAgg g) {
    final color = _overdueColor(g.maxDaysOverdue);

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerOverdueDetailScreen(group: g),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.10),
                child: const Icon(Icons.person, color: primary),
              ),
              const SizedBox(width: 12),

              // Centro: nombre + meta + badge de mora
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Créditos: ${g.loans.length} · Cuotas: ${g.totalInstallments}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _subtitleStyle,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Mora máx: ${g.maxDaysOverdue} días',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Monto + chevron
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 84, maxWidth: 120),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _money(g.totalOverdue),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.black38,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyStateCard() {
    return Card(
      elevation: 1,
      color: Colors.green.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin cuotas vencidas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '¡Todo al día! Buen trabajo 👏',
                    style: TextStyle(color: Colors.black54),
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

// ====== modelos de vista ======

class CustomerAgg {
  final String customerKey;
  final int? customerId;
  final String name;
  final String? phone;
  final Map<int, LoanAgg> loans = {};
  int totalInstallments = 0;
  double totalOverdue = 0;
  int maxDaysOverdue = 0;

  CustomerAgg({
    required this.customerKey,
    required this.customerId,
    required this.name,
    required this.phone,
  });
}

class LoanAgg {
  final int loanId;
  int count = 0;
  double amountOverdue = 0;
  DateTime? oldestDue;

  LoanAgg({required this.loanId});
}

class _SearchSortHeader extends SliverPersistentHeaderDelegate {
  _SearchSortHeader({
    required this.searchCtl,
    required this.sort,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.height,
  });

  final TextEditingController searchCtl;
  final _SortMode sort;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_SortMode> onSortChanged;
  final double height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Material(
      color: bg,
      elevation: overlapsContent ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchCtl,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ordenar por',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Monto vencido'),
                    selected: sort == _SortMode.amount,
                    onSelected: (_) => onSortChanged(_SortMode.amount),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Días de mora'),
                    selected: sort == _SortMode.days,
                    onSelected: (_) => onSortChanged(_SortMode.days),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Nombre'),
                    selected: sort == _SortMode.name,
                    onSelected: (_) => onSortChanged(_SortMode.name),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _SearchSortHeader old) =>
      old.sort != sort ||
      old.searchCtl.text != searchCtl.text ||
      old.height != height;
}
