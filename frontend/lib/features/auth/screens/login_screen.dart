import 'package:flutter/material.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.authService.login(
        username: _userController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'No se pudo conectar con el servidor.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final form = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 64 : 24,
              32,
              wide ? 64 : 24,
              28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Brand(),
                  const SizedBox(height: 40),
                  _buildForm(),
                  const SizedBox(height: 30),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: AppTheme.muted),
                      SizedBox(width: 6),
                      Text(
                        'Acceso seguro para tu equipo',
                        style: TextStyle(fontSize: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        final hero = Stack(
          fit: StackFit.expand,
          children: [
            const OriginImage(radius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x10102E20),
                    Color(0x15102E20),
                    Color(0xEE103D2B),
                  ],
                ),
              ),
            ),
            Positioned(
              left: wide ? 48 : 24,
              right: 30,
              bottom: wide ? 54 : 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'DEL ORIGEN AL MUNDO',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Cada origen merece\nllegar más lejos.',
                    style: TextStyle(
                      fontSize: wide ? 42 : 27,
                      height: 1.13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: Colors.white,
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Café y cacao de Colombia.\nToda tu operación de exportación, conectada.',
                      style: TextStyle(
                        color: Color(0xFFD4DFD4),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: hero,
                      ),
                    ),
                  ),
                  Expanded(flex: 10, child: form),
                ],
              )
            : SafeArea(
                child: ListView(
                  children: [
                    SizedBox(height: 255, child: hero),
                    form,
                  ],
                ),
              );
      },
    ),
  );

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Inicia sesión',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Bienvenido de nuevo. Tu próxima exportación empieza aquí.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _userController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa tu correo o usuario.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Mostrar contrasena'
                    : 'Ocultar contrasena',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Ingresa tu contrasena.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorMessage(message: _error!),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Inicia sesión'),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => Navigator.of(
                    context,
                  ).pushReplacementNamed(AppRoutes.register),
            child: const Text('¿Es tu primera vez? Crea tu cuenta'),
          ),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
