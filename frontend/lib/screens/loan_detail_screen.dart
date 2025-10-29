import 'package:flutter/material.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/receipt_service.dart';
import 'package:intl/intl.dart';
import 'package:frontend/screens/installment_detail_screen.dart';
import 'package:frontend/screens/create_loan_or_purchase_screen.dart';
import 'package:frontend/shared/status.dart';
import 'package:frontend/screens/payment_detail_screen.dart';

class LoanDetailScreen extends StatefulWidget {
  final int loanId;
  final Loan? loanData;
  final bool fromCreateScreen;

  const LoanDetailScreen({
    super.key,
    required this.loanId,
    this.loanData,
    this.fromCreateScreen = false,
  });

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

const String kPendiente = 'Pendiente';
const String kPagada = 'Pagada';
const String kParcial = 'Parcialmente pagada';
const String kVencida = 'Vencida';

DateTime? _parseAny(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) {
    // epoch: 13 dígitos = ms, 10 = seg (tomamos UTC)
    return v > 9999999999
        ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
  }
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

String _fmtLocal(dynamic v, DateFormat fmt) {
  final dt = _parseAny(v);
  if (dt == null) return '-';
  final local = dt.isUtc ? dt.toLocal() : dt;
  return fmt.format(local);
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  String _installmentDisplayStatus(Installment i) {
    // Si no está paga y está vencida → "Vencida" (flag rápido si viene seteado)
    if (i.isPaid == false && i.isOverdue == true) {
      return 'Vencida';
    }
    // Normalizar lo que venga del backend (cuotas)
    final s = normalizeInstallmentStatus(i.status);
    // Si no viene claro, inferimos por montos (EPS)
    const eps = 0.01;
    final paid = i.paidAmount;
    final amt = i.amount;
    if (paid >= amt - eps) return 'Pagada';
    if (paid > eps) return 'Parcialmente pagada';

    // Como último recurso, si venció y no hay pagos → Vencida
    final today = DateTime.now();
    if (i.dueDate.isBefore(DateTime(today.year, today.month, today.day))) {
      return 'Vencida';
    }
    return s.isEmpty ? 'Pendiente' : s;
  }

  // Evita falsos "falta pagar 0.00" por redondeos
  static const double kMoneyEps = 0.01;

  // Nombre del empleado (cobrador/creador) resuelto una sola vez
  late Future<String?> _employeeNameFut;

  bool _isInstallmentPaid(Installment i) {
    final remainingAbs = (i.amount - i.paidAmount).abs();
    return i.isPaid || remainingAbs < kMoneyEps;
  }

  late Future<List<Installment>> installments;
  late Future<Loan?> loanDetails;
  late Future<List<Map<String, dynamic>>> loanPayments; // historial de pagos

  bool isLoading = false;

  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 2,
  );

  final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _loadData();
    _employeeNameFut = ApiService.getEmployeeName();
  }

  void _loadData() {
    setState(() {
      installments = ApiService.fetchInstallmentsByLoan(widget.loanId);
      loanDetails =
          widget.loanData != null
              ? Future.value(widget.loanData)
              : ApiService.fetchLoanDetails(widget.loanId);
      loanPayments = ApiService.fetchPaymentsByLoan(widget.loanId);
    });
  }

  Future<void> _refreshData() async {
    setState(() => isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));
    _loadData();
    setState(() => isLoading = false);
  }

  Widget _buildLoanHeader(Loan loan) {
    final startDate = DateTime.tryParse(loan.startDate) ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy').format(startDate);

    // ⬇️ Normalizador de estado de PRÉSTAMO (UI ES)
    final displayStatus = normalizeLoanStatus(loan.status);

    final progress =
        loan.amount > 0 ? (loan.amount - loan.totalDue) / loan.amount : 0.0;
    final isFullyPaid =
        displayStatus.toLowerCase() == 'pagado' || progress >= 0.999;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Préstamo #${loan.id}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Chip(
                  label: Text(
                    displayStatus,
                    style: const TextStyle(color: Colors.white),
                  ),
                  // ⬇️ Color unificado para PRÉSTAMO
                  backgroundColor: loanStatusColor(displayStatus),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              'Monto Total:',
              currencyFormatter.format(loan.amount),
            ),
            _buildDetailRow(
              'Saldo Pendiente:',
              currencyFormatter.format(loan.totalDue),
            ),
            _buildDetailRow(
              'Cuota:',
              currencyFormatter.format(loan.installmentAmount),
            ),
            _buildDetailRow('Inicio:', formattedDate),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              color: isFullyPaid ? secondaryColor : primaryColor,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(progress * 100).toStringAsFixed(1)}% Pagado',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== sección "Historial de pagos" =====
  Widget _buildPaymentsTimeline(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Este préstamo todavía no tiene pagos.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Historial de pagos (${items.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          ...items.map((p) {
            final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
            p['payment_date']?.toString();
            try {} catch (_) {}
            final rawDate = p['payment_date'] ?? p['created_at'];
            final when = _fmtLocal(
              rawDate,
              _dateTimeFmt,
            ); // _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm')

            final isVoided = p['is_voided'] == true;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              elevation: 1,
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  currencyFormatter.format(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isVoided ? Colors.red.shade700 : Colors.black87,
                    decoration: isVoided ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(isVoided ? '$when — ANULADO' : when),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentDetailScreen(payment: p),
                    ),
                  );
                  if (changed == true && mounted) {
                    await _refreshData();
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===== listar pagos de una cuota y navegar a detalle =====
  Future<void> _showPaymentsForInstallment(int installmentId) async {
    try {
      final items = await ApiService.fetchPaymentsByInstallment(installmentId);
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta cuota no tiene pagos aplicados')),
        );
        return;
      }

      if (items.length == 1) {
        final p = items.first;
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => PaymentDetailScreen(payment: p)),
        );
        if (changed == true && mounted) {
          await _refreshData();
        }
        return;
      }

      // Varios pagos -> selector
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: ListView(
              children: [
                const ListTile(title: Text('Pagos de esta cuota')),
                ...items.map((p) {
                  final rawDate = p['payment_date'] ?? p['created_at'];
                  final when = _fmtLocal(
                    rawDate,
                    _dateTimeFmt,
                  ); // -> muestra en hora local

                  final id = (p['id'] as num?)?.toInt() ?? 0;
                  final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;

                  return ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('Pago #$id — \$${amount.toStringAsFixed(2)}'),
                    subtitle: Text(when),
                    onTap: () => Navigator.pop(ctx, p),
                  );
                }),
              ],
            ),
          );
        },
      );

      if (selected != null && mounted) {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentDetailScreen(payment: selected),
          ),
        );
        if (changed == true && mounted) {
          await _refreshData();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar pagos: $e')),
      );
    }
  }

  Widget _installmentActionsRow(Installment installment) {
    final isPaid = _isInstallmentPaid(installment);
    final hasAnyPayment = installment.paidAmount > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!isPaid)
          TextButton.icon(
            onPressed: () => _navigateToInstallmentDetail(installment),
            icon: const Icon(Icons.attach_money),
            label: const Text('Cobrar'),
          ),
        if (hasAnyPayment) const SizedBox(width: 8),
        if (hasAnyPayment)
          TextButton.icon(
            onPressed: () => _showPaymentsForInstallment(installment.id),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Ver pagos de esta cuota'),
          ),
      ],
    );
  }

  Widget _buildInstallmentItem(Installment installment) {
    final status = _installmentDisplayStatus(installment); // 👈 unificado
    final isPaid = status.toLowerCase() == 'pagada';
    const eps = 0.01;
    final remaining = (installment.amount - installment.paidAmount);
    final remainingShown = remaining.abs() < eps ? 0.0 : remaining;

    final progress =
        installment.amount == 0
            ? 0.0
            : (installment.paidAmount / installment.amount).clamp(0.0, 1.0);

    final dueDate = DateFormat('dd/MM/yyyy').format(installment.dueDate);

    final chipColor = installmentStatusColor(
      status,
    ); // 👈 color UI centralizado
    final isOverdue = status.toLowerCase() == 'vencida';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color:
              isOverdue
                  ? dangerColor.withValues(alpha: 0.3)
                  : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (isPaid) {
            _showPaymentsForInstallment(installment.id);
          } else {
            _navigateToInstallmentDetail(installment);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // título + chip de estado (siempre)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cuota ${installment.number}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isOverdue ? dangerColor : Colors.grey.shade800,
                    ),
                  ),
                  Chip(
                    label: Text(
                      status.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    backgroundColor: chipColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Monto:',
                currencyFormatter.format(installment.amount),
              ),
              _buildDetailRow(
                'Pagado:',
                currencyFormatter.format(installment.paidAmount),
              ),
              _buildDetailRow('Vencimiento:', dueDate),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: isPaid ? secondaryColor : primaryColor,
                minHeight: 6,
              ),
              if (!isPaid && remainingShown > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Falta pagar: ${currencyFormatter.format(remainingShown)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              const SizedBox(height: 8),
              _installmentActionsRow(installment),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToInstallmentDetail(Installment installment) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstallmentDetailScreen(installment: installment),
      ),
    );
    if (!mounted) return;
    await _refreshData(); // refrescamos SIEMPRE al volver
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.fromCreateScreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (widget.fromCreateScreen) {
          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Detalle del Préstamo',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              tooltip: 'Compartir estado',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                final empName = await _employeeNameFut; // puede ser null
                if (!mounted) {
                  return; // 👈 evita usar context tras await si se desmontó
                }
                await ReceiptService.shareLoanStatementByLoanId(
                  context,
                  widget.loanId,
                  collectorName: empName, // “Cobrador”
                  creatorName: empName, // “Creado por” (mismo por ahora)
                );
              },
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'cancel') {
                  _onCancelLoan();
                } else if (value == 'refinance') {
                  _onRefinanceLoan();
                }
              },
              itemBuilder:
                  (ctx) => const [
                    PopupMenuItem<String>(
                      value: 'cancel',
                      child: Text('Cancelar préstamo'),
                    ),
                    PopupMenuItem<String>(
                      value: 'refinance',
                      child: Text('Refinanciar préstamo'),
                    ),
                  ],
            ),
          ],
        ),
        body:
            isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
                : FutureBuilder(
                  future: Future.wait([
                    loanDetails,
                    installments,
                    loanPayments,
                  ]),
                  builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: primaryColor),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: dangerColor,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Error al cargar los datos',
                              style: TextStyle(
                                fontSize: 16,
                                color: dangerColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _refreshData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                              ),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.data == null ||
                        snapshot.data![0] == null ||
                        snapshot.data![1] == null ||
                        snapshot.data![2] == null) {
                      return Center(
                        child: Text(
                          'No se encontraron datos del préstamo',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      );
                    }

                    final loan = snapshot.data![0] as Loan;
                    // Orden consistente 1→n en la UI también
                    final installmentsData =
                        (snapshot.data![1] as List<Installment>).toList()
                          ..sort((a, b) => a.number.compareTo(b.number));
                    final paymentsData =
                        snapshot.data![2] as List<Map<String, dynamic>>;

                    return RefreshIndicator(
                      onRefresh: _refreshData,
                      color: primaryColor,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _buildLoanHeader(loan),

                            const SizedBox(height: 8),

                            // LISTA DE CUOTAS
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Cuotas (${installmentsData.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    'Total: ${currencyFormatter.format(loan.amount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...installmentsData.map(
                              (i) => _buildInstallmentItem(i),
                            ),
                            const SizedBox(height: 20),

                            // HISTORIAL DE PAGOS
                            _buildPaymentsTimeline(paymentsData),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }

  Future<void> _onCancelLoan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Cancelar préstamo'),
            content: const Text(
              '¿Seguro que querés cancelar este préstamo? Las cuotas pendientes quedarán como Canceladas y el saldo en 0.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, cancelar'),
              ),
            ],
          ),
    );
    if (confirm != true) return;
    try {
      final ok = await ApiService.cancelLoan(widget.loanId);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Préstamo cancelado')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _onRefinanceLoan() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Refinanciar préstamo'),
            content: const Text(
              'Esto cerrará el préstamo actual y marcará sus cuotas pendientes como Refinanciadas. ¿Querés continuar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, continuar'),
              ),
            ],
          ),
    );
    if (proceed != true) return;

    try {
      final remaining = await ApiService.refinanceLoan(widget.loanId);
      if (!mounted) return;
      final goCreate = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Refinanciación realizada'),
              content: Text(
                'Saldo a refinanciar: \$${remaining.toStringAsFixed(2)}\n\n¿Crear un nuevo préstamo ahora?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Después'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Crear nuevo'),
                ),
              ],
            ),
      );
      if (!mounted) return;

      if (goCreate == true) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateLoanOrPurchaseScreen()),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saldo a refinanciar: \$${remaining.toStringAsFixed(2)}',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
