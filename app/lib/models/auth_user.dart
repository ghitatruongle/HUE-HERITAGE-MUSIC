class AuthUser {
  final String id;
  final String username;
  final String email;
  final String token;
  final String role;
  final bool isGuest;
  final bool mustChangePassword;

  const AuthUser({
    required this.id,
    required this.username,
    this.email = '',
    required this.token,
    this.role = 'user',
    this.isGuest = false,
    this.mustChangePassword = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      isGuest: json['isGuest'] == true,
      mustChangePassword: json['must_change_password'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'token': token,
      'role': role,
      'isGuest': isGuest,
      'must_change_password': mustChangePassword,
    };
  }
}
