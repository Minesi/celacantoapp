import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/ensaio_model.dart';
import 'package:celacantoapp/filtro_model.dart';
import 'package:celacantoapp/handling_unit_model.dart';
import 'package:celacantoapp/history_entry_model.dart';
import 'package:celacantoapp/paralelismo_model.dart';
import 'package:celacantoapp/projeto_model.dart';
import 'package:celacantoapp/relatorio/relatorio_documento.dart';
import 'package:celacantoapp/relatorio/textos_modelo_relatorio.dart';
import 'package:celacantoapp/sala_model.dart';

void main() {
  final sala1 = SalaModel(
    id: 'S1',
    nome: 'SALA 01',
    area: 10,
    volume: 30,
    grau: GrauSala.d,
    handlingUnitId: 'HU1',
    handlingUnitIdsAdicionais: const ['HU2'],
    filtros: [FiltroModel(id: 'F1', tipo: TipoFiltro.h14, quantidade: 2, localizacao: LocalizacaoFiltro.terminal)],
  );

  ProjetoModel projeto({List<String> ensaios = const ['pressao', 'contagemParticulas']}) => ProjetoModel(
        id: 'PRJ-1',
        cnpjEmpresa: '11222333000181',
        tipoProjeto: 'HVAC',
        ferramentasRequeridas: const [],
        ferramentasEscaneadas: const {},
        area: 'Bloco A',
        salas: [sala1],
        handlingUnits: [HandlingUnitModel(id: 'HU1', nome: 'UTA-01'), HandlingUnitModel(id: 'HU2', nome: 'UTA-02')],
        ensaiosSelecionados: ensaios,
        history: [
          HistoryEntry(usuario: 'r@x.com', dataHora: DateTime(2026, 9, 1), campo: 'status', valorAntigo: 'rascunho', valorNovo: 'pronto_para_campo'),
        ],
      );

  DocumentoRelatorio montar({ConclusaoQualificacao? conclusao, List<String>? ensaios, RegistroParalelismo? paralelismo}) =>
      RelatorioDocumentoBuilder(DadosRelatorio(
        projeto: ensaios == null ? projeto() : projeto(ensaios: ensaios),
        nomeEmpresa: 'VET & CIA',
        sistemaNome: 'HVAC 04',
        dataEmissao: DateTime(2026, 9, 30),
        pontosPorChave: {
          'S1|pressao': [
            {'numeroPonto': 1, 'valor05um': '12.5'},
            {'numeroPonto': 2, 'valor05um': '13'},
          ],
        },
        assinaturas: const [AssinaturaRelatorio(papel: 'Elaborado por', nome: 'Redator', funcao: 'Elaborador')],
        conclusao: conclusao,
        paralelismo: paralelismo,
      )).construir();

  List<String> titulosDeSecao(DocumentoRelatorio d) =>
      d.blocos.whereType<BlocoTitulo>().where((t) => t.nivel == 1).map((t) => t.texto).toList();

  String textoCompleto(DocumentoRelatorio d) => d.blocos.map((b) => b.toJson().toString()).join('\n');

  test('seções modelo na ordem, tópicos selecionados antes das assinaturas e conclusão por último', () {
    expect(titulosDeSecao(montar()), [
      '1. Objetivo',
      '2. Referência',
      '3. Definições',
      '4. Escopo',
      '5. Responsabilidades',
      '6. Anexos',
      '7. Testes',
      '8. Tabela de Testes (Resumo)',
      '9. Documentação de Apoio',
      '10. Máquinas, Salas e Resultados dos Testes',
      '11. Registro de Assinaturas',
      '12. Conclusão da Qualificação de Desempenho',
    ]);
  });

  test('variáveis substituídas no título e nos textos', () {
    final doc = montar();
    expect(doc.titulo, contains('HVAC 04'));
    final texto = textoCompleto(doc);
    expect(texto, contains('VET & CIA'));
    expect(texto, isNot(contains('{EMPRESA}')));
    expect(texto, isNot(matches(RegExp(r'\{[A-Z_]+\}'))));
  });

  test('só os testes selecionados aparecem em Testes e na tabela resumo, na ordem do catálogo', () {
    final doc = montar();
    final subtitulos = doc.blocos.whereType<BlocoTitulo>().where((t) => t.nivel == 2).map((t) => t.texto).toList();
    final nomePressao = TextosModeloRelatorio.ensaios[TipoEnsaio.pressao]!.nome;
    final nomeContagem = TextosModeloRelatorio.ensaios[TipoEnsaio.contagemParticulas]!.nome;
    expect(subtitulos, containsAllInOrder(['7.1. $nomePressao', '7.2. $nomeContagem']));
    expect(subtitulos.any((s) => s.contains(TextosModeloRelatorio.ensaios[TipoEnsaio.vazaoInsuflacao]!.nome)), isFalse);

    final resumo = doc.blocos.whereType<BlocoTabela>().firstWhere((t) => t.cabecalho.contains('Situação'));
    expect(resumo.linhas.map((l) => l[1]), [nomePressao, nomeContagem]);
    expect(resumo.linhas.first.sublist(3), ['2/2', 'Realizado']);
    expect(resumo.linhas.last.last, 'Pendente');
  });

  test('sala com duas máquinas aparece sob as duas; resultados vêm dos pontos', () {
    final doc = montar();
    final tabelasSalas = doc.blocos.whereType<BlocoTabela>().where((t) => t.cabecalho.first == 'Sala' && t.cabecalho.contains('Grau'));
    expect(tabelasSalas, hasLength(2));
    final resultados = doc.blocos.whereType<BlocoTabela>().firstWhere((t) => t.cabecalho.contains('Valor encontrado'));
    expect(resultados.linhas.map((l) => l[2]), ['12.5', '13']);
  });

  test('conclusão e paralelismo', () {
    expect(textoCompleto(montar()), contains('A definir na emissão.'));
    final emitido = montar(
      conclusao: const ConclusaoQualificacao(cumpre: true, comentarios: 'Ok'),
      paralelismo: const RegistroParalelismo(resultado: 'Linhas paralelas', fotoUrl: 'https://firebasestorage.googleapis.com/x.jpg'),
    );
    final texto = textoCompleto(emitido);
    expect(texto, contains('CUMPRE'));
    expect(texto, contains('(X) Sim'));
    expect(texto, contains('Linhas paralelas'));
    expect(emitido.blocos.whereType<BlocoImagem>().map((b) => b.legenda), contains('Paralelismo do fluxo de ar'));
  });

  test('sem testes selecionados', () {
    final doc = montar(ensaios: const []);
    expect(textoCompleto(doc), contains('Nenhum teste selecionado.'));
  });
}
