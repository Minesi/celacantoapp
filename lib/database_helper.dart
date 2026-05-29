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
    // Mantido v2 para garantir que a tabela com CPF e Perfil esteja ativa
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

    // Inserção dos usuários de teste atualizados com Nome e CPF
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Operador Padrão', '11122233344', 'operador@empresa.com', '12345678', 'operador')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Supervisor Geral', '55566677788', 'supervisor@empresa.com', '12345678', 'supervisor')"
    );
    await db.rawInsert(
      "INSERT INTO usuarios (nome, cpf, email, senha, perfil) VALUES ('Administrador Sistema', '99988877766', 'admin@empresa.com', '12345678', 'admin')"
    );
  }

  // --- NOVOS MÉTODOS ADICIONADOS PARA SUPORTAR A TELA DE EDIÇÃO ---

  /// Busca todos os usuários cadastrados na tabela
  Future<List<Map<String, dynamic>>> getUsuarios() async {
    final db = await database;
    // Retorna a lista ordenada por nome para facilitar a visualização no Dropdown
    return await db.query('usuarios', orderBy: 'nome ASC');
  }

  /// Atualiza os dados de um usuário específico utilizando o ID como referência
  Future<int> updateUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.update(
      'usuarios',
      usuario,
      where: 'id = ?',
      whereArgs: [usuario['id']],
      conflictAlgorithm: ConflictAlgorithm.replace, // Substitui em caso de conflito de constraints
    );
  }

  /// Remove permanentemente um usuário do banco pelo ID
  Future<int> deleteUsuario(int id) async {
    final db = await database;
    return await db.delete(
      'usuarios',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}