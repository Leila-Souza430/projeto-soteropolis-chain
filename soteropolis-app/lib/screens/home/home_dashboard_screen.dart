import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_feedback.dart';
import '../camera/camera_descarte_screen.dart';
import '../carteira/carteira_screen.dart';
import '../resgate/resgate_screen.dart';

/// Entry hub after login: current saldo (via the `get_saldo_gt` RPC, called
/// directly against Supabase under the citizen's own session - no FastAPI
/// endpoint exists or is needed for this) plus navigation to the other 3
/// action screens.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.authService,
    required this.onLoggedOut,
  });

  final AuthService authService;
  final VoidCallback onLoggedOut;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  double? _saldo;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSaldo();
  }

  Future<void> _loadSaldo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await Supabase.instance.client.rpc('get_saldo_gt');
      setState(() => _saldo = (result as num).toDouble());
    } catch (e) {
      setState(() => _errorMessage = 'Não foi possível carregar seu saldo.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // Balances change server-side after a descarte/resgate - refresh on
    // return instead of trying to predict the new value client-side.
    _loadSaldo();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Deseja sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.authService.signOut();
      widget.onLoggedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soterópolis Chain'),
        actions: [
          IconButton(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSaldo,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _SaldoCard(saldo: _saldo, isLoading: _isLoading),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              StatusBanner.error(message: _errorMessage!),
            ],
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Registrar Descarte',
              icon: Icons.camera_alt_outlined,
              onPressed: () =>
                  _push(CameraDescarteScreen(authService: widget.authService)),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Minha Carteira Digital',
              icon: Icons.account_balance_wallet_outlined,
              onPressed: () => _push(const CarteiraScreen()),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Resgatar Benefício',
              icon: Icons.redeem_outlined,
              onPressed: () =>
                  _push(ResgateScreen(authService: widget.authService)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaldoCard extends StatelessWidget {
  const _SaldoCard({required this.saldo, required this.isLoading});

  final double? saldo;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seu saldo em Green Tokens',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          isLoading
              ? const SizedBox(
                  height: 32,
                  width: 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Text(
                  '${(saldo ?? 0).toStringAsFixed(2)} GT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ],
      ),
    );
  }
}
