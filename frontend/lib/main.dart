import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/more_screen.dart';
import 'package:frontend/screens/profile_screen.dart';
import 'package:frontend/screens/activity_screen.dart';
import 'package:frontend/services/api_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Handlers de errores de framework/zona
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('UNCAUGHT: $error\n$stack');
        return true;
      };

      // Init seguro de tokens + migración si hace falta
      await ApiService.init();

      runApp(const CuentaClaraApp());
    },
    (error, stack) {
      debugPrint('ZONED ERROR: $error\n$stack');
    },
  );
}

class CuentaClaraApp extends StatefulWidget {
  const CuentaClaraApp({super.key});

  @override
  State<CuentaClaraApp> createState() => _CuentaClaraAppState();
}

class _CuentaClaraAppState extends State<CuentaClaraApp> {
  StreamSubscription<String>? _authSub;
  bool _handlingRedirect = false; // evita doble navegación

  @override
  void initState() {
    super.initState();

    // Listener global de auth events
    _authSub = ApiService.authEvents.listen((evt) async {
      if (!mounted) return;

      // Sesión expirada o logout manual
      if (evt == AuthEvents.sessionExpired || evt == AuthEvents.loggedOut) {
        if (_handlingRedirect) return;
        _handlingRedirect = true;

        final messenger = appNavigatorKey.currentContext != null
            ? ScaffoldMessenger.of(appNavigatorKey.currentContext!)
            : null;

        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Sesión expirada. Iniciá sesión nuevamente.'),
          ),
        );

        // Limpia el backstack y lleva a Login
        await appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/login',
          (r) => false,
        );

        await Future<void>.delayed(Duration.zero);
        _handlingRedirect = false;
      }

      // Login exitoso
      if (evt == AuthEvents.loggedIn) {
        if (_handlingRedirect) return;
        _handlingRedirect = true;

        await appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/home',
          (r) => false,
        );

        await Future<void>.delayed(Duration.zero);
        _handlingRedirect = false;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'CuentaClara',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3366CC),
        ),
        useMaterial3: true,
      ),

      // Decide pantalla inicial dinámicamente
      home: const _AuthGate(),

      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/more': (_) => const MoreScreen(),
        '/profile': (_) => const ProfileScreen(),
        '/activity': (_) => const ActivityScreen(),
      },

      // Manejo de rutas no registradas
      onGenerateRoute: (settings) {
        debugPrint('onGenerateRoute: ${settings.name}');
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Ruta no encontrada')),
            body: Center(
              child: Text(
                'No existe la ruta "${settings.name}".\n'
                'Agregala a MaterialApp.routes o usa push(MaterialPageRoute(...)).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Gate que decide si mostrar login o home
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final ok = await ApiService.trySilentLogin();
      if (!mounted) return;
      setState(() {
        _logged = ok;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _logged = false;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _logged ? const HomeScreen() : const LoginScreen();
  }
}

