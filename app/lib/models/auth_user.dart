class AuthUser {
  final String id;
  final String username;
  final String email;
  final String token;
  final String role;
  final bool isGuest;

  const AuthUser({
    required this.id,
    required this.username,
    this.email = '',
    required this.token,
    this.role = 'user',
    this.isGuest = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      isGuest: json['isGuest'] == true,
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
    };
  }
}
