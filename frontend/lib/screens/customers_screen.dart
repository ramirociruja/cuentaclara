import 'package:flutter/material.dart';
import 'package:frontend/screens/customer_detail_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/screens/add_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  String searchQuery = '';
  bool showOnlyDebtors = false;
  bool isLoading = true;
  bool isRefreshing = false;

  List<Customer> customers = [];
  Map<int, bool> hasOverdueInstallments = {};

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    try {
      setState(() => isLoading = true);
      final fetchedCustomers = await ApiService.fetchCustomersByEmployee();

      // Verificar cuotas vencidas en paralelo
      final debtStatus = await Future.wait(
        fetchedCustomers.map((c) => _checkCustomerDebt(c)),
      );

      setState(() {
        customers = fetchedCustomers;
        for (int i = 0; i < fetchedCustomers.length; i++) {
          hasOverdueInstallments[fetchedCustomers[i].id] = debtStatus[i];
        }
        isLoading = false;
        isRefreshing = false;
      });
    } catch (e) {
      print("Error fetching customers: $e");
      setState(() {
        isLoading = false;
        isRefreshing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al cargar los clientes'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  Future<bool> _checkCustomerDebt(Customer customer) async {
    try {
      final overdueCount = await ApiService.fetchOverdueInstallmentCount(
        customer.id,
      );
      return overdueCount > 0;
    } catch (e) {
      print("Error checking debt for customer ${customer.id}: $e");
      return false;
    }
  }

  Future<void> _refreshData() async {
    setState(() => isRefreshing = true);
    await _fetchCustomers();
  }

  List<Customer> get _filteredCustomers {
    return customers.where((c) {
      final matchesQuery = c.name.toLowerCase().contains(
        searchQuery.toLowerCase(),
      );
      final isDebtor = hasOverdueInstallments[c.id] ?? false;
      return matchesQuery && (!showOnlyDebtors || isDebtor);
    }).toList();
  }

  Widget _buildCustomerCard(Customer customer) {
    final hasDebt = hasOverdueInstallments[customer.id] ?? false;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => CustomerDetailScreen(customerId: customer.id),
            ),
          );
          if (result == true) _fetchCustomers();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar del cliente
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, color: primaryColor, size: 30),
              ),
              const SizedBox(width: 16),
              // Información del cliente
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'DNI: ${customer.dni}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    Text(
                      'Tel: ${customer.phone}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            hasDebt
                                ? dangerColor.withOpacity(0.1)
                                : secondaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasDebt ? Icons.warning : Icons.check_circle,
                            size: 16,
                            color: hasDebt ? dangerColor : secondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasDebt ? 'Tiene cuotas vencidas' : 'Al día',
                            style: TextStyle(
                              color: hasDebt ? dangerColor : secondaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Flecha de navegación
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clientes',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddCustomerScreen()),
          );
          if (result == true) {
            await _fetchCustomers();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Cliente creado exitosamente'),
                backgroundColor: secondaryColor,
              ),
            );
          }
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: primaryColor,
        child: Column(
          children: [
            // Barra de búsqueda y filtros
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Buscar cliente...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    onChanged: (value) => setState(() => searchQuery = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mostrar solo clientes con deuda',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Switch(
                        value: showOnlyDebtors,
                        activeColor: primaryColor,
                        onChanged:
                            (value) => setState(() => showOnlyDebtors = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Lista de clientes
            if (isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              )
            else if (_filteredCustomers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        showOnlyDebtors
                            ? 'No hay clientes con deuda'
                            : 'No se encontraron clientes',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _filteredCustomers.length,
                  itemBuilder:
                      (context, index) =>
                          _buildCustomerCard(_filteredCustomers[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
