import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color primaryColor = Color(0xFF3366CC);
  static const Color dangerColor = Color(0xFFFF4444);

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _loginFailed = false;
  bool _autoTried = false; // para no parpadear la UI mientras hace silent login

  @override
  void initState() {
    super.initState();
    _autoLogin();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _autoLogin() async {
    // Inicializa ApiService (lee/ migra tokens seguros)
    await ApiService.init();

    // Intenta renovar access con refresh si existe
    final ok = await ApiService.trySilentLogin();
    if (!mounted) return;
    if (ok) {
      _goHome();
    } else {
      setState(() => _autoTried = true);
    }
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _login() async {
    // evita taps dobles
    if (_isLoading) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _isLoading = true;
      _loginFailed = false;
    });

    try {
      final ok = await ApiService.login(_emailCtrl.text.trim(), _passCtrl.text);

      if (!mounted) return;

      if (ok) {
        _goHome();
      } else {
        setState(() => _loginFailed = true);
        _showSnack('Email o contraseña incorrectos');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loginFailed = true);
      _showSnack('No se pudo iniciar sesión. Verificá tu conexión.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showHowToGetAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('¿Cómo obtener una cuenta?'),
          content: const Text(
            'CuentaClara es un servicio por suscripción.\n\n'
            'Para solicitar acceso y crear tu cuenta, enviá un email a:\n'
            'cuentaclara@gmail.com\n\n'
            'Incluí tu nombre, tu negocio y la cantidad de cobradores.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: 'cuentaclara@gmail.com'),
                );
                if (!mounted) return;
                Navigator.of(ctx).pop();
                _showSnack('Email copiado: cuentaclara@gmail.com');
              },
              child: const Text('Copiar email'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHowToGetAccountLink() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '¿No tenés cuenta?',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        TextButton(
          onPressed: _showHowToGetAccountDialog,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '¿Cómo obtener una cuenta?',
            style: TextStyle(
              color: Colors.grey.shade700, // 🔽 más neutro
              fontSize: 13,
              fontWeight: FontWeight.w500, // 🔽 menos peso
              decoration: TextDecoration.underline, // 🔽 estilo link
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Image.asset(
          'assets/images/logo.png',
          height: 110,
          width: 110,
          errorBuilder:
              (_, __, ___) =>
                  const Icon(Icons.apartment, size: 72, color: primaryColor),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sistema de Cobranzas',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: primaryColor,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Iniciá sesión para continuar',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      decoration: InputDecoration(
        labelText: 'Email',
        prefixIcon: const Icon(Icons.email_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
      validator: (value) {
        final v = value?.trim() ?? '';
        if (v.isEmpty) return 'Ingrese su email';
        final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,}$');
        if (!emailRegex.hasMatch(v)) return 'Email inválido';
        return null;
      },
      onChanged: (_) {
        if (_loginFailed) setState(() => _loginFailed = false);
      },
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passCtrl,
      focusNode: _passFocus,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onFieldSubmitted: (_) => _login(),
      decoration: InputDecoration(
        labelText: 'Contraseña',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip:
              _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Ingrese su contraseña';
        if (value.length < 6) return 'Mínimo 6 caracteres';
        return null;
      },
      onChanged: (_) {
        if (_loginFailed) setState(() => _loginFailed = false);
      },
    );
  }

  Widget _buildLoginButton() {
    final canSubmit =
        !_isLoading &&
        (_formKey.currentState?.validate() ?? false) &&
        _emailCtrl.text.isNotEmpty &&
        _passCtrl.text.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canSubmit ? _login : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: Colors.grey.shade400,
          foregroundColor:
              Colors.white, // 👈 fuerza texto blanco incluso activo
          textStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.3,
          ),
        ),
        child:
            _isLoading
                ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Text(
                  'INICIAR SESIÓN',
                  style: TextStyle(
                    color: Colors.white, // 👈 asegura contraste alto
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
      ),
    );
  }

  Widget _buildErrorText() {
    return AnimatedCrossFade(
      crossFadeState:
          _loginFailed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 250),
      firstChild: const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Email o contraseña incorrectos',
          style: TextStyle(color: dangerColor),
        ),
      ),
      secondChild: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla de “pre-carga” mientras intenta silent login
    if (!_autoTried) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                onChanged:
                    () => setState(() {}), // para revalidar y habilitar botón
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _buildLogo(),
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(),
                    _buildErrorText(),
                    const SizedBox(height: 24),
                    _buildLoginButton(),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // TODO: Implementar recuperación de contraseña
                        _showSnack('Funcionalidad en desarrollo');
                      },
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildHowToGetAccountLink(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
