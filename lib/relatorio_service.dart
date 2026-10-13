// lib/relatorio_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'cloud_functions_client.dart';
import 'projeto_model.dart';

class RelatorioService {
  static const _canalRelatorios = MethodChannel('celacantoapp/relatorios');

  /// ID do template salvo no Storage em `templates/<templateId>.docx` (ver Cloud Function
  /// `gerarRelatorioDocx` em functions/index.js).
  String templateIdParaProjeto(String tipoProjeto) {
    final tipoNormalizado = tipoProjeto.trim().toLowerCase();

    if (tipoNormalizado.contains('fluxo')) return 'fluxo_laminar';
    if (tipoNormalizado.contains('ar comprimido')) return 'modelo_ar_comprimido';
    if (tipoNormalizado.contains('cabine') || tipoNormalizado.contains('capela')) return 'modelo_cabine_exaustao';
    if (tipoNormalizado.contains('hvac')) return 'modelo_relatorio_hvac';
    if (tipoNormalizado.contains('pesagem')) return 'pesagem';
    return 'modelo_teste';
  }

  /// Chama a Cloud Function `gerarRelatorioDocx`, que carrega o template do Storage,
  /// faz o merge com docxtemplater (loops de salas/handling units incluídos) e devolve a
  /// URL do .docx gerado. Baixa o arquivo e salva localmente (Downloads/Celacanto).
  /// Requer conexão — a aprovação normalmente ocorre no escritório; se estiver offline,
  /// devolve um aviso claro para tentar novamente mais tarde.
  Future<({File? arquivo, String? localizacao, List<String> avisos})> gerarRelatorioProjeto({
    required ProjetoModel projeto,
    required String templateId,
  }) async {
    final avisos = <String>[];

    try {
      final payload = {
        'templateId': templateId,
        'projeto': {'id': projeto.id},
      };
      final dados = await _chamarGerarRelatorio(payload);

      final url = dados['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('A função de geração não retornou uma URL válida.');
      }

      final bytesFinais = await _baixarBytes(url);
      final nomeArquivo = 'Relatorio_${projeto.id.replaceAll(' ', '_')}.docx';
      return await _salvarNoDispositivo(nomeArquivo, bytesFinais, avisos);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Falha ao chamar a função de geração de relatório: ${e.code} - ${e.message}');
      avisos.add(
        'Não foi possível gerar o relatório agora (${e.message ?? e.code}). '
        'Tente novamente quando estiver online — a aprovação normalmente é feita no escritório.',
      );
      return (arquivo: null, localizacao: null, avisos: avisos);
    } catch (e) {
      debugPrint('Falha ao gerar relatório via nuvem: $e');
      avisos.add('Não foi possível gerar o relatório agora (sem conexão?). Tente novamente quando estiver online.');
      return (arquivo: null, localizacao: null, avisos: avisos);
    }
  }

  Future<Map<String, dynamic>> _chamarGerarRelatorio(Map<String, dynamic> payload) =>
      chamarCallable('gerarRelatorioDocx', payload, timeout: const Duration(seconds: 120));

  /// Emite o relatório montado pelo sistema (sem template): a Cloud Function `gerarRelatorioSistema`
  /// reconstrói os blocos a partir do projeto aprovado, renderiza o .docx e salva o arquivo
  /// em Downloads/Celacanto.
  Future<({File? arquivo, String? localizacao, List<String> avisos})> emitirRelatorio({
    required String projetoId,
  }) async {
    final avisos = <String>[];
    try {
      final dados = await chamarCallable(
        'gerarRelatorioSistema',
        {'projetoId': projetoId},
        timeout: const Duration(seconds: 120),
      );
      final url = dados['url'] as String?;
      if (url == null || url.isEmpty) throw Exception('A função de geração não retornou uma URL válida.');
      final bytes = await _baixarBytes(url);
      return await _salvarNoDispositivo('Relatorio_${projetoId.replaceAll(' ', '_')}.docx', bytes, avisos);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Falha ao emitir relatório: ${e.code} - ${e.message}');
      avisos.add('Não foi possível gerar o relatório agora (${e.message ?? e.code}). Tente novamente quando estiver online.');
      return (arquivo: null, localizacao: null, avisos: avisos);
    } catch (e) {
      debugPrint('Falha ao emitir relatório: $e');
      avisos.add('Não foi possível gerar o relatório agora (sem conexão?). Tente novamente quando estiver online.');
      return (arquivo: null, localizacao: null, avisos: avisos);
    }
  }

  Future<({bool enviado, String? aviso})> enviarRelatorioPorEmail({
    required String projetoId,
  }) async {
    try {
      final dados = await chamarCallable(
        'enviarRelatorioEmail',
        {'projetoId': projetoId},
        timeout: const Duration(seconds: 180),
      );
      return (enviado: dados['ok'] == true, aviso: null);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Falha ao enviar relatório por e-mail: ${e.code} - ${e.message}');
      return (enviado: false, aviso: e.message ?? e.code);
    } catch (e) {
      debugPrint('Falha ao enviar relatório por e-mail: $e');
      return (enviado: false, aviso: e.toString());
    }
  }

  Future<List<int>> _baixarBytes(String url) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = BytesBuilder();
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      httpClient.close();
    }
  }

  Future<({File? arquivo, String? localizacao, List<String> avisos})> _salvarNoDispositivo(
    String nomeArquivo,
    List<int> bytesFinais,
    List<String> avisos,
  ) async {
    try {
      if (Platform.isAndroid) {
        final diretorioTemporario = await getApplicationDocumentsDirectory();
        final arquivoTemporario = File('${diretorioTemporario.path}/$nomeArquivo');
        await arquivoTemporario.writeAsBytes(bytesFinais, flush: true);

        final uriDownloads = await _canalRelatorios.invokeMethod<String>(
          'salvarNoDownloads',
          {'nomeArquivo': nomeArquivo, 'bytes': bytesFinais},
        );
        if (uriDownloads == null) {
          throw FileSystemException('Não foi possível salvar o relatório na pasta Downloads.');
        }
        debugPrint('DEBUG SUCCESS: Documento salvo em Downloads: $uriDownloads');
        return (arquivo: arquivoTemporario, localizacao: uriDownloads, avisos: avisos);
      }

      if (Platform.isIOS) {
        final diretorioDocumentos = await getApplicationDocumentsDirectory();
        final arquivoLocal = File('${diretorioDocumentos.path}/$nomeArquivo');
        await arquivoLocal.writeAsBytes(bytesFinais, flush: true);
        return (arquivo: arquivoLocal, localizacao: arquivoLocal.path, avisos: avisos);
      }

      final diretorioDownloads = await getDownloadsDirectory();
      if (diretorioDownloads == null) {
        throw FileSystemException('A pasta Downloads não está disponível nesta plataforma.');
      }
      final subdiretorio = Directory('${diretorioDownloads.path}/Celacanto');
      if (!await subdiretorio.exists()) await subdiretorio.create(recursive: true);
      final arquivoFinal = File('${subdiretorio.path}/$nomeArquivo');

      await arquivoFinal.writeAsBytes(bytesFinais, flush: true);

      debugPrint('DEBUG SUCCESS: Documento salvo em Downloads: ${arquivoFinal.path}');
      return (arquivo: arquivoFinal, localizacao: arquivoFinal.path, avisos: avisos);
    } catch (e) {
      debugPrint('Erro ao salvar relatório gerado no dispositivo: $e');
      avisos.add('Relatório gerado na nuvem, mas houve falha ao salvá-lo neste dispositivo: $e');
      return (arquivo: null, localizacao: null, avisos: avisos);
    }
  }

  Future<bool> abrirRelatorio(String localizacao) async {
    try {
      if (Platform.isAndroid) {
        return await _canalRelatorios.invokeMethod<bool>(
              'abrirRelatorio',
              {'uri': localizacao},
            ) ??
            false;
      }
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [localizacao]);
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint('Falha ao abrir relatório: ${e.message}');
    } catch (e) {
      debugPrint('Falha ao abrir relatório: $e');
    }
    return false;
  }

  Future<bool> compartilharRelatorio({
    required File arquivo,
    required String assunto,
    required String texto,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      await Share.shareXFiles([XFile(arquivo.path)], subject: assunto, text: texto);
      return true;
    } catch (e) {
      debugPrint('Falha ao compartilhar relatório: $e');
      return false;
    }
  }

  Future<bool> abrirImpressaoWindows(String localizacao) async {
    if (!Platform.isWindows) return false;
    try {
      final caminho = localizacao.replaceAll("'", "''");
      final comando = "\$ErrorActionPreference = 'Stop'; "
          "\$word = New-Object -ComObject Word.Application; "
          "\$documento = \$word.Documents.Open('$caminho'); "
          "\$word.Visible = \$true; "
          "\$word.Dialogs.Item(88).Show(); "
          "\$documento.Close([ref]\$false); "
          "\$word.Quit();";
      await Process.start('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', comando]);
      return true;
    } catch (e) {
      debugPrint('Falha ao abrir impressão do relatório: $e');
      return false;
    }
  }
}
