// lib/database_helper.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    // Nome definitivo do banco de dados, sem necessidade de alterar o sufixo no futuro
    final path = join(dbPath, 'celacanto_local_database.db'); 

    return await openDatabase(
      path,
      version: 3, // Incrementado para 3 para suportar a coluna 'dominio_empresa' na tabela de usuários
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // Callback definitivo para gerenciar futuras atualizações de tabelas
    );
  }

  // Executado APENAS na primeira vez que o app é instalado/executado no dispositivo
  Future<void> _onCreate(Database db, int version) async {
    // 1. Criação da Tabela de Usuários
    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT,
        cpf TEXT,
        email TEXT UNIQUE,
        senha TEXT,
        perfil TEXT,
        dominio_empresa TEXT
      )
    ''');

    // 2. Criação da Tabela de Instrumentos
    await db.execute('''
      CREATE TABLE instrumentos (
        id TEXT PRIMARY KEY,
        tipo TEXT,
        tag TEXT UNIQUE,
        numeroSerie TEXT,
        numeroCertificado TEXT,
        validade TEXT,
        estaValido INTEGER,
        dominio_empresa TEXT
      )
    ''');

    // 3. Criação da Tabela de Empresas
    await db.execute('''
      CREATE TABLE empresas (
        cnpj TEXT PRIMARY KEY,
        razaoSocial TEXT,
        nomeFantasia TEXT,
        dominio_empresa TEXT
      )
    ''');

    // 4. Criação da Tabela de Projetos para persistência offline/online
    await db.execute('''
      CREATE TABLE projetos (
        id TEXT PRIMARY KEY,
        cnpjEmpresa TEXT,
        tipoProjeto TEXT,
        ferramentasRequeridas TEXT,
        ferramentasEscaneadas TEXT,
        leiturasOcr TEXT,
        dataCriacao TEXT,
        operadorResponsavel TEXT,
        templateUtilizado TEXT,
        sincronizado INTEGER DEFAULT 0
      )
    ''');
    
    debugPrint("DATABASE BASE CREATED: Todas as tabelas locais foram criadas na versão $version.");
  }

  // Executado AUTOMATICAMENTE se a versão do banco no dispositivo for menor que a definida no código
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("DATABASE UPGRADE: Atualizando banco da versão $oldVersion para $newVersion...");
    
    // Se o dispositivo rodava a versão 1 (sem a coluna dominio_empresa na tabela empresas)
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE empresas ADD COLUMN dominio_empresa TEXT;');
        debugPrint("MIGRATION SUCCESS: Coluna 'dominio_empresa' injetada na tabela 'empresas'.");
      } catch (e) {
        debugPrint("MIGRATION NOTICE: A coluna já existia ou falhou ao injetar: $e");
      }
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE usuarios ADD COLUMN dominio_empresa TEXT;');
        debugPrint("MIGRATION SUCCESS: Coluna 'dominio_empresa' injetada na tabela 'usuarios'.");
      } catch (e) {
        debugPrint("MIGRATION NOTICE: A coluna já existia ou falhou ao injetar na tabela 'usuarios': $e");
      }

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS projetos (
            id TEXT PRIMARY KEY,
            cnpjEmpresa TEXT,
            tipoProjeto TEXT,
            ferramentasRequeridas TEXT,
            ferramentasEscaneadas TEXT,
            leiturasOcr TEXT,
            dataCriacao TEXT,
            operadorResponsavel TEXT,
            templateUtilizado TEXT,
            sincronizado INTEGER DEFAULT 0
          )
        ''');
      } catch (e) {
        debugPrint("MIGRATION NOTICE: Falha ao criar tabela de projetos: $e");
      }
    }
  }

  // --- MÉTODOS GERENCIAIS DE USUÁRIOS ---
  Future<int> insertUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert('usuarios', usuario, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getUsuarios() async {
    final db = await database;
    return await db.query('usuarios');
  }

  Future<Map<String, dynamic>?> loginUsuario(String email, String senha) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'usuarios',
      where: 'email = ? AND senha = ?',
      whereArgs: [email.trim().toLowerCase(), senha],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<int> updateUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.update(
      'usuarios', 
      usuario, 
      where: 'id = ?', 
      whereArgs: [usuario['id']], 
      conflictAlgorithm: ConflictAlgorithm.replace
    );
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
    return await db.update(
      'instrumentos', 
      dados, 
      where: 'tag = ?', 
      whereArgs: [tag.toUpperCase().trim()]
    );
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
    return await db.query('empresas', orderBy: 'nomeFantasia ASC');
  }

  Future<int> deleteEmpresa(String cnpj) async {
    final db = await database;
    return await db.delete('empresas', where: 'cnpj = ?', whereArgs: [cnpj]);
  }

  Future<int> insertProjeto(Map<String, dynamic> projeto) async {
    final db = await database;
    final mapaPersistido = Map<String, dynamic>.from(projeto)
      ..['ferramentasRequeridas'] = jsonEncode(projeto['ferramentasRequeridas'] ?? [])
      ..['ferramentasEscaneadas'] = jsonEncode(projeto['ferramentasEscaneadas'] ?? {})
      ..['leiturasOcr'] = jsonEncode(projeto['leiturasOcr'] ?? [])
      ..['sincronizado'] = 0;

    return await db.insert('projetos', mapaPersistido, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getProjetosPendentes() async {
    final db = await database;
    return await db.query('projetos', where: 'sincronizado = ?', whereArgs: [0]);
  }

  Future<void> sincronizarProjetosPendentes() async {
    final projetosPendentes = await getProjetosPendentes();
    if (projetosPendentes.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final db = await database;

    for (final projeto in projetosPendentes) {
      try {
        final payload = {
          'id': projeto['id'],
          'cnpjEmpresa': projeto['cnpjEmpresa'],
          'tipoProjeto': projeto['tipoProjeto'],
          'ferramentasRequeridas': jsonDecode(projeto['ferramentasRequeridas'] ?? '[]'),
          'ferramentasEscaneadas': jsonDecode(projeto['ferramentasEscaneadas'] ?? '{}'),
          'leiturasOcr': jsonDecode(projeto['leiturasOcr'] ?? '[]'),
          'dataCriacao': projeto['dataCriacao'],
          'operadorResponsavel': projeto['operadorResponsavel'],
          'templateUtilizado': projeto['templateUtilizado'],
        };

        await firestore.collection('projetos').doc(projeto['id'].toString()).set(payload);
        await db.update(
          'projetos',
          {'sincronizado': 1},
          where: 'id = ?',
          whereArgs: [projeto['id']],
        );
      } catch (e) {
        debugPrint('Falha ao sincronizar projeto ${projeto['id']}: $e');
      }
    }
  }
}