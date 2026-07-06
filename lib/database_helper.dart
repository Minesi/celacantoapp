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
    // Alterado para v5 para forçar a criação da tabela com as colunas da tela (razaoSocial, nomeFantasia)
    final path = join(dbPath, 'usuarios_teste_v5.db'); 

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Criação da Tabela de Usuários
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

    // 2. Criação da Tabela de Instrumentos
    await db.execute('''
      CREATE TABLE instrumentos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT,
        tag TEXT UNIQUE,
        numeroSerie TEXT,
        numeroCertificado TEXT,
        validade TEXT,
        estaValido INTEGER
      )
    ''');

    // 3. AJUSTADO: Criação da Tabela de Empresas com as variáveis exatas da View
    await db.execute('''
      CREATE TABLE empresas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        razaoSocial TEXT,
        nomeFantasia TEXT,
        cnpj TEXT UNIQUE
      )
    ''');

    // Inserção dos usuários de teste
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Operador Padrão', '11122233344', 'operador@empresa.com', '12345678', 'operador')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Supervisor Geral', '55566677788', 'supervisor@empresa.com', '12345678', 'supervisor')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Administrador Sistema', '99988877766', 'admin@empresa.com', '12345678', 'admin')"
    );

    // Instrumento padrão de teste
    await db.rawInsert(
      "INSERT INTO instrumentos (tipo, tag, numeroSerie, numeroCertificado, validade, estaValido) VALUES ('Manômetro Diferencial', 'MAN-011', '140812', '2601-049', '01/2027', 1)"
    );
  }

  // --- MÉTODOS GERENCIAIS DE USUÁRIOS ---
  Future<int> insertUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert('usuarios', usuario, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUsuarios() async {
    final db = await database;
    return await db.query('usuarios', orderBy: 'nome ASC');
  }

  Future<int> updateUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.update('usuarios', usuario, where: 'id = ?', whereArgs: [usuario['id']], conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteUsuario(int id) async {
    final db = await database;
    return await db.delete('usuarios', where: 'id = ?', whereArgs: [id]);
  }

  // --- MÉTODOS GERENCIAIS DE INSTRUMENTOS ---
  Future<int> insertInstrumento(Map<String, dynamic> instrumento) async {
    final db = await database;
    return await db.insert('instrumentos', instrumento, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getInstrumentos() async {
    final db = await database;
    return await db.query('instrumentos', orderBy: 'tag ASC');
  }

  Future<int> updateInstrumentoPorTag(String tag, Map<String, dynamic> dados) async {
    final db = await database;
    return await db.update('instrumentos', dados, where: 'tag = ?', whereArgs: [tag.toUpperCase().trim()]);
  }

  // --- MÉTODOS GERENCIAIS DE EMPRESAS ---
  Future<int> insertEmpresa(Map<String, dynamic> empresa) async {
    final db = await database;
    return await db.insert(
      'empresas',
      empresa,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getEmpresas() async {
    final db = await database;
    return await db.query('empresas', orderBy: 'razaoSocial ASC'); // Ordena por Razão Social
  }
}