// integration_test/fluxo_elaboracao_campo_aprovacao_test.dart
//
// Teste ponto a ponto (Windows Desktop) do fluxo Elaboração -> Campo -> Aprovação:
//  1. Resumo do teste vinculado ao catálogo (testes_catalogo)
//  2. Máquina -> Salas -> Filtros definindo a quantidade de testes
//  3. Filtros G4/F9/H14 via dropdown
//  5. Pré-visualização lateral (desktop)
//  6/9. Separação por empresa/tipo/área/data (duplicidade + filtros de busca)
//  7. Bloqueio de ensaio pendente e finalização só com todos os testes ou supervisor
//  8. Revisão dos resultados antes da aprovação
//
// Credenciais: ver CREDENCIAIS_TESTE.md.
// Execução: flutter test integration_test/fluxo_elaboracao_campo_aprovacao_test.dart -d windows

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:celacantoapp/database_helper.dart';
import 'package:celacantoapp/filtro_model.dart';
import 'package:celacantoapp/firebase_options.dart';
import 'package:celacantoapp/main.dart' show MyApp;
import 'package:celacantoapp/projeto_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emailTeste = 'admin@celacanto.com';
  const senhaTeste = 'Senha@123';
  const dominioTeste = 'celacanto.com';
  const cnpjEmpresaTeste = '11.222.333/0001-81';
  const nomeFantasiaTeste = 'EMPRESA TESTE AUTOMATIZADO';
  const tagManometro = 'MAN-9001';
  final areaTeste = 'AREA E2E ${DateTime.now().millisecondsSinceEpoch}';
  final resumoTeste = 'Resumo E2E ${DateTime.now().millisecondsSinceEpoch}: diferencial entre salas.';

  final repaintKey = GlobalKey();
  final screenshotsDir = Directory('integration_test/screenshots/fluxo_elaboracao_campo');
  final passos = <String>[];
  var numeroPasso = 0;

  Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final limite = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Tempo esgotado esperando por: $finder');
  }

  Future<void> aguardar(WidgetTester tester, Duration duracao) async {
    final limite = DateTime.now().add(duracao);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await aguardar(tester, const Duration(milliseconds: 600));
  }

  Future<void> escolherNoDropdown(WidgetTester tester, Finder dropdown, String opcao) async {
    await tocar(tester, dropdown);
    await tester.tap(find.text(opcao).last);
    await aguardar(tester, const Duration(milliseconds: 600));
  }

  Future<void> capturar(WidgetTester tester, String rotulo, String verificacao) async {
    await aguardar(tester, const Duration(milliseconds: 300));
    final boundary = repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imagem = await boundary.toImage(pixelRatio: 1.0);
    final bytes = (await imagem.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    numeroPasso++;
    final nome = '${numeroPasso.toString().padLeft(2, '0')}_$rotulo.png';
    await File('${screenshotsDir.path}/$nome').writeAsBytes(bytes);
    passos.add('| ${numeroPasso.toString().padLeft(2, '0')} | $verificacao | OK | $nome |');
  }

  void registrar(String verificacao) {
    numeroPasso++;
    passos.add('| ${numeroPasso.toString().padLeft(2, '0')} | $verificacao | OK | - |');
  }

  Future<Map<String, dynamic>> projetoDoTeste() async {
    final projetos = await DatabaseHelper().getProjetos();
    final doTeste = projetos.where((p) => p['area'] == areaTeste).toList();
    expect(doTeste, hasLength(1), reason: 'Deve existir exatamente 1 pré-relatório para a área do teste');
    return doTeste.first;
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: -1);

    if (screenshotsDir.existsSync()) screenshotsDir.deleteSync(recursive: true);
    screenshotsDir.createSync(recursive: true);

    // Empresa e instrumento só no cache local, para não depender/alterar dados reais na nuvem.
    final db = DatabaseHelper();
    await db.insertEmpresa({
      'cnpj': cnpjEmpresaTeste,
      'razaoSocial': 'Empresa Teste Automatizado LTDA',
      'nomeFantasia': nomeFantasiaTeste,
      'dominio_empresa': dominioTeste,
    });
    await db.insertInstrumento({
      'id': 'teste-$tagManometro',
      'tipo': 'Manômetro',
      'tag': tagManometro,
      'numeroSerie': 'SN-TESTE',
      'numeroCertificado': 'CERT-TESTE',
      'validade': '12/2030',
      'estaValido': 1,
      'dominio_empresa': dominioTeste,
    });
  });

  tearDownAll(() async {
    final relatorio = StringBuffer()
      ..writeln('# Execução ponto a ponto — Elaboração → Campo → Aprovação')
      ..writeln()
      ..writeln('Data/Hora: ${DateTime.now()}  ')
      ..writeln('Usuário: $emailTeste  ')
      ..writeln('Área do teste: $areaTeste')
      ..writeln()
      ..writeln('| # | Verificação | Resultado | Evidência |')
      ..writeln('|---|---|---|---|')
      ..writeln(passos.join('\n'));
    await File('${screenshotsDir.path}/RELATORIO_EXECUCAO.md').writeAsString(relatorio.toString());
  });

  testWidgets('Elaboração -> Campo -> Revisão para aprovação', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(RepaintBoundary(key: repaintKey, child: const MyApp()));
    await aguardar(tester, const Duration(milliseconds: 500));

    // --- LOGIN ---
    final camposLogin = find.byType(TextFormField);
    await tester.enterText(camposLogin.at(0), emailTeste);
    await tester.enterText(camposLogin.at(1), senhaTeste);
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Entrar'));
    await waitFor(tester, find.text('Utilização do Relatório'));
    await capturar(tester, 'home', 'Login com admin@celacanto.com');

    // --- ELABORAÇÃO ---
    await tocar(tester, find.text('Elaboração do Relatório'));
    await waitFor(tester, find.text('Empresa Cliente'));
    expect(find.text('Pré-visualização do relatório'), findsOneWidget);
    await capturar(tester, 'elaboracao_vazia', 'Item 5: painel lateral de pré-visualização exibido no Windows');

    final dropdownsTexto = find.byType(DropdownButtonFormField<String>);
    await escolherNoDropdown(tester, dropdownsTexto.at(0), nomeFantasiaTeste);
    await escolherNoDropdown(tester, dropdownsTexto.at(1), 'HVAC');
    await tester.enterText(find.widgetWithText(TextField, 'Área atendida pelo sistema'), areaTeste);
    await tester.pump();

    // Sala exige máquina cadastrada antes.
    await tocar(tester, find.text('Adicionar Sala'));
    await waitFor(tester, find.text('Cadastre primeiro a máquina que atende a sala.'));
    registrar('Item 2: sala não pode ser criada sem máquina');

    // Máquina com filtro interno (informativo)
    await tocar(tester, find.text('Adicionar'));
    await waitFor(tester, find.text('Adicionar Máquina (Handling Unit)'));
    await tester.enterText(find.widgetWithText(TextField, 'Nome/Identificação da Máquina'), 'UTA-01');
    await tocar(tester, find.byIcon(Icons.add_circle));
    expect(find.text('G4 — 1 un.'), findsOneWidget);
    await capturar(tester, 'modal_maquina', 'Máquina UTA-01 com filtro interno G4 (padrão do dropdown)');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.textContaining('Salas atendidas: nenhuma'));

    Future<void> adicionarSala(String nome, String tipoFiltro, int qtd) async {
      await tocar(tester, find.text('Adicionar Sala'));
      await waitFor(tester, find.text('Filtros (saídas) da Sala'));
      await tester.enterText(find.widgetWithText(TextField, 'Nome da Sala'), nome);
      await tester.enterText(find.widgetWithText(TextField, 'Área (m²)'), '10');
      await tester.enterText(find.widgetWithText(TextField, 'Volume (m³)'), '30');
      final dropdownFiltro = find.byType(DropdownButtonFormField<TipoFiltro>);
      await tocar(tester, dropdownFiltro);
      expect(find.text('G4'), findsWidgets);
      expect(find.text('F9'), findsWidgets);
      expect(find.text('H14'), findsWidgets);
      await tester.tap(find.text(tipoFiltro).last);
      await aguardar(tester, const Duration(milliseconds: 600));
      await tester.enterText(find.widgetWithText(TextField, 'Qtd.'), '$qtd');
      await tocar(tester, find.byIcon(Icons.add_circle));
      expect(find.text('$tipoFiltro — $qtd un.'), findsOneWidget);
      await capturar(tester, 'modal_$nome'.replaceAll(' ', '_'), 'Item 3: sala $nome com filtro $tipoFiltro x$qtd via dropdown');
      await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
      await waitFor(tester, find.text('$nome — Grau D'));
    }

    await adicionarSala('SALA 01', 'H14', 2);
    await adicionarSala('SALA 02', 'F9', 1);
    expect(find.textContaining('Salas atendidas: SALA 01, SALA 02'), findsOneWidget);
    registrar('Item 2: máquina UTA-01 atende SALA 01 e SALA 02');

    // Ensaio + resumo
    await tocar(tester, find.text('Diferença de Pressão'));
    await waitFor(tester, find.widgetWithText(TextField, 'Resumo do teste'));
    await tester.enterText(find.widgetWithText(TextField, 'Resumo do teste'), resumoTeste);
    await aguardar(tester, const Duration(milliseconds: 500));

    // Prévia: 1 linha por unidade de filtro de cada sala + resumo
    expect(find.text('Filtro 1 (H14)'), findsOneWidget);
    expect(find.text('Filtro 2 (H14)'), findsOneWidget);
    expect(find.text('Filtro 1 (F9)'), findsOneWidget);
    expect(find.text(resumoTeste), findsNWidgets(2));
    await capturar(tester, 'elaboracao_completa', 'Itens 1/2/5: prévia com resumo e tabela salas × filtros (3 linhas)');

    await tocar(tester, find.text('Concluir Elaboração'));
    await waitFor(tester, find.text('Projetos Realizados'));

    // Verificações de persistência
    final db = DatabaseHelper();
    final projeto = await projetoDoTeste();
    final projetoId = projeto['id'].toString();
    expect(projeto['status'], 'prontoParaCampo');
    final salas = await db.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnits = await db.getHandlingUnitsPorProjeto(projetoId);
    expect(salas, hasLength(2));
    expect(handlingUnits, hasLength(1));
    expect(salas.every((s) => s['handlingUnitId'] == handlingUnits.first['id']), isTrue);
    final filtrosSala1 = (salas.firstWhere((s) => s['nome'] == 'SALA 01')['filtros'] as List);
    expect(filtrosSala1.single['tipo'], 'h14');
    expect(filtrosSala1.single['quantidade'], 2);
    registrar('Item 2: salas gravadas com máquina e filtros (SQLite)');

    final catalogo = await db.getTesteCatalogo(dominioTeste, 'pressao');
    expect(catalogo?['resumo'], resumoTeste);
    registrar('Item 1: resumo gravado em testes_catalogo (domínio $dominioTeste)');

    final dataCriacao = DateTime.parse(projeto['dataCriacao'].toString());
    final service = ProjetoService();
    expect(
      await service.existeDuplicata(cnpjEmpresa: cnpjEmpresaTeste, tipoProjeto: 'HVAC', area: areaTeste, dataHora: dataCriacao),
      isTrue,
    );
    expect(
      await service.existeDuplicata(
        cnpjEmpresa: cnpjEmpresaTeste,
        tipoProjeto: 'HVAC',
        area: areaTeste,
        dataHora: dataCriacao.add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    registrar('Item 6: duplicidade detectada no mesmo minuto e liberada no minuto seguinte');

    // --- CAMPO ---
    await tocar(tester, find.text('Utilização do Relatório'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    final cardDoProjeto = find.descendant(of: find.byType(ListTile), matching: find.textContaining(areaTeste));
    await waitFor(tester, cardDoProjeto);
    await capturar(tester, 'campo_lista_filtrada', 'Item 9: lista do técnico filtrada por área');
    await tocar(tester, cardDoProjeto.first);
    await waitFor(tester, find.text('Testes realizados: 0 de 3'));
    expect(find.text('Máquina: UTA-01'), findsOneWidget);
    await capturar(tester, 'campo_inicio', 'Item 7: 3 testes exigidos (2 filtros SALA 01 + 1 filtro SALA 02)');

    // Sai de um ensaio sem concluir -> ele fica pendente e bloqueia os demais
    await tocar(tester, find.text('Diferença de Pressão (0/1)'));
    await waitFor(tester, find.text('Concluir Ensaio'));
    expect(find.widgetWithText(TextField, 'Filtro 1 (F9)'), findsOneWidget);
    await tester.pageBack();
    await waitFor(tester, find.text('Testes realizados: 0 de 3'));
    await tocar(tester, find.text('Diferença de Pressão (0/2)'));
    await waitFor(tester, find.textContaining('Finalize (ou solicite liberação do supervisor para)'));
    await capturar(tester, 'campo_bloqueio_pendente', 'Item 7: outro ensaio bloqueado enquanto há ensaio pendente');

    // Conclui o ensaio da SALA 02
    await tocar(tester, find.text('Diferença de Pressão (0/1)'));
    await waitFor(tester, find.text('Concluir Ensaio'));
    await tocar(tester, find.byIcon(Icons.keyboard));
    await waitFor(tester, find.text('Digitar TAG para Manômetro'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), tagManometro);
    await tocar(tester, find.text('Validar'));
    await waitFor(tester, find.descendant(of: find.byType(Chip), matching: find.text(tagManometro)));
    await tester.enterText(find.widgetWithText(TextField, 'Filtro 1 (F9)'), '12.5');
    await capturar(tester, 'campo_execucao_sala02', 'Item 7: ponto por filtro (Filtro 1 (F9)) preenchido');
    await tocar(tester, find.text('Concluir Ensaio'));
    await waitFor(tester, find.text('Testes realizados: 1 de 3'));
    expect(find.text('Diferença de Pressão (1/1)'), findsOneWidget);

    // Finalizar com testes faltando exige supervisor
    await tocar(tester, find.text('Finalizar Relatório (requer supervisor)'));
    await waitFor(tester, find.text('Testes Pendentes'));
    expect(find.textContaining('Foram realizados 1 de 3 testes'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'E-mail do Supervisor'), emailTeste);
    await tester.enterText(find.widgetWithText(TextField, 'Senha de Liberação'), 'senha-errada');
    await tocar(tester, find.text('Autorizar'));
    await waitFor(tester, find.text('Credenciais inválidas ou usuário sem nível de Supervisor!'));
    await capturar(tester, 'campo_liberacao_negada', 'Item 7: senha errada do supervisor recusada');

    // No desktop, um segundo enterText no mesmo diálogo cai no campo que já tinha foco: grava direto.
    tester.widget<TextField>(find.widgetWithText(TextField, 'Senha de Liberação')).controller!.text = senhaTeste;
    await tester.pump();
    String textoDoCampo(String rotulo) => tester.widget<TextField>(find.widgetWithText(TextField, rotulo)).controller!.text;
    expect(textoDoCampo('E-mail do Supervisor'), emailTeste);
    expect(textoDoCampo('Senha de Liberação'), senhaTeste);
    await tocar(tester, find.text('Autorizar'));
    try {
      await waitFor(tester, find.text('Relatório finalizado e enviado para revisão.'), timeout: const Duration(seconds: 60));
    } on TestFailure {
      await capturar(tester, 'FALHA_finalizacao', 'Estado da tela na falha da finalização');
      rethrow;
    }
    await capturar(tester, 'campo_finalizado', 'Item 7: relatório finalizado com liberação do supervisor');

    final projetoFinalizado = await projetoDoTeste();
    expect(projetoFinalizado['status'], 'emRevisao');
    final historico = List<Map<String, dynamic>>.from(jsonDecode(projetoFinalizado['history'].toString()));
    expect(historico.any((h) => h['campo'] == 'liberacao_testes_pendentes'), isTrue);
    final pontos = await db.getPontosLeituraPorProjeto(projetoId);
    expect(pontos, hasLength(1));
    expect(pontos.single['filtroId'], isNotEmpty);
    registrar('Item 7: status em revisão + histórico da liberação + ponto vinculado ao filtro');

    // --- APROVAÇÃO (revisão antes de aprovar) ---
    await tester.pageBack();
    await waitFor(tester, find.text('Projetos Realizados'));
    await tocar(tester, find.text('Projetos Realizados'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    await waitFor(tester, find.byIcon(Icons.task_alt));
    await capturar(tester, 'aprovacao_lista', 'Item 9: lista de aprovação filtrada por área');
    await tocar(tester, find.byIcon(Icons.task_alt));
    await waitFor(tester, find.text('Revisão dos Resultados'));
    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text(resumoTeste), findsOneWidget);
    expect(find.text('Aprovar e gerar relatório'), findsOneWidget);
    await capturar(tester, 'aprovacao_revisao', 'Item 8: supervisor vê resultados (12.5) e pendências (—) antes de aprovar');

    await tester.pageBack();
    await waitFor(tester, find.byIcon(Icons.task_alt));
    expect((await projetoDoTeste())['status'], 'emRevisao');
    registrar('Item 8: voltar da revisão não aprova o relatório');

    // --- EMISSÃO DO RELATÓRIO (Cloud Function gerarRelatorioDocx) ---
    // Espera a tela de revisão sair: o botão dela também usa o ícone task_alt.
    await aguardar(tester, const Duration(seconds: 1));
    await tocar(tester, find.byIcon(Icons.task_alt));
    await waitFor(tester, find.text('Aprovar e gerar relatório'));
    await aguardar(tester, const Duration(seconds: 1));
    await tocar(tester, find.text('Aprovar e gerar relatório').last);
    final sucesso = find.text('Relatório aprovado e gerado com sucesso!');
    bool ehFalha(String? t) => t != null && (t.contains('Não foi possível gerar o relatório') || t.contains('Falha ao aprovar'));
    final falha = find.byWidgetPredicate((w) => w is Text && ehFalha(w.data));
    await waitFor(
      tester,
      find.byWidgetPredicate((w) => w is Text && (w.data == 'Relatório aprovado e gerado com sucesso!' || ehFalha(w.data))),
      timeout: const Duration(seconds: 120),
    );
    if (falha.evaluate().isNotEmpty) {
      await capturar(tester, 'FALHA_emissao', 'Falha na emissão do relatório');
      fail('Emissão falhou: ${(tester.widget<Text>(falha.first)).data}');
    }
    expect(sucesso, findsOneWidget);
    await capturar(tester, 'relatorio_emitido', 'Emissão: relatório aprovado e .docx gerado pela Cloud Function (Node 22)');

    expect((await projetoDoTeste())['status'], 'aprovado');
    final downloads = Platform.environment['USERPROFILE']!;
    final arquivo = File('$downloads/Downloads/Celacanto/Relatorio_$projetoId.docx');
    expect(arquivo.existsSync(), isTrue, reason: 'Relatório não encontrado em ${arquivo.path}');
    expect(arquivo.lengthSync(), greaterThan(1000));
    registrar('Emissão: status aprovado e arquivo ${arquivo.path} (${arquivo.lengthSync()} bytes)');
  });
}
