import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/screens/loan_detail_screen.dart';
import 'package:intl/intl.dart';
import 'package:frontend/models/loan.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:frontend/services/api_service.dart';

class CreateLoanOrPurchaseScreen extends StatefulWidget {
  const CreateLoanOrPurchaseScreen({super.key});

  @override
  _CreateLoanOrPurchaseScreenState createState() =>
      _CreateLoanOrPurchaseScreenState();
}

class _CreateLoanOrPurchaseScreenState
    extends State<CreateLoanOrPurchaseScreen> {
  // Paleta de colores consistente
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  bool isLoan = true;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController installmentsController = TextEditingController();
  final TextEditingController frequencyController = TextEditingController(
    text: "Semanal",
  );
  final TextEditingController startDateController = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );

  int? selectedClientId;
  double? previewAmount;
  DateTime? previewEndDate;
  List<Customer> customers = [];

  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    amountController.dispose();
    installmentsController.dispose();
    frequencyController.dispose();
    startDateController.dispose();
    super.dispose();
  }

  String formatCurrency(double amount) {
    return currencyFormatter.format(amount);
  }

  double? parseCurrency(String value) {
    try {
      String cleaned = value
          .replaceAll(RegExp(r'[^\d,]'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      return double.tryParse(cleaned);
    } catch (e) {
      return null;
    }
  }

  void _updatePreview() {
    final amount = parseCurrency(amountController.text);
    final installments = int.tryParse(installmentsController.text);
    final isWeekly = frequencyController.text == "Semanal";

    if (amount != null && installments != null && installments > 0) {
      setState(() {
        previewAmount = amount;
        previewEndDate = DateTime.now().add(
          Duration(days: isWeekly ? installments * 7 : installments * 30),
        );
      });
    }
  }

  Future<void> _createLoan() async {
    try {
      if (selectedClientId == null) {
        _showErrorSnackbar('Por favor, selecciona un cliente');
        return;
      }

      final amount = parseCurrency(amountController.text);
      if (amount == null || amount <= 0) {
        _showErrorSnackbar('Monto inválido');
        return;
      }

      final installments = int.tryParse(installmentsController.text);
      if (installments == null || installments <= 0) {
        _showErrorSnackbar('Cantidad de cuotas inválida');
        return;
      }

      final installmentAmount = amount / installments;

      var loan = Loan(
        customerId: selectedClientId!,
        amount: amount,
        totalDue: amount,
        installmentsCount: installments,
        installmentAmount: installmentAmount,
        frequency: frequencyController.text == "Semanal" ? "weekly" : "monthly",
        startDate: startDateController.text,
        status: 'Pendiente',
        id: 0,
        companyId: await ApiService.getCompanyId() ?? 0,
      );

      var loanResponse = await ApiService.createLoan(loan);

      if (loanResponse != null) {
        _showSuccessSnackbar(
          '${isLoan ? 'Préstamo' : 'Venta'} creado con éxito',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => LoanDetailScreen(
                  loanId: loanResponse.id,
                  fromCreateScreen: true,
                ),
          ),
        );
      }
    } catch (e) {
      print("Error al crear préstamo: $e");
      _showErrorSnackbar('Error al crear ${isLoan ? 'préstamo' : 'venta'}');
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: dangerColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: secondaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.grey[800]!,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        startDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final customerList = await ApiService.fetchCustomersByEmployee();
      setState(() {
        customers = customerList;
      });
    } catch (e) {
      _showErrorSnackbar('Error al cargar clientes');
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
          selectedClientId == null
              ? null
              : customers.firstWhere((c) => c.id == selectedClientId).name,
      onChanged: (value) {
        setState(() {
          selectedClientId =
              value == null
                  ? null
                  : customers
                      .firstWhere((c) => '${c.name} - ${c.dni}' == value)
                      .id;
        });
      },
      popupProps: PopupProps.menu(
        showSearchBox: true,
        searchFieldProps: TextFieldProps(
          decoration: InputDecoration(
            labelText: "Buscar cliente",
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
          labelText: "Selecciona al Cliente",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    return TextFormField(
      controller: amountController,
      decoration: InputDecoration(
        labelText: 'Monto',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixText: '\$ ',
        suffixIcon: IconButton(
          icon: Icon(Icons.calculate),
          onPressed: _updatePreview,
        ),
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
    );
  }

  Widget _buildInstallmentsInput() {
    return TextFormField(
      controller: installmentsController,
      decoration: InputDecoration(
        labelText: 'Cantidad de Cuotas',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      keyboardType: TextInputType.number,
      onChanged: (_) => _updatePreview(),
    );
  }

  Widget _buildFrequencyDropdown() {
    return DropdownButtonFormField<String>(
      value: frequencyController.text,
      decoration: InputDecoration(
        labelText: 'Frecuencia',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: [
        DropdownMenuItem(value: "Semanal", child: Text("Semanal")),
        DropdownMenuItem(value: "Mensual", child: Text("Mensual")),
      ],
      onChanged: (value) {
        setState(() {
          frequencyController.text = value!;
          _updatePreview();
        });
      },
    );
  }

  Widget _buildDatePicker() {
    return TextFormField(
      controller: startDateController,
      decoration: InputDecoration(
        labelText: 'Fecha de Inicio',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: Icon(Icons.calendar_today),
          onPressed: _selectStartDate,
        ),
      ),
      readOnly: true,
    );
  }

  Widget _buildPreviewSection() {
    if (previewAmount == null || previewEndDate == null) {
      return SizedBox();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            SizedBox(height: 8),
            _buildPreviewRow(
              'Monto por cuota:',
              formatCurrency(
                previewAmount! / int.parse(installmentsController.text),
              ),
            ),
            _buildPreviewRow(
              'Fecha de pago final:',
              DateFormat('dd/MM/yyyy').format(previewEndDate!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
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

  Widget _buildCreateButton() {
    return ElevatedButton(
      onPressed: _createLoan,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        minimumSize: Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        isLoan ? 'Crear Préstamo' : 'Crear Venta',
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isLoan ? 'Crear Nuevo Préstamo' : 'Registrar Nueva Venta',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        isLoan ? 'Tipo: Préstamo' : 'Tipo: Venta',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      value: isLoan,
                      onChanged: (bool value) {
                        setState(() => isLoan = value);
                      },
                      activeColor: primaryColor,
                    ),
                  ),
                  SizedBox(height: 16),
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
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Datos del ${isLoan ? 'Préstamo' : 'Venta'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 16),
                          _buildCustomerDropdown(),
                          SizedBox(height: 16),
                          _buildAmountInput(),
                          SizedBox(height: 16),
                          _buildInstallmentsInput(),
                          SizedBox(height: 16),
                          _buildFrequencyDropdown(),
                          SizedBox(height: 16),
                          _buildDatePicker(),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildPreviewSection(),
                  SizedBox(height: 24),
                  _buildCreateButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
