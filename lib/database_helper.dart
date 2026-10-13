// lib/database_helper.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'firestore_colecoes.dart';
import 'offline_authorization_service.dart';
import 'execucao_database.dart';

class DatabaseHelper implements ExecucaoDatabase {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  Future<int>? _sincronizacaoEmAndamento;

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
      version: 10, // 10: dados estruturados dos novos ensaios do Fluxo Laminar
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // Callback definitivo para gerenciar futuras atualizações de tabelas
      onOpen: _validarEsquemaBanco,
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
        history TEXT,
        paralelismo TEXT,
        validadeTestesMeses INTEGER
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
        handlingUnitId TEXT,
        handlingUnitIdsAdicionais TEXT,
        configEnsaios TEXT
      )
    ''');

    // 7. Handling units (máquinas) de cada projeto
    await db.execute('''
      CREATE TABLE handling_units (
        id TEXT PRIMARY KEY,
        projetoId TEXT,
        nome TEXT,
        numero TEXT,
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
        salaId TEXT,
        marca TEXT,
        modelo TEXT,
        dimensoes TEXT
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
        filtroId TEXT,
        filtroIndice TEXT,
        estado TEXT
      )
    ''');

    await _criarTabelaResultadosEnsaio(db);

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

    if (oldVersion < 8) {
      for (final alter in [
        'ALTER TABLE salas ADD COLUMN handlingUnitIdsAdicionais TEXT;',
        'ALTER TABLE filtros ADD COLUMN marca TEXT;',
        'ALTER TABLE filtros ADD COLUMN modelo TEXT;',
        'ALTER TABLE filtros ADD COLUMN dimensoes TEXT;',
      ]) {
        try {
          await db.execute(alter);
        } catch (e) {
          debugPrint("MIGRATION NOTICE: '$alter' falhou (coluna já existia?): $e");
        }
      }
    }

    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE projetos ADD COLUMN paralelismo TEXT;');
      } catch (e) {
        debugPrint("MIGRATION NOTICE: coluna 'paralelismo' já existia ou falhou ao injetar: $e");
      }
    }
      if (oldVersion < 10) {
        for (final alter in [
          'ALTER TABLE projetos ADD COLUMN validadeTestesMeses INTEGER;',
          'ALTER TABLE salas ADD COLUMN configEnsaios TEXT;',
          'ALTER TABLE handling_units ADD COLUMN numero TEXT;',
          'ALTER TABLE pontos_leitura ADD COLUMN filtroIndice TEXT;',
          'ALTER TABLE pontos_leitura ADD COLUMN estado TEXT;',
        ]) {
          try {
            await db.execute(alter);
          } catch (e) {
            debugPrint("MIGRATION NOTICE: '$alter' falhou (coluna já existia?): $e");
          }
        }
        await _criarTabelaResultadosEnsaio(db);
      }
  }

    Future<void> _criarTabelaResultadosEnsaio(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS resultados_ensaio (
          id TEXT PRIMARY KEY,
          projetoId TEXT,
          salaId TEXT,
          ensaioTipo TEXT,
          conforme INTEGER,
          observacoes TEXT,
          tecnicoEmail TEXT,
          dataHora TEXT,
          dados TEXT
        )
      ''');
    }

  Future<void> _validarEsquemaBanco(Database db) async {
    const esquemaObrigatorio = <String, List<String>>{
      'usuarios': ['id', 'nome', 'cpf', 'email', 'senha', 'perfil', 'dominio_empresa'],
      'instrumentos': ['id', 'tipo', 'tag', 'numeroSerie', 'numeroCertificado', 'validade', 'estaValido', 'dominio_empresa'],
      'empresas': ['cnpj', 'razaoSocial', 'nomeFantasia', 'dominio_empresa'],
      'projetos': [
        'id', 'cnpjEmpresa', 'tipoProjeto', 'ferramentasRequeridas', 'ferramentasEscaneadas', 'leiturasOcr',
        'dataCriacao', 'operadorResponsavel', 'templateUtilizado', 'sincronizado', 'sistemaId', 'area',
        'ensaiosSelecionados', 'status', 'history', 'paralelismo', 'validadeTestesMeses',
      ],
      'sistemas': ['id', 'nome', 'areasAtendidas', 'dominio_empresa'],
      'salas': ['id', 'projetoId', 'nome', 'area', 'volume', 'grau', 'qtdDifusores', 'handlingUnitId', 'handlingUnitIdsAdicionais', 'configEnsaios'],
      'handling_units': ['id', 'projetoId', 'nome', 'numero', 'temFiltroTerminal', 'qtdFiltrosTerminais'],
      'filtros': ['id', 'handlingUnitId', 'tipo', 'quantidade', 'localizacao', 'salaId', 'marca', 'modelo', 'dimensoes'],
      'pontos_leitura': [
        'id', 'projetoId', 'salaId', 'ensaioTipo', 'numeroPonto', 'valor05um', 'valor5um', 'fotoEvidenciaUrl',
        'dataHoraCaptura', 'filtroId', 'filtroIndice', 'estado',
      ],
      'testes_catalogo': ['id', 'tipoEnsaio', 'dominio_empresa', 'resumo', 'tabelaConfig', 'atualizadoEm'],
      'resultados_ensaio': ['id', 'projetoId', 'salaId', 'ensaioTipo', 'conforme', 'observacoes', 'tecnicoEmail', 'dataHora', 'dados'],
    };

    for (final entrada in esquemaObrigatorio.entries) {
      final colunas = await db.rawQuery('PRAGMA table_info(${entrada.key})');
      if (colunas.isEmpty) {
        throw StateError('Banco local inconsistente: tabela ${entrada.key} ausente.');
      }

      final nomes = colunas.map((coluna) => coluna['name']?.toString()).toSet();
      final faltantes = entrada.value.where((nome) => !nomes.contains(nome)).toList();
      if (faltantes.isNotEmpty) {
        throw StateError(
          'Banco local inconsistente: ${entrada.key} sem coluna(s): ${faltantes.join(', ')}.',
        );
      }
    }
  }

  Future<void> recriarBancoLocal() async {
    final dbAberto = _database;
    _database = null;
    if (dbAberto != null) await dbAberto.close();

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'celacanto_local_database.db');
    await deleteDatabase(path);
    await database;
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

  Future<void> aplicarImportacaoInstrumentos(
    List<Map<String, dynamic>> novos,
    List<Map<String, dynamic>> atualizacoes,
  ) async {
    final db = await database;
    await db.transaction((transacao) async {
      for (final instrumento in novos) {
        await transacao.insert(
          'instrumentos',
          instrumento,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final atualizacao in atualizacoes) {
        final tag = atualizacao['tag']?.toString().toUpperCase().trim();
        final dados = atualizacao['dados'];
        if (tag == null || tag.isEmpty || dados is! Map<String, dynamic>) continue;
        await transacao.update(
          'instrumentos',
          dados,
          where: 'tag = ?',
          whereArgs: [tag],
        );
      }
    });
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
      ..['paralelismo'] = projeto['paralelismo'] == null ? null : jsonEncode(projeto['paralelismo'])
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
      ..['paralelismo'] = projeto['paralelismo'] == null ? null : jsonEncode(projeto['paralelismo'])
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
        'numero': huMap['numero'] ?? '',
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
    for (final resultado in (projeto['resultadosEnsaios'] as List? ?? const [])) {
      await inserirResultadoEnsaio({...Map<String, dynamic>.from(resultado), 'projetoId': projetoId});
    }
  }

  static const Set<String> _colunasProjetos = {
    'id', 'cnpjEmpresa', 'tipoProjeto', 'ferramentasRequeridas', 'ferramentasEscaneadas',
    'leiturasOcr', 'dataCriacao', 'operadorResponsavel', 'templateUtilizado', 'sincronizado',
    'sistemaId', 'area', 'ensaiosSelecionados', 'status', 'history', 'paralelismo', 'validadeTestesMeses',
  };

  Future<int> sincronizarProjetosPendentes() {
    final sincronizacaoAtual = _sincronizacaoEmAndamento;
    if (sincronizacaoAtual != null) return sincronizacaoAtual;

    final novaSincronizacao = _sincronizarProjetosPendentes();
    _sincronizacaoEmAndamento = novaSincronizacao;
    novaSincronizacao.then(
      (_) {
        if (identical(_sincronizacaoEmAndamento, novaSincronizacao)) {
          _sincronizacaoEmAndamento = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_sincronizacaoEmAndamento, novaSincronizacao)) {
          _sincronizacaoEmAndamento = null;
        }
      },
    );
    return novaSincronizacao;
  }

  Future<int> _sincronizarProjetosPendentes() async {
    final projetosPendentes = await getProjetosPendentes();
    if (projetosPendentes.isEmpty) return 0;

    final firestore = FirebaseFirestore.instance;
    final db = await database;
    var sincronizados = 0;

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
          'paralelismo': projeto['paralelismo'] == null ? null : jsonDecode(projeto['paralelismo'].toString()),
          'validadeTestesMeses': projeto['validadeTestesMeses'],
          'salas': await getSalasComFiltrosPorProjeto(projetoId),
          'handlingUnits': await _handlingUnitsComFiltrosPorProjeto(projetoId),
          'pontosLeitura': await getPontosLeituraPorProjeto(projetoId),
          'resultadosEnsaios': await getResultadosEnsaioPorProjeto(projetoId),
        };

        await _reconciliarAutorizacoesOffline(payload);
        await firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set(payload, SetOptions(merge: true));
        await db.update(
          'projetos',
          {'sincronizado': 1},
          where: 'id = ?',
          whereArgs: [projeto['id']],
        );
        sincronizados++;
      } on FirebaseException catch (erro) {
        if (erro.code == 'permission-denied' &&
            projeto['status']?.toString() == 'aprovado') {
          await db.update(
            'projetos',
            {'sincronizado': 1},
            where: 'id = ?',
            whereArgs: [projeto['id']],
          );
          debugPrint(
            'Projeto ${projeto['id']} já está aprovado na nuvem; sincronização local encerrada.',
          );
        } else {
          debugPrint('Falha ao sincronizar projeto ${projeto['id']}: $erro');
        }
      } catch (e) {
        debugPrint('Falha ao sincronizar projeto ${projeto['id']}: $e');
      }
    }
    return sincronizados;
  }

  Future<void> _reconciliarAutorizacoesOffline(Map<String, dynamic> projeto) async {
    final historico = projeto['history'];
    if (historico is! List) return;

    final tokens = <String>{};
    for (final entrada in historico) {
      if (entrada is! Map) continue;
      final detalhes = entrada['detalhes'];
      if (detalhes is! Map) continue;
      final liberacao = detalhes['liberacao'];
      if (liberacao is! Map || liberacao['metodo']?.toString() != 'offline_assinada') continue;
      final token = liberacao['autorizacaoOffline']?.toString().trim() ?? '';
      if (token.isNotEmpty) tokens.add(token);
    }

    for (final token in tokens) {
      await OfflineAuthorizationService.instance.reconciliarAutorizacao(responseToken: token);
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
      for (final sala in salas)
        {
          ...sala,
          'handlingUnitIdsAdicionais': _decodificarListaIds(sala['handlingUnitIdsAdicionais']),
          'configEnsaios': _decodificarMapa(sala['configEnsaios']),
          'filtros': await getFiltrosPorSala(sala['id'].toString()),
        },
    ];
  }

  static List<String> _decodificarListaIds(dynamic valor) {
    if (valor is! String || valor.isEmpty) return const [];
    try {
      return (jsonDecode(valor) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> _decodificarMapa(dynamic valor) {
    if (valor is Map) return Map<String, dynamic>.from(valor);
    if (valor is String && valor.isNotEmpty) {
      try {
        final decodificado = jsonDecode(valor);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {}
    }
    return const {};
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
      await insertSala({
        ...salaMap,
        'projetoId': projetoId,
        'handlingUnitIdsAdicionais': jsonEncode(salaMap['handlingUnitIdsAdicionais'] ?? const []),
        'configEnsaios': jsonEncode(salaMap['configEnsaios'] ?? const {}),
      });
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
        'numero': handlingUnit['numero'] ?? '',
        'temFiltroTerminal': handlingUnit['temFiltroTerminal'] == 1,
        'qtdFiltrosTerminais': handlingUnit['qtdFiltrosTerminais'],
        'filtros': filtros,
      });
    }

    return resultado;
  }

  // --- MÉTODOS GERENCIAIS DE PONTOS DE LEITURA ---
  @override
  Future<int> insertPontoLeitura(Map<String, dynamic> ponto) async {
    final db = await database;
    return await db.insert('pontos_leitura', ponto, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPontosLeituraPorProjeto(String projetoId) async {
    final db = await database;
    return await db.query('pontos_leitura', where: 'projetoId = ?', whereArgs: [projetoId]);
  }

  @override
  Future<List<Map<String, dynamic>>> getPontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async {
    final db = await database;
    return await db.query(
      'pontos_leitura',
      where: 'salaId = ? AND ensaioTipo = ?',
      whereArgs: [salaId, ensaioTipo],
    );
  }

  @override
  Future<int> deletePontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo) async {
    final db = await database;
    return await db.delete(
      'pontos_leitura',
      where: 'salaId = ? AND ensaioTipo = ?',
      whereArgs: [salaId, ensaioTipo],
    );
  }

  Future<int> inserirResultadoEnsaio(Map<String, dynamic> resultado) async {
    final db = await database;
    final mapa = Map<String, dynamic>.from(resultado)
      ..['dataHora'] = resultado['dataHora'] is Timestamp
          ? (resultado['dataHora'] as Timestamp).toDate().toIso8601String()
          : resultado['dataHora']?.toString()
      ..['conforme'] = resultado['conforme'] == null
          ? null
          : resultado['conforme'] == true || resultado['conforme'] == 1
              ? 1
              : 0
      ..['dados'] = jsonEncode(resultado['dados'] ?? {});
    return await db.insert('resultados_ensaio', mapa, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getResultadosEnsaioPorProjeto(String projetoId) async {
    final db = await database;
    final resultados = await db.query('resultados_ensaio', where: 'projetoId = ?', whereArgs: [projetoId]);
    return resultados.map(_decodificarResultadoEnsaio).toList();
  }

  @override
  Future<Map<String, dynamic>?> getResultadoEnsaio(String salaId, String ensaioTipo) async {
    final db = await database;
    final resultados = await db.query(
      'resultados_ensaio',
      where: 'salaId = ? AND ensaioTipo = ?',
      whereArgs: [salaId, ensaioTipo],
      limit: 1,
    );
    return resultados.isEmpty ? null : _decodificarResultadoEnsaio(resultados.first);
  }

  static Map<String, dynamic> _decodificarResultadoEnsaio(Map<String, dynamic> resultado) {
    final mapa = Map<String, dynamic>.from(resultado);
    final dados = mapa['dados'];
    mapa['dados'] = dados is String && dados.isNotEmpty ? jsonDecode(dados) : (dados ?? {});
    if (mapa['conforme'] is num) mapa['conforme'] = mapa['conforme'] == 1;
    return mapa;
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

  Future<int> atualizarParalelismoProjeto(String projetoId, Map<String, dynamic> paralelismo) async {
    final db = await database;
    return await db.update(
      'projetos',
      {'paralelismo': jsonEncode(paralelismo)},
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
    bool sincronizado = false,
  }) async {
    final db = await database;
    return await db.update(
      'projetos',
      {
        'status': novoStatus,
        'history': jsonEncode(historicoCompleto),
        'sincronizado': sincronizado ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [projetoId],
    );
  }
}