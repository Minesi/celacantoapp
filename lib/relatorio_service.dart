// lib/relatorio_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/services.dart' show MethodChannel, PlatformException, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'projeto_model.dart';
import 'leitura_model.dart';

class RelatorioService {
  static const _canalRelatorios = MethodChannel('celacantoapp/relatorios');
  // Quantidade de slots {VALOR_N}/{EQUIP_VALOR_N} suportados pelo esquema legado (lista plana)
  static const int maxSlotsLeituraTemplate = 10;

  // Modelos "agrupados por ferramenta" (ex: HVAC) reservam 1 linha por ferramenta distinta
  // e um número fixo de colunas de leitura por linha (ex: {VALOR_2_1}, {VALOR_2_2})
  static const int maxLinhasFerramentaTemplate = 6;
  static const int maxLeiturasPorLinhaTemplate = 2;

  String assetPathParaProjeto(String tipoProjeto) {
    final tipoNormalizado = tipoProjeto.trim().toLowerCase();

    if (tipoNormalizado.contains('fluxo')) {
      return 'assets/templates/fluxo_laminar.docx';
    }
    if (tipoNormalizado.contains('ar comprimido')) {
      return 'assets/templates/modelo_ar_comprimido.docx';
    }
    if (tipoNormalizado.contains('cabine')) {
      return 'assets/templates/modelo_cabine_exaustao.docx';
    }
    if (tipoNormalizado.contains('hvac')) {
      return 'assets/templates/modelo_relatorio_hvac.docx';
    }
    return 'assets/templates/modelo_teste.docx';
  }

  // O template HVAC organiza as leituras em linhas fixas por ferramenta (não em lista plana)
  bool _usaModeloAgrupadoPorFerramenta(String tipoProjeto) {
    return tipoProjeto.trim().toLowerCase().contains('hvac');
  }

  /// Injeta os dados consolidados do projeto, instrumentos e OCR dentro do template Word.
  /// Retorna o arquivo gerado, a localização pública e avisos sobre dados que não
  /// couberam nos slots fixos do template.
  Future<({File? arquivo, String? localizacao, List<String> avisos})> gerarRelatorioProjeto({
    required ProjetoModel projeto,
    required String nomeEmpresa,
    required String assetTemplatePath, 
  }) async {
    final avisos = <String>[];
    try {
      debugPrint('DEBUG ASSET: Iniciando leitura segura do asset: "$assetTemplatePath"');
      
      // 1. Carrega os bytes do asset
      final dadosTemplate = await rootBundle.load(assetTemplatePath);
      final bytesBrutos = dadosTemplate.buffer.asUint8List(
        dadosTemplate.offsetInBytes, 
        dadosTemplate.lengthInBytes
      );

      // 2. Decodifica a estrutura ZIP do .docx
      final zipDecoder = ZipDecoder();
      final Archive arquivoZip = zipDecoder.decodeBytes(bytesBrutos);

      final novoZipEncoder = ZipEncoder();
      final Archive novoWordZip = Archive();

      // 3. Varre a estrutura interna para aplicar as substituições no XML principal
      for (final ArchiveFile arquivoInterno in arquivoZip) {
        dynamic dadosArquivo = arquivoInterno.content;

        if (arquivoInterno.name == 'word/document.xml') {
          String conteudoXml = utf8.decode(dadosArquivo as List<int>);

          // O Word costuma fragmentar um mesmo placeholder ({TAG}) em múltiplas runs de
          // formatação; sem isso, replaceAll nunca encontra o texto e a tag some do relatório.
          conteudoXml = _normalizarTagsFragmentadas(conteudoXml);

          // Substições de Cabeçalho Geral do Escopo
          conteudoXml = conteudoXml.replaceAll('{PROJETO}', _escaparXml(projeto.tipoProjeto));
          conteudoXml = conteudoXml.replaceAll('{EMPRESA}', _escaparXml(nomeEmpresa));
          conteudoXml = conteudoXml.replaceAll('{CNPJ}', _escaparXml(projeto.cnpjEmpresa));
          conteudoXml = conteudoXml.replaceAll('{DATA_GERACAO}', _obterDataAtualFormatada());

          // Substituição Dinâmica de Ativos/Instrumentos Escaneados
          // Varre o mapa de ferramentas vinculadas por QR Code (ex: 'Anemômetro', 'Manômetro Diferencial')
          projeto.ferramentasEscaneadas.forEach((nomeFerramenta, instrumento) {
            // Criamos tags baseadas no nome da ferramenta para evitar colisão caso use mais de uma
            // Exemplo no Word: {TAG_ANEMÔMETRO}, {CERTIFICADO_MANÔMETRO_DIFERENCIAL}
            // Tentamos as variantes com e sem acento pois os templates não seguem um padrão único
            final sufixoComAcento = nomeFerramenta.toUpperCase().replaceAll(' ', '_');
            final sufixoSemAcento = _removerAcentos(sufixoComAcento);

            for (final sufixoTag in {sufixoComAcento, sufixoSemAcento}) {
              conteudoXml = conteudoXml.replaceAll('{EQUIPAMENTO_$sufixoTag}', _escaparXml(instrumento.tipo));
              conteudoXml = conteudoXml.replaceAll('{TAG_$sufixoTag}', _escaparXml(instrumento.tag));
              conteudoXml = conteudoXml.replaceAll('{SERIE_$sufixoTag}', _escaparXml(instrumento.numeroSerie));
              conteudoXml = conteudoXml.replaceAll('{CERTIFICADO_$sufixoTag}', _escaparXml(instrumento.numeroCertificado));
              conteudoXml = conteudoXml.replaceAll('{VALIDADE_$sufixoTag}', _escaparXml(instrumento.validade));
            }
          });

          if (_usaModeloAgrupadoPorFerramenta(projeto.tipoProjeto)) {
            conteudoXml = _preencherLeiturasAgrupadasPorFerramenta(conteudoXml, projeto.leiturasOcr, avisos);
          } else {
            conteudoXml = _preencherLeiturasEmListaPlana(conteudoXml, projeto.leiturasOcr, avisos);
          }

          dadosArquivo = utf8.encode(conteudoXml);
        }

        novoWordZip.addFile(ArchiveFile(
          arquivoInterno.name,
          dadosArquivo.length,
          dadosArquivo,
        ));
      }

      // 4. Compacta o novo documento final modificado
      final listaBytesFinais = novoZipEncoder.encode(novoWordZip);

      if (listaBytesFinais != null) {
        final nomeArquivoSanitizado = projeto.id.replaceAll(' ', '_');
        final nomeArquivo = 'Relatorio_$nomeArquivoSanitizado.docx';
        final bytesFinais = listaBytesFinais;

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
        
        // 6. Grava fisicamente no disco de forma assíncrona
        await arquivoFinal.writeAsBytes(bytesFinais, flush: true);
        
        debugPrint('DEBUG SUCCESS: Documento salvo em Downloads: ${arquivoFinal.path}');
        return (arquivo: arquivoFinal, localizacao: arquivoFinal.path, avisos: avisos);
      }
      
      return (arquivo: null, localizacao: null, avisos: avisos);
    } catch (e) {
      debugPrint('Erro ao gerar relatório unificado no Word: $e');
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

  /// Esquema legado: lista plana, 1 slot global por leitura ({VALOR_N}/{EQUIP_VALOR_N}).
  /// Usado por templates como fluxo_laminar/modelo_teste, que não agrupam por ferramenta.
  String _preencherLeiturasEmListaPlana(String conteudoXml, List<LeituraModel> leiturasOcr, List<String> avisos) {
    for (int i = 0; i < leiturasOcr.length; i++) {
      final leitura = leiturasOcr[i];
      conteudoXml = conteudoXml.replaceAll('{VALOR_${i + 1}}', _escaparXml(leitura.valorCapturado));
      conteudoXml = conteudoXml.replaceAll('{EQUIP_VALOR_${i + 1}}', _escaparXml(leitura.equipamento));
    }

    // Limpa tags sobressalentes caso o template tenha mais slots de leitura do que o coletado
    for (int i = leiturasOcr.length; i < maxSlotsLeituraTemplate; i++) {
      conteudoXml = conteudoXml.replaceAll('{VALOR_${i + 1}}', '-');
      conteudoXml = conteudoXml.replaceAll('{EQUIP_VALOR_${i + 1}}', '-');
    }

    if (leiturasOcr.length > maxSlotsLeituraTemplate) {
      avisos.add('$maxSlotsLeituraTemplate leituras exibidas de ${leiturasOcr.length} coletadas — as excedentes não aparecem no relatório.');
    }
    return conteudoXml;
  }

  /// Esquema agrupado por ferramenta: 1 linha por ferramenta distinta ({EQUIP_VALOR_R}),
  /// com até [maxLeiturasPorLinhaTemplate] leituras dessa ferramenta na própria linha
  /// ({VALOR_R_1}, {VALOR_R_2}, ...), preservando a separação entre ferramentas diferentes.
  String _preencherLeiturasAgrupadasPorFerramenta(String conteudoXml, List<LeituraModel> leiturasOcr, List<String> avisos) {
    final ferramentasEmOrdem = <String>[];
    final leiturasPorFerramenta = <String, List<LeituraModel>>{};
    for (final leitura in leiturasOcr) {
      final lista = leiturasPorFerramenta.putIfAbsent(leitura.equipamento, () {
        ferramentasEmOrdem.add(leitura.equipamento);
        return [];
      });
      lista.add(leitura);
    }

    for (int linha = 0; linha < maxLinhasFerramentaTemplate; linha++) {
      final numeroLinha = linha + 1;
      final temFerramentaNestaLinha = linha < ferramentasEmOrdem.length;
      final nomeFerramentaLinha = temFerramentaNestaLinha ? ferramentasEmOrdem[linha] : null;
      final leiturasDaLinha = nomeFerramentaLinha != null ? leiturasPorFerramenta[nomeFerramentaLinha]! : const <LeituraModel>[];

      conteudoXml = conteudoXml.replaceAll(
        '{EQUIP_VALOR_$numeroLinha}',
        nomeFerramentaLinha != null ? _escaparXml(nomeFerramentaLinha) : '-',
      );

      for (int n = 0; n < maxLeiturasPorLinhaTemplate; n++) {
        final valor = n < leiturasDaLinha.length ? _escaparXml(leiturasDaLinha[n].valorCapturado) : '-';
        conteudoXml = conteudoXml.replaceAll('{VALOR_${numeroLinha}_${n + 1}}', valor);
      }

      if (leiturasDaLinha.length > maxLeiturasPorLinhaTemplate) {
        avisos.add('$nomeFerramentaLinha: ${leiturasDaLinha.length} leituras capturadas, mas o modelo só exibe $maxLeiturasPorLinhaTemplate por ferramenta.');
      }
    }

    if (ferramentasEmOrdem.length > maxLinhasFerramentaTemplate) {
      final excedentes = ferramentasEmOrdem.skip(maxLinhasFerramentaTemplate).join(', ');
      avisos.add('O modelo só exibe $maxLinhasFerramentaTemplate ferramentas; não aparecem no relatório: $excedentes.');
    }

    return conteudoXml;
  }

  /// Reconstrói placeholders `{TAG}` que o Word fragmentou em múltiplas runs de texto
  /// (`<w:t>`) por causa de edições/formatação, unindo-os em uma única run antes das
  /// substituições simples via replaceAll — do contrário a tag nunca é encontrada.
  String _normalizarTagsFragmentadas(String xml) {
    // Teto de segurança: se uma "{" nunca fechar dentro desses limites, é tratada como
    // texto solto (não uma tag fragmentada) para não apagar conteúdo real do documento
    // caso o template tenha uma chave desbalanceada/typo.
    const maxRunsPendentes = 20;
    const maxTamanhoBuffer = 120;

    final regexRun = RegExp(r'<w:t\b([^>]*)>([^<]*)</w:t>');
    final matches = regexRun.allMatches(xml).toList();
    if (matches.isEmpty) return xml;

    final novosTextos = List<String?>.filled(matches.length, null);

    String? bufferPendente;
    int? indiceInicioPendente;
    String? prefixoAntesDaChave;

    void abortarPendencia(int ateIndice) {
      // Desiste da fusão: restaura todas as runs percorridas sem nenhuma alteração
      if (indiceInicioPendente != null) {
        for (int k = indiceInicioPendente!; k <= ateIndice; k++) {
          novosTextos[k] = null;
        }
      }
      bufferPendente = null;
      indiceInicioPendente = null;
      prefixoAntesDaChave = null;
    }

    for (int i = 0; i < matches.length; i++) {
      final texto = matches[i].group(2)!;

      if (bufferPendente == null) {
        final ultimaAbertura = texto.lastIndexOf('{');
        final ultimoFechamento = texto.lastIndexOf('}');
        if (ultimaAbertura >= 0 && ultimaAbertura > ultimoFechamento) {
          // Esta run termina com uma "{" que não fecha nela mesma: possível tag fragmentada
          prefixoAntesDaChave = texto.substring(0, ultimaAbertura);
          bufferPendente = texto.substring(ultimaAbertura);
          indiceInicioPendente = i;
        }
        continue;
      }

      bufferPendente = bufferPendente! + texto;

      if (bufferPendente!.length > maxTamanhoBuffer || (i - indiceInicioPendente!) > maxRunsPendentes) {
        // "{" desbalanceada (typo no template ou texto solto): não mexe em nada
        abortarPendencia(i);
        continue;
      }

      final fechamentoIdx = bufferPendente!.indexOf('}');
      if (fechamentoIdx == -1) {
        // Ainda não fechou: esta run inteira faz parte do texto fragmentado
        novosTextos[i] = '';
        continue;
      }

      final tagCompleta = bufferPendente!.substring(0, fechamentoIdx + 1);
      final tamanhoRestante = bufferPendente!.length - (fechamentoIdx + 1);
      final restanteNestaRun = tamanhoRestante > 0 ? texto.substring(texto.length - tamanhoRestante) : '';

      novosTextos[indiceInicioPendente!] = '$prefixoAntesDaChave$tagCompleta';
      novosTextos[i] = restanteNestaRun;

      bufferPendente = null;
      indiceInicioPendente = null;
      prefixoAntesDaChave = null;
    }

    final sb = StringBuffer();
    int cursor = 0;
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      sb.write(xml.substring(cursor, m.start));
      final textoFinal = novosTextos[i] ?? m.group(2)!;
      sb.write('<w:t${m.group(1)}>$textoFinal</w:t>');
      cursor = m.end;
    }
    sb.write(xml.substring(cursor));
    return sb.toString();
  }

  /// Remove acentos comuns em português para casar com templates que usam tags sem acentuação
  String _removerAcentos(String texto) {
    const comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const semAcento = 'AAAAAEEEEIIIIOOOOOUUUUC';
    var resultado = texto;
    for (int i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }
    return resultado;
  }

  String _obterDataAtualFormatada() {
    final agora = DateTime.now();
    final dia = agora.day.toString().padLeft(2, '0');
    final mes = agora.month.toString().padLeft(2, '0');
    final ano = agora.year;
    return "$dia/$mes/$ano";
  }

  /// Escapa caracteres reservados do XML para não corromper o document.xml do .docx
  String _escaparXml(String texto) {
    return texto
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}