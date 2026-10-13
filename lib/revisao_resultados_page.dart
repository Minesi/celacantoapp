import 'package:flutter/material.dart';
import 'relatorio/relatorio_documento.dart';
import 'relatorio/documento_relatorio_widget.dart';

class ResultadoRevisaoRelatorio {
  final Map<String, List<Map<String, dynamic>>> pontosPorChave;
  final String observacoes;

  const ResultadoRevisaoRelatorio({required this.pontosPorChave, required this.observacoes});
}

class RevisaoResultadosPage extends StatefulWidget {
  final DocumentoRelatorio documentoInicial;
  final Map<String, List<Map<String, dynamic>>> pontosIniciais;
  final Future<DocumentoRelatorio> Function(Map<String, List<Map<String, dynamic>>>) reconstruirDocumento;

  const RevisaoResultadosPage({
    super.key,
    required this.documentoInicial,
    required this.pontosIniciais,
    required this.reconstruirDocumento,
  });

  @override
  State<RevisaoResultadosPage> createState() => _RevisaoResultadosPageState();
}

class _RevisaoResultadosPageState extends State<RevisaoResultadosPage> {
  late DocumentoRelatorio _documento;
  late Map<String, List<Map<String, dynamic>>> _pontosPorChave;
  final _observacoesController = TextEditingController();
  bool _reconstruindo = false;

  @override
  void initState() {
    super.initState();
    _documento = widget.documentoInicial;
    _pontosPorChave = _copiarPontos(widget.pontosIniciais);
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  Map<String, List<Map<String, dynamic>>> _copiarPontos(Map<String, List<Map<String, dynamic>>> origem) => {
        for (final entrada in origem.entries)
          entrada.key: entrada.value.map((ponto) => Map<String, dynamic>.from(ponto)).toList(),
      };

  List<MapEntry<String, Map<String, dynamic>>> get _pontos => [
        for (final grupo in _pontosPorChave.entries)
          for (final ponto in grupo.value) MapEntry(grupo.key, ponto),
      ];

  String _nomeGrupo(String chave) {
    final partes = chave.split('|');
    if (partes.length < 2) return chave;
    return '${partes[0]} - ${partes[1]}';
  }

  Future<void> _editarPonto(String chave, Map<String, dynamic> ponto) async {
    final principalController = TextEditingController(text: ponto['valor05um']?.toString() ?? '');
    final secundarioController = TextEditingController(text: ponto['valor5um']?.toString() ?? '');
    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar ponto ${ponto['numeroPonto'] ?? '-'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: principalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Resultado principal'),
            ),
            TextField(
              controller: secundarioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Resultado secundário (se aplicável)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop({
              'valor05um': principalController.text.trim(),
              'valor5um': secundarioController.text.trim(),
            }),
            child: const Text('Aplicar correção'),
          ),
        ],
      ),
    );

    if (resultado == null || !mounted) return;
    final grupo = _pontosPorChave[chave];
    if (grupo == null) return;
    final indice = grupo.indexWhere((item) => item['id']?.toString() == ponto['id']?.toString());
    if (indice < 0) return;

    setState(() {
      grupo[indice]
        ..['valor05um'] = resultado['valor05um'] ?? ''
        ..['valor5um'] = resultado['valor5um'] ?? '';
      _reconstruindo = true;
    });

    try {
      final documentoAtualizado = await widget.reconstruirDocumento(_pontosPorChave);
      if (!mounted) return;
      setState(() => _documento = documentoAtualizado);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar a prévia: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _reconstruindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisão dos Resultados'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocumentoRelatorioWidget(documento: _documento),
            const SizedBox(height: 20),
            const Text('Correções dos resultados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Altere somente valores que tenham sido identificados como incorretos na revisão.'),
            const SizedBox(height: 8),
            if (_pontos.isEmpty)
              const Text('Nenhum ponto de leitura registrado.', style: TextStyle(color: Colors.grey))
            else
              ..._pontos.map((entrada) {
                final ponto = entrada.value;
                final valorPrincipal = ponto['valor05um']?.toString().trim() ?? '';
                final valorSecundario = ponto['valor5um']?.toString().trim() ?? '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_nomeGrupo(entrada.key)} - ponto ${ponto['numeroPonto'] ?? '-'}'),
                  subtitle: Text(
                    'Principal: ${valorPrincipal.isEmpty ? 'não informado' : valorPrincipal}'
                    '${valorSecundario.isEmpty ? '' : ' | Secundário: $valorSecundario'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Editar resultado',
                    onPressed: _reconstruindo ? null : () => _editarPonto(entrada.key, ponto),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                );
              }),
            const SizedBox(height: 12),
            TextField(
              controller: _observacoesController,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações da revisão',
                hintText: 'Registre observações que devem acompanhar o relatório',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _reconstruindo
                ? null
                : () => Navigator.of(context).pop(
                      ResultadoRevisaoRelatorio(
                        pontosPorChave: _pontosPorChave,
                        observacoes: _observacoesController.text.trim(),
                      ),
                    ),
            icon: const Icon(Icons.task_alt, color: Colors.white),
            label: const Text('Continuar para aprovação', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ),
    );
  }
}
