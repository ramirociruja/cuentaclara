import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/models/loan.dart';
import 'package:frontend/services/api_service.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:frontend/utils/utils.dart'; // shareReceiptByPaymentId

class RegisterPaymentScreen extends StatefulWidget {
  const RegisterPaymentScreen({super.key});

  @override
  _RegisterPaymentScreenState createState() => _RegisterPaymentScreenState();
}

class _RegisterPaymentScreenState extends State<RegisterPaymentScreen> {
  // Paleta de colores
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  // Estado
  List<Customer> customers = [];
  Customer? selectedCustomer;
  Loan? selectedLoan;
  List<Loan> customerLoans = [];

  double paymentAmount = 0.0;
  bool isLoadingLoans = false;

  final TextEditingController _paymentController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  // Tipo de pago + descripción (solo para "other")
  String? _paymentType; // 'cash' | 'transfer' | 'other'
  final TextEditingController _descCtrl = TextEditingController();

  // Helpers UI
  final NumberFormat _money = NumberFormat.currency(
    locale: 'es_AR',
    symbol: r'$',
  );

  bool get _isFormValid =>
      selectedLoan != null &&
      paymentAmount > 0 &&
      paymentAmount <= (selectedLoan?.totalDue ?? 0) &&
      _paymentType != null; // 👈 ya NO exige descripción cuando es "other"

  void _setAmount(double v) {
    _paymentController.text = v.toStringAsFixed(2);
    setState(() => paymentAmount = v);
  }

  int _remainingInstallments() {
    if (selectedLoan == null) return 0;
    return selectedLoan!.installments.where((i) => !i.isPaid).length;
  }

  int _affectedInstallments() {
    if (selectedLoan == null) return 0;
    final loan = selectedLoan!;
    final double installment = loan.installmentAmount;

    if (installment <= 0 || paymentAmount <= 0) return 0;

    final int remaining = _remainingInstallments();
    final int affected =
        (paymentAmount / installment).ceil(); // 👈 redondea hacia arriba

    return affected > remaining
        ? remaining
        : affected; // cap al máximo de cuotas pendientes
  }

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  @override
  void dispose() {
    _paymentController.dispose();
    _descCtrl.dispose();
    _amountFocus.dispose();
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
      // Reset de tipo/desc al cambiar de cliente
      _paymentType = null;
      _descCtrl.clear();
      _paymentController.clear();
      paymentAmount = 0.0;
    });

    final loans = await ApiService.fetchLoansByCustomer(customer.id);

    // Filtrar préstamos: solo los no pagados y con saldo > 0
    final activeLoans =
        loans
            .where(
              (loan) =>
                  loan.status.toLowerCase() != "paid" && loan.totalDue > 0,
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
          content: const Text(
            "Por favor, selecciona un cliente, préstamo y monto válido",
          ),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_paymentType == null || _paymentType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Elegí un tipo de pago"),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (paymentAmount > selectedLoan!.totalDue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "El monto supera el saldo pendiente del préstamo.",
          ),
          backgroundColor: dangerColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _showConfirmationDialog();
  }

  String _paymentTypeLabel(String? v) {
    switch (v) {
      case 'cash':
        return 'Efectivo';
      case 'transfer':
        return 'Transferencia';
      case 'other':
        return 'Otro';
      default:
        return '-';
    }
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
                  const Text(
                    "¿Está seguro de registrar este pago?",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  _buildDetailRow(
                    "Cliente:",
                    "${selectedCustomer!.fullName} (${selectedCustomer!.dni})",
                  ),
                  _buildDetailRow("Préstamo:", "#${selectedLoan!.id}"),
                  _buildDetailRow(
                    "Monto a pagar:",
                    _money.format(paymentAmount),
                  ),
                  _buildDetailRow(
                    "Saldo anterior:",
                    _money.format(selectedLoan!.totalDue),
                  ),
                  _buildDetailRow(
                    "Nuevo saldo:",
                    _money.format(
                      (selectedLoan!.totalDue - paymentAmount).clamp(
                        0,
                        selectedLoan!.totalDue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    "Tipo de pago:",
                    _paymentTypeLabel(_paymentType),
                  ),
                  if (_paymentType == 'other' &&
                      _descCtrl.text.trim().isNotEmpty)
                    _buildDetailRow("Descripción:", _descCtrl.text.trim()),
                  const SizedBox(height: 10),
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
                child: const Text(
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final loanId = selectedLoan!.id;

      final int? paymentId = await ApiService.registerPayment(
        loanId,
        paymentAmount,
        paymentType: _paymentType,
        description:
            _paymentType == 'other' && _descCtrl.text.trim().isNotEmpty
                ? _descCtrl.text.trim()
                : null,
      );

      // Si el backend devolvió payment_id → generamos/compartimos el recibo
      if (paymentId != null) {
        await shareReceiptByPaymentId(context, paymentId);
      } else {
        // Backend legacy que no envía payment_id
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Pago registrado, pero no recibimos el ID del recibo.',
            ),
          ),
        );
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: const Text("✅ Pago registrado exitosamente"),
          backgroundColor: secondaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Recargar los datos actualizados
      await _loadLoansForCustomer(selectedCustomer!);

      // Mantener la selección pero limpiar el monto y campos
      setState(() {
        _paymentController.clear();
        paymentAmount = 0.0;
        _paymentType = null;
        _descCtrl.clear();

        // Intentar mantener el mismo préstamo seleccionado (si sigue)
        selectedLoan =
            customerLoans.isNotEmpty
                ? customerLoans.firstWhere(
                  (loan) => loan.id == loanId,
                  orElse: () => customerLoans.first,
                )
                : null;
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
            .where(
              (c) => c.fullName.toLowerCase().contains(filter.toLowerCase()),
            )
            .map((c) => '${c.fullName} - ${c.dni}')
            .toList();
      },
      selectedItem:
          selectedCustomer == null
              ? null
              : '${selectedCustomer!.fullName} - ${selectedCustomer!.dni}',
      onChanged: (value) async {
        final customer = customers.firstWhere(
          (c) => '${c.fullName} - ${c.dni}' == value,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
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
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }

    if (customerLoans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
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

    // ⚠️ Importante: esta lista NO es scrollable; el scroll lo maneja el padre
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children:
          customerLoans.map((loan) {
            final bool isSelected = loan == selectedLoan;
            final int cuotasPagadas =
                loan.installments.where((i) => i.isPaid).length;
            final int cuotasTotales = loan.installmentsCount;
            final DateTime startDate =
                DateTime.tryParse(loan.startDate) ?? DateTime.now();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
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
                      const Icon(Icons.check_circle, color: primaryColor),
                  ],
                ),
                subtitle: Text(
                  "Saldo: ${_money.format(loan.totalDue)}",
                  style: TextStyle(
                    color: isSelected ? primaryColor : Colors.grey[700],
                  ),
                ),
                initiallyExpanded: isSelected,
                onExpansionChanged: (expanded) {
                  setState(() {
                    selectedLoan = expanded ? loan : null;
                    if (expanded) {
                      _paymentType ??=
                          'cash'; // default al seleccionar préstamo
                    } else {
                      _paymentType = null;
                      _descCtrl.clear();
                      _paymentController.clear();
                      paymentAmount = 0.0;
                    }
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
                          _money.format(loan.amount),
                        ),
                        _buildLoanDetail(
                          "💵 Total pagado:",
                          _money.format(
                            loan.installments.fold(
                              0.0,
                              (sum, i) => sum + i.paidAmount,
                            ),
                          ),
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
                          _money.format(loan.installmentAmount),
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
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // Entrada de monto mejorada
  Widget _buildPaymentInput() {
    return TextFormField(
      controller: _paymentController,
      focusNode: _amountFocus,
      enabled: selectedLoan != null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+([.,]\d{0,2})?$')),
      ],
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        helperText:
            selectedLoan == null
                ? null
                : "Saldo: ${_money.format(selectedLoan!.totalDue)}   •   Cuota: ${_money.format(selectedLoan!.installmentAmount)}",
      ),
      onChanged: (value) {
        final normalized = value.replaceAll(',', '.');
        setState(() {
          paymentAmount = double.tryParse(normalized) ?? 0.0;
        });
      },
    );
  }

  // Chips de monto rápido
  Widget _buildQuickAmountChips() {
    if (selectedLoan == null) return const SizedBox.shrink();
    final loan = selectedLoan!;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text('Cuota ${_money.format(loan.installmentAmount)}'),
          selected: false,
          onSelected: (_) => _setAmount(loan.installmentAmount),
        ),
        ChoiceChip(
          label: const Text('50% del saldo'),
          selected: false,
          onSelected:
              (_) => _setAmount((loan.totalDue / 2).clamp(0, loan.totalDue)),
        ),
        ChoiceChip(
          label: Text('Saldo ${_money.format(loan.totalDue)}'),
          selected: false,
          onSelected: (_) => _setAmount(loan.totalDue),
        ),
      ],
    );
  }

  // Dropdown de tipo de pago (habilitado al seleccionar préstamo)
  Widget _buildPaymentTypeDropdown() {
    final bool enabled = selectedLoan != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DropdownButtonFormField<String>(
      value: enabled ? _paymentType : null,
      items: const [
        DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
        DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
        DropdownMenuItem(value: 'other', child: Text('Otro')),
      ],
      onChanged:
          enabled
              ? (value) {
                setState(() {
                  _paymentType = value;
                  if (value != 'other') _descCtrl.clear();
                });
              }
              : null,
      decoration: InputDecoration(
        labelText: "Tipo de Pago",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!.withOpacity(0.3)),
        ),
        filled: true,
        fillColor:
            enabled
                ? (isDark ? Colors.grey[900]! : Colors.grey[50]!)
                : (isDark ? Colors.grey[850]! : Colors.grey[200]!),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  // Campo descripción (solo si tipo = "other")
  Widget _buildPaymentDescriptionField() {
    final bool enabled = selectedLoan != null && _paymentType == 'other';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: _descCtrl,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: "Descripción",
        hintText: "Detalle o referencia (opcional)",
        helperText:
            enabled ? "Opcional" : null, // 👈 aclara que no es obligatoria
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!.withOpacity(0.3)),
        ),
        filled: true,
        fillColor:
            enabled
                ? (isDark ? Colors.grey[900]! : Colors.grey[50]!)
                : (isDark ? Colors.grey[850]! : Colors.grey[200]!),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final double newBalance =
        selectedLoan == null
            ? 0
            : (selectedLoan!.totalDue - paymentAmount).clamp(
              0,
              selectedLoan!.totalDue,
            );

    final int affected = _affectedInstallments();
    final int remaining = _remainingInstallments();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Registrar Pago"),
        elevation: 2,
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              100,
            ), // espacio para la bottom bar
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
                        const SizedBox(height: 8),
                        _buildCustomerDropdown(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Sección Préstamos (lista NO scrollable; scrollea toda la pantalla)
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
                          "Préstamos Activos",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildLoanList(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

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
                        const SizedBox(height: 12),
                        _buildPaymentInput(),
                        const SizedBox(height: 8),
                        _buildQuickAmountChips(),
                        const SizedBox(height: 12),
                        _buildPaymentTypeDropdown(),
                        const SizedBox(height: 12),
                        _buildPaymentDescriptionField(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // Bottom bar con resumen, cuotas impactadas y acción fija
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              // Resumen compacto
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedLoan == null
                          ? 'Seleccioná un préstamo'
                          : 'Nuevo saldo: ${_money.format(newBalance)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                            selectedLoan == null
                                ? Colors.grey[600]
                                : (paymentAmount >
                                        (selectedLoan?.totalDue ?? 0) ||
                                    paymentAmount <= 0)
                                ? Colors.orange[700]
                                : Colors.green[700],
                      ),
                    ),
                    if (selectedLoan != null)
                      Text(
                        'Cuotas impactadas: $affected de $remaining',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    if (_paymentType != null)
                      Text(
                        'Método: ${_paymentType == 'cash'
                            ? 'Efectivo'
                            : _paymentType == 'transfer'
                            ? 'Transferencia'
                            : 'Otro'}'
                        '${_paymentType == 'other' && _descCtrl.text.trim().isNotEmpty ? ' • ${_descCtrl.text.trim()}' : ''}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isFormValid ? _registerPayment : null,
                icon: const Icon(Icons.payment),
                label: const Text('Registrar pago'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
