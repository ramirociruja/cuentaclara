import 'package:flutter/material.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:frontend/utils/utils.dart';

// 👇 Estados centralizados
import 'package:frontend/shared/status.dart';

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
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _otherDescCtrl.dispose();
    super.dispose();
  }

  // --------- Estados / UI coherente ---------

  String _installmentDisplayStatus(Installment i) {
    // Si no está paga y está vencida → "Vencida"
    if ((i.isPaid == false) && (i.isOverdue == true)) {
      return 'Vencida';
    }
    // Normalizar lo que venga del backend (cuotas)
    final s = normalizeInstallmentStatus(i.status);
    // Si no viene claro, inferimos por montos
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

  // --------- Pago ---------

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

      // Llama a la API enviando payment_type y description (opcional)
      final result = await ApiService.payInstallment(
        installmentId: installment.id,
        amount: amount,
        paymentType: _selectedMethod, // 'cash' | 'transfer' | 'other'
        description: description, // sólo si "Otro"
      );

      // actualizar la cuota en la UI
      setState(() => installment = result.installment);

      // si vino payment_id, compartir el recibo
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
      setState(() => isProcessingPayment = false);
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

  // ---------------- UI ----------------

  Widget _statusChip() {
    final status = _installmentDisplayStatus(installment);
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white),
      ),
      // ⬇️ color unificado para CUOTAS
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
                    const SizedBox(height: 16),
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
