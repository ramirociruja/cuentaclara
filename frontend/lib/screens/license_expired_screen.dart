import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';

class LicenseExpiredScreen extends StatelessWidget {
  const LicenseExpiredScreen({super.key});

  static const Color primaryColor = Color(0xFF3366CC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy, size: 72, color: primaryColor),
                  const SizedBox(height: 16),
                  const Text(
                    'Licencia vencida',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La licencia de la empresa se encuentra vencida y el servicio fue suspendido.\n\n'
                    'Para continuar utilizando la aplicación, el administrador debe renovarla.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        await ApiService.clearAuth(); // emite loggedOut
                      },
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
