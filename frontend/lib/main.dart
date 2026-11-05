import 'package:flutter/material.dart';

import 'core/routes/app_router.dart';
import 'core/services/auth_service.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const RiTechApp());
}

class RiTechApp extends StatelessWidget {
  const RiTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return MaterialApp(
      title: 'RiTech SAS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      onGenerateRoute: AppRouter(authService: authService).onGenerateRoute,
      initialRoute: AppRoutes.splash,
    );
  }
}
