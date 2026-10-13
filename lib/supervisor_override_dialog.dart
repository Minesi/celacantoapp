// lib/supervisor_override_dialog.dart
// Diálogo reutilizável para autorizações excepcionais feitas online por supervisor/admin.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cloud_functions_client.dart';
import 'offline_authorization_service.dart';

class LiberacaoSupervisor {
  final String supervisorUid;
  final String supervisorNome;
  final String supervisorEmail;
  final String metodo;
  final String justificativa;
  final DateTime dataHora;
  final String? autorizacaoOffline;

  const LiberacaoSupervisor({
    required this.supervisorUid,
    required this.supervisorNome,
    required this.supervisorEmail,
    required this.metodo,
    required this.justificativa,
    required this.dataHora,
    this.autorizacaoOffline,
  });

  Map<String, dynamic> toMap() => {
        'supervisorUid': supervisorUid,
        'supervisorNome': supervisorNome,
        'supervisorEmail': supervisorEmail,
        'metodo': metodo,
        'justificativa': justificativa,
        'dataHora': dataHora.toIso8601String(),
        if (autorizacaoOffline != null) 'autorizacaoOffline': autorizacaoOffline,
      };
}

/// Valida o código TOTP na Cloud Function; retorna o nome do supervisor ou lança com a mensagem de erro.
Future<Map<String, dynamic>> _validarCodigoAutenticador(
  String codigo,
  String motivo, {
  required Map<String, dynamic> contexto,
}) async {
  try {
    return await chamarCallable('validarCodigoLiberacao', {
      'codigo': codigo,
      'motivo': motivo,
      'auditoria': contexto,
    });
  } on FirebaseFunctionsException catch (e) {
    throw switch (e.code) {
      'resource-exhausted' => 'Muitas tentativas. Aguarde alguns minutos.',
      'permission-denied' => 'Código inválido ou expirado.',
      'unauthenticated' => 'Sessão expirada. Entre novamente no app.',
      _ => 'Não foi possível validar o código (${e.message ?? e.code}). Verifique a conexão com a internet.',
    };
  } catch (e) {
    debugPrint('Falha ao validar código de liberação: $e');
    throw 'Sem conexão para validar o código. A liberação exige internet.';
  }
}

/// Mostra o diálogo de liberação e retorna os dados auditáveis da autorização
/// (código do autenticador validado de fato no Firebase), ou `null` se cancelado/recusado.
Future<LiberacaoSupervisor?> solicitarLiberacaoSupervisor({
  required BuildContext context,
  required String titulo,
  required String mensagem,
  String projetoId = '',
  String salaId = '',
  String ensaioTipo = '',
  String ferramentaTipo = '',
  String ferramentaTag = '',
  String? justificativa,
}) async {
  final codigoController = TextEditingController();
  final justificativaController = TextEditingController();
  LiberacaoSupervisor? liberacao;

  String? obterJustificativaFinal() {
    final justificativaTecnico = justificativaController.text.trim();
    if (justificativaTecnico.isEmpty) return null;
    final contextoJustificativa = justificativa?.trim().isNotEmpty == true ? justificativa!.trim() : '$titulo: $mensagem';
    return '$contextoJustificativa Justificativa do técnico: $justificativaTecnico';
  }

  Future<LiberacaoSupervisor?> autorizarOffline(BuildContext dialogContext) async {
    final justificativaFinal = obterJustificativaFinal();
    if (justificativaFinal == null) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Informe a justificativa do técnico para continuar.'), backgroundColor: Colors.red),
      );
      return null;
    }
    final servico = OfflineAuthorizationService.instance;
    final contexto = OfflineAuthorizationContext(
      projetoId: projetoId,
      salaId: salaId,
      ensaioTipo: ensaioTipo,
      ferramentaTipo: ferramentaTipo,
      ferramentaTag: ferramentaTag,
      justificativa: justificativaFinal,
    );
    final solicitacao = await servico.emitirSolicitacao(contexto: contexto);
    if (!dialogContext.mounted) return null;
    final respostaController = TextEditingController();
    String? erro;
    bool processando = false;

    final envelope = await showDialog<OfflineAuthorizationEnvelope>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Autorização offline'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Envie a solicitação ao supervisor. Depois, cole aqui o token assinado.'),
                const SizedBox(height: 12),
                SelectableText(solicitacao, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                IconButton(
                  tooltip: 'Copiar solicitação',
                  icon: const Icon(Icons.copy),
                  onPressed: () => Clipboard.setData(ClipboardData(text: solicitacao)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: respostaController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Token assinado pelo supervisor',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (erro != null) ...[
                  const SizedBox(height: 12),
                  Text(erro!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: processando
                  ? null
                  : () async {
                      setDialogState(() {
                        processando = true;
                        erro = null;
                      });
                      try {
                        try {
                          await servico.sincronizarChavesOnline().timeout(const Duration(seconds: 3));
                        } catch (_) {
                          // O cache local de chaves é suficiente quando o dispositivo está offline.
                        }
                        final resposta = await servico.verificarAutorizacao(
                          responseToken: respostaController.text.trim(),
                          contextoEsperado: contexto,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop(resposta);
                      } catch (e) {
                        setDialogState(() {
                          processando = false;
                          erro = e is FormatException ? e.message : 'Não foi possível validar a autorização offline.';
                        });
                      }
                    },
              child: Text(processando ? 'Validando...' : 'Validar autorização'),
            ),
          ],
        ),
      ),
    );
    respostaController.dispose();
    if (envelope == null) return null;

    return LiberacaoSupervisor(
      supervisorUid: envelope.supervisorUid,
      supervisorNome: envelope.supervisorNome,
      supervisorEmail: envelope.supervisorEmail,
      metodo: 'offline_assinada',
      justificativa: justificativaFinal,
      dataHora: DateTime.now(),
      autorizacaoOffline: envelope.toToken(),
    );
  }

  Future<void> autorizar(BuildContext dialogContext) async {
    final justificativaFinal = obterJustificativaFinal();
    if (justificativaFinal == null) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Informe a justificativa do técnico para continuar.'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    String? erro;
    Map<String, dynamic>? resultado;
    try {
      resultado = await _validarCodigoAutenticador(
        codigoController.text.trim(),
        justificativaFinal,
        contexto: {
          'projetoId': projetoId,
          'salaId': salaId,
          'ensaioTipo': ensaioTipo,
          'ferramentaTipo': ferramentaTipo,
          'ferramentaTag': ferramentaTag,
          'justificativa': justificativaFinal,
        },
      );
    } catch (e) {
      erro = e.toString();
    }

    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop(); // fecha o indicador de carregamento

    if (resultado != null) {
      liberacao = LiberacaoSupervisor(
        supervisorUid: resultado['supervisorUid']?.toString() ?? '',
        supervisorNome: resultado['supervisorNome']?.toString() ?? '',
        supervisorEmail: resultado['supervisorEmail']?.toString() ?? '',
        metodo: 'totp',
        justificativa: justificativaFinal,
        dataHora: DateTime.now(),
      );
      Navigator.of(dialogContext).pop(); // fecha o diálogo de liberação
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text(liberacao!.supervisorNome.isEmpty
              ? 'Liberação autorizada!'
              : 'Liberação autorizada por ${liberacao!.supervisorNome}!'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(erro ?? 'Liberação recusada.'), backgroundColor: Colors.red),
      );
    }
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(mensagem),
                const SizedBox(height: 16),
                TextField(
                  controller: justificativaController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Justificativa do técnico',
                    hintText: 'Descreva o motivo da liberação excepcional',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Peça ao supervisor o código de 6 dígitos do autenticador. O dispositivo precisa estar conectado à internet.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codigoController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 6),
                  decoration: const InputDecoration(labelText: 'Código do autenticador', counterText: ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            if (projetoId.trim().isNotEmpty)
              TextButton(
                onPressed: () async {
                  final autorizacao = await autorizarOffline(dialogContext);
                  if (autorizacao == null || !dialogContext.mounted) return;
                  liberacao = autorizacao;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(autorizacao.supervisorNome.isEmpty
                          ? 'Liberação offline autorizada!'
                          : 'Liberação offline autorizada por ${autorizacao.supervisorNome}!'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
                child: const Text('Sem internet'),
              ),
            ElevatedButton(
              onPressed: () => autorizar(dialogContext),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
              child: const Text('Autorizar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
    },
  );

  // Controllers não são descartados aqui: o diálogo ainda os usa durante a animação de saída.
  return liberacao;
}
