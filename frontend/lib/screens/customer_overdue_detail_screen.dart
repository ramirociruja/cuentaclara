import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'overdue_screen.dart' show CustomerAgg, LoanAgg;
import 'package:frontend/screens/loan_detail_screen.dart';

class CustomerOverdueDetailScreen extends StatelessWidget {
  const CustomerOverdueDetailScreen({super.key, required this.group});

  final CustomerAgg group;

  static const primary = Color(0xFF3366CC);
  static final NumberFormat _moneyFmtDec = NumberFormat.decimalPattern('es_AR');

  // Sin espacio para evitar cortes de línea entre $ y el número
  String _money(num v, {bool symbol = true}) =>
      symbol ? '\$${_moneyFmtDec.format(v)}' : _moneyFmtDec.format(v);

  static const TextStyle _subtitleStyle = TextStyle(
    color: Colors.black54,
    fontSize: 13,
  );

  String _fmtDMY(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final loans =
        group.loans.values.toList()
          ..sort((a, b) => b.amountOverdue.compareTo(a.amountOverdue));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          group.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context),
          const SizedBox(height: 12),
          const Text(
            'Créditos con deuda',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (int i = 0; i < loans.length; i++) ...[
                  _loanTile(context, loans[i]),
                  if (i != loans.length - 1)
                    Divider(height: 1, color: Colors.grey.shade300),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- UI blocks ----------

  Widget _summaryCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con avatar + datos del cliente
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: primary.withOpacity(.1),
                  child: const Icon(Icons.person, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (group.phone != null && group.phone!.trim().isNotEmpty)
                        Text(
                          'Tel: ${group.phone!}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _subtitleStyle,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // KPIs compactos (mismo criterio que OverdueScreen)
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
                      Icons.assignment,
                      group.loans.length.toString(),
                      'Créditos con mora',
                    ),
                    _kpiCell(
                      Icons.event_busy,
                      group.totalInstallments.toString(),
                      'Cuotas vencidas',
                    ),
                  ],
                ),
                const TableRow(
                  children: [SizedBox(height: 12), SizedBox(height: 12)],
                ),
                TableRow(
                  children: [
                    _kpiCell(
                      Icons.timer_outlined,
                      '${group.maxDaysOverdue}d',
                      'Mora máxima',
                    ),
                    _kpiCell(
                      Icons.attach_money,
                      _money(group.totalOverdue, symbol: false),
                      'Total vencido',
                      emphasize: true,
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
  }) {
    return Row(
      mainAxisAlignment:
          alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
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
                  fontSize: emphasize ? 18 : 16, // sobrio (sin números XXL)
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

  Widget _loanTile(BuildContext context, LoanAgg la) {
    final oldest = la.oldestDue != null ? _fmtDMY(la.oldestDue!) : '-';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: primary.withOpacity(.08),
        child: const Icon(Icons.assignment, color: primary),
      ),
      title: Text(
        'Préstamo #${la.loanId}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Cuotas vencidas: ${la.count} · Venc. más antiguo: $oldest',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _subtitleStyle,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 84, maxWidth: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _money(la.amountOverdue),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
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
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoanDetailScreen(loanId: la.loanId),
          ),
        );
      },
    );
  }
}
