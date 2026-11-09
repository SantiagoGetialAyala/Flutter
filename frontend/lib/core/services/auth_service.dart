import '../../features/auth/models/auth_session.dart';
import '../../features/auth/models/auth_user.dart';
import 'api_client.dart';

typedef AuthException = ApiException;

class AuthService {
  AuthService({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient();

  final ApiClient apiClient;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final body = await apiClient.post('/auth/login/', {
      'email': username.trim(),
      'password': password,
    });
    final session = AuthSession.fromJson(body);
    await apiClient.saveTokens(session.accessToken, session.refreshToken);
    return session;
  }

  Future<AuthSession> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String passwordConfirm,
    String? invitationCode,
  }) async {
    final body = await apiClient.post('/auth/register/', {
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirm': passwordConfirm,
      if (invitationCode != null && invitationCode.trim().isNotEmpty)
        'invitation_code': invitationCode.trim(),
    });
    final session = AuthSession.fromJson(body);
    await apiClient.saveTokens(session.accessToken, session.refreshToken);
    return session;
  }

  Future<AuthSession> registerCompany({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String passwordConfirm,
    required String companyName,
    required String taxId,
  }) async {
    final body = await apiClient.post('/auth/register-company/', {
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirm': passwordConfirm,
      'company_name': companyName.trim(),
      'tax_id': taxId.trim(),
    });
    final session = AuthSession.fromJson(body);
    await apiClient.saveTokens(session.accessToken, session.refreshToken);
    return session;
  }

  Future<AuthUser?> currentUser() async {
    final token = await apiClient.accessToken;
    if (token == null) {
      return null;
    }
    try {
      return AuthUser.fromJson(await apiClient.getMap('/auth/me/'));
    } on ApiException {
      return null;
    }
  }

  Future<void> logout() => apiClient.clearTokens();
}
