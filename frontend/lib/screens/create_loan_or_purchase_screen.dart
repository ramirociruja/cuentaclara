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
  State<CreateLoanOrPurchaseScreen> createState() =>
      _CreateLoanOrPurchaseScreenState();
}

class _CreateLoanOrPurchaseScreenState
    extends State<CreateLoanOrPurchaseScreen> {
  // Paleta de colores consistente
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);
  static const Color disabledGrey = Color(0xFFBDBDBD); // P0#2

  // P0#2: forzamos siempre préstamo, toggle deshabilitado
  final bool isLoan = true;

  final TextEditingController amountController = TextEditingController();
  final TextEditingController installmentsController = TextEditingController();
  final TextEditingController frequencyController = TextEditingController(
    text: "Semanal",
  );
  final TextEditingController startDateController = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );

  // Nuevos campos
  final _descCtrl = TextEditingController(); // descripción libre
  int _selectedCollectionDay = DateTime.now().weekday; // 1..7 (L=1 .. D=7)

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
    _updatePreview(); // P0#3: para que muestre preview inicial coherente
  }

  @override
  void dispose() {
    amountController.dispose();
    installmentsController.dispose();
    frequencyController.dispose();
    startDateController.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String formatCurrency(double amount) => currencyFormatter.format(amount);

  double? parseCurrency(String value) {
    try {
      final cleaned = value
          .replaceAll(RegExp(r'[^\d,]'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      return double.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }

  // ======= P0#3: helpers para calcular fecha final desde la FECHA DE INICIO =======
  DateTime? _parseStartDateText() {
    try {
      return DateFormat('yyyy-MM-dd').parse(startDateController.text);
    } catch (_) {
      return null;
    }
  }

  DateTime _addMonthsSafe(DateTime d, int months) {
    final y = d.year + ((d.month - 1 + months) ~/ 12);
    final m = ((d.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day; // último día del mes destino
    final day = d.day.clamp(1, lastDay);
    return DateTime(
      y,
      m,
      day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      d.microsecond,
    );
  }

  DateTime computeEndDate({
    required DateTime start,
    required int installments,
    required String frequencyLabel, // "Semanal" | "Mensual"
  }) {
    if (installments <= 0) return start;
    if (frequencyLabel == "Semanal") {
      // última cuota: n semanas después del inicio
      return start.add(Duration(days: installments * 7));
    } else {
      // mensual de calendario real (no 30 fijo)
      return _addMonthsSafe(start, installments);
    }
  }
  // ==============================================================================

  void _updatePreview() {
    final amount = parseCurrency(amountController.text);
    final installments = int.tryParse(installmentsController.text);
    final start = _parseStartDateText();
    final freqLabel = frequencyController.text; // "Semanal" | "Mensual"

    if (amount != null &&
        installments != null &&
        installments > 0 &&
        start != null) {
      final end = computeEndDate(
        start: start,
        installments: installments,
        frequencyLabel: freqLabel,
      );
      setState(() {
        previewAmount = amount;
        previewEndDate = end;
      });
    } else {
      setState(() {
        previewAmount = null;
        previewEndDate = null;
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

      if (_selectedCollectionDay < 1 || _selectedCollectionDay > 7) {
        _showErrorSnackbar('Seleccioná el día de cobro');
        return;
      }

      final start = _parseStartDateText();
      if (start == null) {
        _showErrorSnackbar('Fecha de inicio inválida');
        return;
      }

      final installmentAmount = amount / installments;

      // P0#2: siempre creamos PRÉSTAMO (no venta)
      final loan = Loan(
        id: 0,
        customerId: selectedClientId!,
        amount: amount,
        totalDue: amount,
        installmentsCount: installments,
        installmentAmount: installmentAmount,
        frequency: frequencyController.text == "Semanal" ? "weekly" : "monthly",
        startDate: DateFormat('yyyy-MM-dd').format(start), // usa fecha elegida
        status: 'active',
        companyId: await ApiService.getCompanyId() ?? 0,

        // nuevos campos
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        collectionDay: _selectedCollectionDay,
      );

      final loanResponse = await ApiService.createLoan(loan);

      if (loanResponse != null) {
        _showSuccessSnackbar('Préstamo creado con éxito');
        if (!mounted) return;
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
      _showErrorSnackbar('Error al crear préstamo');
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
    final initial = _parseStartDateText() ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
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
      _updatePreview(); // P0#3: recalcular usando la nueva fecha de inicio
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final customerList = await ApiService.fetchCustomersByEmployee();
      setState(() => customers = customerList);
    } catch (_) {
      _showErrorSnackbar('Error al cargar clientes');
    }
  }

  // =========================
  //     UI BUILDERS
  // =========================

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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
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
          icon: const Icon(Icons.calculate),
          onPressed: _updatePreview,
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: (_) => _updatePreview(), // P0#3: recalcular en vivo
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
      items: const [
        DropdownMenuItem(value: "Semanal", child: Text("Semanal")),
        DropdownMenuItem(value: "Mensual", child: Text("Mensual")),
      ],
      onChanged: (value) {
        setState(() {
          frequencyController.text = value!;
        });
        _updatePreview(); // P0#3
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
          icon: const Icon(Icons.calendar_today),
          onPressed: _selectStartDate,
        ),
      ),
      readOnly: true,
    );
  }

  Widget _buildDescriptionInput() {
    return TextFormField(
      controller: _descCtrl,
      decoration: InputDecoration(
        labelText: 'Descripción (opcional)',
        hintText: 'Ejm: “Préstamo por compra de electrodoméstico”',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      maxLines: 3,
      textInputAction: TextInputAction.newline,
    );
  }

  Widget _buildCollectionDaySelector() {
    // Orden ISO: L=1, M=2, M=3, J=4, V=5, S=6, D=7
    const days = [
      {'label': 'L', 'value': 1},
      {'label': 'M', 'value': 2},
      {'label': 'M', 'value': 3}, // miércoles (pediste "M")
      {'label': 'J', 'value': 4},
      {'label': 'V', 'value': 5},
      {'label': 'S', 'value': 6},
      {'label': 'D', 'value': 7},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Día de cobro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              days.map((d) {
                final int val = d['value'] as int;
                final bool selected = _selectedCollectionDay == val;
                return ChoiceChip(
                  label: Text(
                    d['label'] as String,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedCollectionDay = val);
                  },
                  selectedColor: primaryColor,
                  backgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
        ),
        const SizedBox(height: 4),
        const Text(
          'Seleccioná el día en que se cobra habitualmente (obligatorio).',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    if (previewAmount == null || previewEndDate == null) {
      return const SizedBox();
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
            const Text(
              'Resumen:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 8),
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
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton(
      onPressed: _createLoan,
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text(
        'Crear Préstamo', // P0#2: texto fijo
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
        title: const Text(
          'Crear Nuevo Préstamo', // P0#2: título fijo
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
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
                  // ================= P0#2: Toggle “gris” y bloqueado =================
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance,
                        color: primaryColor,
                      ),
                      title: const Text(
                        'Tipo: Préstamo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Row(
                        children: const [
                          Icon(Icons.lock_clock, size: 14, color: disabledGrey),
                          SizedBox(width: 6),
                          Text(
                            'Compra (próximamente)',
                            style: TextStyle(fontSize: 12, color: disabledGrey),
                          ),
                        ],
                      ),
                      trailing: Switch(
                        value: true,
                        onChanged: null, // deshabilitado
                        activeColor: primaryColor,
                        inactiveThumbColor: disabledGrey,
                        inactiveTrackColor: disabledGrey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),

                  // ==================================================================
                  const SizedBox(height: 16),
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
                            'Datos del Préstamo', // P0#2 fijo
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildCustomerDropdown(),
                          const SizedBox(height: 16),
                          _buildAmountInput(),
                          const SizedBox(height: 16),
                          _buildInstallmentsInput(),
                          const SizedBox(height: 16),
                          _buildFrequencyDropdown(),
                          const SizedBox(height: 16),
                          _buildDatePicker(),
                          const SizedBox(height: 16),
                          _buildCollectionDaySelector(),
                          const SizedBox(height: 16),
                          _buildDescriptionInput(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPreviewSection(),
                  const SizedBox(height: 24),
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
