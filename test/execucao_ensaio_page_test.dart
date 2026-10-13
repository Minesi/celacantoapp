import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:celacantoapp/ensaio_model.dart';
import 'package:celacantoapp/execucao_database.dart';
import 'package:celacantoapp/execucao_ensaio_page.dart';
import 'package:celacantoapp/execucao_projeto_service.dart';
import 'package:celacantoapp/instrumento_model.dart';
import 'package:celacantoapp/resultado_ensaio_model.dart';
import 'package:celacantoapp/sala_model.dart';

class _FakeExecucaoProjetoService implements ExecucaoProjetoService {
  final resultados = <ResultadoEnsaioModel>[];
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
      rotulos: const ['Ponto 1'],
      filtroIds: const [null],
      dbHelper: database,
      projetoService: projetoService,
      ferramentasJaEscaneadas: {ensaio.ferramentasNecessarias.single: [instrumento]},
      capturadorFoto: capturadorFoto,
    ),
  );
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
    await tester.pump();

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
    await tester.pump();
    final concluir = find.text('Concluir Ensaio');
    await tester.ensureVisible(concluir);
    await tester.tap(concluir);
    await tester.pump();
    final pontos = database.pontos;
    expect(pontos, hasLength(2));
    expect(pontos.map((ponto) => ponto['estado']).toSet(), {'repouso', 'operacao'});
    expect(pontos.map((ponto) => ponto['id'].toString()).every((id) => id.contains('-')), isTrue);
    expect(projetoService.resultados, hasLength(1));
  });
}
