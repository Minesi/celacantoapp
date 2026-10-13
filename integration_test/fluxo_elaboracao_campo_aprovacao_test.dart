// integration_test/fluxo_elaboracao_campo_aprovacao_test.dart
//
// E2E (Windows Desktop) de um projeto Fluxo Laminar: Elaboração -> Campo -> Revisão/Aprovação
// -> emissão pelo modelo do cliente (gerarRelatorioDocx) -> envio real por e-mail.
// Grava dados reais e permanentes no Firebase (projeto aprovado, DOCX no Storage, e-mail).
//
// Execução a partir da raiz do projeto:
//   flutter test integration_test/fluxo_elaboracao_campo_aprovacao_test.dart -d windows \
//     --dart-define=E2E_EMAIL=<admin> --dart-define=E2E_SENHA=<senha>

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:celacantoapp/database_helper.dart';
import 'package:celacantoapp/firebase_options.dart';
import 'package:celacantoapp/main.dart' show MyApp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emailTeste = String.fromEnvironment('E2E_EMAIL');
  const senhaTeste = String.fromEnvironment('E2E_SENHA');
  const semCredenciais = emailTeste == '' || senhaTeste == '';
  final dominioTeste = emailTeste.split('@').last.toLowerCase();
  const cnpjEmpresaTeste = '11.222.333/0001-81';
  const nomeFantasiaTeste = 'EMPRESA TESTE AUTOMATIZADO';
  const tipoProjeto = 'Fluxo Laminar';
  const nomeMaquina = 'FLUXO-01';
  const nomeSala = 'SALA 01';
  const tagFotometro = 'FOT-9001';
  const tagManometro = 'MAN-9001';
  final marca = DateTime.now().millisecondsSinceEpoch;
  final nomeSistemaTeste = 'SISTEMA E2E $marca';
  final areaTeste = 'AREA E2E $marca';
  final tagInexistente = 'E2E-INEXISTENTE-$marca';
  const observacoesRevisao = 'Revisão E2E confirmada pelo supervisor.';

  final repaintKey = GlobalKey();
  final screenshotsDir = Directory('integration_test/screenshots/fluxo_elaboracao_campo');
  final passos = <String>[];
  var numeroPasso = 0;
  String? projetoIdExecucao;
  String? registroEmail;

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

  void anotar(String verificacao, {String resultado = 'OK', String evidencia = '-'}) {
    numeroPasso++;
    passos.add('| ${numeroPasso.toString().padLeft(2, '0')} | $verificacao | $resultado | $evidencia |');
  }

  Future<void> capturar(WidgetTester tester, String rotulo, String verificacao, {String resultado = 'OK'}) async {
    await aguardar(tester, const Duration(milliseconds: 300));
    final boundary = repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imagem = await boundary.toImage(pixelRatio: 1.0);
    final bytes = (await imagem.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final nome = '${(numeroPasso + 1).toString().padLeft(2, '0')}_$rotulo.png';
    await File('${screenshotsDir.path}/$nome').writeAsBytes(bytes);
    anotar(verificacao, resultado: resultado, evidencia: nome);
  }

  Future<Map<String, dynamic>> projetoDoTeste() async {
    final projetos = await DatabaseHelper().getProjetos();
    final doTeste = projetos.where((p) => p['area'] == areaTeste).toList();
    expect(doTeste, hasLength(1), reason: 'Deve existir exatamente 1 projeto para a área do teste');
    return doTeste.first;
  }

  Future<void> aguardarStatus(String status, {Duration timeout = const Duration(seconds: 30)}) async {
    final limite = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(limite)) {
      if ((await projetoDoTeste())['status'] == status) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TestFailure('Projeto não chegou ao status $status');
  }

  String textoDoDocx(File arquivo) {
    final zip = ZipDecoder().decodeBytes(arquivo.readAsBytesSync());
    final documento = zip.findFile('word/document.xml');
    expect(documento, isNotNull, reason: 'DOCX sem word/document.xml');
    final xml = utf8.decode(documento!.content as List<int>);
    return xml.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  setUpAll(() async {
    if (semCredenciais) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: -1);

    if (screenshotsDir.existsSync()) screenshotsDir.deleteSync(recursive: true);
    screenshotsDir.createSync(recursive: true);

    // Empresa e instrumentos só no cache local, para não alterar cadastros reais na nuvem.
    final db = DatabaseHelper();
    await db.insertEmpresa({
      'cnpj': cnpjEmpresaTeste,
      'razaoSocial': 'Empresa Teste Automatizado LTDA',
      'nomeFantasia': nomeFantasiaTeste,
      'dominio_empresa': dominioTeste,
    });
    for (final (tipo, tag) in [('Fotômetro', tagFotometro), ('Manômetro', tagManometro)]) {
      await db.insertInstrumento({
        'id': 'teste-$tag',
        'tipo': tipo,
        'tag': tag,
        'numeroSerie': 'SN-$tag',
        'numeroCertificado': 'CERT-$tag',
        'validade': '12/2030',
        'estaValido': 1,
        'dominio_empresa': dominioTeste,
      });
    }
  });

  tearDownAll(() async {
    if (semCredenciais) return;
    final relatorio = StringBuffer()
      ..writeln('# Execução E2E — Fluxo Laminar: Elaboração → Campo → Aprovação → Emissão')
      ..writeln()
      ..writeln('Data/Hora: ${DateTime.now()}  ')
      ..writeln('Usuário: $emailTeste  ')
      ..writeln('Área do teste: $areaTeste  ')
      ..writeln('Projeto: ${projetoIdExecucao ?? '-'}  ')
      ..writeln('Registro de e-mail: ${registroEmail ?? '-'}')
      ..writeln()
      ..writeln('| # | Verificação | Resultado | Evidência |')
      ..writeln('|---|---|---|---|')
      ..writeln(passos.join('\n'));
    await File('${screenshotsDir.path}/RELATORIO_EXECUCAO.md').writeAsString(relatorio.toString());
  });

  testWidgets('Fluxo Laminar: elaboração -> campo -> aprovação -> emissão e e-mail', (tester) async {
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
    await capturar(tester, 'home', 'Login com $emailTeste');

    // A emissão no servidor exige a empresa na nuvem; não é criada aqui (o doc ID é o domínio).
    final empresas = await FirebaseFirestore.instance
        .collection('empresas')
        .where('cnpj', isEqualTo: cnpjEmpresaTeste)
        .limit(1)
        .get();
    expect(empresas.docs, isNotEmpty, reason: 'Empresa $cnpjEmpresaTeste precisa existir no Firestore');
    final empresaNuvem = empresas.docs.first.data();
    final nomeEmpresaNuvem = (empresaNuvem['nome_fantasia'] ?? empresaNuvem['nomeFantasia'] ?? cnpjEmpresaTeste).toString();
    anotar('Empresa $cnpjEmpresaTeste encontrada no Firestore ($nomeEmpresaNuvem)');
    final usuarios = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('email', isEqualTo: emailTeste.toLowerCase())
        .limit(1)
        .get();
    final nomeUsuario = usuarios.docs.isEmpty ? '' : (usuarios.docs.first.data()['nome'] ?? '').toString();

    // --- ELABORAÇÃO ---
    await tocar(tester, find.text('Elaboração do Relatório'));
    await waitFor(tester, find.text('Empresa Cliente'));
    final dropdownsTexto = find.byType(DropdownButtonFormField<String>);
    await escolherNoDropdown(tester, dropdownsTexto.at(0), nomeFantasiaTeste);
    await escolherNoDropdown(tester, dropdownsTexto.at(1), tipoProjeto);
    await tester.enterText(find.widgetWithText(TextField, 'Área atendida pelo sistema'), areaTeste);
    await tester.pump();

    await tocar(tester, find.text('Novo Sistema'));
    await waitFor(tester, find.byType(AlertDialog));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), nomeSistemaTeste);
    await tocar(tester, find.text('Criar'));
    await waitFor(tester, find.text(nomeSistemaTeste));

    await tocar(tester, find.text('Adicionar Sala'));
    await waitFor(tester, find.text('Cadastre primeiro a máquina que atende a sala.'));
    anotar('Sala não pode ser criada sem máquina');

    await tocar(tester, find.text('Adicionar'));
    await waitFor(tester, find.text('Adicionar Máquina (Handling Unit)'));
    await tester.enterText(find.widgetWithText(TextField, 'Nome/Identificação da Máquina'), nomeMaquina);
    // Linhas padrão do editor: G4, F9, H14.
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').at(2), '2');
    await aguardar(tester, const Duration(milliseconds: 300));
    await capturar(tester, 'modal_maquina', 'Máquina $nomeMaquina com 2× H14');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.textContaining('2× H14'));

    await tocar(tester, find.text('Adicionar Sala'));
    await waitFor(tester, find.text('Filtros da Sala'));
    await tester.enterText(find.widgetWithText(TextField, 'Nome da Sala'), nomeSala);
    await tester.enterText(find.widgetWithText(TextField, 'Área (m²)'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Volume (m³)'), '30');
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').first, '2');
    await aguardar(tester, const Duration(milliseconds: 300));
    await capturar(tester, 'modal_sala', 'Sala $nomeSala com os 2 filtros H14 da máquina alocados');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.text('$nomeSala — Grau D'));

    // Só Integridade: Contagem de Partículas exige foto, indisponível no Windows.
    await tocar(tester, find.text('Integridade de Filtros').first);
    await aguardar(tester, const Duration(milliseconds: 500));
    expect(find.text('Filtro 1 (H14)'), findsWidgets);
    expect(find.text('Filtro 2 (H14)'), findsWidgets);
    await capturar(tester, 'elaboracao_completa', 'Prévia com Integridade de Filtros em 2 pontos H14');

    await tocar(tester, find.text('Concluir Elaboração'));
    try {
      await waitFor(tester, find.text('Projetos Realizados'));
    } on TestFailure {
      await capturar(tester, 'FALHA_concluir_elaboracao', 'Concluir Elaboração', resultado: 'FALHA');
      rethrow;
    }

    final db = DatabaseHelper();
    final projeto = await projetoDoTeste();
    final projetoId = projeto['id'].toString();
    projetoIdExecucao = projetoId;
    expect(projeto['status'], 'prontoParaCampo');
    expect(projeto['tipoProjeto'], tipoProjeto);
    final salas = await db.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnits = await db.getHandlingUnitsPorProjeto(projetoId);
    expect(handlingUnits.single['nome'], nomeMaquina);
    expect(salas.single['nome'], nomeSala);
    expect(salas.single['handlingUnitId'], handlingUnits.single['id']);
    final filtrosSala = salas.single['filtros'] as List;
    expect(filtrosSala.single['tipo'], 'h14');
    expect(filtrosSala.single['quantidade'], 2);
    anotar('Projeto $projetoId pronto para campo com máquina, sala e 2 H14 alocados');

    // --- CAMPO ---
    await tocar(tester, find.text('Utilização do Relatório'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    final cardDoProjeto = find.descendant(of: find.byType(ListTile), matching: find.textContaining(areaTeste));
    await waitFor(tester, cardDoProjeto);
    await capturar(tester, 'campo_lista', 'Lista do técnico filtrada por área');
    await tocar(tester, cardDoProjeto.first);
    await waitFor(tester, find.text('Ferramentas do relatório'));

    Future<void> digitarTag(String tag) async {
      await tocar(tester, find.byIcon(Icons.keyboard));
      await waitFor(tester, find.text('Digitar TAG para Fotômetro'));
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), tag);
      await tocar(tester, find.text('Validar'));
    }

    await digitarTag(tagInexistente);
    await waitFor(tester, find.text('Ferramenta "$tagInexistente" não encontrada.'));
    anotar('TAG inexistente rejeitada');
    await digitarTag(tagManometro);
    await waitFor(tester, find.textContaining('pertence a "Manômetro"'));
    anotar('TAG de outro tipo (Manômetro) rejeitada para Fotômetro');
    await digitarTag(tagFotometro);
    await waitFor(tester, find.descendant(of: find.byType(Chip), matching: find.text(tagFotometro)));
    await capturar(tester, 'campo_ferramentas', 'Fotômetro $tagFotometro validado');
    await tocar(tester, find.text('Continuar para as salas'));
    await waitFor(tester, find.text('Testes realizados: 0 de 2'));
    final botaoEnsaio = find.text('Integridade de Filtros (0/2)');
    expect(botaoEnsaio, findsOneWidget);

    await tocar(tester, find.text('Finalizar Relatório (requer supervisor)'));
    await waitFor(tester, find.text('Testes Pendentes'));
    expect(find.text('Justificativa do técnico'), findsOneWidget);
    expect(find.text('Código do autenticador'), findsOneWidget);
    expect(find.text('Sem internet'), findsOneWidget);
    await capturar(tester, 'campo_liberacao_pendentes', 'Finalizar com pendências exige liberação (TOTP/offline); cancelado');
    await tocar(tester, find.text('Cancelar'));

    await tocar(tester, botaoEnsaio);
    await waitFor(tester, find.text('Concluir Ensaio'));
    await tester.enterText(find.widgetWithText(TextField, 'Filtro 1 (H14)'), '0.005');
    await tocar(tester, find.text('Encerrar Incompleto (requer supervisor)'));
    await waitFor(tester, find.text('Teste Incompleto'));
    expect(find.text('Código do autenticador'), findsOneWidget);
    anotar('Encerramento incompleto exige liberação do supervisor; cancelado');
    await tocar(tester, find.text('Cancelar'));

    await tester.enterText(find.widgetWithText(TextField, 'Filtro 2 (H14)'), '0.008');
    await escolherNoDropdown(
      tester,
      find.byType(DropdownButtonFormField<bool?>),
      'Conforme',
    );
    await capturar(tester, 'campo_execucao', 'Integridade: 2 pontos H14 preenchidos');
    await tocar(tester, find.text('Concluir Ensaio'));
    await waitFor(tester, find.text('Testes realizados: 2 de 2'));
    await aguardarStatus('emRevisao');
    await waitFor(tester, find.text('Relatório já finalizado (em revisão/aprovado).'));
    expect(find.text('Finalizar Relatório'), findsNothing);
    await capturar(tester, 'campo_concluido', 'Todos os testes feitos: relatório enviado para revisão');

    final projetoEmRevisao = await projetoDoTeste();
    final historicoCampo = List<Map<String, dynamic>>.from(jsonDecode(projetoEmRevisao['history'].toString()));
    expect(historicoCampo.where((h) => h['campo'] == 'execucao_fim'), isNotEmpty);
    expect(historicoCampo.any((h) => h['campo'].toString().startsWith('liberacao')), isFalse);
    final pontos = await db.getPontosLeituraPorProjeto(projetoId);
    expect(pontos.map((p) => p['valor05um']).toSet(), {'0.005', '0.008'});
    expect(pontos.every((p) => (p['filtroId']?.toString() ?? '').isNotEmpty), isTrue);
    anotar('Status em revisão; 2 pontos gravados e vinculados aos filtros');

    // --- REVISÃO E APROVAÇÃO ---
    // Execução usa seta própria para voltar à lista; a lista volta à home pelo BackButton padrão.
    await tocar(tester, find.byIcon(Icons.arrow_back));
    await waitFor(tester, find.text('Utilização do Relatório'));
    await tester.pageBack();
    await waitFor(tester, find.text('Projetos Realizados'));
    await tocar(tester, find.text('Projetos Realizados'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    await waitFor(tester, find.byIcon(Icons.task_alt));
    await tocar(tester, find.byIcon(Icons.task_alt));
    await waitFor(tester, find.text('Revisão dos Resultados'));
    expect(find.textContaining('Principal: 0.005'), findsOneWidget);

    await tocar(tester, find.byIcon(Icons.edit_outlined).first);
    await waitFor(tester, find.text('Editar ponto 1'));
    await tester.enterText(find.widgetWithText(TextField, 'Resultado principal'), '0.006');
    await tocar(tester, find.text('Aplicar correção'));
    await waitFor(tester, find.textContaining('Principal: 0.006'));
    await tester.enterText(find.widgetWithText(TextField, 'Observações da revisão'), observacoesRevisao);
    await capturar(tester, 'revisao_correcao', 'Supervisor corrige ponto 1 de 0.005 para 0.006');
    await tocar(tester, find.text('Continuar para aprovação'));
    await waitFor(tester, find.text('Aprovar relatório?'));
    await tocar(tester, find.text('Aprovar definitivamente'));
    await waitFor(tester, find.text('Conclusão da qualificação'));
    await tocar(tester, find.text('Cumpre'));
    await capturar(tester, 'emissao_conclusao', 'Conclusão "Cumpre" antes da emissão');
    await tocar(tester, find.text('Emitir relatório'));

    const sucesso = 'Relatório aprovado, gerado e enviado por e-mail com sucesso!';
    bool ehFalha(String t) =>
        t.startsWith('Relatório aprovado e gerado. O e-mail não foi enviado') ||
        t.startsWith('Relatório aprovado, mas a geração falhou') ||
        t.startsWith('Falha ao aprovar/gerar relatório');
    final resultadoEmissao = find.byWidgetPredicate((w) => w is Text && w.data != null && (w.data == sucesso || ehFalha(w.data!)));
    await waitFor(tester, resultadoEmissao, timeout: const Duration(seconds: 330));
    final mensagem = tester.widget<Text>(resultadoEmissao.first).data!;
    if (mensagem != sucesso) {
      await capturar(tester, 'FALHA_emissao', 'Emissão/e-mail: $mensagem', resultado: 'FALHA');
      fail(mensagem);
    }
    await capturar(tester, 'relatorio_emitido', 'Relatório Fluxo Laminar aprovado, gerado e enviado por e-mail');

    await waitFor(tester, find.text('Relatório pronto'));
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Imprimir'), findsOneWidget);
    expect(find.text('Reenviar e-mail'), findsOneWidget);
    await tocar(tester, find.text('Fechar'));

    final projetoAprovado = await projetoDoTeste();
    expect(projetoAprovado['status'], 'aprovado');
    final historico = List<Map<String, dynamic>>.from(jsonDecode(projetoAprovado['history'].toString()));
    final aprovacao = historico.lastWhere((h) => h['campo'] == 'status' && h['valorNovo'] == 'aprovado');
    expect(((aprovacao['detalhes'] as Map)['conclusao'] as Map)['cumpre'], isTrue);
    expect((aprovacao['detalhes'] as Map)['observacoesRevisao'], observacoesRevisao);
    expect(
      historico.any((h) => h['campo'] == 'pontoLeitura.valor05um' && h['valorAntigo'] == '0.005' && h['valorNovo'] == '0.006'),
      isTrue,
    );
    anotar('Status aprovado; conclusão, observações e correção 0.005 → 0.006 no histórico');

    // --- E-MAIL (auditoria server-side) ---
    QueryDocumentSnapshot<Map<String, dynamic>>? envio;
    final limiteEmail = DateTime.now().add(const Duration(seconds: 30));
    while (envio == null && DateTime.now().isBefore(limiteEmail)) {
      final envios = await FirebaseFirestore.instance
          .collection('relatorios_email')
          .where('projetoId', isEqualTo: projetoId)
          .get(const GetOptions(source: Source.server));
      envio = envios.docs.where((d) => d.data()['status'] == 'enviado').firstOrNull;
        if (envio == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
    }
    expect(envio, isNotNull, reason: 'Nenhum registro "enviado" em relatorios_email para $projetoId');
    expect(envio!.data()['destinatario'], emailTeste.toLowerCase());
    registroEmail = 'relatorios_email/${envio.id}';
    anotar('E-mail registrado como enviado para $emailTeste ($registroEmail)');

    // --- CONTEÚDO DO DOCX ---
    final downloads = Platform.environment['USERPROFILE']!;
    final arquivo = File('$downloads/Downloads/Celacanto/Relatorio_$projetoId.docx');
    expect(arquivo.existsSync(), isTrue, reason: 'Relatório não encontrado em ${arquivo.path}');
    final texto = textoDoDocx(arquivo);
    for (final esperado in [nomeEmpresaNuvem, areaTeste, nomeMaquina]) {
      expect(texto, contains(esperado), reason: 'DOCX sem "$esperado"');
    }
    expect(
      texto.contains(emailTeste) || (nomeUsuario.isNotEmpty && texto.contains(nomeUsuario)),
      isTrue,
      reason: 'DOCX sem técnico/revisor',
    );
    for (final esperado in ['REGISTRO ESTRUTURADO DOS ENSAIOS', nomeSala, 'Filtro 1 (H14)', 'Filtro 2 (H14)']) {
      expect(texto, contains(esperado), reason: 'DOCX sem tabela escalável "$esperado"');
    }
    expect(RegExp(r'\{[A-ZÀ-Ú ]+\}').hasMatch(texto), isFalse, reason: 'DOCX com placeholder sem substituição');
    anotar('DOCX ${arquivo.path}: cliente, área, equipamento e técnico preenchidos');

    final textoMaiusculo = texto.toUpperCase();
    expect(textoMaiusculo, contains('ANEXO 1 - INTEGRIDADE E ESTANQUEIDADE'));
    expect(textoMaiusculo, contains('ANEXO 2 – VERIFICAÇÃO DA CALIBRAÇÃO'));
    for (final ausente in [
      'AVALIAÇÃO DO SISTEMA DE FILTRAGEM',
      'VELOCIDADE E UNIFORMIDADE',
      'NÍVEL DE RUÍDO',
      'INTENSIDADE LUMINOSA',
      'CONTAGEM DE PARTÍCULAS NÃO VIÁVEIS',
      'VISUALIZAÇÃO DO FLUXO DE AR',
      'PARALELISMO DO FLUXO DE AR',
    ]) {
      expect(textoMaiusculo.contains(ausente), isFalse, reason: 'DOCX não deveria conter "$ausente"');
    }
    anotar('DOCX traz só o teste executado (Integridade = Anexo 1) e anexos renumerados em sequência');
    if (nomeUsuario.isNotEmpty && !texto.contains(nomeUsuario)) {
      anotar('DOCX mostra o e-mail em vez do nome "$nomeUsuario" (nomeDoUsuario no backend)', resultado: 'LACUNA');
    }

    for (final (descricao, valor) in [
      ('ferramenta (TAG do Fotômetro)', tagFotometro),
      ('sala', nomeSala),
      ('leituras do campo', '0.006'),
    ]) {
      anotar(
        texto.contains(valor) ? 'DOCX contém $descricao' : 'DOCX sem $descricao: o modelo Fluxo Laminar não tem placeholder para isso',
        resultado: texto.contains(valor) ? 'OK' : 'LACUNA',
      );
    }

    // --- REGENERAÇÃO ---
    final modificadoAntes = arquivo.lastModifiedSync();
    await waitFor(tester, find.byTooltip('Gerar relatório novamente'));
    await tocar(tester, find.byTooltip('Gerar relatório novamente'));
    await waitFor(tester, find.text('Relatório regenerado com sucesso!'), timeout: const Duration(seconds: 150));
    await waitFor(tester, find.text('Relatório pronto'));
    await tocar(tester, find.text('Fechar'));
    expect(arquivo.lastModifiedSync().isAfter(modificadoAntes), isTrue, reason: 'DOCX não foi regravado');
    expect((await projetoDoTeste())['status'], 'aprovado');
    anotar('Regeneração gravou um novo DOCX e manteve o status aprovado');
  }, skip: semCredenciais); // requer --dart-define=E2E_EMAIL=... --dart-define=E2E_SENHA=...
}
