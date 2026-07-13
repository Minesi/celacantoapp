import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:celacantoapp/database_helper.dart';
import 'package:celacantoapp/instrumento_model.dart';
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

    final legacyDb = await openDatabase(path, version: 1, onCreate: (db, version) async {
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
    });
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

    expect(service.assetPathParaProjeto('Fluxo Laminar'), 'assets/templates/fluxo_laminar.docx');
    expect(service.assetPathParaProjeto('Ar Comprimido'), 'assets/templates/modelo_ar_comprimido.docx');
    expect(service.assetPathParaProjeto('Cabine de Exaustão'), 'assets/templates/modelo_cabine_exaustao.docx');
    expect(service.assetPathParaProjeto('HVAC'), 'assets/templates/modelo_relatorio_hvac.docx');
    expect(service.assetPathParaProjeto('Teste'), 'assets/templates/modelo_teste.docx');
    expect(service.assetPathParaProjeto('Outro escopo'), 'assets/templates/modelo_teste.docx');
  });

  test('keeps tool validity valid through the end of the declared month', () {
    final dataFutura = DateTime.now().year + 1;
    expect(InstrumentoModel.validadeEhValida('12/$dataFutura'), isTrue);
    expect(InstrumentoModel.validadeEhValida('01/1900'), isFalse);
  });
}
