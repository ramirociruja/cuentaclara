import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const Color primaryColor = Color(0xFF3366CC);
  static const Color dangerColor = Color(0xFFFF4444);

  Future<void> _logout(BuildContext context) async {
    await ApiService.clearAuth();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sesión cerrada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Más',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            subtitle: const Text('Tu información básica'),
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Actividad'),
            subtitle: const Text('Pagos realizados y créditos otorgados'),
            onTap: () => Navigator.pushNamed(context, '/activity'),
          ),
          const Divider(height: 0),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              onPressed: () => _logout(context),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
