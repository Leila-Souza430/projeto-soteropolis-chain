import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/transacao.dart';
import '../../widgets/status_feedback.dart';

/// "Carteira Digital": saldo + comprovante history. Reads
/// `transacoes_tokens` directly via the citizen's own Supabase session -
/// RLS policy `auth.uid() = user_id` already scopes rows to their own, so no
/// backend endpoint exists or is needed for this (SPEC: direct-Supabase
/// calls section).
///
/// Never shows "hash," "blockchain," or "transação" as UI copy - MINT/BURN
/// rows are presented as "Créditos" / "Resgates" and tx_hash as
/// "Comprovante," per SPEC #6.
class CarteiraScreen extends StatefulWidget {
  const CarteiraScreen({super.key});

  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  List<Transacao>? _transacoes;
  double? _saldo;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _errorMessage = null);
    try {
      final client = Supabase.instance.client;
      // Sequential, not Future.wait: rpc()/from() return differently-typed
      // Postgrest builders, and both queries are cheap enough that running
      // them one after another isn't worth fighting Dart's type inference
      // for a shared List<E> element type.
      final saldo = (await client.rpc('get_saldo_gt') as num).toDouble();
      final rows =
          await client
                  .from('transacoes_tokens')
                  .select()
                  .order('created_at', ascending: false)
              as List<dynamic>;

      setState(() {
        _saldo = saldo;
        _transacoes = rows
            .map((row) => Transacao.fromJson(row as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Não foi possível carregar seu extrato.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carteira Digital')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _transacoes == null
            ? (_errorMessage != null
                  ? _ErrorBody(message: _errorMessage!, onRetry: _load)
                  : const LoadingState(label: 'Carregando extrato...'))
            : _TransacoesList(saldo: _saldo, transacoes: _transacoes!),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        StatusBanner.error(message: message),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }
}

class _TransacoesList extends StatelessWidget {
  const _TransacoesList({required this.saldo, required this.transacoes});

  final double? saldo;
  final List<Transacao> transacoes;

  @override
  Widget build(BuildContext context) {
    if (transacoes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 48),
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.black26),
          SizedBox(height: 16),
          Text(
            'Nenhum comprovante ainda. Registre um descarte para começar a acumular Green Tokens.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: transacoes.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Saldo atual: ${(saldo ?? 0).toStringAsFixed(2)} GT',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }
        return _TransacaoTile(transacao: transacoes[index - 1]);
      },
    );
  }
}

class _TransacaoTile extends StatelessWidget {
  const _TransacaoTile({required this.transacao});

  final Transacao transacao;

  @override
  Widget build(BuildContext context) {
    final isCredito = transacao.tipo == TipoTransacaoToken.mint;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isCredito ? Icons.add_circle_outline : Icons.remove_circle_outline,
            color: isCredito ? Colors.green.shade700 : Colors.orange.shade800,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCredito ? 'Crédito por descarte' : 'Resgate de benefício',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateFormat.format(transacao.createdAt.toLocal()),
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  'Comprovante: ${transacao.txHash.substring(0, transacao.txHash.length.clamp(0, 12))}...',
                  style: const TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ],
            ),
          ),
          Text(
            '${isCredito ? '+' : '-'}${transacao.quantidade.toStringAsFixed(2)} GT',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isCredito ? Colors.green.shade700 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
