import 'package:flutter/material.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../auth/models/auth_user.dart';
import '../../workspace/workspace_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.authService,
    required this.user,
  });
  final AuthService authService;
  final AuthUser user;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: WorkspaceScreen(
      api: authService.apiClient,
      user: user,
      onLogout: () async {
        await authService.logout();
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
        }
      },
    ),
  );
}
