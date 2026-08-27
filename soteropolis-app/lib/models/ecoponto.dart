/// Mirrors `EcopontoPublic` in soteropolis-backend/models/schemas.py,
/// returned by GET /ecopontos.
class Ecoponto {
  final String id;
  final String nome;
  final double latitude;
  final double longitude;
  final bool ativo;
  final DateTime createdAt;

  const Ecoponto({
    required this.id,
    required this.nome,
    required this.latitude,
    required this.longitude,
    required this.ativo,
    required this.createdAt,
  });

  factory Ecoponto.fromJson(Map<String, dynamic> json) {
    return Ecoponto(
      id: json['id'] as String,
      nome: json['nome'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      ativo: json['ativo'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
