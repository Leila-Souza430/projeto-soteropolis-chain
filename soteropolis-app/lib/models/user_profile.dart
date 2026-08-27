/// Mirrors `UserPublic` in soteropolis-backend/models/schemas.py, returned
/// by GET/PATCH /users/me.
class UserProfile {
  final String id;
  final String email;
  final String? walletAddress;
  final String? instalacaoCoelba;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    this.walletAddress,
    this.instalacaoCoelba,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      walletAddress: json['wallet_address'] as String?,
      instalacaoCoelba: json['instalacao_coelba'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Whether the Web3Auth-derived Solana address has been linked via
  /// PATCH /users/me. Descartes/resgates 400 server-side without this.
  bool get hasWallet => walletAddress != null && walletAddress!.isNotEmpty;
}
