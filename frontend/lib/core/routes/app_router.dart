import 'package:flutter/material.dart';

import '../../features/auth/models/auth_user.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../services/auth_service.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const registerCompany = '/register-company';
  static const dashboard = '/dashboard';
}

class AppRouter {
  AppRouter({required this.authService});

  final AuthService authService;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute(
          builder: (_) => LoginScreen(authService: authService),
          settings: settings,
        );
      case AppRoutes.registerCompany:
        return MaterialPageRoute(
          builder: (_) =>
              RegisterScreen(authService: authService, createCompany: true),
          settings: settings,
        );
      case AppRoutes.register:
        return MaterialPageRoute(
          builder: (_) => RegisterScreen(authService: authService),
          settings: settings,
        );
      case AppRoutes.dashboard:
        return MaterialPageRoute(
          builder: (_) => _ProtectedRoute(authService: authService),
          settings: settings,
        );
      case AppRoutes.splash:
      default:
        return MaterialPageRoute(
          builder: (_) => _SessionGate(authService: authService),
          settings: settings,
        );
    }
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate({required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthUser?>(
      future: authService.currentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route = snapshot.data == null
              ? AppRoutes.login
              : AppRoutes.dashboard;
          Navigator.of(context).pushReplacementNamed(route);
        });

        return const Scaffold(body: SizedBox.shrink());
      },
    );
  }
}

class _ProtectedRoute extends StatelessWidget {
  const _ProtectedRoute({required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthUser?>(
      future: authService.currentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacementNamed(AppRoutes.login);
          });
          return const Scaffold(body: SizedBox.shrink());
        }

        return DashboardScreen(authService: authService, user: user);
      },
    );
  }
}
