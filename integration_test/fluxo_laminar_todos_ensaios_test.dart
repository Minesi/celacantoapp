// E2E do Fluxo Laminar com os oito ensaios selecionados.
// Executar a partir da raiz do projeto:
// flutter test integration_test/fluxo_laminar_todos_ensaios_test.dart -d windows --dart-define=E2E_EMAIL=<admin> --dart-define=E2E_SENHA=<senha>

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
  const e2eAndroid = bool.fromEnvironment('E2E_ANDROID');
  const cnpjEmpresaTeste = '11.222.333/0001-81';
  const nomeFantasiaTeste = 'EMPRESA TESTE AUTOMATIZADO';
  const tipoProjeto = 'Fluxo Laminar';
  const nomeMaquina = 'FLUXO-E2E-01';
  const nomeSala = 'SALA E2E FL';
  final semCredenciais = emailTeste.isEmpty || senhaTeste.isEmpty;
  final dominioTeste = emailTeste.split('@').last.toLowerCase();
  final marca = DateTime.now().millisecondsSinceEpoch;
  final nomeSistemaTeste = 'SISTEMA FL E2E $marca';
  final areaTeste = 'AREA FL E2E $marca';
  final repaintKey = GlobalKey();
  final screenshotsDir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}celacanto-e2e-fluxo-laminar-$marca',
  );
  final passos = <String>[];
  final tags = <String, String>{
    'Manômetro': 'MAN-FL-E2E-$marca',
    'Anemômetro': 'ANE-FL-E2E-$marca',
    'Fotômetro': 'FOT-FL-E2E-$marca',
    'Decibelímetro': 'DEC-FL-E2E-$marca',
    'Luxímetro': 'LUX-FL-E2E-$marca',
    'Máquina de Fumaça': 'FUM-FL-E2E-$marca',
    'Contador de Partículas': 'CNT-FL-E2E-$marca',
  };
  final fotoFake = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}celacanto-fl-e2e-$marca.png',
  );
  var numeroPasso = 0;
  String? projetoIdExecucao;
  String? registroEmail;

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
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

  Future<void> aguardarSincronizacao(WidgetTester tester) async {
    final limite = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      if (find.textContaining('Sincronizando').evaluate().isEmpty) return;
    }
    throw TestFailure('Sincronização de projetos não terminou');
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await waitFor(tester, finder);
    await tester.ensureVisible(finder);
    final limite = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(limite)) {
      await tester.pump();
      if (finder.hitTestable().evaluate().isNotEmpty) {
        await tester.tap(finder);
        await aguardar(tester, const Duration(milliseconds: 600));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TestFailure('Alvo não ficou tocável: $finder');
  }

  Future<void> escolherNoDropdown(
    WidgetTester tester,
    Finder dropdown,
    String opcao,
  ) async {
    await tocar(tester, dropdown);
    await tester.tap(find.text(opcao).last);
    await aguardar(tester, const Duration(milliseconds: 600));
  }

  Finder campoFormulario(String label) =>
      find.widgetWithText(TextFormField, label);

  Finder campoExecucaoContendo(String trecho) =>
      find.byWidgetPredicate((widget) {
        if (widget is! TextField) return false;
        final rotulo = widget.decoration?.labelText ?? '';
        return rotulo == trecho || (trecho != '5µm' && rotulo.contains(trecho));
      });

  Finder dropdownComRotulo(String label) => find.byWidgetPredicate((widget) {
    return widget is DropdownButtonFormField &&
        widget.decoration.labelText == label;
  });

  void anotar(
    String verificacao, {
    String resultado = 'OK',
    String evidencia = '-',
  }) {
    numeroPasso++;
    passos.add(
      '| ${numeroPasso.toString().padLeft(2, '0')} | $verificacao | $resultado | $evidencia |',
    );
  }

  Future<void> capturar(
    WidgetTester tester,
    String rotulo,
    String verificacao, {
    String resultado = 'OK',
  }) async {
    await aguardar(tester, const Duration(milliseconds: 300));
    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imagem = await boundary.toImage(pixelRatio: 1.0);
    final bytes = (await imagem.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final nome = '${(numeroPasso + 1).toString().padLeft(2, '0')}_$rotulo.png';
    await File('${screenshotsDir.path}/$nome').writeAsBytes(bytes);
    anotar(verificacao, resultado: resultado, evidencia: nome);
  }

  Future<Map<String, dynamic>> projetoDoTeste() async {
    final projetos = await DatabaseHelper().getProjetos();
    final doTeste = projetos
        .where((projeto) => projeto['area'] == areaTeste)
        .toList();
    expect(
      doTeste,
      hasLength(1),
      reason: 'Deve existir exatamente um projeto para a área do teste',
    );
    return doTeste.single;
  }

  Future<void> aguardarStatus(
    String status, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final limite = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(limite)) {
      if ((await projetoDoTeste())['status'] == status) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TestFailure('Projeto não chegou ao status $status');
  }

  String textoDoDocx(File arquivo) {
    final zip = ZipDecoder().decodeBytes(arquivo.readAsBytesSync());
    final partes = zip.files
        .where((item) => RegExp(r'^word/(document|header\d+|footer\d+)\.xml$').hasMatch(item.name))
        .toList();
    expect(partes, isNotEmpty, reason: 'DOCX sem word/document.xml');
    return partes
        .map((item) => utf8.decode(item.content as List<int>).replaceAll(RegExp(r'<[^>]+>'), ' '))
        .join(' ');
  }

  Future<void> selecionarConforme(WidgetTester tester) async {
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Conformidade'),
      'Conforme',
    );
  }

  Future<void> preencherResultado(
    WidgetTester tester,
    String trecho,
    String valor,
  ) async {
    final campo = campoExecucaoContendo(trecho);
    expect(
      campo,
      findsOneWidget,
      reason: 'Campo de resultado não encontrado: $trecho',
    );
    await tester.ensureVisible(campo);
    await tester.enterText(campo, valor);
  }

  Future<void> anexarFoto(WidgetTester tester) async {
    await tocar(tester, find.text('Anexar Foto de Evidência'));
    await waitFor(tester, find.text('Foto Anexada ✓'));
  }

  Future<void> executarEnsaio(
    WidgetTester tester, {
    required String nome,
    required String valor,
    required String rotulo,
    required int realizadosDepois,
    bool exigeFoto = false,
  }) async {
    await tocar(tester, find.widgetWithText(ActionChip, '$nome (0/1)'));
    await waitFor(tester, find.text('Concluir Ensaio'));
    await preencherResultado(tester, rotulo, valor);
    await selecionarConforme(tester);
    if (exigeFoto) await anexarFoto(tester);
    await tocar(tester, find.text('Concluir Ensaio'));
    await waitFor(
      tester,
      find.text('Testes realizados: $realizadosDepois de 9'),
    );
  }

  setUpAll(() async {
    if (semCredenciais) return;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: -1,
    );

    if (screenshotsDir.existsSync()) screenshotsDir.deleteSync(recursive: true);
    screenshotsDir.createSync(recursive: true);
    const pngFake =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    await fotoFake.writeAsBytes(base64Decode(pngFake));

    final db = DatabaseHelper();
    await db.insertEmpresa({
      'cnpj': cnpjEmpresaTeste,
      'razaoSocial': 'Empresa Teste Automatizado LTDA',
      'nomeFantasia': nomeFantasiaTeste,
      'dominio_empresa': dominioTeste,
    });
    for (final entrada in tags.entries) {
      if (entrada.key == 'Máquina de Fumaça') continue;
      await db.insertInstrumento({
        'id': 'teste-${entrada.value}',
        'tipo': entrada.key,
        'tag': entrada.value,
        'numeroSerie': 'SN-${entrada.value}',
        'numeroCertificado': 'CERT-${entrada.value}',
        'validade': '12/2030',
        'estaValido': 1,
        'dominio_empresa': dominioTeste,
      });
    }
  });

  tearDownAll(() async {
    if (fotoFake.existsSync()) {
      try {
        await fotoFake.delete();
      } on FileSystemException {
        // O arquivo pode já ter sido removido pelo fluxo de encerramento.
      }
    }
    if (semCredenciais) return;
    final relatorio = StringBuffer()
      ..writeln('# Execução E2E — Fluxo Laminar com os oito ensaios')
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
    await File(
      '${screenshotsDir.path}/RELATORIO_EXECUCAO.md',
    ).writeAsString(relatorio.toString());
  });

  testWidgets('Fluxo Laminar: executa os oito ensaios, aprova e emite DOCX', (
    tester,
  ) async {
    final alvoDesktop = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
    if (!e2eAndroid && alvoDesktop) {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    Future<String?> capturadorFotoFake(BuildContext _) async => fotoFake.path;

    await tester.pumpWidget(
      RepaintBoundary(
        key: repaintKey,
        child: MyApp(capturadorFoto: capturadorFotoFake),
      ),
    );
    await aguardar(tester, const Duration(milliseconds: 500));

    final camposLogin = find.byType(TextFormField);
    await tester.enterText(camposLogin.at(0), emailTeste);
    await tester.enterText(camposLogin.at(1), senhaTeste);
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Entrar'));
    await waitFor(tester, find.text('Utilização do Relatório'));
    await capturar(tester, 'home', 'Login do usuário E2E');

    final empresas = await FirebaseFirestore.instance
        .collection('empresas')
        .where('cnpj', isEqualTo: cnpjEmpresaTeste)
        .limit(1)
        .get();
    expect(
      empresas.docs,
      isNotEmpty,
      reason: 'A empresa do teste precisa existir no Firestore',
    );
    final empresaNuvem = empresas.docs.single.data();
    final nomeEmpresaNuvem =
        (empresaNuvem['nome_fantasia'] ??
                empresaNuvem['nomeFantasia'] ??
                cnpjEmpresaTeste)
            .toString();

    await tocar(tester, find.text('Elaboração do Relatório'));
    await waitFor(tester, find.text('Empresa Cliente'));
    final dropdownsTexto = find.byType(DropdownButtonFormField<String>);
    await escolherNoDropdown(tester, dropdownsTexto.at(0), nomeFantasiaTeste);
    await escolherNoDropdown(tester, dropdownsTexto.at(1), tipoProjeto);
    await tester.enterText(
      find.widgetWithText(TextField, 'Área atendida pelo sistema'),
      areaTeste,
    );
    await tester.pump();

    await tocar(tester, find.text('Novo Sistema'));
    await waitFor(tester, find.byType(AlertDialog));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      nomeSistemaTeste,
    );
    await tocar(tester, find.text('Criar'));
    await waitFor(tester, find.text(nomeSistemaTeste));

    await tocar(tester, find.text('Adicionar'));
    await waitFor(tester, find.text('Adicionar Máquina (Handling Unit)'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome/Identificação da Máquina'),
      nomeMaquina,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').at(2), '1');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.textContaining('1× H14'));

    await tocar(tester, find.text('Adicionar Sala'));
    await waitFor(tester, find.text('Filtros da Sala'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome da Sala'),
      nomeSala,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Área (m²)'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Volume (m³)'), '30');
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').first, '1');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.text('$nomeSala — Grau D'));

    const nomesEnsaios = [
      'Avaliação do Sistema de Filtragem',
      'Velocidade e Uniformidade do Fluxo de Ar',
      'Integridade de Filtros',
      'Nível de Ruído',
      'Luminosidade',
      'Paralelismo do Fluxo de Ar',
      'Visualização do Fluxo de Ar',
      'Contagem de Partículas',
    ];
    for (final nomeEnsaio in nomesEnsaios) {
      final checkbox = find.widgetWithText(CheckboxListTile, nomeEnsaio);
      await waitFor(tester, checkbox);
      await tocar(tester, checkbox);
    }

    final pontosPorFiltro = campoFormulario('Pontos/filtro');
    expect(pontosPorFiltro, findsOneWidget);
    await tester.ensureVisible(pontosPorFiltro);
    await tester.enterText(pontosPorFiltro, '1');
    final pontosConfig = campoFormulario('Pontos');
    expect(pontosConfig, findsNWidgets(4));
    for (var indice = 0; indice < 4; indice++) {
      final campo = pontosConfig.at(indice);
      await tester.ensureVisible(campo);
      await tester.enterText(campo, '1');
    }
    await capturar(
      tester,
      'elaboracao_oito_ensaios',
      'Elaboração com os oito ensaios e um H14',
    );

    await tocar(tester, find.text('Concluir Elaboração'));
    await waitFor(tester, find.text('Projetos Realizados'));

    final db = DatabaseHelper();
    final projeto = await projetoDoTeste();
    final projetoId = projeto['id'].toString();
    projetoIdExecucao = projetoId;
    expect(projeto['status'], 'prontoParaCampo');
    expect(projeto['tipoProjeto'], tipoProjeto);
    expect(
      List<String>.from(jsonDecode(projeto['ensaiosSelecionados'].toString())),
      containsAll(
        nomesEnsaios.map((nome) {
          const mapa = {
            'Avaliação do Sistema de Filtragem': 'avaliacaoFiltragem',
            'Velocidade e Uniformidade do Fluxo de Ar': 'velocidadeFluxo',
            'Integridade de Filtros': 'integridadeFiltros',
            'Nível de Ruído': 'nivelRuido',
            'Luminosidade': 'luminosidade',
            'Paralelismo do Fluxo de Ar': 'paralelismoFluxo',
            'Visualização do Fluxo de Ar': 'visualizacaoFluxo',
            'Contagem de Partículas': 'contagemParticulas',
          };
          return mapa[nome]!;
        }),
      ),
    );
    final salas = await db.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnits = await db.getHandlingUnitsPorProjeto(projetoId);
    expect(handlingUnits.single['nome'], nomeMaquina);
    expect(salas.single['nome'], nomeSala);
    expect((salas.single['filtros'] as List).single['tipo'], 'h14');
    expect((salas.single['filtros'] as List).single['quantidade'], 1);
    final configEnsaios = Map<String, dynamic>.from(
      salas.single['configEnsaios'] as Map,
    );
    expect(configEnsaios['velocidadeFluxo']['pontos'].toString(), '1');
    anotar(
      'Projeto $projetoId pronto para campo com oito ensaios, uma sala e um H14',
    );

    await tocar(tester, find.text('Utilização do Relatório'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    final cardDoProjeto = find.descendant(
      of: find.byType(ListTile),
      matching: find.textContaining(areaTeste),
    );
    await waitFor(tester, cardDoProjeto);
    await tocar(tester, cardDoProjeto.first);
    await waitFor(tester, find.text('Ferramentas do relatório'));

    Future<void> digitarTag(String tipo) async {
      final card = find
          .ancestor(of: find.text(tipo), matching: find.byType(Card))
          .first;
      final teclado = find.descendant(
        of: card,
        matching: find.byIcon(Icons.keyboard),
      );
      await tocar(tester, teclado);
      await waitFor(tester, find.text('Digitar TAG para $tipo'));
      final campo = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(campo, tags[tipo]!);
      await tocar(tester, find.text('Validar'));
      await waitFor(tester, find.text(tags[tipo]!));
    }

    for (final tipo in tags.keys) {
      await digitarTag(tipo);
    }
    await tocar(tester, find.text('Continuar para as salas'));
    await waitFor(tester, find.text('Testes realizados: 0 de 9'));
    anotar('Sete tipos de instrumento vinculados para os oito ensaios');

    const dadosEnsaios = [
      ('Avaliação do Sistema de Filtragem', '0.45', 'Filtro 1 (H14)', false),
      ('Velocidade e Uniformidade do Fluxo de Ar', '0.46', 'Ponto 1', false),
      ('Integridade de Filtros', '0.006', 'Filtro 1 (H14)', false),
      ('Nível de Ruído', '60', 'Ponto 1', false),
      ('Luminosidade', '500', 'Ponto 1', false),
      ('Paralelismo do Fluxo de Ar', '3', 'Ponto 1', true),
      (
        'Visualização do Fluxo de Ar',
        'Fluxo descendente conforme',
        'Sentido do fluxo',
        true,
      ),
    ];
    var realizados = 0;
    for (final (nome, valor, rotulo, exigeFoto) in dadosEnsaios) {
      realizados++;
      await executarEnsaio(
        tester,
        nome: nome,
        valor: valor,
        rotulo: rotulo,
        realizadosDepois: realizados,
        exigeFoto: exigeFoto,
      );
    }

    await tocar(tester, find.text('Contagem de Partículas (0/2)'));
    await waitFor(tester, find.text('Concluir Ensaio'));
    await preencherResultado(tester, '0,5µm', '100');
    await preencherResultado(tester, '5µm', '5');
    await selecionarConforme(tester);
    await anexarFoto(tester);
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Estado da medição'),
      'Operação',
    );
    await preencherResultado(tester, '0,5µm', '120');
    await preencherResultado(tester, '5µm', '6');
    await tocar(tester, find.text('Concluir Ensaio'));
    await waitFor(tester, find.text('Testes realizados: 9 de 9'));
    await aguardarStatus('emRevisao');

    final pontosLeitura = await db.getPontosLeituraPorProjeto(projetoId);
    expect(pontosLeitura, hasLength(9));
    expect(
      pontosLeitura
          .where((ponto) => ponto['ensaioTipo'] == 'contagemParticulas')
          .map((ponto) => ponto['estado'])
          .toSet(),
      {'repouso', 'operacao'},
    );
    expect(
      pontosLeitura
          .where((ponto) => ponto['ensaioTipo'] == 'contagemParticulas')
          .map((ponto) => ponto['valor05um'])
          .toSet(),
      {'100', '120'},
    );
    expect(
      pontosLeitura
          .where((ponto) => ponto['ensaioTipo'] == 'contagemParticulas')
          .map((ponto) => ponto['valor5um'])
          .toSet(),
      {'5', '6'},
    );
    final tiposComFoto = {
      'paralelismoFluxo',
      'visualizacaoFluxo',
      'contagemParticulas',
    };
    expect(
      pontosLeitura
          .where((ponto) => tiposComFoto.contains(ponto['ensaioTipo']))
          .every(
            (ponto) => (ponto['fotoEvidenciaUrl']?.toString() ?? '').isNotEmpty,
          ),
      isTrue,
      reason: 'Ensaios com política de foto devem persistir a evidência',
    );
    final urlsEvidencias = pontosLeitura
        .where((ponto) => tiposComFoto.contains(ponto['ensaioTipo']))
        .map((ponto) => ponto['fotoEvidenciaUrl']?.toString() ?? '')
        .toSet();
    expect(
      urlsEvidencias.every(
        (url) {
          final uri = Uri.tryParse(url);
          return uri?.scheme == 'https' &&
              uri?.host == 'firebasestorage.googleapis.com';
        },
      ),
      isTrue,
      reason: 'Evidências precisam estar publicadas no Firebase Storage',
    );
    expect(await db.getResultadosEnsaioPorProjeto(projetoId), hasLength(8));
    anotar(
      'Campo concluído: nove pontos, dois estados da Contagem e fotos persistidos',
    );

    await tocar(tester, find.byIcon(Icons.arrow_back));
    await waitFor(tester, find.text('Utilização do Relatório'));
    await tester.pageBack();
    await waitFor(tester, find.text('Projetos Realizados'));
    await tocar(tester, find.text('Projetos Realizados'));
    await waitFor(tester, find.widgetWithText(TextField, 'Área'));
    await aguardarSincronizacao(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Área'), areaTeste);
    await waitFor(tester, find.byIcon(Icons.task_alt));
    await tocar(tester, find.byIcon(Icons.task_alt));
    await waitFor(tester, find.text('Revisão dos Resultados'));
    expect(find.textContaining('Principal: 0.45'), findsOneWidget);
    expect(find.textContaining('Principal: 120'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Observações da revisão'),
      'Revisão dos oito ensaios confirmada.',
    );
    await tocar(tester, find.text('Continuar para aprovação'));
    await waitFor(tester, find.text('Aprovar relatório?'));
    await tocar(tester, find.text('Aprovar definitivamente'));
    await waitFor(tester, find.text('Conclusão da qualificação'));
    await tocar(tester, find.text('Cumpre'));
    await tocar(tester, find.text('Emitir relatório'));

    const sucesso =
        'Relatório aprovado, gerado e enviado por e-mail com sucesso!';
    bool ehFalha(String texto) {
      return texto.startsWith(
            'Relatório aprovado e gerado. O e-mail não foi enviado',
          ) ||
          texto.startsWith('Relatório aprovado, mas a geração falhou') ||
          texto.startsWith('Falha ao aprovar/gerar relatório');
    }

    final resultadoEmissao = find.byWidgetPredicate((widget) {
      if (widget is! Text || widget.data == null) return false;
      return widget.data == sucesso || ehFalha(widget.data!);
    });
    await waitFor(
      tester,
      resultadoEmissao,
      timeout: const Duration(seconds: 330),
    );
    final mensagem = tester.widget<Text>(resultadoEmissao.first).data!;
    if (mensagem != sucesso) {
      await capturar(
        tester,
        'FALHA_emissao',
        'Emissão dos oito ensaios: $mensagem',
        resultado: 'FALHA',
      );
      fail(mensagem);
    }
    await capturar(
      tester,
      'relatorio_emitido',
      'DOCX dos oito ensaios gerado e e-mail enviado',
    );

    await waitFor(tester, find.text('Relatório pronto'));
    await tocar(tester, find.text('Fechar'));

    final projetoAprovado = await projetoDoTeste();
    expect(projetoAprovado['status'], 'aprovado');
    final historico = List<Map<String, dynamic>>.from(
      jsonDecode(projetoAprovado['history'].toString()),
    );
    final aprovacao = historico.lastWhere(
      (entrada) =>
          entrada['campo'] == 'status' && entrada['valorNovo'] == 'aprovado',
    );
    expect(
      ((aprovacao['detalhes'] as Map)['conclusao'] as Map)['cumpre'],
      isTrue,
    );
    expect(
      (aprovacao['detalhes'] as Map)['observacoesRevisao'],
      'Revisão dos oito ensaios confirmada.',
    );

    final servidor = await FirebaseFirestore.instance
        .collection('projetos')
        .doc(projetoId)
        .get(const GetOptions(source: Source.server));
    expect(servidor.exists, isTrue);
    final projetoServidor = servidor.data()!;
    expect(projetoServidor['status'], 'aprovado');
    expect((projetoServidor['pontosLeitura'] as List), hasLength(9));
    expect((projetoServidor['resultadosEnsaios'] as List), hasLength(8));
    final pontosServidor = List<Map<String, dynamic>>.from(
      (projetoServidor['pontosLeitura'] as List).map(
        (ponto) => Map<String, dynamic>.from(ponto),
      ),
    );
    expect(
      pontosServidor
          .where((ponto) => ponto['ensaioTipo'] == 'contagemParticulas')
          .map((ponto) => ponto['estado'])
          .toSet(),
      {'repouso', 'operacao'},
    );
    anotar(
      'Firestore contém o projeto aprovado, nove pontos e oito resultados',
    );

    QueryDocumentSnapshot<Map<String, dynamic>>? envio;
    final limiteEmail = DateTime.now().add(const Duration(seconds: 30));
    while (envio == null && DateTime.now().isBefore(limiteEmail)) {
      final envios = await FirebaseFirestore.instance
          .collection('relatorios_email')
          .where('projetoId', isEqualTo: projetoId)
          .get(const GetOptions(source: Source.server));
      envio = envios.docs
          .where((documento) => documento.data()['status'] == 'enviado')
          .firstOrNull;
      if (envio == null) await Future<void>.delayed(const Duration(seconds: 2));
    }
    expect(
      envio,
      isNotNull,
      reason: 'Nenhum registro enviado em relatorios_email para $projetoId',
    );
    expect(envio!.data()['destinatario'], emailTeste.toLowerCase());
    registroEmail = 'relatorios_email/${envio.id}';

    final downloads = Platform.environment['USERPROFILE']!;
    final arquivo = File(
      '$downloads/Downloads/Celacanto/Relatorio_$projetoId.docx',
    );
    expect(
      arquivo.existsSync(),
      isTrue,
      reason: 'Relatório não encontrado em ${arquivo.path}',
    );
    final arquivosDocx = ZipDecoder().decodeBytes(arquivo.readAsBytesSync());
    expect(
      arquivosDocx.files.any((item) => item.name.startsWith('word/media/')),
      isTrue,
      reason: 'DOCX sem imagens de evidência incorporadas',
    );
    final texto = textoDoDocx(arquivo);
    final inicioContagem = texto.indexOf('ANEXO 6');
    final fimContagem = texto.indexOf('ANEXO 7', inicioContagem);
    expect(inicioContagem, greaterThanOrEqualTo(0));
    expect(fimContagem, greaterThan(inicioContagem));
    final textoContagem = texto.substring(inicioContagem, fimContagem);
    for (final esperado in [
      'D (Repouso)',
      '100',
      '5',
      'D (Operação)',
      '120',
      '6',
    ]) {
      expect(
        textoContagem,
        contains(esperado),
        reason: 'Anexo 6 sem resultado/estado "$esperado"',
      );
    }
    for (final esperado in [
      nomeEmpresaNuvem,
      areaTeste,
      nomeMaquina,
      nomeSala,
      'H14',
      tags['Manômetro']!,
      tags['Contador de Partículas']!,
    ]) {
      expect(texto, contains(esperado), reason: 'DOCX sem "$esperado"');
    }
    for (final esperado in [
      '100',
      '120',
      '5',
      '6',
      'Conforme',
      '3°',
      'Fluxo descendente conforme',
      '0,46',
      '0,006%',
    ]) {
      expect(
        texto,
        contains(esperado),
        reason: 'DOCX sem resultado "$esperado"',
      );
    }
    for (final anexo in [
      'AVALIAÇÃO DO SISTEMA DE FILTRAGEM',
      'VELOCIDADE E UNIFORMIDADE DO FLUXO DE AR',
      'INTEGRIDADE',
      'NÍVEL DE RUÍDO',
      'LUMINOSIDADE',
      'CONTAGEM DE PARTÍCULAS',
      'VISUALIZAÇÃO DO FLUXO DE AR',
      'PARALELISMO DO FLUXO DE AR',
    ]) {
      expect(
        texto.toUpperCase(),
        contains(anexo),
        reason: 'DOCX sem anexo/ensaio "$anexo"',
      );
    }
    expect(
      RegExp(r'\{[A-ZÀ-Ú0-9_ .#/-]+\}').hasMatch(texto),
      isFalse,
      reason: 'DOCX com placeholder sem substituição',
    );
    expect(texto, contains(projetoId));
    expect(texto, isNot(contains('REGISTRO ESTRUTURADO DOS ENSAIOS')));
    anotar(
      'DOCX final contém os oito ensaios, instrumentos, sala, valores e estados da Contagem',
    );
  }, skip: semCredenciais);
}
