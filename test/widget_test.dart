import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

import 'package:celacantoapp/database_helper.dart';
import 'package:celacantoapp/instrumento_model.dart';
import 'package:celacantoapp/main.dart';
import 'package:celacantoapp/relatorio_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('adds dominio_empresa to the usuarios table during migration', () async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'celacanto_migration_test.db');
    await databaseFactory.deleteDatabase(path);

    final legacyDb = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE usuarios (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT,
          cpf TEXT,
          email TEXT UNIQUE,
          senha TEXT,
          perfil TEXT
        )
      ''');
      },
    );
    await legacyDb.close();

    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final columns = await db.rawQuery('PRAGMA table_info(usuarios)');
    final columnNames = columns.map((column) => column['name']).toList();

    expect(columnNames, contains('dominio_empresa'));
    await db.close();
    await databaseFactory.deleteDatabase(path);
  });

  test('selects the correct Word template for each project type', () {
    final service = RelatorioService();

    expect(service.templateIdParaProjeto('Fluxo Laminar'), 'fluxo_laminar');
    expect(
      service.templateIdParaProjeto('Ar Comprimido'),
      'modelo_ar_comprimido',
    );
    expect(
      service.templateIdParaProjeto('Cabine de Exaustão'),
      'modelo_cabine_exaustao',
    );
    expect(service.templateIdParaProjeto('HVAC'), 'modelo_relatorio_hvac');
    expect(service.templateIdParaProjeto('Teste'), 'modelo_teste');
    expect(service.templateIdParaProjeto('Outro escopo'), 'modelo_teste');
  });

  test('keeps tool validity valid through the end of the declared month', () {
    final dataFutura = DateTime.now().year + 1;
    expect(InstrumentoModel.validadeEhValida('12/$dataFutura'), isTrue);
    expect(InstrumentoModel.validadeEhValida('01/1900'), isFalse);
  });

  testWidgets(
    'submits the login form when Enter is pressed on the password field',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));

      final campos = find.byType(TextFormField);
      expect(campos, findsNWidgets(2));

      await tester.tap(campos.at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        find.text('Por favor, insira seu e-mail ou usuário'),
        findsOneWidget,
      );
      expect(find.text('Por favor, insira sua senha'), findsOneWidget);
    },
  );
}
