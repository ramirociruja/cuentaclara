import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/api_service.dart';

class EditCustomerScreen extends StatefulWidget {
  final Customer customer;

  const EditCustomerScreen({super.key, required this.customer});

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  late String name;
  late String dni;
  late String address;
  late String phone;
  late String province;
  late String email;

  @override
  void initState() {
    super.initState();
    name = widget.customer.name;
    dni = widget.customer.dni;
    address = widget.customer.address;
    phone = widget.customer.phone;
    province = widget.customer.province;
    email = widget.customer.email;
  }

  void _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final updatedCustomer = Customer(
        id: widget.customer.id,
        name: name,
        dni: dni,
        address: address,
        phone: phone,
        province: province,
        email: email,
        companyId: widget.customer.companyId,
        employeeId: widget.customer.employeeId,
        createdAt: widget.customer.createdAt,
      );

      try {
        await ApiService.updateCustomer(updatedCustomer);
        if (context.mounted) {
          Navigator.pop(context, true); // devolvés el cliente actualizado
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Cliente')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: 'Nombre'),
                onSaved: (value) => name = value ?? '',
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Campo requerido'
                            : null,
              ),
              TextFormField(
                initialValue: dni,
                decoration: const InputDecoration(labelText: 'DNI'),
                onSaved: (value) => dni = value ?? '',
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Campo requerido'
                            : null,
              ),
              TextFormField(
                initialValue: address,
                decoration: const InputDecoration(labelText: 'Dirección'),
                onSaved: (value) => address = value ?? '',
              ),
              TextFormField(
                initialValue: phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                onSaved: (value) => phone = value ?? '',
              ),
              TextFormField(
                initialValue: province,
                decoration: const InputDecoration(labelText: 'Provincia'),
                onSaved: (value) => province = value ?? '',
              ),
              TextFormField(
                initialValue: email,
                decoration: const InputDecoration(labelText: 'Email'),
                onSaved: (value) => email = value ?? '',
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Campo requerido';
                  final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value)) return 'Email no válido';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveCustomer,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
