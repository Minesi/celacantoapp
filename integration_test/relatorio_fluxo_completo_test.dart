// integration_test/relatorio_fluxo_completo_test.dart
//
// Teste ponta a ponta (Windows Desktop): login -> criação de projeto HVAC ->
// validação manual de TAG das ferramentas -> leitura manual de display (OCR
// substituído por digitação, sem usar câmera/QR) -> emissão do relatório Word.
//
// Cada etapa relevante é fotografada (screenshot PNG) em
// integration_test/screenshots/, e um relatório de execução em Markdown é
// gerado ao final resumindo os passos e apontando o .docx gerado pelo app.
//
// Pré-requisitos (ver conversa/README): usuário real admin@celacanto.com já
// cadastrado no Firebase Auth + Firestore do projeto 'ocrion-eda2a'.
//
// Execução: flutter test integration_test/relatorio_fluxo_completo_test.dart -d windows

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:celacantoapp/database_helper.dart';
import 'package:celacantoapp/firebase_options.dart';
import 'package:celacantoapp/main.dart' show MyApp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emailTeste = 'admin@celacanto.com';
  const senhaTeste = 'Senha@123';
  const dominioTeste = 'celacanto.com';
  const cnpjEmpresaTeste = '11.222.333/0001-81'; // CNPJ fictício, checksum válido
  const nomeFantasiaTeste = 'EMPRESA TESTE AUTOMATIZADO';
  const razaoSocialTeste = 'Empresa Teste Automatizado LTDA';
  const tipoProjetoTeste = 'HVAC';

  // Prefixos exigidos por tipo de ferramenta (fonte: planilha SIVS_PADROES,
  // replicada em novo_projeto_page.dart -> _prefixosPorTipo).
  const ferramentasHvac = <String, String>{
    'Balômetro': 'BLM',
    'Manômetro': 'MAN',
    'Anemômetro': 'ANE',
    'Fotômetro': 'FOT',
    'Termohigrômetro': 'TRH',
    'Contador de Partículas': 'COP',
    'Decibelímetro': 'DEC',
    'Luxímetro': 'LUX',
  };

  final tagsPorFerramenta = <String, String>{
    for (final entry in ferramentasHvac.entries) entry.key: '${entry.value}-9001',
  };

  final repaintKey = GlobalKey();
  // Em Android o diretório do projeto não é gravável pelo app (sandbox); usamos
  // o diretório de documentos do app e recuperamos as evidências via `adb pull`.
  late Directory screenshotsDir;
  final random = Random();
  int passo = 0;
  final passosRelatorio = <String>[];

  // Em execução ao vivo (LiveTestWidgetsFlutterBinding), pump(duration) usa um
  // relógio real e pode colidir com animações/disposals em andamento (ex: fechar
  // um AlertDialog e abrir outro em seguida). Usamos Future.delayed real +
  // pump() de 1 frame, que é o padrão recomendado para integration_test.
  Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
    final limite = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Tempo esgotado esperando por: $finder');
  }

  Future<void> capturarTela(WidgetTester tester, String rotulo) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
    final boundary = repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imagem = await boundary.toImage(pixelRatio: 1.0);
    final bytes = (await imagem.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    passo++;
    final nomeArquivo = '${passo.toString().padLeft(2, '0')}_$rotulo.png';
    await File('${screenshotsDir.path}/$nomeArquivo').writeAsBytes(bytes);
    passosRelatorio.add('${passo.toString().padLeft(2, '0')}. $rotulo -> screenshots/$nomeArquivo');
  }

  setUpAll(() async {
    // No Android, o plugin sqflite nativo já funciona no sandbox do app; o factory
    // ffi (para Windows/desktop) resolve caminhos relativos ao cwd, que no Android
    // não é gravável e quebra a abertura do banco.
    if (!Platform.isAndroid) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: -1);

    final diretorioBase = Platform.isAndroid ? (await getApplicationDocumentsDirectory()).path : 'integration_test';
    screenshotsDir = Directory('$diretorioBase/screenshots');
    if (screenshotsDir.existsSync()) {
      screenshotsDir.deleteSync(recursive: true);
    }
    screenshotsDir.createSync(recursive: true);

    // Semeia localmente (SQLite) os instrumentos exigidos pelo escopo HVAC, com
    // dados fictícios no padrão da planilha SIVS_PADROES, evitando depender de
    // dados reais na nuvem para a etapa de validação de ferramentas.
    final dbHelper = DatabaseHelper();
    for (final entry in tagsPorFerramenta.entries) {
      await dbHelper.insertInstrumento({
        'id': 'teste-${entry.value}',
        'tipo': entry.key,
        'tag': entry.value,
        'numeroSerie': 'SN-TESTE-${entry.value}',
        'numeroCertificado': 'CERT-TESTE-${entry.value}',
        'validade': '12/2030',
        'estaValido': 1,
        'dominio_empresa': dominioTeste,
      });
    }
  });

  tearDownAll(() async {
    final buffer = StringBuffer()
      ..writeln('# Relatório de Execução — Teste E2E Celacanto App')
      ..writeln()
      ..writeln('Data/Hora: ${DateTime.now()}')
      ..writeln('Usuário de teste: $emailTeste')
      ..writeln('Empresa fictícia: $nomeFantasiaTeste ($cnpjEmpresaTeste)')
      ..writeln('Escopo testado: $tipoProjetoTeste')
      ..writeln()
      ..writeln('## Passos executados (com screenshot)')
      ..writeln(passosRelatorio.join('\n'));
    await File('${screenshotsDir.path}/RELATORIO_EXECUCAO.md').writeAsString(buffer.toString());
  });

  testWidgets('Fluxo completo: login -> novo projeto HVAC (input manual) -> relatório Word', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(RepaintBoundary(key: repaintKey, child: const MyApp()));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
    await capturarTela(tester, 'tela_login');

    // --- LOGIN ---
    final camposLogin = find.byType(TextFormField);
    await tester.enterText(camposLogin.at(0), emailTeste);
    await tester.enterText(camposLogin.at(1), senhaTeste);
    await tester.pump();
    await capturarTela(tester, 'login_preenchido');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
    await waitFor(tester, find.text('Novo Projeto'));
    await capturarTela(tester, 'home_pos_login');

    // --- NOVO PROJETO: ETAPA 1 ---
    await tester.tap(find.widgetWithText(ElevatedButton, 'Novo Projeto'));
    await waitFor(tester, find.text('Novo Projeto Operacional'));
    await capturarTela(tester, 'novo_projeto_etapa1');

    await tester.tap(find.widgetWithText(TextButton, 'Nova Empresa'));
    await waitFor(tester, find.text('Cadastrar Nova Empresa'));

    final camposEmpresa = find.byType(TextFormField);
    await tester.enterText(camposEmpresa.at(0), cnpjEmpresaTeste);
    await tester.enterText(camposEmpresa.at(1), razaoSocialTeste);
    await tester.enterText(camposEmpresa.at(2), nomeFantasiaTeste);
    await tester.pump();
    await capturarTela(tester, 'nova_empresa_preenchida');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar Empresa'));
    await waitFor(tester, find.text('Selecione a Empresa Cliente'));

    // A gravação da empresa dispara um recarregamento assíncrono não aguardado
    // (_carregarEmpresasCadastradas: SQLite + Firestore): aguarda tempo real
    // suficiente em vez de reabrir/fechar o dropdown repetidamente (instável).
    final limiteEspera = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(limiteEspera)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    }

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.at(0));
    await tester.pumpAndSettle();
    expect(find.text(nomeFantasiaTeste), findsWidgets, reason: 'Empresa recém-criada não apareceu na lista a tempo');
    await tester.tap(find.text(nomeFantasiaTeste).last);
    await tester.pumpAndSettle();

    await tester.tap(dropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tipoProjetoTeste).last);
    await tester.pumpAndSettle();
    await capturarTela(tester, 'empresa_e_escopo_selecionados');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Avançar para Ferramental'));
    await waitFor(tester, find.textContaining('Validação Obrigatória para'));
    await capturarTela(tester, 'etapa2_inicio');

    // --- VALIDAÇÃO MANUAL DAS TAGS (sem QR Code) ---
    var indiceFerramenta = 0;
    for (final entry in tagsPorFerramenta.entries) {
      final botaoManual = find.byTooltip('Digitar TAG Manualmente').at(indiceFerramenta);
      await tester.ensureVisible(botaoManual);
      await tester.pumpAndSettle();
      await tester.tap(botaoManual);
      await waitFor(tester, find.text('Digitar TAG para ${entry.key}'));

      final campoTag = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(campoTag, entry.value);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Validar'));
      await waitFor(tester, find.textContaining('TAG: ${entry.value}'));
      await capturarTela(tester, 'ferramenta_validada_${entry.value}');
      indiceFerramenta++;
    }

    // --- LEITURAS DE DISPLAY (OCR) VIA DIGITAÇÃO MANUAL, VALOR ALEATÓRIO ---
    for (var i = 0; i < tagsPorFerramenta.length; i++) {
      final botaoCapturar = find.widgetWithText(ElevatedButton, 'Capturar').first;
      await tester.ensureVisible(botaoCapturar);
      await tester.pumpAndSettle();
      await tester.tap(botaoCapturar);

      if (Platform.isAndroid) {
        // No emulador há câmera real disponível; o fallback automático para a
        // entrada manual só ocorre quando não há câmera (ex: desktop), então
        // alternamos manualmente tocando no botão de teclado. Usa o heroTag
        // (em vez do ícone) porque telas anteriores (validação de TAG) seguem
        // montadas na pilha de rotas e têm o mesmo ícone de teclado.
        final botaoTeclado = find.byWidgetPredicate((w) => w is FloatingActionButton && w.heroTag == 'btn_manual');
        await waitFor(tester, botaoTeclado);
        await tester.tap(botaoTeclado);
        await tester.pumpAndSettle();
      }

      // Sem câmera no desktop: a tela cai automaticamente na entrada manual.
      await waitFor(tester, find.widgetWithText(ElevatedButton, 'Confirmar Medição'));

      final valorAleatorio = (10 + random.nextDouble() * 40).toStringAsFixed(1);
      await tester.enterText(find.byType(TextFormField).first, valorAleatorio);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar Medição'));
      await waitFor(tester, find.textContaining('Confirmar Medição'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await waitFor(tester, find.text('Nova Medição?'));

      await tester.tap(find.text('Foi a Última'));
      await waitFor(tester, find.textContaining('Validação Obrigatória para'));
      await capturarTela(tester, 'leitura_ocr_manual_${i + 1}');
    }

    await capturarTela(tester, 'todas_ferramentas_e_leituras_ok');

    // --- FINALIZAÇÃO E GERAÇÃO DO RELATÓRIO WORD ---
    final inicioGeracao = DateTime.now();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Finalizar e Emitir Relatório Word'));
    await waitFor(tester, find.text('Novo Projeto'), timeout: const Duration(seconds: 30));
    await capturarTela(tester, 'home_apos_relatorio_gerado');

    // --- VERIFICAÇÃO: O .docx foi realmente gravado pelo app ---
    // No Android o relatório final vai para o MediaStore (URI opaca, não listável),
    // mas o app grava antes uma cópia em getApplicationDocumentsDirectory(); usamos
    // essa cópia sandboxed como evidência em vez da pasta Downloads real.
    final Directory diretorioRelatorios;
    if (Platform.isAndroid) {
      diretorioRelatorios = await getApplicationDocumentsDirectory();
    } else {
      final diretorioDownloads = await getDownloadsDirectory();
      expect(diretorioDownloads, isNotNull, reason: 'Pasta Downloads não está disponível');
      diretorioRelatorios = Directory('${diretorioDownloads!.path}/Celacanto');
    }
    expect(diretorioRelatorios.existsSync(), isTrue, reason: 'Pasta de relatórios não foi criada: ${diretorioRelatorios.path}');

    final relatorioGerado = diretorioRelatorios
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.docx') && f.statSync().modified.isAfter(inicioGeracao.subtract(const Duration(seconds: 5))))
        .toList();

    expect(relatorioGerado, isNotEmpty, reason: 'Nenhum relatório .docx novo foi encontrado em ${diretorioRelatorios.path}');

    final arquivoFinal = relatorioGerado.first;
    final copiaParaEvidencia = File('${screenshotsDir.path}/RELATORIO_GERADO_${arquivoFinal.uri.pathSegments.last}');
    await arquivoFinal.copy(copiaParaEvidencia.path);
    passosRelatorio.add('Relatório Word gerado pelo app: ${arquivoFinal.path}');
    passosRelatorio.add('Cópia salva em: ${copiaParaEvidencia.path}');
  });
}
