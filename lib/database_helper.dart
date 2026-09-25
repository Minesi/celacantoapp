// lib/database_helper.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'firestore_colecoes.dart';

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
    // Nome definitivo do banco de dados, sem necessidade de alterar o sufixo no futuro
    final path = join(dbPath, 'celacanto_local_database.db'); 

    return await openDatabase(
      path,
      version: 7, // 7: salas→máquina, filtros por sala, filtro por ponto e catálogo de testes
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
        sincronizado INTEGER DEFAULT 0,
        sistemaId TEXT,
        area TEXT,
        ensaiosSelecionados TEXT,
        status TEXT DEFAULT 'rascunho',
        history TEXT
      )
    ''');

    // 5. Sistemas (ex.: "HDA04"), reutilizáveis entre relatórios do mesmo cliente
    await db.execute('''
      CREATE TABLE sistemas (
        id TEXT PRIMARY KEY,
        nome TEXT,
        areasAtendidas TEXT,
        dominio_empresa TEXT
      )
    ''');

    // 6. Salas de cada projeto (qtdDifusores só por compatibilidade; saídas agora ficam em 'filtros')
    await db.execute('''
      CREATE TABLE salas (
        id TEXT PRIMARY KEY,
        projetoId TEXT,
        nome TEXT,
        area REAL,
        volume REAL,
        grau TEXT,
        qtdDifusores INTEGER,
        handlingUnitId TEXT
      )
    ''');

    // 7. Handling units (máquinas) de cada projeto
    await db.execute('''
      CREATE TABLE handling_units (
        id TEXT PRIMARY KEY,
        projetoId TEXT,
        nome TEXT,
        temFiltroTerminal INTEGER,
        qtdFiltrosTerminais INTEGER
      )
    ''');

    // 8. Filtros G4/F9/H14: internos da máquina (handlingUnitId) ou saídas da sala (salaId)
    await db.execute('''
      CREATE TABLE filtros (
        id TEXT PRIMARY KEY,
        handlingUnitId TEXT,
        tipo TEXT,
        quantidade INTEGER,
        localizacao TEXT,
        salaId TEXT
      )
    ''');

    // 9. Pontos de leitura de campo (ex.: contagem de partículas por sala/ensaio)
    await db.execute('''
      CREATE TABLE pontos_leitura (
        id TEXT PRIMARY KEY,
        projetoId TEXT,
        salaId TEXT,
        ensaioTipo TEXT,
        numeroPonto INTEGER,
        valor05um TEXT,
        valor5um TEXT,
        fotoEvidenciaUrl TEXT,
        dataHoraCaptura TEXT,
        filtroId TEXT
      )
    ''');

    await _criarTabelaTestesCatalogo(db);
    
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

    // A autenticação real sempre foi feita via Firebase Auth; a coluna local 'senha'
    // era um cache redundante em texto puro. Expurga qualquer valor já armazenado.
    if (oldVersion < 4) {
      try {
        await db.execute("UPDATE usuarios SET senha = NULL;");
        debugPrint("MIGRATION SUCCESS: Senhas em texto puro removidas da tabela 'usuarios'.");
      } catch (e) {
        debugPrint("MIGRATION NOTICE: Falha ao expurgar senhas locais: $e");
      }
    }

    // Fundação de dados da reunião de requisitos: sistema/área/salas/handling units/ensaios/pontos
    if (oldVersion < 5) {
      for (final coluna in ['sistemaId', 'area', 'ensaiosSelecionados']) {
        try {
          await db.execute('ALTER TABLE projetos ADD COLUMN $coluna TEXT;');
        } catch (e) {
          debugPrint("MIGRATION NOTICE: Coluna '$coluna' já existia ou falhou ao injetar em 'projetos': $e");
        }
      }

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sistemas (
            id TEXT PRIMARY KEY,
            nome TEXT,
            areasAtendidas TEXT,
            dominio_empresa TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS salas (
            id TEXT PRIMARY KEY,
            projetoId TEXT,
            nome TEXT,
            area REAL,
            volume REAL,
            grau TEXT,
            qtdDifusores INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS handling_units (
            id TEXT PRIMARY KEY,
            projetoId TEXT,
            nome TEXT,
            temFiltroTerminal INTEGER,
            qtdFiltrosTerminais INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS filtros (
            id TEXT PRIMARY KEY,
            handlingUnitId TEXT,
            tipo TEXT,
            quantidade INTEGER,
            localizacao TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pontos_leitura (
            id TEXT PRIMARY KEY,
            projetoId TEXT,
            salaId TEXT,
            ensaioTipo TEXT,
            numeroPonto INTEGER,
            valor05um TEXT,
            valor5um TEXT,
            fotoEvidenciaUrl TEXT,
            dataHoraCaptura TEXT
          )
        ''');
        debugPrint("MIGRATION SUCCESS: Tabelas 'sistemas/salas/handling_units/filtros/pontos_leitura' criadas.");
      } catch (e) {
        debugPrint("MIGRATION NOTICE: Falha ao criar tabelas da fundação de dados v5: $e");
      }
    }

    // Fluxo de status/aprovação do relatório (rascunho -> pronto_para_campo -> em_revisao -> aprovado)
    if (oldVersion < 6) {
      try {
        await db.execute("ALTER TABLE projetos ADD COLUMN status TEXT DEFAULT 'rascunho';");
        await db.execute('ALTER TABLE projetos ADD COLUMN history TEXT;');
        debugPrint("MIGRATION SUCCESS: Colunas 'status'/'history' injetadas na tabela 'projetos'.");
      } catch (e) {
        debugPrint("MIGRATION NOTICE: Colunas 'status'/'history' já existiam ou falharam ao injetar: $e");
      }
    }

    if (oldVersion < 7) {
      for (final alter in [
        'ALTER TABLE salas ADD COLUMN handlingUnitId TEXT;',
        'ALTER TABLE filtros ADD COLUMN salaId TEXT;',
        'ALTER TABLE pontos_leitura ADD COLUMN filtroId TEXT;',
      ]) {
        try {
          await db.execute(alter);
        } catch (e) {
          debugPrint("MIGRATION NOTICE: '$alter' falhou (coluna já existia?): $e");
        }
      }
      try {
        await _criarTabelaTestesCatalogo(db);
      } catch (e) {
        debugPrint("MIGRATION NOTICE: Falha ao criar tabela 'testes_catalogo': $e");
      }
    }
  }

  Future<void> _criarTabelaTestesCatalogo(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS testes_catalogo (
        id TEXT PRIMARY KEY,
        tipoEnsaio TEXT,
        dominio_empresa TEXT,
        resumo TEXT,
        tabelaConfig TEXT,
        atualizadoEm TEXT,
        UNIQUE(dominio_empresa, tipoEnsaio)
      )
    ''');
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
      ..['ensaiosSelecionados'] = jsonEncode(projeto['ensaiosSelecionados'] ?? [])
      ..['status'] = projeto['status'] ?? 'rascunho'
      ..['history'] = jsonEncode(projeto['history'] ?? [])
      ..['sincronizado'] = 0;

    return await db.insert('projetos', mapaPersistido, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getProjetosPendentes() async {
    final db = await database;
    return await db.query('projetos', where: 'sincronizado = ?', whereArgs: [0]);
  }

  Future<List<Map<String, dynamic>>> getProjetos() async {
    final db = await database;
    return await db.query('projetos', orderBy: 'dataCriacao DESC');
  }

  Future<int> marcarProjetoSincronizado(String projetoId) async {
    final db = await database;
    return await db.update(
      'projetos',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [projetoId],
    );
  }

  // Grava no cache local um projeto vindo do Firestore (já sincronizado), incluindo suas
  // salas/handling units/filtros aninhados nas tabelas normalizadas correspondentes.
  Future<void> insertProjetoSincronizado(Map<String, dynamic> projeto) async {
    final db = await database;
    final projetoId = projeto['id'].toString();

    final mapaPersistido = Map<String, dynamic>.from(projeto)
      ..['ferramentasRequeridas'] = jsonEncode(projeto['ferramentasRequeridas'] ?? [])
      ..['ferramentasEscaneadas'] = jsonEncode(projeto['ferramentasEscaneadas'] ?? {})
      ..['leiturasOcr'] = jsonEncode(projeto['leiturasOcr'] ?? [])
      ..['ensaiosSelecionados'] = jsonEncode(projeto['ensaiosSelecionados'] ?? [])
      ..['status'] = projeto['status'] ?? 'rascunho'
      ..['history'] = jsonEncode(projeto['history'] ?? [])
      ..['sincronizado'] = 1;
    // Mantém só colunas existentes na tabela; campos aninhados vão para tabelas próprias.
    mapaPersistido.removeWhere((chave, _) => !_colunasProjetos.contains(chave));

    await db.insert('projetos', mapaPersistido, conflictAlgorithm: ConflictAlgorithm.replace);

    await substituirSalasDoProjeto(
      projetoId,
      (projeto['salas'] as List? ?? const []).map((s) => Map<String, dynamic>.from(s)).toList(),
    );

    await deleteHandlingUnitsPorProjeto(projetoId);
    for (final handlingUnit in (projeto['handlingUnits'] as List? ?? const [])) {
      final huMap = Map<String, dynamic>.from(handlingUnit);
      final filtros = (huMap.remove('filtros') as List? ?? const []);
      final huId = huMap['id'].toString();
      await insertHandlingUnit({
        'id': huId,
        'projetoId': projetoId,
        'nome': huMap['nome'],
        'temFiltroTerminal': huMap['temFiltroTerminal'] == true ? 1 : 0,
        'qtdFiltrosTerminais': huMap['qtdFiltrosTerminais'],
      });
      await deleteFiltrosPorHandlingUnit(huId);
      for (final filtro in filtros) {
        final filtroMap = Map<String, dynamic>.from(filtro);
        await insertFiltro({...filtroMap, 'handlingUnitId': huId});
      }
    }

    // Só acrescenta/atualiza (IDs determinísticos): nunca apaga pontos locais ainda não enviados.
    for (final ponto in (projeto['pontosLeitura'] as List? ?? const [])) {
      await insertPontoLeitura({...Map<String, dynamic>.from(ponto), 'projetoId': projetoId});
    }
  }

  static const Set<String> _colunasProjetos = {
    'id', 'cnpjEmpresa', 'tipoProjeto', 'ferramentasRequeridas', 'ferramentasEscaneadas',
    'leiturasOcr', 'dataCriacao', 'operadorResponsavel', 'templateUtilizado', 'sincronizado',
    'sistemaId', 'area', 'ensaiosSelecionados', 'status', 'history',
  };

  Future<void> sincronizarProjetosPendentes() async {
    final projetosPendentes = await getProjetosPendentes();
    if (projetosPendentes.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final db = await database;

    for (final projeto in projetosPendentes) {
      try {
        final projetoId = projeto['id'].toString();
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
          'sistemaId': projeto['sistemaId'],
          'area': projeto['area'],
          'ensaiosSelecionados': jsonDecode(projeto['ensaiosSelecionados'] ?? '[]'),
          'status': projeto['status'] ?? 'rascunho',
          'history': jsonDecode(projeto['history'] ?? '[]'),
          'salas': await getSalasComFiltrosPorProjeto(projetoId),
          'handlingUnits': await _handlingUnitsComFiltrosPorProjeto(projetoId),
          'pontosLeitura': await getPontosLeituraPorProjeto(projetoId),
        };

        await firestore.collection(FirestoreColecoes.projetos).doc(projetoId).set(payload);
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

  // --- MÉTODOS GERENCIAIS DE SISTEMAS ---
  Future<int> insertSistema(Map<String, dynamic> sistema) async {
    final db = await database;
    return await db.insert('sistemas', sistema, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getSistemas() async {
    final db = await database;
    return await db.query('sistemas', orderBy: 'nome ASC');
  }

  // --- MÉTODOS GERENCIAIS DE SALAS ---
  Future<int> insertSala(Map<String, dynamic> sala) async {
    final db = await database;
    return await db.insert('salas', sala, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getSalasPorProjeto(String projetoId) async {
    final db = await database;
    return await db.query('salas', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  Future<int> deleteSalasPorProjeto(String projetoId) async {
    final db = await database;
    return await db.delete('salas', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  /// Salas do projeto já com a lista 'filtros' (saídas) embutida, no formato de SalaModel.fromMap.
  Future<List<Map<String, dynamic>>> getSalasComFiltrosPorProjeto(String projetoId) async {
    final salas = await getSalasPorProjeto(projetoId);
    return [
      for (final sala in salas) {...sala, 'filtros': await getFiltrosPorSala(sala['id'].toString())},
    ];
  }

  /// Regrava as salas do projeto e suas saídas (filtros) a partir de mapas no formato SalaModel.toMap().
  Future<void> substituirSalasDoProjeto(String projetoId, List<Map<String, dynamic>> salas) async {
    final db = await database;
    await db.delete(
      'filtros',
      where: 'salaId IN (SELECT id FROM salas WHERE projetoId = ?)',
      whereArgs: [projetoId],
    );
    await deleteSalasPorProjeto(projetoId);

    for (final sala in salas) {
      final salaMap = Map<String, dynamic>.from(sala);
      final filtros = (salaMap.remove('filtros') as List? ?? const []);
      final salaId = salaMap['id'].toString();
      await insertSala({...salaMap, 'projetoId': projetoId});
      for (final filtro in filtros) {
        await insertFiltro({...Map<String, dynamic>.from(filtro), 'salaId': salaId});
      }
    }
  }

  // --- MÉTODOS GERENCIAIS DE HANDLING UNITS ---
  Future<int> insertHandlingUnit(Map<String, dynamic> handlingUnit) async {
    final db = await database;
    return await db.insert('handling_units', handlingUnit, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getHandlingUnitsPorProjeto(String projetoId) async {
    final db = await database;
    return await db.query('handling_units', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  Future<int> deleteHandlingUnitsPorProjeto(String projetoId) async {
    final db = await database;
    return await db.delete('handling_units', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  // --- MÉTODOS GERENCIAIS DE FILTROS ---
  Future<int> insertFiltro(Map<String, dynamic> filtro) async {
    final db = await database;
    return await db.insert('filtros', filtro, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getFiltrosPorHandlingUnit(String handlingUnitId) async {
    final db = await database;
    return await db.query('filtros', where: 'handlingUnitId = ?', whereArgs: [handlingUnitId]);
  }

  Future<int> deleteFiltrosPorHandlingUnit(String handlingUnitId) async {
    final db = await database;
    return await db.delete('filtros', where: 'handlingUnitId = ?', whereArgs: [handlingUnitId]);
  }

  Future<List<Map<String, dynamic>>> getFiltrosPorSala(String salaId) async {
    final db = await database;
    return await db.query('filtros', where: 'salaId = ?', whereArgs: [salaId]);
  }

  // --- MÉTODOS GERENCIAIS DO CATÁLOGO DE TESTES ---
  Future<int> insertTesteCatalogo(Map<String, dynamic> teste) async {
    final db = await database;
    return await db.insert('testes_catalogo', teste, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getTestesCatalogoPorDominio(String dominio) async {
    final db = await database;
    return await db.query('testes_catalogo', where: 'dominio_empresa = ?', whereArgs: [dominio]);
  }

  Future<Map<String, dynamic>?> getTesteCatalogo(String dominio, String tipoEnsaio) async {
    final db = await database;
    final resultado = await db.query(
      'testes_catalogo',
      where: 'dominio_empresa = ? AND tipoEnsaio = ?',
      whereArgs: [dominio, tipoEnsaio],
      limit: 1,
    );
    return resultado.isEmpty ? null : resultado.first;
  }

  // Reconstrói cada handling unit já com seus filtros embutidos, no formato esperado pelo Firestore
  // (HandlingUnitModel.toMap()/fromMap()).
  Future<List<Map<String, dynamic>>> _handlingUnitsComFiltrosPorProjeto(String projetoId) async {
    final handlingUnits = await getHandlingUnitsPorProjeto(projetoId);
    final resultado = <Map<String, dynamic>>[];

    for (final handlingUnit in handlingUnits) {
      final filtros = await getFiltrosPorHandlingUnit(handlingUnit['id'].toString());
      resultado.add({
        'id': handlingUnit['id'],
        'nome': handlingUnit['nome'],
        'temFiltroTerminal': handlingUnit['temFiltroTerminal'] == 1,
        'qtdFiltrosTerminais': handlingUnit['qtdFiltrosTerminais'],
        'filtros': filtros,
      });
    }

    return resultado;
  }

  // --- MÉTODOS GERENCIAIS DE PONTOS DE LEITURA ---
  Future<int> insertPontoLeitura(Map<String, dynamic> ponto) async {
    final db = await database;
    return await db.insert('pontos_leitura', ponto, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPontosLeituraPorProjeto(String projetoId) async {
    final db = await database;
    return await db.query('pontos_leitura', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  Future<List<Map<String, dynamic>>> getPontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async {
    final db = await database;
    return await db.query(
      'pontos_leitura',
      where: 'salaId = ? AND ensaioTipo = ?',
      whereArgs: [salaId, ensaioTipo],
    );
  }

  Future<int> deletePontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async {
    final db = await database;
    return await db.delete(
      'pontos_leitura',
      where: 'salaId = ? AND ensaioTipo = ?',
      whereArgs: [salaId, ensaioTipo],
    );
  }

  // Atualiza só o campo de ferramentas escaneadas (usado quando o técnico vincula instrumentos
  // durante a execução de um ensaio em campo, sem precisar regravar o projeto inteiro).
  Future<int> atualizarFerramentasEscaneadasProjeto(String projetoId, Map<String, dynamic> ferramentas) async {
    final db = await database;
    return await db.update(
      'projetos',
      {'ferramentasEscaneadas': jsonEncode(ferramentas)},
      where: 'id = ?',
      whereArgs: [projetoId],
    );
  }

  // Atualiza o status do fluxo de aprovação (rascunho/pronto_para_campo/em_revisao/aprovado)
  // e acrescenta uma entrada no histórico de auditoria (quem, quando, campo, valores).
  Future<int> atualizarStatusEHistoricoProjeto(
    String projetoId, {
    required String novoStatus,
    required List<Map<String, dynamic>> historicoCompleto,
  }) async {
    final db = await database;
    return await db.update(
      'projetos',
      {'status': novoStatus, 'history': jsonEncode(historicoCompleto)},
      where: 'id = ?',
      whereArgs: [projetoId],
    );
  }
}