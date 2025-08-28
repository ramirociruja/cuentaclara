import 'package:flutter/material.dart';
//import 'package:frontend/models/purchase.dart';
import 'package:frontend/models/installment.dart';

class PurchaseDetailScreen extends StatefulWidget {
  final int purchaseId;

  const PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  late Future<List<Installment>> installments;

  @override
  void initState() {
    super.initState();
    //installments = ApiService.fetchInstallmentsByPurchase(widget.purchaseId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la Compra')),
      body: FutureBuilder<List<Installment>>(
        future: installments,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          }

          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          if (snapshot.data == null || snapshot.data!.isEmpty) {
            return const Text('No hay cuotas para esta compra.');
          }

          return ListView(
            children:
                snapshot.data!.map((installment) {
                  return ListTile(
                    title: Text('Cuota ${installment.number}'),
                    subtitle: Text(
                      'Monto: ${installment.amount} - Pagado: ${installment.paidAmount} - Estado: ${installment.isPaid ? "Pagada" : "Pendiente"}',
                    ),
                  );
                }).toList(),
          );
        },
      ),
    );
  }
}
