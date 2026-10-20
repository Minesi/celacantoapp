// E2E da Pesagem com os oito ensaios selecionados.
// Executar a partir da raiz do projeto:
// flutter test integration_test/pesagem_todos_ensaios_test.dart -d windows --dart-define=E2E_EMAIL=<admin> --dart-define=E2E_SENHA=<senha>

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
  const tipoProjeto = 'Pesagem';
  const nomeMaquina = 'PESAGEM-E2E-01';
  const nomeSala = 'SALA E2E PESAGEM';
  // Pontos exigidos por ensaio: ruído e contagem contam dois estados.
  const totalExigido = 25;
  final semCredenciais = emailTeste.isEmpty || senhaTeste.isEmpty;
  final dominioTeste = emailTeste.split('@').last.toLowerCase();
  final marca = DateTime.now().millisecondsSinceEpoch;
  final nomeSistemaTeste = 'SISTEMA PESAGEM E2E $marca';
  final areaTeste = 'AREA PESAGEM E2E $marca';
  final repaintKey = GlobalKey();
  final screenshotsDir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}celacanto-e2e-pesagem-$marca',
  );
  final passos = <String>[];
  final tags = <String, String>{
    'Manômetro': 'MAN-PES-E2E-$marca',
    'Anemômetro': 'ANE-PES-E2E-$marca',
    'Fotômetro': 'FOT-PES-E2E-$marca',
    'Decibelímetro': 'DEC-PES-E2E-$marca',
    'Luxímetro': 'LUX-PES-E2E-$marca',
    'Máquina de Fumaça': 'FUM-PES-E2E-$marca',
    'Contador de Partículas': 'CNT-PES-E2E-$marca',
  };
  final fotoFake = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}celacanto-pes-e2e-$marca.png',
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

  // Rótulo exato: evita casar "Ponto 1" dentro de "L (mm) — Ponto 1".
  Finder campoPorRotulo(String rotulo) => find.byWidgetPredicate((widget) {
    return widget is TextField && widget.decoration?.labelText == rotulo;
  });

  Finder dropdownComRotulo(String label) => find.byWidgetPredicate((widget) {
    return widget is DropdownButtonFormField &&
        widget.decoration.labelText == label;
  });

  Future<void> preencherCampo(
    WidgetTester tester,
    Finder campo,
    String valor,
  ) async {
    expect(campo, findsOneWidget, reason: 'Campo não encontrado: $campo');
    await tester.ensureVisible(campo);
    await tester.enterText(campo, valor);
    await aguardar(tester, const Duration(milliseconds: 200));
  }

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

  // Sem espaço entre tags removidas: runs do Word que dividem uma palavra continuam juntas.
  String textoDoDocx(File arquivo) {
    final zip = ZipDecoder().decodeBytes(arquivo.readAsBytesSync());
    final partes = zip.files
        .where((item) => RegExp(r'^word/(document|header\d+|footer\d+)\.xml$').hasMatch(item.name))
        .toList();
    expect(partes, isNotEmpty, reason: 'DOCX sem word/document.xml');
    return partes
        .map((item) => utf8.decode(item.content as List<int>).replaceAll(RegExp(r'<[^>]+>'), ''))
        .join(' ');
  }

  Future<void> selecionarConforme(WidgetTester tester) async {
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Conformidade'),
      'Conforme',
    );
  }

  Future<void> anexarFoto(WidgetTester tester) async {
    await tocar(tester, find.text('Anexar Foto de Evidência'));
    await waitFor(tester, find.text('Foto Anexada ✓'));
  }

  Future<void> abrirEnsaio(WidgetTester tester, String rotuloChip) async {
    await tocar(tester, find.widgetWithText(ActionChip, rotuloChip));
    await waitFor(tester, find.text('Concluir Ensaio'));
  }

  Future<void> concluirEnsaio(WidgetTester tester, int realizadosDepois) async {
    await tocar(tester, find.text('Concluir Ensaio'));
    await waitFor(
      tester,
      find.text('Testes realizados: $realizadosDepois de $totalExigido'),
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
      ..writeln('# Execução E2E — Pesagem com os oito ensaios')
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

  testWidgets('Pesagem: executa os oito ensaios, aprova e emite DOCX', (
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
    // Dimensões em mm do H14: o editor da sala copia o filtro da máquina (área e vazão dos anexos 2 e 7).
    await waitFor(tester, find.widgetWithText(TextField, 'Dimensões'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Dimensões').first,
      '610x610',
    );
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
    // Grau C ativa os limites de contagem da Pesagem (anexo 7).
    await escolherNoDropdown(tester, dropdownComRotulo('Grau'), 'Grau C');
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').first, '1');
    await tocar(tester, find.widgetWithText(ElevatedButton, 'Adicionar'));
    await waitFor(tester, find.text('$nomeSala — Grau C'));

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

    await preencherCampo(
      tester,
      campoFormulario('Pontos/filtro'),
      '1',
    );
    await preencherCampo(
      tester,
      campoFormulario('Média esperada (m/s)'),
      '0,45',
    );
    // Campos "Pontos" na ordem das linhas de ensaio: ruído, luminosidade, paralelismo, visualização.
    final pontosConfig = campoFormulario('Pontos');
    expect(pontosConfig, findsNWidgets(4));
    const pontosPorEnsaio = ['5', '5', '4', '1'];
    for (var indice = 0; indice < pontosPorEnsaio.length; indice++) {
      await preencherCampo(
        tester,
        pontosConfig.at(indice),
        pontosPorEnsaio[indice],
      );
    }
    await capturar(
      tester,
      'elaboracao_oito_ensaios',
      'Elaboração da Pesagem com os oito ensaios, sala Grau C e um H14',
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
      containsAll(const [
        'avaliacaoFiltragem',
        'velocidadeFluxo',
        'integridadeFiltros',
        'nivelRuido',
        'luminosidade',
        'paralelismoFluxo',
        'visualizacaoFluxo',
        'contagemParticulas',
      ]),
    );
    final salas = await db.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnits = await db.getHandlingUnitsPorProjeto(projetoId);
    expect(handlingUnits.single['nome'], nomeMaquina);
    expect(salas.single['nome'], nomeSala);
    expect(salas.single['grau'], 'c');
    expect((salas.single['filtros'] as List).single['dimensoes'], '610x610');
    final configEnsaios = Map<String, dynamic>.from(
      salas.single['configEnsaios'] as Map,
    );
    expect(configEnsaios['nivelRuido']['pontos'].toString(), '5');
    expect(configEnsaios['velocidadeFluxo']['mediaEsperada'].toString(), '0,45');
    anotar(
      'Projeto $projetoId pronto para campo com a Pesagem, oito ensaios, sala Grau C e um H14',
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
    await waitFor(tester, find.text('Testes realizados: 0 de $totalExigido'));
    anotar('Sete tipos de instrumento vinculados para os oito ensaios');

    // Avaliação: perda de carga do filtro (Pa), conforme manual.
    await abrirEnsaio(tester, 'Avaliação do Sistema de Filtragem (0/1)');
    await preencherCampo(tester, campoPorRotulo('Filtro 1 (H14)'), '250');
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 1);

    // Velocidade: média 0,46 m/s, dentro de 0,36–0,54 e desvio zero.
    await abrirEnsaio(tester, 'Velocidade e Uniformidade do Fluxo de Ar (0/1)');
    await preencherCampo(tester, campoPorRotulo('F1 (H14) — Ponto 1'), '0,46');
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 2);

    // Integridade: concentração 0,006% (limite 0,01%) e resultado parcial conforme.
    await abrirEnsaio(tester, 'Integridade de Filtros (0/1)');
    await preencherCampo(tester, campoPorRotulo('Filtro 1 (H14)'), '0,006');
    for (final parcial in const [
      'Assentamento do filtro',
      'Estrutura do filtro',
      'Meio filtrante',
    ]) {
      await escolherNoDropdown(tester, dropdownComRotulo(parcial), 'Conforme');
    }
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 3);

    // Ruído: 5 pontos em repouso e 5 em operação, limite 85 dB.
    await abrirEnsaio(tester, 'Nível de Ruído (0/10)');
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Estado da medição'),
      'Repouso',
    );
    for (var ponto = 1; ponto <= 5; ponto++) {
      await preencherCampo(tester, campoPorRotulo('Ponto $ponto'), '60');
    }
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Estado da medição'),
      'Operação',
    );
    for (var ponto = 1; ponto <= 5; ponto++) {
      await preencherCampo(tester, campoPorRotulo('Ponto $ponto'), '62');
    }
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 13);

    // Luminosidade: cinco pontos, todos acima de 500 lux.
    await abrirEnsaio(tester, 'Luminosidade (0/5)');
    for (var ponto = 1; ponto <= 5; ponto++) {
      await preencherCampo(tester, campoPorRotulo('Ponto $ponto'), '520');
    }
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 18);

    // Paralelismo: L 1000 mm e X 100 mm resultam em 5,71°, abaixo de 14°.
    await abrirEnsaio(tester, 'Paralelismo do Fluxo de Ar (0/4)');
    for (var ponto = 1; ponto <= 4; ponto++) {
      await preencherCampo(
        tester,
        campoPorRotulo('L (mm) — Ponto $ponto'),
        '1000',
      );
      await preencherCampo(
        tester,
        campoPorRotulo('X (mm) — Ponto $ponto'),
        '100',
      );
    }
    await anexarFoto(tester);
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 22);

    // Visualização: as duas verificações conforme e tempo de dissipação de 30 s.
    await abrirEnsaio(tester, 'Visualização do Fluxo de Ar (0/1)');
    for (final verificacao in const [
      '1 - O sentido do fluxo de ar é para o interior da cabine',
      '2 - Não houve escape de ar do interior da cabine',
    ]) {
      await escolherNoDropdown(tester, dropdownComRotulo(verificacao), 'Conforme');
    }
    await preencherCampo(
      tester,
      campoPorRotulo('Tempo de dissipação (segundos)'),
      '30',
    );
    await anexarFoto(tester);
    await selecionarConforme(tester);
    await concluirEnsaio(tester, 23);

    // Contagem Grau C: repouso e operação, com foto de evidência em cada estado.
    await abrirEnsaio(tester, 'Contagem de Partículas (0/2)');
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Estado da medição'),
      'Repouso',
    );
    await preencherCampo(tester, campoPorRotulo('Ponto 1 — 0,5µm'), '100000');
    await preencherCampo(tester, campoPorRotulo('5µm'), '5');
    await anexarFoto(tester);
    await escolherNoDropdown(
      tester,
      dropdownComRotulo('Estado da medição'),
      'Operação',
    );
    await preencherCampo(tester, campoPorRotulo('Ponto 1 — 0,5µm'), '120000');
    await preencherCampo(tester, campoPorRotulo('5µm'), '6');
    await selecionarConforme(tester);
    await concluirEnsaio(tester, totalExigido);
    await aguardarStatus('emRevisao');

    final pontosLeitura = await db.getPontosLeituraPorProjeto(projetoId);
    expect(pontosLeitura, hasLength(totalExigido));
    expect(
      pontosLeitura
          .where((ponto) => ponto['ensaioTipo'] == 'contagemParticulas')
          .map((ponto) => ponto['estado'])
          .toSet(),
      {'repouso', 'operacao'},
    );
    expect(
      pontosLeitura
          .where((ponto) => ponto['ensaioTipo'] == 'nivelRuido')
          .map((ponto) => ponto['estado'])
          .toSet(),
      {'repouso', 'operacao'},
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
    expect(await db.getResultadosEnsaioPorProjeto(projetoId), hasLength(8));
    anotar(
      'Campo concluído: $totalExigido pontos, dois estados de Ruído e Contagem, fotos persistidas',
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Observações da revisão'),
      'Revisão dos oito ensaios da Pesagem confirmada.',
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
        'Emissão da Pesagem: $mensagem',
        resultado: 'FALHA',
      );
      fail(mensagem);
    }
    await capturar(
      tester,
      'relatorio_emitido',
      'DOCX da Pesagem gerado e e-mail enviado',
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

    final servidor = await FirebaseFirestore.instance
        .collection('projetos')
        .doc(projetoId)
        .get(const GetOptions(source: Source.server));
    expect(servidor.exists, isTrue);
    final projetoServidor = servidor.data()!;
    expect(projetoServidor['status'], 'aprovado');
    expect((projetoServidor['pontosLeitura'] as List), hasLength(totalExigido));
    expect((projetoServidor['resultadosEnsaios'] as List), hasLength(8));
    anotar(
      'Firestore contém o projeto da Pesagem aprovado, $totalExigido pontos e oito resultados',
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
    final texto = textoDoDocx(arquivo);
    final textoMaiusculo = texto.toUpperCase();

    // Anexos 1 a 8 e 9 a 11 com a numeração gerada pelas condições de ensaio.
    for (final anexo in const [
      'ANEXO 1 - AVALIAÇÃO DO SISTEMA DE FILTRAGEM',
      'ANEXO 2 - VELOCIDADE E UNIFORMIDADE DO FLUXO DE AR',
      'ANEXO 3 - INTEGRIDADE E ESTANQUEIDADE DE FILTROS ABSOLUTOS',
      'ANEXO 4 - NÍVEL DE RUÍDO',
      'ANEXO 5 - VERIFICAÇÃO DA INTENSIDADE LUMINOSA',
      'ANEXO 6 - PARALELISMO DO FLUXO DE AR',
      'ANEXO 7 - ENSAIO DE CONTAGEM DE PARTÍCULAS',
      'ANEXO 8 - VISUALIZAÇÃO DO FLUXO DE AR',
      'ANEXO 9 – VERIFICAÇÃO DA CALIBRAÇÃO',
      'ANEXO 10 - REGISTRO DE ASSINATURAS',
      'ANEXO 11 - CONCLUSÃO DE QUALIFICAÇÃO',
    ]) {
      expect(
        textoMaiusculo,
        contains(anexo),
        reason: 'DOCX sem anexo "$anexo"',
      );
    }

    // Valores calculados e medidos em cada anexo.
    for (final esperado in const [
      '0,460', // velocidade média (anexo 2)
      '0,3721', // área do filtro 610x610 mm (anexo 2)
      '616,2', // vazão em m³/h (anexo 2)
      '0,006', // concentração (anexo 3)
      '5,71', // ângulo de paralelismo (anexo 6)
      '100.000', // média de 0,5 µm em repouso (anexo 7)
      '120.000', // média de 0,5 µm em operação (anexo 7)
      'Glicerina',
      'Unidirecional',
      'Conforme',
      '30 segundos',
    ]) {
      expect(texto, contains(esperado), reason: 'DOCX sem valor "$esperado"');
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
    // Código do projeto fica no cabeçalho das páginas (header2/header4 do modelo).
    expect(texto, contains(projetoId));
    expect(
      RegExp(r'\{[A-ZÀ-Ú0-9_ .#/-]+\}').hasMatch(texto),
      isFalse,
      reason: 'DOCX com placeholder sem substituição',
    );
    final urlsEvidencias = pontosLeitura
        .where((ponto) => tiposComFoto.contains(ponto['ensaioTipo']))
        .map((ponto) => ponto['fotoEvidenciaUrl']?.toString() ?? '');
    expect(
      urlsEvidencias.every(
        (url) => Uri.tryParse(url)?.host == 'firebasestorage.googleapis.com',
      ),
      isTrue,
      reason: 'Evidências não publicadas no Firebase Storage (upload negado)',
    );
    anotar(
      'DOCX da Pesagem contém os anexos, instrumentos, sala, valores e sem placeholders',
    );
  }, skip: semCredenciais);
}
