import 'package:flutter/material.dart';
import 'package:frontend/models/installment.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';

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
  bool isLoading = false;
  bool isProcessingPayment = false;
  final TextEditingController _paymentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    installment = widget.installment;
    _paymentController.text = (installment.amount - installment.paidAmount)
        .toStringAsFixed(2);
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _processPayment(double amount) async {
    if (isLoading || isProcessingPayment) return;

    setState(() => isProcessingPayment = true);

    try {
      // Validaciones en el frontend
      if (amount <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }

      final remainingAmount = installment.amount - installment.paidAmount;
      if (amount > remainingAmount) {
        throw Exception(
          'El monto excede el saldo pendiente de \$${remainingAmount.toStringAsFixed(2)}',
        );
      }

      // Llamar al nuevo servicio de pago de cuotas
      final updatedInstallment = await ApiService.payInstallment(
        installmentId: installment.id,
        amount: amount,
      );

      // Actualizar el estado con la cuota modificada
      setState(() {
        installment = updatedInstallment;
      });

      // Mostrar feedback al usuario
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            amount == remainingAmount
                ? 'Cuota marcada como pagada completamente'
                : 'Pago parcial registrado exitosamente',
          ),
          backgroundColor: secondaryColor,
        ),
      );

      // Notificar a la pantalla anterior si es necesario
      widget.onPaymentSuccess?.call();

      // Cerrar la pantalla y devolver true para indicar éxito
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: dangerColor),
      );
    } finally {
      setState(() => isProcessingPayment = false);
    }
  }

  Future<void> _markAsFullyPaid() async {
    final amountToPay = installment.amount - installment.paidAmount;
    await _processPayment(amountToPay);
  }

  Future<void> _registerPartialPayment() async {
    final amount = double.tryParse(_paymentController.text);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingrese un monto válido'),
          backgroundColor: dangerColor,
        ),
      );
      return;
    }
    await _processPayment(amount);
  }

  Widget _buildPaymentStatusChip() {
    if (installment.isPaid) {
      return Chip(
        label: Text('PAGADA COMPLETA', style: TextStyle(color: Colors.white)),
        backgroundColor: secondaryColor,
      );
    } else if (installment.paidAmount > 0) {
      return Chip(
        label: Text('PAGO PARCIAL', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
      );
    } else {
      return Chip(
        label: Text(
          installment.isOverdue ? 'VENCIDA' : 'PENDIENTE',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: installment.isOverdue ? dangerColor : Colors.orange,
      );
    }
  }

  Widget _buildPaymentProgress() {
    final progress = installment.paidAmount / installment.amount;
    final remaining = installment.amount - installment.paidAmount;

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          color: progress == 1 ? secondaryColor : primaryColor,
        ),
        SizedBox(height: 8),
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

  Widget _buildPaymentActions() {
    if (installment.isPaid) {
      return Column(
        children: [
          Icon(Icons.check_circle, size: 60, color: secondaryColor),
          SizedBox(height: 16),
          Text(
            'Esta cuota ya fue pagada completamente',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          'Opciones de pago:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: isProcessingPayment ? null : _markAsFullyPaid,
          style: ElevatedButton.styleFrom(
            backgroundColor: secondaryColor,
            minimumSize: Size(double.infinity, 50),
          ),
          icon:
              isProcessingPayment
                  ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                  : Icon(Icons.check_circle, color: Colors.white),
          label: Text(
            isProcessingPayment
                ? 'Procesando...'
                : 'Marcar como Pagada Completa',
            style: TextStyle(color: Colors.white),
          ),
        ),
        SizedBox(height: 12),
        Text(
          'O pagar un monto específico:',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        SizedBox(height: 12),
        TextField(
          controller: _paymentController,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Monto a pagar',
            prefixText: '\$ ',
            border: OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(Icons.attach_money),
              onPressed: () {
                _paymentController.text = (installment.amount -
                        installment.paidAmount)
                    .toStringAsFixed(2);
              },
            ),
            filled: isProcessingPayment,
          ),
          enabled: !isProcessingPayment,
        ),
        SizedBox(height: 12),
        ElevatedButton(
          onPressed: isProcessingPayment ? null : _registerPartialPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            minimumSize: Size(double.infinity, 50),
          ),
          child:
              isProcessingPayment
                  ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                  : Text(
                    'Registrar Pago Parcial',
                    style: TextStyle(color: Colors.white),
                  ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = DateFormat('dd/MM/yyyy').format(installment.dueDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cuota #${installment.number}',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cuota #${installment.number}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _buildPaymentStatusChip(),
                      ],
                    ),
                    SizedBox(height: 16),
                    _buildDetailRow(
                      'Monto total:',
                      '\$${installment.amount.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow(
                      'Pagado:',
                      '\$${installment.paidAmount.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow('Vencimiento:', dueDate),
                    SizedBox(height: 16),
                    _buildPaymentProgress(),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: _buildPaymentActions(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
