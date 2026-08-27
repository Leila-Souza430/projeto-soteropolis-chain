/// Mirrors the `tipo_transacao_token` Postgres enum (database_schema.sql).
enum TipoTransacaoToken {
  mint,
  burn;

  static TipoTransacaoToken fromWire(String value) {
    switch (value) {
      case 'MINT':
        return TipoTransacaoToken.mint;
      case 'BURN':
        return TipoTransacaoToken.burn;
      default:
        throw ArgumentError('tipo_transacao_token desconhecido: $value');
    }
  }
}

/// Mirrors `public.transacoes_tokens` (database_schema.sql). Fetched by
/// carteira_screen.dart directly from Supabase (`.from('transacoes_tokens')`)
/// under the citizen's own session - RLS already scopes rows to
/// `auth.uid() = user_id`, so no backend endpoint exists or is needed for
/// this.
class Transacao {
  final String id;
  final TipoTransacaoToken tipo;
  final double quantidade;
  final String txHash;
  final DateTime createdAt;

  const Transacao({
    required this.id,
    required this.tipo,
    required this.quantidade,
    required this.txHash,
    required this.createdAt,
  });

  factory Transacao.fromJson(Map<String, dynamic> json) {
    return Transacao(
      id: json['id'] as String,
      tipo: TipoTransacaoToken.fromWire(json['tipo'] as String),
      quantidade: (json['quantidade'] as num).toDouble(),
      txHash: json['tx_hash'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
