// lib/relatorio_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:path_provider/path_provider.dart';
import 'projeto_model.dart';

class RelatorioService {
  static const _canalRelatorios = MethodChannel('celacantoapp/relatorios');
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// ID do template salvo no Storage em `templates/<templateId>.docx` (ver Cloud Function
  /// `gerarRelatorioDocx` em functions/index.js).
  String templateIdParaProjeto(String tipoProjeto) {
    final tipoNormalizado = tipoProjeto.trim().toLowerCase();

    if (tipoNormalizado.contains('fluxo')) return 'fluxo_laminar';
    if (tipoNormalizado.contains('ar comprimido')) return 'modelo_ar_comprimido';
    if (tipoNormalizado.contains('cabine')) return 'modelo_cabine_exaustao';
    if (tipoNormalizado.contains('hvac')) return 'modelo_relatorio_hvac';
    return 'modelo_teste';
  }

  /// Mantido por compatibilidade com o fluxo legado (assets locais). A geração real do
  /// .docx agora ocorre na nuvem (ver [gerarRelatorioProjeto]); este caminho só é usado
  /// para registrar/derivar qual template foi originalmente selecionado.
  String assetPathParaProjeto(String tipoProjeto) {
    return 'assets/templates/${templateIdParaProjeto(tipoProjeto)}.docx';
  }

  /// Chama a Cloud Function `gerarRelatorioDocx`, que carrega o template do Storage,
  /// faz o merge com docxtemplater (loops de salas/handling units incluídos) e devolve a
  /// URL do .docx gerado. Baixa o arquivo e salva localmente (Downloads/Celacanto).
  /// Requer conexão — a aprovação normalmente ocorre no escritório; se estiver offline,
  /// devolve um aviso claro para tentar novamente mais tarde.
  Future<({File? arquivo, String? localizacao, List<String> avisos})> gerarRelatorioProjeto({
    required ProjetoModel projeto,
    required String nomeEmpresa,
    required String assetTemplatePath,
  }) async {
    final avisos = <String>[];
    final templateId = _templateIdDoAssetPath(assetTemplatePath);

    try {
      final payload = _montarPayloadMerge(projeto: projeto, nomeEmpresa: nomeEmpresa, templateId: templateId);
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

  /// No Windows/Linux o plugin cloud_functions não tem implementação nativa: usa o protocolo
  /// HTTPS de callable (POST {data} com ID token) direto na função.
  Future<Map<String, dynamic>> _chamarGerarRelatorio(Map<String, dynamic> payload) async {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) {
      final resultado = await _functions.httpsCallable('gerarRelatorioDocx').call(payload);
      return Map<String, dynamic>.from(resultado.data as Map);
    }

    final usuario = FirebaseAuth.instance.currentUser;
    if (usuario == null) throw Exception('Usuário não autenticado.');
    final token = await usuario.getIdToken();
    final projectId = Firebase.app().options.projectId;

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.https('us-central1-$projectId.cloudfunctions.net', '/gerarRelatorioDocx'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({'data': payload}));
      final response = await request.close().timeout(const Duration(seconds: 120));
      final texto = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> corpo;
      try {
        corpo = jsonDecode(texto) as Map<String, dynamic>;
      } on FormatException {
        debugPrint('gerarRelatorioDocx respondeu HTTP ${response.statusCode} sem JSON: '
            '${texto.length > 300 ? texto.substring(0, 300) : texto}');
        throw FirebaseFunctionsException(code: 'http-${response.statusCode}', message: 'HTTP ${response.statusCode}');
      }
      if (response.statusCode != 200 || corpo['error'] != null) {
        final erro = corpo['error'] as Map<String, dynamic>? ?? {};
        throw FirebaseFunctionsException(
          code: erro['status']?.toString().toLowerCase() ?? 'http-${response.statusCode}',
          message: erro['message']?.toString() ?? 'HTTP ${response.statusCode}',
        );
      }
      return Map<String, dynamic>.from(corpo['result'] as Map);
    } finally {
      client.close();
    }
  }

  String _templateIdDoAssetPath(String assetPath) {
    final nomeArquivo = assetPath.split('/').last;
    return nomeArquivo.replaceAll('.docx', '');
  }

  /// Monta o payload enviado à Cloud Function: dados escalares do projeto + salas/handling
  /// units estruturados + instrumentos escaneados + leituras (compat. com os templates atuais).
  Map<String, dynamic> _montarPayloadMerge({
    required ProjetoModel projeto,
    required String nomeEmpresa,
    required String templateId,
  }) {
    return {
      'templateId': templateId,
      'projeto': {
        'id': projeto.id,
        'tipoProjeto': projeto.tipoProjeto,
        'cnpjEmpresa': projeto.cnpjEmpresa,
        'nomeEmpresa': nomeEmpresa,
        'sistemaNome': projeto.sistemaId,
        'area': projeto.area,
        'salas': projeto.salas.map((s) => s.toMap()).toList(),
        'handlingUnits': projeto.handlingUnits.map((h) => h.toMap()).toList(),
        'ferramentasEscaneadas': projeto.ferramentasEscaneadas.map(
          (tipo, instrumentos) => MapEntry(tipo, instrumentos.map((i) => i.toMap()).toList()),
        ),
        'leiturasOcr': projeto.leiturasOcr.map((l) => l.toMap()).toList(),
      },
    };
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
}
