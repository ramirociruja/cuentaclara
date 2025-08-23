import 'package:flutter/material.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/services/api_service.dart';
import 'package:dropdown_search/dropdown_search.dart';

class RegisterPaymentScreen extends StatefulWidget {
  const RegisterPaymentScreen({Key? key}) : super(key: key);

  @override
  _RegisterPaymentScreenState createState() => _RegisterPaymentScreenState();
}

class _RegisterPaymentScreenState extends State<RegisterPaymentScreen> {
  // Paleta de colores
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  List<Customer> customers = [];
  Customer? selectedCustomer;
  Loan? selectedLoan;
  List<Loan> customerLoans = [];
  double paymentAmount = 0.0;
  bool isLoadingLoans = false;
  final TextEditingController _paymentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers() async {
    final fetchedCustomers = await ApiService.fetchCustomersByEmployee();
    setState(() {
      customers = fetchedCustomers;
    });
  }

  Future<void> _loadLoansForCustomer(Customer customer) async {
    setState(() {
      isLoadingLoans = true;
      selectedLoan = null;
      customerLoans = [];
    });

    final loans = await ApiService.fetchLoansByCustomer(customer.id);

    // Filtrar préstamos: solo los no pagados y con saldo > 0
    final activeLoans =
        loans
            .where(
              (loan) =>
                  loan.status?.toLowerCase() != "paid" && loan.totalDue > 0,
            )
            .toList();

    // Ordenar por ID ascendente
    activeLoans.sort((a, b) => a.id.compareTo(b.id));

    setState(() {
      customerLoans = activeLoans;
      isLoadingLoans = false;
    });
  }

  Future<void> _registerPayment() async {
    if (selectedCustomer == null ||
        selectedLoan == null ||
        paymentAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Por favor, selecciona un cliente, préstamo y monto válido",
          ),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (paymentAmount > selectedLoan!.totalDue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("El monto supera el saldo pendiente del préstamo."),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _showConfirmationDialog();
  }

  Future<void> _showConfirmationDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text(
              "Confirmar Pago",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "¿Está seguro de registrar este pago?",
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 20),
                  _buildDetailRow(
                    "Cliente:",
                    "${selectedCustomer!.name} (${selectedCustomer!.dni})",
                  ),
                  _buildDetailRow("Préstamo:", "#${selectedLoan!.id}"),
                  _buildDetailRow(
                    "Monto a pagar:",
                    "\$${paymentAmount.toStringAsFixed(2)}",
                  ),
                  _buildDetailRow(
                    "Saldo anterior:",
                    "\$${selectedLoan!.totalDue.toStringAsFixed(2)}",
                  ),
                  _buildDetailRow(
                    "Nuevo saldo:",
                    "\$${(selectedLoan!.totalDue - paymentAmount).toStringAsFixed(2)}",
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Esta acción no se puede deshacer.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancelar", style: TextStyle(color: dangerColor)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  "Confirmar Pago",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
    );

    if (confirmed == true) {
      await _processPayment();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final loanId = selectedLoan!.id;

      await ApiService.registerPayment(loanId, paymentAmount);

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text("✅ Pago registrado exitosamente"),
          backgroundColor: secondaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Recargar los datos actualizados
      await _loadLoansForCustomer(selectedCustomer!);

      // Mantener la selección pero limpiar el monto
      setState(() {
        _paymentController.clear();
        paymentAmount = 0.0;
        // Buscar y mantener seleccionado el mismo préstamo (si sigue existiendo)
        selectedLoan = customerLoans.firstWhere(
          (loan) => loan.id == loanId,
          orElse:
              () =>
                  customerLoans.isNotEmpty ? customerLoans.first : null as Loan,
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error al registrar el pago: ${e.toString()}"),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildCustomerDropdown() {
    return DropdownSearch<String>(
      asyncItems: (String filter) async {
        return customers
            .where((c) => c.name.toLowerCase().contains(filter.toLowerCase()))
            .map((c) => '${c.name} - ${c.dni}')
            .toList();
      },
      selectedItem:
          selectedCustomer == null
              ? null
              : '${selectedCustomer!.name} - ${selectedCustomer!.dni}',
      onChanged: (value) async {
        final customer = customers.firstWhere(
          (c) => '${c.name} - ${c.dni}' == value,
          orElse: () => customers.first,
        );
        setState(() {
          selectedCustomer = customer;
        });
        await _loadLoansForCustomer(customer);
      },
      popupProps: PopupProps.menu(
        showSearchBox: true,
        searchFieldProps: TextFieldProps(
          decoration: InputDecoration(
            labelText: "Buscar Cliente",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        menuProps: MenuProps(
          borderRadius: BorderRadius.circular(10),
          elevation: 4,
        ),
      ),
      dropdownDecoratorProps: DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: "Seleccionar Cliente",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildLoanList() {
    if (selectedCustomer == null) {
      return Center(
        child: Text(
          "Selecciona un cliente",
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    if (isLoadingLoans) {
      return Center(child: CircularProgressIndicator(color: primaryColor));
    }

    if (customerLoans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off, size: 48, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              "Este cliente no tiene préstamos activos",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            Text(
              "(Todos están pagados o sin saldo pendiente)",
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      physics: ClampingScrollPhysics(),
      children:
          customerLoans.map((loan) {
            final bool isSelected = loan == selectedLoan;
            final int cuotasPagadas =
                loan.installments.where((i) => i.isPaid).length;
            final int cuotasTotales = loan.installmentsCount;
            final DateTime startDate =
                DateTime.tryParse(loan.startDate) ?? DateTime.now();

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? primaryColor : Colors.grey[300]!,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              color: isSelected ? primaryColor.withOpacity(0.05) : null,
              child: ExpansionTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Préstamo #${loan.id}",
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? primaryColor : Colors.grey[800],
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, color: primaryColor),
                  ],
                ),
                subtitle: Text(
                  "Saldo: \$${loan.totalDue.toStringAsFixed(2)}",
                  style: TextStyle(
                    color: isSelected ? primaryColor : Colors.grey[700],
                  ),
                ),
                initiallyExpanded: isSelected,
                onExpansionChanged: (expanded) {
                  setState(() {
                    selectedLoan = expanded ? loan : null;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLoanDetail(
                          "💰 Monto total:",
                          "\$${loan.amount.toStringAsFixed(2)}",
                        ),
                        _buildLoanDetail(
                          "💵 Total pagado:",
                          "\$${loan.installments.fold(0.0, (sum, i) => sum + i.paidAmount).toStringAsFixed(2)}",
                        ),
                        _buildLoanDetail(
                          "📆 Fecha de inicio:",
                          "${startDate.day}/${startDate.month}/${startDate.year}",
                        ),
                        _buildLoanDetail(
                          "📊 Cuotas pagadas:",
                          "$cuotasPagadas de $cuotasTotales",
                        ),
                        _buildLoanDetail(
                          "💸 Monto por cuota:",
                          "\$${loan.installmentAmount.toStringAsFixed(2)}",
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _buildLoanDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPaymentInput() {
    return TextFormField(
      controller: _paymentController,
      enabled: selectedLoan != null,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: "Monto a pagar",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        filled: true,
        fillColor:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!
                : Colors.grey[50]!,
        prefixIcon: Icon(Icons.attach_money, color: Colors.grey[600]),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      onChanged: (value) {
        setState(() {
          paymentAmount = double.tryParse(value) ?? 0.0;
        });
      },
    );
  }

  Widget _buildRegisterButton() {
    return ElevatedButton(
      onPressed: _registerPayment,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payment, color: Colors.white),
          SizedBox(width: 8),
          Text(
            "Registrar Pago",
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Registrar Pago",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        elevation: 2,
        backgroundColor: primaryColor,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sección Cliente
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Cliente",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        _buildCustomerDropdown(),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Sección Préstamos
                Expanded(
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Préstamos Activos",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Expanded(child: _buildLoanList()),
                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Sección Pago
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Registrar Pago",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 16),
                        _buildPaymentInput(),
                        SizedBox(height: 16),
                        _buildRegisterButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
