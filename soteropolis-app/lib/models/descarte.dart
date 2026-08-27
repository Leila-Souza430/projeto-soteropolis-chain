/// Mirrors `StatusDescarte` in soteropolis-backend/models/schemas.py.
enum StatusDescarte {
  pendente('Pendente'),
  validado('Validado'),
  rejeitado('Rejeitado');

  final String wireValue;
  const StatusDescarte(this.wireValue);

  static StatusDescarte fromWire(String value) {
    return StatusDescarte.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => StatusDescarte.pendente,
    );
  }
}

/// Mirrors `DescarteCreate` in soteropolis-backend/models/schemas.py, sent
/// as the body of POST /descartes.
class DescarteRequest {
  final String ecopontoId;
  final double latitude;
  final double longitude;
  final String tipoResiduo;
  final double? pesoEstimado;
  final String fotoUrl;

  const DescarteRequest({
    required this.ecopontoId,
    required this.latitude,
    required this.longitude,
    required this.tipoResiduo,
    this.pesoEstimado,
    required this.fotoUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'ecoponto_id': ecopontoId,
      'latitude': latitude,
      'longitude': longitude,
      'tipo_residuo': tipoResiduo,
      if (pesoEstimado != null) 'peso_estimado': pesoEstimado,
      'foto_url': fotoUrl,
    };
  }
}

/// Mirrors `DescarteResponse` in soteropolis-backend/models/schemas.py, the
/// 201 body of POST /descartes.
class DescarteResponse {
  final String id;
  final StatusDescarte status;
  final double distanciaMetros;
  final String? txHash;
  final double? quantidadeTokens;
  final DateTime createdAt;

  const DescarteResponse({
    required this.id,
    required this.status,
    required this.distanciaMetros,
    this.txHash,
    this.quantidadeTokens,
    required this.createdAt,
  });

  factory DescarteResponse.fromJson(Map<String, dynamic> json) {
    return DescarteResponse(
      id: json['id'] as String,
      status: StatusDescarte.fromWire(json['status'] as String),
      distanciaMetros: (json['distancia_metros'] as num).toDouble(),
      txHash: json['tx_hash'] as String?,
      quantidadeTokens: (json['quantidade_tokens'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
