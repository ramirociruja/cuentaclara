import 'package:flutter/material.dart';
import 'package:frontend/models/customer.dart';
import 'package:frontend/services/api_service.dart';

class EditCustomerScreen extends StatefulWidget {
  final Customer customer;

  const EditCustomerScreen({super.key, required this.customer});

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  // Paleta (igual a AddCustomerScreen)
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  final _formKey = GlobalKey<FormState>();

  // Controllers (se precargan con datos del cliente)
  final TextEditingController nameController = TextEditingController();
  final TextEditingController dniController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController provinceController = TextEditingController();

  String? selectedProvince;
  bool isLoading = false;

  final List<String> provinces = const [
    'Buenos Aires',
    'Catamarca',
    'Chaco',
    'Chubut',
    'CABA',
    'Córdoba',
    'Corrientes',
    'Entre Ríos',
    'Formosa',
    'Jujuy',
    'La Pampa',
    'La Rioja',
    'Mendoza',
    'Misiones',
    'Neuquén',
    'Río Negro',
    'Salta',
    'San Juan',
    'San Luis',
    'Santa Cruz',
    'Santa Fe',
    'Santiago del Estero',
    'Tierra del Fuego',
    'Tucumán',
  ];

  @override
  void initState() {
    super.initState();
    // Precarga de datos en los campos
    nameController.text = widget.customer.name;
    dniController.text = widget.customer.dni;
    addressController.text = widget.customer.address;
    phoneController.text = widget.customer.phone;
    emailController.text = widget.customer.email;
    selectedProvince = widget.customer.province;
    provinceController.text = selectedProvince ?? '';
  }

  @override
  void dispose() {
    nameController.dispose();
    dniController.dispose();
    addressController.dispose();
    phoneController.dispose();
    emailController.dispose();
    provinceController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Ingrese el correo electrónico';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(value)) return 'Ingrese un correo válido';
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: dangerColor),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: secondaryColor),
    );
  }

  Future<void> _saveCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => isLoading = true);
    try {
      final updatedCustomer = Customer(
        id: widget.customer.id,
        name: nameController.text.trim(),
        dni: dniController.text.trim(),
        address: addressController.text.trim(),
        phone: phoneController.text.trim(),
        email: emailController.text.trim(),
        province: selectedProvince ?? '',
        companyId: widget.customer.companyId,
        employeeId: widget.customer.employeeId,
        createdAt: widget.customer.createdAt,
      );

      await ApiService.updateCustomer(updatedCustomer);
      if (!mounted) return;
      _showSuccess('Cliente actualizado');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // -------- UI helpers (idénticos a AddCustomerScreen) --------
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    IconData? icon,
    TextInputType? keyboardType,
    int? maxLength,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          suffixIcon: readOnly ? const Icon(Icons.chevron_right) : null,
          filled: true,
          fillColor: const Color(0xFFF6F8FF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFFE0E4F2)),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: primaryColor, width: 1.4),
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          counterText: '',
        ),
        validator: validator,
        keyboardType: keyboardType,
        maxLength: maxLength,
      ),
    );
  }

  Widget _card({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE9ECF5)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: primaryColor, size: 18),
                  ),
                if (icon != null) const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  // === Selector de provincias en bottom sheet (igual que en AddCustomerScreen)
  Future<void> _pickProvince() async {
    final sorted = [...provinces]..sort();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final sheetHeight = media.size.height * 0.65;
        return SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E4F2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Seleccionar provincia',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = sorted[i];
                      final isSelected = p == selectedProvince;
                      return ListTile(
                        title: Text(p),
                        trailing:
                            isSelected
                                ? const Icon(Icons.check, color: primaryColor)
                                : null,
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE0E4F2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null) {
      setState(() {
        selectedProvince = chosen;
        provinceController.text = chosen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FE),
      appBar: AppBar(
        title: const Text(
          'Editar Cliente',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + 72 + bottomPadding),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Encabezado
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDDE6FF)),
                  ),
                  child: Row(
                    children: const [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xFFD9E6FF),
                        child: Icon(
                          Icons.manage_accounts_outlined,
                          color: Color(0xFF2C64D8),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Editá los datos del cliente y guardá los cambios.',
                          style: TextStyle(
                            color: Color(0xFF2C64D8),
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                _card(
                  title: 'Datos personales',
                  icon: Icons.badge_outlined,
                  children: [
                    _buildFormField(
                      controller: nameController,
                      label: 'Nombre completo',
                      icon: Icons.person_outline,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Ingrese el nombre'
                                  : null,
                    ),
                    _buildFormField(
                      controller: dniController,
                      label: 'DNI',
                      icon: Icons.credit_card,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingrese el DNI';
                        }
                        if (!RegExp(r'^\d+$').hasMatch(v.trim())) {
                          return 'Solo números';
                        }
                        return null;
                      },
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                    ),
                  ],
                ),

                _card(
                  title: 'Contacto',
                  icon: Icons.call_outlined,
                  children: [
                    _buildFormField(
                      controller: phoneController,
                      label: 'Teléfono',
                      icon: Icons.phone_outlined,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingrese el teléfono';
                        }
                        if (!RegExp(r'^\d+$').hasMatch(v.trim())) {
                          return 'Solo números';
                        }
                        return null;
                      },
                      keyboardType: TextInputType.phone,
                    ),
                    _buildFormField(
                      controller: emailController,
                      label: 'Correo electrónico',
                      icon: Icons.alternate_email,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),

                _card(
                  title: 'Ubicación',
                  icon: Icons.location_on_outlined,
                  children: [
                    _buildFormField(
                      controller: addressController,
                      label: 'Dirección',
                      icon: Icons.home_outlined,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Ingrese la dirección'
                                  : null,
                    ),
                    _buildFormField(
                      controller: provinceController,
                      label: 'Provincia',
                      icon: Icons.map_outlined,
                      readOnly: true,
                      onTap: _pickProvince,
                      validator:
                          (_) =>
                              (selectedProvince == null ||
                                      selectedProvince!.trim().isEmpty)
                                  ? 'Seleccione una provincia'
                                  : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),

      // Botón fijo abajo
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: isLoading ? null : _saveCustomer,
              icon:
                  isLoading
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.save_outlined),
              label: Text(
                isLoading ? 'Guardando…' : 'GUARDAR CAMBIOS',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: primaryColor.withOpacity(0.55),
                disabledForegroundColor: Colors.white.withOpacity(0.95),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
