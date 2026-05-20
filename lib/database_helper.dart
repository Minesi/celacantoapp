// lib/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    // Alterado para v2 para forçar a atualização da tabela no seu aparelho
    final path = join(dbPath, 'usuarios_teste_v2.db'); 

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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

    // Inserção dos usuários de teste atualizados com Nome e CPF fictícios
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Operador Padrão', '11122233344', 'operador@empresa.com', '123', 'operador')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Supervisor Geral', '55566677788', 'supervisor@empresa.com', '456', 'supervisor')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Administrador Sistema', '99988877766', 'admin@empresa.com', '123456', 'admin')"
    );
  }
}