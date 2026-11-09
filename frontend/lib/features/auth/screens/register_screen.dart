import 'package:flutter/material.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.authService,
    this.createCompany = false,
  });

  final AuthService authService;
  final bool createCompany;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _companyController = TextEditingController();
  final _taxController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _companyController.dispose();
    _taxController.dispose();
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
      if (widget.createCompany) {
        await widget.authService.registerCompany(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          passwordConfirm: _confirmController.text,
          companyName: _companyController.text,
          taxId: _taxController.text,
        );
      } else {
        await widget.authService.register(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          passwordConfirm: _confirmController.text,
        );
      }
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.createCompany
                              ? 'Registrar mi empresa'
                              : 'Crear mi cuenta',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.createCompany
                              ? 'Crea tu empresa y tu cuenta administradora en un solo paso. Después podrás invitar a tu equipo.'
                              : 'Usa el correo al que te invitó el administrador. Solo completa tus datos y contraseña. Tu empresa y tu rol se asignan automáticamente con ese correo.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        _nameFields(),
                        const SizedBox(height: 16),
                        if (widget.createCompany) ...[
                          TextFormField(
                            controller: _companyController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la empresa',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Escribe el nombre de tu empresa.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _taxController,
                            decoration: const InputDecoration(
                              labelText: 'NIT (opcional)',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: 'Correo',
                            helperText: widget.createCompany
                                ? 'Será tu correo de acceso como administrador.'
                                : 'Debe ser el mismo correo que registró el administrador.',
                            helperMaxLines: 2,
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa el correo.';
                            }
                            if (!value.contains('@')) {
                              return 'Ingresa un correo válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ingresa una contraseña.';
                            }
                            if (value.length < 8) {
                              return 'Debe tener mínimo 8 caracteres.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscurePassword,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar contraseña',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Las contraseñas no coinciden.';
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(
                                  widget.createCompany
                                      ? 'Crear empresa y cuenta'
                                      : 'Crear cuenta',
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pushReplacementNamed(AppRoutes.login),
                          child: const Text('Ya tengo cuenta'),
                        ),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () =>
                                    Navigator.of(context).pushReplacementNamed(
                                      widget.createCompany
                                          ? AppRoutes.register
                                          : AppRoutes.registerCompany,
                                    ),
                          child: Text(
                            widget.createCompany
                                ? 'Tengo una invitación de una empresa'
                                : 'Quiero registrar mi empresa',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final firstName = TextFormField(
          controller: _firstNameController,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            prefixIcon: Icon(Icons.person_outline),
          ),
        );
        final lastName = TextFormField(
          controller: _lastNameController,
          decoration: const InputDecoration(labelText: 'Apellido'),
        );

        if (stacked) {
          return Column(
            children: [firstName, const SizedBox(height: 16), lastName],
          );
        }
        return Row(
          children: [
            Expanded(child: firstName),
            const SizedBox(width: 12),
            Expanded(child: lastName),
          ],
        );
      },
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
