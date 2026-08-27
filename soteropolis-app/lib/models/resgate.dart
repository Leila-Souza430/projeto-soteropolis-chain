/// Mirrors `ResgateCreate` in soteropolis-backend/models/schemas.py, sent
/// as the body of POST /resgates.
class ResgateRequest {
  final double quantidade;
  final String instalacaoCoelba;

  const ResgateRequest({
    required this.quantidade,
    required this.instalacaoCoelba,
  });

  Map<String, dynamic> toJson() {
    return {'quantidade': quantidade, 'instalacao_coelba': instalacaoCoelba};
  }
}

/// Mirrors `ResgateResponse` in soteropolis-backend/models/schemas.py, the
/// 201 body of POST /resgates. `status` is a plain string server-side
/// (always "Confirmado" today), not an enum - kept as String here too so a
/// future server-side value doesn't need a client update to parse.
class ResgateResponse {
  final String id;
  final String status;
  final String txHash;
  final double quantidade;
  final DateTime createdAt;

  const ResgateResponse({
    required this.id,
    required this.status,
    required this.txHash,
    required this.quantidade,
    required this.createdAt,
  });

  factory ResgateResponse.fromJson(Map<String, dynamic> json) {
    return ResgateResponse(
      id: json['id'] as String,
      status: json['status'] as String,
      txHash: json['tx_hash'] as String,
      quantidade: (json['quantidade'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
