import 'package:flutter/material.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:frontend/utils/utils.dart';

// Estados centralizados
import 'package:frontend/shared/status.dart';

// Asegurate que el import coincida con tu ruta real y constructor
import 'package:frontend/screens/loan_detail_screen.dart';

class InstallmentDetailScreen extends StatefulWidget {
  final Installment installment;
  final VoidCallback? onPaymentSuccess;

  const InstallmentDetailScreen({
    Key? key,
    required this.installment,
    this.onPaymentSuccess,
  }) : super(key: key);

  @override
  _InstallmentDetailScreenState createState() =>
      _InstallmentDetailScreenState();
}

class _InstallmentDetailScreenState extends State<InstallmentDetailScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  late Installment installment;
  bool isProcessingPayment = false;

  // Info del préstamo
  int? _loanId;
  bool _loanLoading = false;
  bool _loanHasOverdues = false;

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _otherDescCtrl = TextEditingController();

  // Dropdown “descripción/método” → mapeo a payment_type del backend
  final List<Map<String, String>> _methods = const [
    {'label': 'Efectivo', 'value': 'cash'},
    {'label': 'Transferencia', 'value': 'transfer'},
    {'label': 'Otro', 'value': 'other'},
  ];
  String? _selectedMethod; // 'cash' | 'transfer' | 'other'

  @override
  void initState() {
    super.initState();
    installment = widget.installment;

    // por defecto monto = saldo pendiente
    final remaining = (installment.amount - installment.paidAmount).clamp(
      0,
      double.infinity,
    );
    _amountCtrl.text = remaining.toStringAsFixed(2);

    // Detectar loanId y cargar vencidas
    _loanId = _extractLoanId(installment);
    if (_loanId != null) {
      _loadLoanOverdues(_loanId!);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _otherDescCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers de préstamo / vencidas ----------

  int? _extractLoanId(Installment i) {
    // Tolerante a distintos nombres/estructuras
    try {
      final dyn = i as dynamic;
      final v1 = dyn.loanId;
      if (v1 is int) return v1;
      if (v1 is num) return v1.toInt();
    } catch (_) {}
    try {
      final dyn = i as dynamic;
      final v2 = dyn.loan_id;
      if (v2 is int) return v2;
      if (v2 is num) return v2.toInt();
    } catch (_) {}
    try {
      final dyn = i as dynamic;
      final v3 = dyn.loanID;
      if (v3 is int) return v3;
      if (v3 is num) return v3.toInt();
    } catch (_) {}
    try {
      final dyn = i as dynamic;
      final loanObj = dyn.loan;
      if (loanObj != null) {
        final id = (loanObj['id'] ?? loanObj['loan_id']);
        if (id is int) return id;
        if (id is num) return id.toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadLoanOverdues(int loanId) async {
    setState(() => _loanLoading = true);
    try {
      final loan = await ApiService.fetchLoanDetails(loanId);

      bool hasOverdue = false;
      final insts = loan.installments;
      if (insts.isNotEmpty) {
        hasOverdue = insts.any((inst) => _isOverdue(inst));
      } else {
        // Plan B: si el préstamo no trae cuotas, pedimos las cuotas del loan
        final list = await ApiService.fetchInstallmentsByLoan(loanId);
        hasOverdue = list.any((inst) => _isOverdue(inst));
      }

      if (mounted) setState(() => _loanHasOverdues = hasOverdue);
    } catch (_) {
      if (mounted) setState(() => _loanHasOverdues = false);
    } finally {
      if (mounted) setState(() => _loanLoading = false);
    }
  }

  bool _isOverdue(Installment i) {
    final norm = normalizeInstallmentStatus(i.status);
    final byFlag = i.isOverdue == true;
    final byLabel = norm == 'Vencida';
    final notPaid = !(i.isPaid == true);
    return (byFlag || byLabel) && notPaid;
  }

  void _goToLoan() {
    if (_loanId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LoanDetailScreen(
              // Ajustá si tu constructor es distinto
              loanId: _loanId!,
            ),
      ),
    );
  }

  // ---------- Estados / UI coherente ----------

  String _installmentDisplayStatus(Installment i) {
    if ((i.isPaid == false) && (i.isOverdue == true)) {
      return 'Vencida';
    }
    final s = normalizeInstallmentStatus(i.status);
    if (s.isEmpty || s == 'Pendiente') {
      final paid = i.paidAmount;
      final amt = i.amount;
      if (paid >= amt - 1e-6) return 'Pagada';
      if (paid > 0) return 'Parcialmente pagada';
      return 'Pendiente';
    }
    return s;
  }

  bool _isFullyPaid(Installment i) =>
      _installmentDisplayStatus(i).toLowerCase() == 'pagada';

  // ---------- Pago ----------

  Future<void> _registerPayment() async {
    if (isProcessingPayment) return;

    try {
      final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        _showErr('Ingrese un monto válido (> 0)');
        return;
      }

      final remaining = (installment.amount - installment.paidAmount).clamp(
        0,
        double.infinity,
      );
      if (amount > remaining + 1e-6) {
        _showErr(
          'El monto excede el saldo pendiente de \$${remaining.toStringAsFixed(2)}',
        );
        return;
      }

      if (_selectedMethod == null) {
        _showErr('Seleccione el método/descr. del pago');
        return;
      }

      String? description;
      if (_selectedMethod == 'other') {
        if (_otherDescCtrl.text.trim().isEmpty) {
          _showErr('Describa el pago si selecciona “Otro”');
          return;
        }
        description = _otherDescCtrl.text.trim();
      }

      setState(() => isProcessingPayment = true);

      final result = await ApiService.payInstallment(
        installmentId: installment.id,
        amount: amount,
        paymentType: _selectedMethod, // 'cash' | 'transfer' | 'other'
        description: description,
      );

      setState(() => installment = result.installment);

      if (result.paymentId != null) {
        await shareReceiptByPaymentId(context, result.paymentId!);
      }

      final paidAll = amount >= remaining - 1e-6;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paidAll ? 'Cuota pagada por el total' : 'Pago parcial registrado',
          ),
          backgroundColor: secondaryColor,
        ),
      );

      widget.onPaymentSuccess?.call();
      Navigator.pop(context, true);
    } catch (e) {
      _showErr(e.toString());
    } finally {
      if (mounted) setState(() => isProcessingPayment = false);
    }
  }

  void _prefillRemaining() {
    final remaining = (installment.amount - installment.paidAmount).clamp(
      0,
      double.infinity,
    );
    _amountCtrl.text = remaining.toStringAsFixed(2);
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: dangerColor));
  }

  // ---------- UI widgets ----------

  Widget _statusChip() {
    final status = _installmentDisplayStatus(installment);
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: installmentStatusColor(status),
    );
  }

  Widget _progress() {
    final status = _installmentDisplayStatus(installment);
    final progress =
        (installment.paidAmount / installment.amount).clamp(0, 1).toDouble();
    final remaining = (installment.amount - installment.paidAmount).clamp(
      0,
      double.infinity,
    );

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          color:
              status.toLowerCase() == 'pagada' ? secondaryColor : primaryColor,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pagado: \$${installment.paidAmount.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            Text(
              'Falta: \$${remaining.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  // Franja/aviso por cuotas vencidas
  Widget _overdueBanner() {
    // Mostrar si (a) el préstamo tiene vencidas o (b) ESTA cuota es vencida
    final show = (_loanHasOverdues || _isOverdue(installment));
    if (_loanLoading || !show) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC27A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Este crédito tiene cuotas vencidas. Los pagos que registres se aplicarán primero a saldar esas cuotas.',
              style: TextStyle(fontSize: 13, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  // Mini-detalle de préstamo clickeable, sutil
  Widget _loanInlineLink() {
    if (_loanId == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _goToLoan,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'Préstamo #$_loanId',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  decoration: TextDecoration.underline,
                  decorationThickness: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final dueDate = DateFormat('dd/MM/yyyy').format(installment.dueDate);
    final fullyPaid = _isFullyPaid(installment);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cuota #${installment.number}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AVISO (si corresponde)
            _overdueBanner(),

            // Resumen de la cuota
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título + estado
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cuota #${installment.number}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _statusChip(),
                      ],
                    ),

                    // Enlace sutil al préstamo
                    _loanInlineLink(),
                    const SizedBox(height: 12),

                    _row(
                      'Monto total:',
                      '\$${installment.amount.toStringAsFixed(2)}',
                    ),
                    _row(
                      'Pagado:',
                      '\$${installment.paidAmount.toStringAsFixed(2)}',
                    ),
                    _row('Vencimiento:', dueDate),
                    const SizedBox(height: 16),
                    _progress(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Registrar pago (solo si NO está pagada)
            if (!fullyPaid)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Dropdown método/descr.
                      DropdownButtonFormField<String>(
                        value: _selectedMethod,
                        items:
                            _methods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m['value'],
                                    child: Text(m['label']!),
                                  ),
                                )
                                .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Descripción del pago',
                          hintText: 'Seleccioná el método',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _selectedMethod = v),
                      ),
                      const SizedBox(height: 12),

                      // Campo libre si “Otro”
                      if (_selectedMethod == 'other')
                        TextField(
                          controller: _otherDescCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Detalle (obligatorio si elegís “Otro”)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      if (_selectedMethod == 'other')
                        const SizedBox(height: 12),

                      // Monto
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Monto a pagar',
                          prefixText: '\$ ',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.payments),
                            tooltip: 'Usar saldo pendiente',
                            onPressed: _prefillRemaining,
                          ),
                        ),
                        enabled: !isProcessingPayment,
                      ),
                      const SizedBox(height: 16),

                      // Botón único
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed:
                              isProcessingPayment ? null : _registerPayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                          ),
                          icon:
                              isProcessingPayment
                                  ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  ),
                          label: Text(
                            isProcessingPayment
                                ? 'Procesando...'
                                : 'Registrar pago',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(a, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            b,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
