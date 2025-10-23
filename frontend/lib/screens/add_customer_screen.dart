import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/customer.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  // Paleta
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
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

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Ingrese el correo electrónico';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(value)) return 'Ingrese un correo válido';
    return null;
  }

  Future<void> _addCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => isLoading = true);

    try {
      final employeeId = await ApiService.getEmployeeId();
      if (employeeId == null) {
        if (!mounted) return;
        _showError('No se encontró el ID del empleado');
        return;
      }

      final companyId = await ApiService.getCompanyId();
      if (companyId == null) {
        if (!mounted) return;
        _showError('No se encontró el ID de la empresa');
        return;
      }

      final customer = Customer(
        id: 0,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        dni: dniController.text.trim(),
        address: addressController.text.trim(),
        phone: phoneController.text.trim(),
        email: emailController.text.trim(),
        province: selectedProvince ?? '',
        companyId: companyId,
        employeeId: employeeId,
      );

      final result = await ApiService.createCustomer(customer);
      if (!mounted) return;

      if (result.isOk) {
        _showSuccess('Cliente creado exitosamente');
        Navigator.pop(context, true);
      } else {
        _showError(result.error ?? 'No se pudo crear el cliente');
      }
    } catch (e) {
      _showError('Error al crear cliente: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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

  // Campo genérico con ícono y estética
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    IconData? icon,
    TextInputType? keyboardType,
    int? maxLength,
    bool readOnly = false,
    VoidCallback? onTap,

    // 👇 NUEVO: capitalización por defecto
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        // 👇 aplica capitalización
        textCapitalization: textCapitalization,
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

  // Tarjeta seccional
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

  // === NUEVO: selector de provincias en bottom sheet (no pantalla completa)
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
        final sheetHeight = media.size.height * 0.65; // 65% de alto
        return SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                // Handle + título
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
                // Lista de opciones
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
                // Botón cancelar
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
          'Agregar Cliente',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),

      // Contenido scroll
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + 72 + bottomPadding),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Encabezado simpático
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
                          Icons.person_add_alt_1,
                          color: Color(0xFF2C64D8),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Completá los datos del cliente.\nLos campos marcados son obligatorios.',
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
                      controller: firstNameController,
                      label: 'Nombre',
                      icon: Icons.person_outline,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Ingrese el nombre'
                                  : null,
                    ),
                    _buildFormField(
                      controller: lastNameController,
                      label: 'Apellido',
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
                    // Campo Provincia -> abre bottom sheet con lista
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

      // Botón fijo abajo (siempre legible)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: isLoading ? null : _addCustomer,
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
                isLoading ? 'Guardando…' : 'GUARDAR CLIENTE',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: primaryColor.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.95),
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
