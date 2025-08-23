import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const CuentaClaraApp());
}

class CuentaClaraApp extends StatelessWidget {
  const CuentaClaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CuentaClara',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text("Pantalla vacía")));
  }
}
