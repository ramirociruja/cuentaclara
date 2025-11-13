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

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Handler de errores de Flutter
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);
      };

      // Handler de errores no capturados a nivel de plataforma
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('UNCAUGHT (platform): $error\n$stack');
        return true;
      };

      runApp(const CuentaClaraApp());
    },
    (error, stack) {
      debugPrint('ZONED ERROR (main): $error\n$stack');
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

      if (evt == AuthEvents.sessionExpired || evt == AuthEvents.loggedOut) {
        if (_handlingRedirect) return;
        _handlingRedirect = true;

        final messenger =
            appNavigatorKey.currentContext != null
                ? ScaffoldMessenger.of(appNavigatorKey.currentContext!)
                : null;

        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Sesión expirada. Iniciá sesión nuevamente.'),
          ),
        );

        await appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/login',
          (r) => false,
        );

        await Future<void>.delayed(Duration.zero);
        _handlingRedirect = false;
      }

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3366CC)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/more': (_) => const MoreScreen(),
        '/profile': (_) => const ProfileScreen(),
        '/activity': (_) => const ActivityScreen(),
      },
      onGenerateRoute: (settings) {
        debugPrint('onGenerateRoute: ${settings.name}');
        return MaterialPageRoute(
          builder:
              (_) => Scaffold(
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

/// Controla la pantalla inicial:
/// - Muestra spinner
/// - Inicializa ApiService
/// - Intenta trySilentLogin()
/// - Redirige a Home o Login
class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 👉 Versión ultra simple:
    // - Logueamos el baseUrl (por si después mirás logs)
    // - Intentamos init de ApiService pero si falla NO nos frena el arranque
    // - No hacemos trySilentLogin, siempre vamos a Login

    try {
      debugPrint('### API_BASE_URL (runtime) = ${ApiService.baseUrl}');
      await ApiService.init();
    } catch (e, st) {
      debugPrint('Error en ApiService.init(): $e\n$st');
    }

    if (!mounted) return;
    setState(() {
      // 👈 Siempre Login por ahora
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 👇 Siempre va a Login. Si esto aparece en iOS, sabemos que la UI está bien.
    return const LoginScreen();
  }
}
