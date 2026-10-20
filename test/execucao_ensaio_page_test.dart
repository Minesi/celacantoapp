import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/captura_ocr_page.dart';
import 'package:celacantoapp/ensaio_model.dart';
import 'package:celacantoapp/execucao_database.dart';
import 'package:celacantoapp/execucao_ensaio_page.dart';
import 'package:celacantoapp/execucao_projeto_service.dart';
import 'package:celacantoapp/history_entry_model.dart';
import 'package:celacantoapp/instrumento_model.dart';
import 'package:celacantoapp/resultado_ensaio_model.dart';
import 'package:celacantoapp/sala_model.dart';

class _FakeExecucaoProjetoService implements ExecucaoProjetoService {
  final resultados = <ResultadoEnsaioModel>[];
  final historicos = <HistoryEntry>[];
  int sincronizacoes = 0;

  @override
  Future<void> atualizarFerramentasEscaneadas(String projetoId, Map<String, List<InstrumentoModel>> ferramentas) async {}

  @override
  Future<void> salvarResultadoEnsaio(ResultadoEnsaioModel resultado) async {
    resultados.add(resultado);
  }

  @override
  Future<void> sincronizarPontosLeitura(String projetoId) async {
    sincronizacoes++;
  }

  @override
  Future<void> adicionarHistorico(String projetoId, HistoryEntry entrada) async {
    historicos.add(entrada);
  }
}

class _FakeExecucaoDatabase implements ExecucaoDatabase {
  final pontos = <Map<String, dynamic>>[];

  @override
  Future<int> deletePontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async {
    pontos.removeWhere((ponto) => ponto['salaId'] == salaId && ponto['ensaioTipo'] == ensaioTipo);
    return 0;
  }

  @override
  Future<Map<String, dynamic>?> getResultadoEnsaio(String salaId, String ensaioTipo) async => null;

  @override
  Future<List<Map<String, dynamic>>> getPontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async =>
      pontos.where((ponto) => ponto['salaId'] == salaId && ponto['ensaioTipo'] == ensaioTipo).toList();

  @override
  Future<int> insertPontoLeitura(Map<String, dynamic> ponto) async {
    pontos.removeWhere((item) => item['id'] == ponto['id']);
    pontos.add(Map<String, dynamic>.from(ponto));
    return pontos.length;
  }
}

InstrumentoModel _instrumento(String tipo) => InstrumentoModel(
      tipo: tipo,
      tag: 'TAG-01',
      numeroSerie: 'SERIE-01',
      numeroCertificado: 'CERT-01',
      validade: '12/2099',
      estaValido: true,
      dominioEmpresa: 'teste.local',
    );

SalaModel _sala({TipoEnsaio? tipo}) => SalaModel(
      id: 'S1',
      nome: 'Sala 1',
      area: 10,
      volume: 30,
      grau: GrauSala.d,
      configEnsaios: tipo == null ? const {} : {tipo.name: {'pontos': '1'}},
    );

Widget _app({
  required EnsaioModel ensaio,
  required SalaModel sala,
  required _FakeExecucaoDatabase database,
  required _FakeExecucaoProjetoService projetoService,
  CapturadorFotoEvidencia? capturadorFoto,
  CapturadorOcr? capturadorOcr,
  String tipoProjeto = 'Fluxo Laminar',
  List<String> dimensoesPorPonto = const [],
}) {
  final instrumento = _instrumento(ensaio.ferramentasNecessarias.single);
  return MaterialApp(
    home: ExecucaoEnsaioPage(
      projetoId: 'P1',
      execucaoId: 'E1',
      tecnicoEmail: 'tecnico@teste.local',
      dataInicio: DateTime(2026, 10, 7),
      sala: sala,
      ensaio: ensaio,
      dominio: 'teste.local',
      tipoProjeto: tipoProjeto,
      dimensoesPorPonto: dimensoesPorPonto,
      rotulos: const ['Ponto 1'],
      filtroIds: const [null],
      dbHelper: database,
      projetoService: projetoService,
      ferramentasJaEscaneadas: {ensaio.ferramentasNecessarias.single: [instrumento]},
      capturadorFoto: capturadorFoto,
      capturadorOcr: capturadorOcr,
      enviarEvidencia: ({required caminhoArquivo, required caminhoStorage}) async =>
          'https://firebasestorage.googleapis.com/v0/b/teste/o/$caminhoStorage',
    ),
  );
}

const _verificacaoPesagem1 = '1 - O sentido do fluxo de ar é para o interior da cabine';
const _verificacaoPesagem2 = '2 - Não houve escape de ar do interior da cabine';

EnsaioModel _ensaioVisualizacao() => EnsaioModel(
      tipo: TipoEnsaio.visualizacaoFluxo,
      nome: 'Visualização do Fluxo de Ar',
      ferramentasNecessarias: const ['Máquina de Fumaça'],
    );

Finder _dropdownComRotulo(String rotulo) => find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField && widget.decoration.labelText == rotulo,
    );

Finder _campoComRotulo(String rotulo) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == rotulo,
    );

Future<void> _escolherOpcao(WidgetTester tester, Finder dropdown, String opcao) async {
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcao).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('usa capturador fake e exibe foto como anexada', (tester) async {
    var capturas = 0;
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    final ensaio = EnsaioModel(
      tipo: TipoEnsaio.visualizacaoFluxo,
      nome: 'Visualização do Fluxo de Ar',
      ferramentasNecessarias: const ['Máquina de Fumaça'],
    );

    await tester.pumpWidget(_app(
      ensaio: ensaio,
      sala: _sala(),
      database: database,
      projetoService: projetoService,
      capturadorFoto: (_) async {
        capturas++;
        return 'foto-fake.jpg';
      },
    ));
    await tester.pump();

    expect(find.text('Anexar Foto de Evidência'), findsOneWidget);
    await tester.tap(find.text('Anexar Foto de Evidência'));
    await tester.pumpAndSettle();

    expect(capturas, 1);
    expect(find.text('Foto Anexada ✓'), findsOneWidget);
  });

  testWidgets('mantém leituras separadas para repouso e operação', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    final ensaio = EnsaioModel(
      tipo: TipoEnsaio.contagemParticulas,
      nome: 'Contagem de Partículas',
      ferramentasNecessarias: const ['Contador de Partículas'],
    );

    await tester.pumpWidget(_app(
      ensaio: ensaio,
      sala: _sala(tipo: TipoEnsaio.contagemParticulas),
      database: database,
      projetoService: projetoService,
      capturadorFoto: (_) async => 'foto-fake.jpg',
    ));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Ponto 1 — 0,5µm'), '10');
    await tester.enterText(find.bySemanticsLabel('5µm'), '1');
    final estadoDropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(estadoDropdown);
    await tester.tap(estadoDropdown);
    await tester.pump();
    await tester.tap(find.text('Operação').last);
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('Ponto 1 — 0,5µm'), '20');
    await tester.enterText(find.bySemanticsLabel('5µm'), '2');

    final conformidadeDropdown = find.text('Selecione');
    await tester.ensureVisible(conformidadeDropdown);
    await tester.tap(conformidadeDropdown);
    await tester.pump();
    await tester.tap(find.text('Conforme').last);
    await tester.pump();
    await tester.tap(find.text('Anexar Foto de Evidência'));
    await tester.pumpAndSettle();
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();
    final pontos = database.pontos;
    expect(pontos, hasLength(2));
    expect(pontos.map((ponto) => ponto['estado']).toSet(), {'repouso', 'operacao'});
    expect(pontos.map((ponto) => ponto['id'].toString()).every((id) => id.contains('-')), isTrue);
    expect(projetoService.resultados, hasLength(1));
  });

  testWidgets('visualização da Pesagem fica conforme com as duas verificações conformes', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: _ensaioVisualizacao(),
      sala: _sala(tipo: TipoEnsaio.visualizacaoFluxo),
      database: database,
      projetoService: projetoService,
      tipoProjeto: EnsaioModel.tipoPesagem,
      capturadorFoto: (_) async => 'foto-fake.jpg',
    ));
    await tester.pump();

    await _escolherOpcao(tester, _dropdownComRotulo(_verificacaoPesagem1), 'Conforme');
    await _escolherOpcao(tester, _dropdownComRotulo(_verificacaoPesagem2), 'Conforme');
    await tester.enterText(_campoComRotulo('Tempo de dissipação (segundos)'), '30');
    await tester.tap(find.text('Anexar Foto de Evidência'));
    await tester.pumpAndSettle();
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();

    final resultado = projetoService.resultados.single;
    expect(resultado.conforme, isTrue);
    expect(resultado.dados['verificacoesVisualizacao'], [true, true]);
  });

  testWidgets('visualização da Pesagem reprova quando uma verificação não é conforme', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: _ensaioVisualizacao(),
      sala: _sala(tipo: TipoEnsaio.visualizacaoFluxo),
      database: database,
      projetoService: projetoService,
      tipoProjeto: EnsaioModel.tipoPesagem,
      capturadorFoto: (_) async => 'foto-fake.jpg',
    ));
    await tester.pump();

    await _escolherOpcao(tester, _dropdownComRotulo(_verificacaoPesagem1), 'Conforme');
    await _escolherOpcao(tester, _dropdownComRotulo(_verificacaoPesagem2), 'Não conforme');
    await tester.enterText(_campoComRotulo('Tempo de dissipação (segundos)'), '30');
    await tester.tap(find.text('Anexar Foto de Evidência'));
    await tester.pumpAndSettle();
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();

    expect(projetoService.resultados.single.conforme, isFalse);
  });

  testWidgets('velocidade da Pesagem usa o critério da média e calcula a vazão do filtro', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: _ensaioVelocidade(),
      sala: _sala(tipo: TipoEnsaio.velocidadeFluxo),
      database: database,
      projetoService: projetoService,
      tipoProjeto: EnsaioModel.tipoPesagem,
      dimensoesPorPonto: const ['1250 x 730'],
    ));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Ponto 1'), '0.46');
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();

    final resultado = projetoService.resultados.single;
    expect(resultado.conforme, isTrue);
    final vazoes = resultado.dados['vazaoPorFiltro'] as List;
    expect((vazoes.single as Map)['vazaoM3h'] as double, closeTo(1511.1, 0.01));
  });

  testWidgets('paralelismo da Pesagem calcula o ângulo por L e X e reprova acima de 14°', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: EnsaioModel(
        tipo: TipoEnsaio.paralelismoFluxo,
        nome: 'Paralelismo do Fluxo de Ar',
        ferramentasNecessarias: const ['Máquina de Fumaça'],
      ),
      sala: _sala(tipo: TipoEnsaio.paralelismoFluxo),
      database: database,
      projetoService: projetoService,
      tipoProjeto: EnsaioModel.tipoPesagem,
      capturadorFoto: (_) async => 'foto-fake.jpg',
    ));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('L (mm) — Ponto 1'), '900');
    await tester.enterText(find.bySemanticsLabel('X (mm) — Ponto 1'), '225');
    await tester.pump();
    await tester.tap(find.text('Anexar Foto de Evidência'));
    await tester.pumpAndSettle();
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();

    final resultado = projetoService.resultados.single;
    expect(database.pontos.single['valor05um'], '14.04');
    expect(resultado.conforme, isFalse);
    expect(resultado.dados['paralelismo'], [
      {'numeroPonto': 1, 'distanciaL': '900', 'distanciaX': '225'},
    ]);
  });

  testWidgets('ruído da Pesagem registra repouso e operação em pontos separados', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: EnsaioModel(
        tipo: TipoEnsaio.nivelRuido,
        nome: 'Nível de Ruído',
        ferramentasNecessarias: const ['Decibelímetro'],
      ),
      sala: _sala(tipo: TipoEnsaio.nivelRuido),
      database: database,
      projetoService: projetoService,
      tipoProjeto: EnsaioModel.tipoPesagem,
    ));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Ponto 1'), '70');
    final estadoDropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(estadoDropdown);
    await tester.tap(estadoDropdown);
    await tester.pump();
    await tester.tap(find.text('Operação').last);
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('Ponto 1'), '72');
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pumpAndSettle();

    expect(database.pontos.map((ponto) => ponto['estado']).toList(), ['repouso', 'operacao']);
    expect(database.pontos.map((ponto) => ponto['valor05um']).toList(), ['70', '72']);
    expect(projetoService.resultados.single.conforme, isTrue);
  });

  testWidgets('valor lido pela câmera fica marcado como ocr no histórico', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: _ensaioVelocidade(),
      sala: _sala(tipo: TipoEnsaio.velocidadeFluxo),
      database: database,
      projetoService: projetoService,
      capturadorOcr: (context, nomeFerramenta) async =>
          const ResultadoCapturaOcr(valores: ['0.46'], digitadosManualmente: [false]),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.document_scanner_outlined));
    await tester.pumpAndSettle();
    await _concluirComConformidade(tester);

    expect(database.pontos.single['valor05um'], '0.46');
    final leituras = projetoService.historicos.single.detalhes['leituras'] as List;
    expect(leituras.single['origem05um'], 'ocr');
  });

  testWidgets('valor digitado à mão fica marcado como manual no histórico', (tester) async {
    final database = _FakeExecucaoDatabase();
    final projetoService = _FakeExecucaoProjetoService();
    await tester.pumpWidget(_app(
      ensaio: _ensaioVelocidade(),
      sala: _sala(tipo: TipoEnsaio.velocidadeFluxo),
      database: database,
      projetoService: projetoService,
    ));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Ponto 1'), '0.5');
    await _concluirComConformidade(tester);

    expect(database.pontos.single['valor05um'], '0.5');
    final leituras = projetoService.historicos.single.detalhes['leituras'] as List;
    expect(leituras.single['origem05um'], 'manual');
    expect(projetoService.historicos.single.campo, 'leituras_ensaio');
  });
}

EnsaioModel _ensaioVelocidade() => EnsaioModel(
      tipo: TipoEnsaio.velocidadeFluxo,
      nome: 'Velocidade e Uniformidade do Fluxo de Ar',
      ferramentasNecessarias: const ['Anemômetro'],
    );

Future<void> _concluirComConformidade(WidgetTester tester) async {
  final conformidade = find.text('Selecione');
  await tester.ensureVisible(conformidade);
  await tester.tap(conformidade);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Conforme').last);
  await tester.pumpAndSettle();
  final concluir = find.text('Concluir Ensaio');
  await tester.ensureVisible(concluir);
  await tester.tap(concluir);
  await tester.pumpAndSettle();
}
