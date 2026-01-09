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
  static const Color disabledGrey = Color(0xFFBDBDBD);

  // P0#2: forzamos siempre préstamo, toggle deshabilitado
  final bool isLoan = true;

  final TextEditingController amountController = TextEditingController();
  final TextEditingController installmentsController = TextEditingController();
  final TextEditingController frequencyController = TextEditingController(
    text: "Semanal",
  );
  final TextEditingController startDateController = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );

  // Nuevos campos
  final _descCtrl = TextEditingController();
  int _selectedCollectionDay = DateTime.now().weekday; // 1..7

  // NUEVO: intervalo en días (reemplaza/convive con frequency)
  // Si _installmentIntervalDays != null => usamos esta lógica (duración fija en días)
  int? _installmentIntervalDays = 7; // default: semanal
  bool _useCustomInterval = false;
  final TextEditingController _customIntervalCtrl = TextEditingController();

  int? selectedClientId;
  double? previewAmount;
  DateTime? previewEndDate;
  List<Customer> customers = [];

  // ---- manejo de cobradores ----
  List<Map<String, dynamic>> _collectors = [];
  int? _selectedCollectorId;
  bool _isAdmin = false;
  bool _loadingCollectors = false;
  // -----------------------------

  final currencyFormatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadCollectors();
    _syncIntervalUIFromFrequency(); // mantiene coherencia inicial
    _updatePreview();
  }

  @override
  void dispose() {
    amountController.dispose();
    installmentsController.dispose();
    frequencyController.dispose();
    startDateController.dispose();
    _descCtrl.dispose();
    _customIntervalCtrl.dispose();
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

  DateTime? _parseStartDateText() {
    try {
      return DateFormat('dd/MM/yyyy').parse(startDateController.text);
    } catch (_) {
      return null;
    }
  }

  DateTime _addMonthsSafe(DateTime d, int months) {
    final y = d.year + ((d.month - 1 + months) ~/ 12);
    final m = ((d.month - 1 + months) % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
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
    required String frequencyLabel, // Semanal|Mensual (fallback)
    required int? intervalDays, // si viene, manda
  }) {
    if (installments <= 0) return start;

    // 1) Si el usuario eligió intervalo en días, es la fuente de verdad
    if (intervalDays != null && intervalDays >= 1) {
      return start.add(Duration(days: installments * intervalDays));
    }

    // 2) Fallback histórico
    if (frequencyLabel == "Semanal") {
      return start.add(Duration(days: installments * 7));
    } else {
      return _addMonthsSafe(start, installments);
    }
  }

  void _updatePreview() {
    final amount = parseCurrency(amountController.text);
    final installments = int.tryParse(installmentsController.text);
    final start = _parseStartDateText();
    final freqLabel = frequencyController.text;

    if (amount != null &&
        installments != null &&
        installments > 0 &&
        start != null) {
      final end = computeEndDate(
        start: start,
        installments: installments,
        frequencyLabel: freqLabel,
        intervalDays: _installmentIntervalDays,
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

  // Mantener frecuencia + interval coherentes al inicio
  void _syncIntervalUIFromFrequency() {
    final f = frequencyController.text;
    // defaults: si el usuario usa la frecuencia vieja
    if (f == "Semanal") {
      _installmentIntervalDays = 7;
      _useCustomInterval = false;
      _customIntervalCtrl.text = "";
    } else if (f == "Mensual") {
      // Si querés mensual calendario real, podés poner intervalDays=null.
      // Pero como vos pedís "cantidad de días", dejo 30 como preset (mensual fijo).
      _installmentIntervalDays = 30;
      _useCustomInterval = false;
      _customIntervalCtrl.text = "";
    }
  }

  // ==========================
  //  Carga de datos remotos
  // ==========================

  Future<void> _loadCustomers() async {
    try {
      final customerList = await ApiService.fetchCompanyCustomers();
      if (!mounted) return;
      setState(() => customers = customerList);
    } catch (_) {
      _showErrorSnackbar('Error al cargar clientes');
    }
  }

  Future<void> _loadCollectors() async {
    try {
      setState(() {
        _loadingCollectors = true;
      });

      final empId = await ApiService.getEmployeeId();
      final rawList = await ApiService.fetchEmployeesInCompany();
      if (!mounted) return;

      final normalized =
          rawList
              .whereType<Map<String, dynamic>>()
              .map((e) {
                final id = (e['id'] ?? e['employee_id']) as int?;
                final name =
                    (e['name'] ?? e['full_name'] ?? e['email'] ?? 'Empleado')
                        as String;
                final role = (e['role'] ?? '').toString();
                return {'id': id, 'name': name, 'role': role};
              })
              .where((e) => e['id'] != null)
              .toList();

      bool isAdmin = false;
      if (empId != null) {
        final me = normalized.cast<Map<String, dynamic>?>().firstWhere(
          (e) =>
              e != null &&
              (e['id'] as int?) != null &&
              (e['id'] as int) == empId,
          orElse: () => null,
        );
        final myRole = (me?['role'] ?? '') as String;
        isAdmin = myRole.toLowerCase() == 'admin';
      }

      final collectors =
          normalized.where((e) {
            final r = (e['role'] ?? '') as String;
            final rl = r.toLowerCase();
            return rl == 'collector' || rl == 'admin';
          }).toList();

      setState(() {
        _isAdmin = isAdmin;
        _collectors = collectors;
        if (isAdmin && empId != null) {
          _selectedCollectorId = empId;
        } else {
          _selectedCollectorId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      _showErrorSnackbar('Error al cargar cobradores');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCollectors = false;
        });
      }
    }
  }

  // ==========================
  //   Crear préstamo
  // ==========================

  int? _getIntervalDaysValidated() {
    // Preset elegido
    if (!_useCustomInterval) {
      return _installmentIntervalDays;
    }

    // Custom
    final raw = _customIntervalCtrl.text.trim();
    if (raw.isEmpty) return null;
    final v = int.tryParse(raw);
    if (v == null) return null;
    if (v < 1 || v > 3650) return null;
    return v;
  }

  Future<void> _createLoan() async {
    try {
      if (selectedClientId == null) {
        _showErrorSnackbar('Por favor, selecciona un cliente');
        return;
      }

      if (_isAdmin && _selectedCollectorId == null) {
        _showErrorSnackbar('Por favor, selecciona un cobrador');
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

      final intervalDays = _getIntervalDaysValidated();
      if (intervalDays == null) {
        _showErrorSnackbar('Ingresá el intervalo en días (1 a 3650)');
        return;
      }

      final installmentAmount = amount / installments;

      // Si el usuario usa intervalDays, no enviamos frequency.
      // Esto te permite convivir con datos viejos y migrar de a poco.
      final loan = Loan(
        id: 0,
        customerId: selectedClientId!,
        amount: amount,
        totalDue: amount,
        installmentsCount: installments,
        installmentAmount: installmentAmount,
        frequency: null, // 👈 dejamos de depender de weekly/monthly
        startDate: DateFormat('yyyy-MM-dd').format(start),
        status: 'active',
        companyId:
            await ApiService.getCompanyId(), // ahora nullable en tu Loan.dart

        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        collectionDay: _selectedCollectionDay,

        employeeId: _isAdmin ? _selectedCollectorId : null,
        installmentIntervalDays: intervalDays,
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
    } catch (_) {
      _showErrorSnackbar('Error al crear préstamo');
    }
  }

  // =========================
  //   Snackbars helpers
  // =========================

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

  // =========================
  //   Date picker
  // =========================

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
        startDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
      _updatePreview();
    }
  }

  // =========================
  //     UI BUILDERS
  // =========================

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
          selectedClientId == null
              ? null
              : customers.firstWhere((c) => c.id == selectedClientId).fullName,
      onChanged: (value) {
        setState(() {
          selectedClientId =
              value == null
                  ? null
                  : customers
                      .firstWhere((c) => '${c.fullName} - ${c.dni}' == value)
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

  Widget _buildCollectorDropdown() {
    if (!_isAdmin) return const SizedBox.shrink();

    if (_loadingCollectors) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_collectors.isEmpty) {
      return const Text(
        'No se encontraron cobradores en la empresa.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }

    return DropdownButtonFormField<int>(
      value: _selectedCollectorId,
      decoration: InputDecoration(
        labelText: 'Cobrador asignado',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items:
          _collectors.map((c) {
            final id = (c['id'] as int);
            final name = (c['name'] as String?) ?? 'Empleado $id';
            final role = (c['role'] as String?)?.toLowerCase();
            String label = name;
            if (role == 'admin') {
              label = '$name (Admin)';
            } else if (role == 'collector') {
              label = '$name (Cobrador)';
            }
            return DropdownMenuItem<int>(value: id, child: Text(label));
          }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedCollectorId = value;
        });
      },
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
      onChanged: (_) => _updatePreview(),
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

  // Mantengo el dropdown por compatibilidad visual, pero el valor final se gobierna por intervalDays

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
    const days = [
      {'label': 'L', 'value': 1},
      {'label': 'M', 'value': 2},
      {'label': 'M', 'value': 3}, // miércoles
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

  // ✅ NUEVO: selector de intervalo en días (presets + personalizado)
  Widget _buildInstallmentIntervalSelector() {
    final presets = <int>[7, 15, 30, 45, 60];

    Widget _chip(
      String label, {
      required bool selected,
      required VoidCallback onTap,
    }) {
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: primaryColor,
        backgroundColor: Colors.grey.shade200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Intervalo entre cuotas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...presets.map((d) {
              final selected =
                  !_useCustomInterval && _installmentIntervalDays == d;
              final label =
                  d == 7
                      ? '7 (Semanal)'
                      : d == 15
                      ? '15 (Quincenal)'
                      : d == 30
                      ? '30 (Mensual)'
                      : '$d';
              return _chip(
                label,
                selected: selected,
                onTap: () {
                  setState(() {
                    _useCustomInterval = false;
                    _installmentIntervalDays = d;
                    _customIntervalCtrl.text = "";
                  });
                  _updatePreview();
                },
              );
            }),
            _chip(
              'Personalizado',
              selected: _useCustomInterval,
              onTap: () {
                setState(() {
                  _useCustomInterval = true;
                  // no forzamos intervalDays acá, se toma del input
                });
                _updatePreview();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_useCustomInterval)
          TextFormField(
            controller: _customIntervalCtrl,
            decoration: InputDecoration(
              labelText: 'Días (1 a 3650)',
              hintText: 'Ej: 10, 21, 28...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (_) {
              // reflejarlo también en _installmentIntervalDays para preview
              final v = int.tryParse(_customIntervalCtrl.text.trim());
              setState(() {
                _installmentIntervalDays = v;
              });
              _updatePreview();
            },
          ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    if (previewAmount == null || previewEndDate == null) {
      return const SizedBox();
    }

    final installments = int.tryParse(installmentsController.text) ?? 0;
    if (installments <= 0) return const SizedBox();

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
              formatCurrency(previewAmount! / installments),
            ),
            _buildPreviewRow(
              'Fecha de pago final:',
              DateFormat('dd/MM/yyyy').format(previewEndDate!),
            ),
            if (_installmentIntervalDays != null)
              _buildPreviewRow(
                'Intervalo:',
                '${_installmentIntervalDays!} días',
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
        'Crear Préstamo',
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
          'Crear Nuevo Préstamo',
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
                        onChanged: null,
                        activeColor: primaryColor,
                        inactiveThumbColor: disabledGrey,
                        inactiveTrackColor: disabledGrey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
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
                            'Datos del Préstamo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildCustomerDropdown(),
                          const SizedBox(height: 16),

                          _buildCollectorDropdown(),
                          if (_isAdmin) const SizedBox(height: 16),

                          _buildAmountInput(),
                          const SizedBox(height: 16),

                          _buildInstallmentsInput(),
                          const SizedBox(height: 16),

                          _buildInstallmentIntervalSelector(),
                          const SizedBox(height: 16),

                          _buildCollectionDaySelector(),
                          const SizedBox(height: 16),

                          _buildDatePicker(),
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
