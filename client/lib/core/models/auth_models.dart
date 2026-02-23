class AuthResult {
  const AuthResult({
    required this.userId,
    required this.userDisplayId,
    required this.token,
  });

  final int userId;
  final String userDisplayId;
  final String token;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      userId: (json['user_id'] as num).toInt(),
      userDisplayId: json['user_display_id'] as String,
      token: json['token'] as String,
    );
  }
}
