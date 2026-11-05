class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roleDisplay,
    this.role,
    this.position,
    this.isActive = true,
    this.isPlatform = false,
  });

  final int id;
  final String email;
  final String fullName;
  final String? role;
  final String roleDisplay;
  final String? position;
  final bool isActive;
  final bool isPlatform;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? json['email'] as String? ?? '',
      role: json['role'] as String?,
      roleDisplay: json['role_display'] as String? ?? 'Sin rol asignado',
      position: json['position'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isPlatform: json['is_platform'] as bool? ?? false,
    );
  }

  bool get isAdmin => role == 'administrador';
}
