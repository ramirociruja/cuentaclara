import 'package:flutter/material.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/screens/edit_customer_screen.dart';
import 'package:frontend/screens/loan_detail_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:intl/intl.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color warningColor = Color(0xFFFFA000);

  Customer? customer;
  List<Loan> loans = [];
  bool isLoading = true;
  bool showCompletedLoans = false;
  final DateFormat dateFormat = DateFormat('dd/MM/yyyy');
  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => isLoading = true);
      final fetchedCustomer = await ApiService.fetchCustomerById(
        widget.customerId,
      );
      final fetchedLoans = await ApiService.fetchLoansByCustomer(
        widget.customerId,
      );
      setState(() {
        customer = fetchedCustomer;
        loans = fetchedLoans;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading customer details: $e");
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al cargar los datos del cliente'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  void _navigateToEditCustomer() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCustomerScreen(customer: customer!),
      ),
    );
    if (result == true) {
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cliente editado exitosamente'),
          backgroundColor: secondaryColor,
        ),
      );
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(Loan loan) {
    final isActive = loan.status == 'active';
    final progress = (loan.amount - loan.totalDue) / loan.amount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LoanDetailScreen(loanId: loan.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Préstamo #${loan.id}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Chip(
                    label: Text(
                      isActive ? 'Activo' : 'Completado',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: isActive ? primaryColor : secondaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Monto:', currencyFormatter.format(loan.amount)),
              _buildDetailRow(
                'Saldo:',
                currencyFormatter.format(loan.totalDue),
              ),
              _buildDetailRow(
                'Fecha:',
                dateFormat.format(DateTime.parse(loan.startDate)),
              ),
              if (isActive) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade200,
                  color: progress == 1 ? secondaryColor : primaryColor,
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}% Pagado',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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

  Widget _buildLoansSection(String title, List<Loan> loans, bool isActive) {
    if (loans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Badge(
              label: Text(loans.length.toString()),
              backgroundColor: isActive ? primaryColor : secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...loans.map((loan) => _buildLoanCard(loan)).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeLoans = loans.where((loan) => loan.status == 'active').toList();
    final completedLoans =
        loans.where((loan) => loan.status != 'active').toList();

    if (isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              const Text(
                'Cargando información...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cliente no encontrado'),
          backgroundColor: primaryColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: dangerColor),
              const SizedBox(height: 16),
              const Text(
                'No se encontró el cliente solicitado',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('Volver atrás'),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            customer!.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar cliente',
              onPressed: _navigateToEditCustomer,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: _loadData,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: primaryColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sección de información del cliente
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryColor.withOpacity(0.1),
                              radius: 30,
                              child: Icon(
                                Icons.person,
                                size: 30,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                customer!.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.credit_card, 'DNI', customer!.dni),
                        _buildInfoRow(Icons.phone, 'Teléfono', customer!.phone),
                        _buildInfoRow(
                          Icons.location_on,
                          'Provincia',
                          customer!.province,
                        ),
                        _buildInfoRow(
                          Icons.home,
                          'Dirección',
                          customer!.address,
                        ),
                      ],
                    ),
                  ),
                ),

                // Sección de préstamos activos
                _buildLoansSection('Préstamos Activos', activeLoans, true),

                // Sección de préstamos completados (expandible)
                if (completedLoans.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap:
                        () => setState(
                          () => showCompletedLoans = !showCompletedLoans,
                        ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Préstamos Completados',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Badge(
                              label: Text(completedLoans.length.toString()),
                              backgroundColor: secondaryColor,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              showCompletedLoans
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showCompletedLoans)
                    ...completedLoans
                        .map((loan) => _buildLoanCard(loan))
                        .toList(),
                ] else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.credit_card_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No hay préstamos registrados',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // TODO: Implementar creación de nuevo préstamo
          },
          backgroundColor: primaryColor,
          child: const Icon(Icons.add, color: Colors.white),
          tooltip: 'Agregar préstamo',
        ),
      ),
    );
  }
}
