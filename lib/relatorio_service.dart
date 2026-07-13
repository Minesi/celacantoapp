// lib/relatorio_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'projeto_model.dart';

class RelatorioService {
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

  /// Injeta os dados consolidados do projeto, instrumentos e OCR dentro do template Word.
  Future<File?> gerarRelatorioProjeto({
    required ProjetoModel projeto,
    required String nomeEmpresa,
    required String assetTemplatePath, 
  }) async {
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

          // Substições de Cabeçalho Geral do Escopo
          conteudoXml = conteudoXml.replaceAll('{PROJETO}', projeto.tipoProjeto);
          conteudoXml = conteudoXml.replaceAll('{EMPRESA}', nomeEmpresa);
          conteudoXml = conteudoXml.replaceAll('{CNPJ}', projeto.cnpjEmpresa);
          conteudoXml = conteudoXml.replaceAll('{DATA_GERACAO}', _obterDataAtualFormatada());

          // Substituição Dinâmica de Ativos/Instrumentos Escaneados
          // Varre o mapa de ferramentas vinculadas por QR Code (ex: 'Anemômetro', 'Manômetro Diferencial')
          projeto.ferramentasEscaneadas.forEach((nomeFerramenta, instrumento) {
            // Criamos tags baseadas no nome da ferramenta para evitar colisão caso use mais de uma
            // Exemplo no Word: {TAG_ANEMÔMETRO}, {CERTIFICADO_MANÔMETRO_DIFERENCIAL}
            final sufixoTag = nomeFerramenta.toUpperCase().replaceAll(' ', '_');
            
            conteudoXml = conteudoXml.replaceAll('{EQUIPAMENTO_$sufixoTag}', instrumento.tipo);
            conteudoXml = conteudoXml.replaceAll('{TAG_$sufixoTag}', instrumento.tag);
            conteudoXml = conteudoXml.replaceAll('{SERIE_$sufixoTag}', instrumento.numeroSerie);
            conteudoXml = conteudoXml.replaceAll('{CERTIFICADO_$sufixoTag}', instrumento.numeroCertificado);
            conteudoXml = conteudoXml.replaceAll('{VALIDADE_$sufixoTag}', instrumento.validade);
          });

          // Substituição Dinâmica das Leituras Coletadas via OCR
          // Como as leituras vêm em lista ordenada, substituímos por índices {VALOR_1}, {VALOR_2}, etc.
          for (int i = 0; i < projeto.leiturasOcr.length; i++) {
            final leitura = projeto.leiturasOcr[i];
            conteudoXml = conteudoXml.replaceAll('{VALOR_${i + 1}}', leitura.valorCapturado);
            conteudoXml = conteudoXml.replaceAll('{EQUIP_VALOR_${i + 1}}', leitura.equipamento);
          }

          // Limpa tags sobressalentes caso o template tenha mais slots de leitura do que o coletado
          for (int i = projeto.leiturasOcr.length; i < 10; i++) {
            conteudoXml = conteudoXml.replaceAll('{VALOR_${i + 1}}', '-');
            conteudoXml = conteudoXml.replaceAll('{EQUIP_VALOR_${i + 1}}', '-');
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
        // 5. Localiza a pasta local segura do dispositivo
        final diretorio = await getApplicationDocumentsDirectory();
        final subdiretorio = Directory('${diretorio.path}/relatorios');
        if (!await subdiretorio.exists()) {
          await subdiretorio.create(recursive: true);
        }
        
        final nomeArquivoSanitizado = projeto.id.replaceAll(' ', '_');
        final stringCaminhoFinal = "${subdiretorio.path}/Relatorio_$nomeArquivoSanitizado.docx";
        
        // 6. Grava fisicamente no disco de forma assíncrona
        final arquivoFinal = File(stringCaminhoFinal);
        await arquivoFinal.writeAsBytes(listaBytesFinais, flush: true);
        
        debugPrint('DEBUG SUCCESS: Documento gerado fisicamente em: $stringCaminhoFinal');
        return arquivoFinal; 
      }
      
      return null;
    } catch (e) {
      debugPrint('Erro ao gerar relatório unificado no Word: $e');
      return null;
    }
  }

  String _obterDataAtualFormatada() {
    final agora = DateTime.now();
    final dia = agora.day.toString().padLeft(2, '0');
    final mes = agora.month.toString().padLeft(2, '0');
    final ano = agora.year;
    return "$dia/$mes/$ano";
  }
}