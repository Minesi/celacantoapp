import 'package:flutter/material.dart';
import 'database_helper.dart';

class DatabaseRecoveryPage extends StatefulWidget {
  final VoidCallback onRecuperado;
  final WidgetBuilder paginaInicial;

  const DatabaseRecoveryPage({
    super.key,
    required this.onRecuperado,
    required this.paginaInicial,
  });

  @override
  State<DatabaseRecoveryPage> createState() => _DatabaseRecoveryPageState();
}

class _DatabaseRecoveryPageState extends State<DatabaseRecoveryPage> {
  bool _reconstruindo = false;
  String? _erro;

  Future<void> _reconstruirBanco() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reconstruir banco local?'),
        content: const Text(
          'Os dados locais pendentes serão removidos. Dados já sincronizados com o servidor não serão afetados. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reconstruir'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() {
      _reconstruindo = true;
      _erro = null;
    });

    try {
      await DatabaseHelper().recriarBancoLocal();
      if (!mounted) return;
      widget.onRecuperado();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => _RecoveryCompletePage(paginaInicial: widget.paginaInicial)),
        (route) => false,
      );
    } catch (e, stackTrace) {
      debugPrint('Falha ao reconstruir banco local: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _reconstruindo = false;
        _erro = 'Não foi possível reconstruir o banco local. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperação do armazenamento local')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.storage_rounded, size: 64, color: Colors.orange),
                const SizedBox(height: 20),
                const Text(
                  'O armazenamento local precisa ser reconstruído',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'O aplicativo encontrou uma inconsistência no banco usado para o trabalho offline. A reconstrução remove apenas o cache local e permite baixar novamente os dados disponíveis no servidor.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _reconstruindo ? null : _reconstruirBanco,
                  icon: _reconstruindo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_reconstruindo ? 'Reconstruindo...' : 'Reconstruir banco local'),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 16),
                  Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryCompletePage extends StatelessWidget {
  final WidgetBuilder paginaInicial;

  const _RecoveryCompletePage({required this.paginaInicial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Armazenamento local reconstruído.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(builder: paginaInicial),
                  (route) => false,
                ),
                child: const Text('Voltar ao login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
