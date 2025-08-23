import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/customer.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color secondaryColor = Color(0xFF00CC66);
  static const Color dangerColor = Color(0xFFFF4444);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController dniController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  TextEditingController provinceController = TextEditingController();
  String? selectedProvince;
  bool isLoading = false;

  final List<String> provinces = [
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
        name: nameController.text,
        dni: dniController.text,
        address: addressController.text,
        phone: phoneController.text,
        email: emailController.text,
        province: selectedProvince ?? '',
        companyId: companyId,
        employeeId: employeeId,
      );

      final result = await ApiService.createCustomer(customer);
      if (!mounted) return;

      if (result != null) {
        Navigator.pop(context, true);
        _showSuccess('Cliente creado exitosamente');
      } else {
        _showError('No se pudo crear el cliente');
      }
    } catch (e) {
      _showError('Error al crear cliente: ${e.toString()}');
      print('Error completo: $e');
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

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agregar Cliente',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFormField(
                controller: nameController,
                label: 'Nombre completo',
                validator:
                    (value) =>
                        value?.isEmpty ?? true ? 'Ingrese el nombre' : null,
              ),
              _buildFormField(
                controller: dniController,
                label: 'DNI',
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Ingrese el DNI';
                  if (!RegExp(r'^\d+$').hasMatch(value!)) return 'Solo números';
                  return null;
                },
                keyboardType: TextInputType.number,
                maxLength: 8,
              ),
              _buildFormField(
                controller: addressController,
                label: 'Dirección',
                validator:
                    (value) =>
                        value?.isEmpty ?? true ? 'Ingrese la dirección' : null,
              ),
              _buildFormField(
                controller: phoneController,
                label: 'Teléfono',
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Ingrese el teléfono';
                  if (!RegExp(r'^\d+$').hasMatch(value!)) return 'Solo números';
                  return null;
                },
                keyboardType: TextInputType.phone,
              ),
              _buildFormField(
                controller: emailController,
                label: 'Correo electrónico',
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Autocomplete<String>(
                  optionsBuilder: (textEditingValue) {
                    return provinces.where(
                      (province) => province.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      ),
                    );
                  },
                  onSelected: (selection) {
                    setState(() {
                      selectedProvince = selection;
                      provinceController.text = selection;
                    });
                  },
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onEditingComplete,
                  ) {
                    provinceController = controller;
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Provincia',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      validator:
                          (value) =>
                              value?.isEmpty ?? true
                                  ? 'Seleccione una provincia'
                                  : null,
                      onEditingComplete: onEditingComplete,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width - 40,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                title: Text(option),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: isLoading ? null : _addCustomer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child:
                    isLoading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          'GUARDAR CLIENTE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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
