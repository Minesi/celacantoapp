// lib/projeto_service.dart
// Centraliza o acesso híbrido (SQLite local + Firestore) aos projetos/relatórios,
// no mesmo padrão de empresa_service.dart e instrumento_service.dart.
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'empresa_service.dart';
import 'execucao_projeto_service.dart';
import 'firestore_colecoes.dart';
import 'history_entry_model.dart';
import 'instrumento_model.dart';
import 'paralelismo_model.dart';
import 'projeto_model.dart';
import 'resultado_ensaio_model.dart';

class ProjetoService implements ExecucaoProjetoService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EmpresaService _empresaService = EmpresaService();

  /// Sincroniza os projetos das empresas do domínio a partir do Firestore para o cache local
  /// e retorna a lista local já atualizada (mesmo formato de Map usado pelo SQLite).
  Future<List<Map<String, dynamic>>> listarPorDominio(String dominio) async {
    try {
      final empresas = await _empresaService.listarPorDominio(dominio);
      final cnpjs = empresas
          .map((e) => e['cnpj']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();

      // Firestore 'whereIn' aceita no máximo 30 valores; suficiente para o volume atual de clientes.
      for (var i = 0; i < cnpjs.length; i += 30) {
        final lote = cnpjs.sublist(
          i,
          i + 30 > cnpjs.length ? cnpjs.length : i + 30,
        );
        if (lote.isEmpty) continue;

        final snapshotNuvem = await _firestore
            .collection(FirestoreColecoes.projetos)
            .where('cnpjEmpresa', whereIn: lote)
            .get();

        for (final doc in snapshotNuvem.docs) {
          await _dbHelper.insertProjetoSincronizado(doc.data());
        }
      }
    } catch (e) {
      debugPrint(
        "ProjetoService: modo offline ativo ou erro de sincronização: $e",
      );
    }

    return await _dbHelper.getProjetos();
  }

  /// Persiste um projeto recém-elaborado no Firestore (quando online) e sempre no cache local,
  /// incluindo salas/handling units/filtros nas tabelas normalizadas.
  Future<void> salvarNovoProjeto(
    ProjetoModel projeto, {
    required String operadorResponsavel,
    String templateUtilizado = '',
    DateTime? dataCriacao,
  }) async {
    final mapaCompleto = projeto.toMap()
      ..['dataCriacao'] = (dataCriacao ?? DateTime.now()).toIso8601String()
      ..['operadorResponsavel'] = operadorResponsavel
      ..['templateUtilizado'] = templateUtilizado;

    bool sincronizado = false;
    try {
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projeto.id)
          .set(mapaCompleto);
      sincronizado = true;
    } catch (e) {
      debugPrint(
        'ProjetoService: projeto ${projeto.id} salvo apenas localmente (offline): $e',
      );
    }

    final mapaSqlite = Map<String, dynamic>.from(mapaCompleto)
      ..remove('salas')
      ..remove('handlingUnits');
    await _dbHelper.insertProjeto(mapaSqlite);
    if (sincronizado) {
      await _dbHelper.marcarProjetoSincronizado(projeto.id);
    }

    await _dbHelper.substituirSalasDoProjeto(
      projeto.id,
      projeto.salas.map((s) => s.toMap()).toList(),
    );

    await _dbHelper.deleteHandlingUnitsPorProjeto(projeto.id);
    for (final handlingUnit in projeto.handlingUnits) {
      await _dbHelper.insertHandlingUnit({
        'id': handlingUnit.id,
        'projetoId': projeto.id,
        'nome': handlingUnit.nome,
        'numero': handlingUnit.numero,
        'temFiltroTerminal': handlingUnit.temFiltroTerminal ? 1 : 0,
        'qtdFiltrosTerminais': handlingUnit.qtdFiltrosTerminais,
      });
      await _dbHelper.deleteFiltrosPorHandlingUnit(handlingUnit.id);
      for (final filtro in handlingUnit.filtros) {
        await _dbHelper.insertFiltro({
          ...filtro.toMap(),
          'handlingUnitId': handlingUnit.id,
        });
      }
    }
  }

  /// Chave de separação dos pré-relatórios: empresa + tipo de teste + área + data até o minuto.
  static String chaveSeparacao({
    required String cnpjEmpresa,
    required String tipoProjeto,
    required String area,
    required DateTime dataHora,
  }) {
    final minuto = dataHora.toIso8601String().substring(0, 16);
    return '${cnpjEmpresa.trim()}|${tipoProjeto.trim().toLowerCase()}|${area.trim().toLowerCase()}|$minuto';
  }

  Future<bool> existeDuplicata({
    required String cnpjEmpresa,
    required String tipoProjeto,
    required String area,
    required DateTime dataHora,
  }) async {
    final chave = chaveSeparacao(
      cnpjEmpresa: cnpjEmpresa,
      tipoProjeto: tipoProjeto,
      area: area,
      dataHora: dataHora,
    );
    final projetos = await _dbHelper.getProjetos();
    return projetos.any((p) {
      final data = DateTime.tryParse(p['dataCriacao']?.toString() ?? '');
      if (data == null) return false;
      return chaveSeparacao(
            cnpjEmpresa: p['cnpjEmpresa']?.toString() ?? '',
            tipoProjeto: p['tipoProjeto']?.toString() ?? '',
            area: p['area']?.toString() ?? '',
            dataHora: data,
          ) ==
          chave;
    });
  }

  /// Envia os pontos de leitura locais do projeto para o doc do Firestore, para que o supervisor
  /// veja os resultados na aprovação mesmo em outro aparelho.
  @override
  Future<void> sincronizarPontosLeitura(
    String projetoId, {
    bool exigirSincronizacao = false,
  }) async {
    try {
      final pontos = await _dbHelper.getPontosLeituraPorProjeto(projetoId);
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set({'pontosLeitura': pontos}, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'ProjetoService: pontos de leitura salvos apenas localmente (offline?): $e',
      );
      if (exigirSincronizacao) rethrow;
    }
  }

  Future<void> adicionarHistorico(
    String projetoId,
    HistoryEntry entrada,
  ) async {
    final projetosLocais = await _dbHelper.getProjetos();
    final projetoAtual = projetosLocais.firstWhere(
      (p) => p['id'].toString() == projetoId,
      orElse: () => <String, dynamic>{},
    );
    final historicoBruto = projetoAtual['history']?.toString() ?? '';
    final historicoAtual = historicoBruto.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(jsonDecode(historicoBruto));
    historicoAtual.add(entrada.toMap());

    var sincronizado = false;
    try {
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set({'history': historicoAtual}, SetOptions(merge: true));
      sincronizado = true;
    } catch (e) {
      debugPrint(
        'ProjetoService: evento de auditoria salvo apenas localmente (offline?): $e',
      );
    }

    await _dbHelper.atualizarStatusEHistoricoProjeto(
      projetoId,
      novoStatus:
          projetoAtual['status']?.toString() ?? StatusRelatorio.rascunho.name,
      historicoCompleto: historicoAtual,
      sincronizado: sincronizado,
    );
  }

  /// Persiste apenas o vínculo de instrumentos escaneados em campo (sem regravar salas/handling
  /// units), usado quando o técnico associa ferramentas durante a execução de um ensaio.
  @override
  Future<void> atualizarFerramentasEscaneadas(
    String projetoId,
    Map<String, List<InstrumentoModel>> ferramentas,
  ) async {
    final mapaSerializado = ferramentas.map(
      (k, v) => MapEntry(k, v.map((i) => i.toMap()).toList()),
    );

    try {
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set({
            'ferramentasEscaneadas': mapaSerializado,
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'ProjetoService: ferramentas escaneadas salvas apenas localmente (offline?): $e',
      );
    }

    await _dbHelper.atualizarFerramentasEscaneadasProjeto(
      projetoId,
      mapaSerializado,
    );
  }

  Future<void> atualizarParalelismo(
    String projetoId,
    RegistroParalelismo registro,
  ) async {
    try {
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set({'paralelismo': registro.toMap()}, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'ProjetoService: paralelismo salvo apenas localmente (offline?): $e',
      );
    }
    await _dbHelper.atualizarParalelismoProjeto(projetoId, registro.toMap());
  }

  @override
  Future<void> salvarResultadoEnsaio(ResultadoEnsaioModel resultado) async {
    await _dbHelper.inserirResultadoEnsaio(resultado.toMap());
    try {
      final resultados = await _dbHelper.getResultadosEnsaioPorProjeto(
        resultado.projetoId,
      );
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(resultado.projetoId)
          .set({'resultadosEnsaios': resultados}, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'ProjetoService: resultado do ensaio salvo apenas localmente (offline?): $e',
      );
    }
  }

  /// Avança o status do fluxo de aprovação (rascunho -> pronto_para_campo -> em_revisao ->
  /// aprovado) e acrescenta uma entrada no histórico de auditoria, preservando o histórico
  /// já existente tanto no Firestore quanto no cache local.
  Future<void> registrarHistoricoEAtualizarStatus(
    String projetoId, {
    required StatusRelatorio novoStatus,
    required HistoryEntry novaEntrada,
    bool exigirSincronizacao = false,
  }) async {
    final projetosLocais = await _dbHelper.getProjetos();
    final projetoAtual = projetosLocais.firstWhere(
      (p) => p['id'].toString() == projetoId,
      orElse: () => <String, dynamic>{},
    );

    final historicoBruto = projetoAtual['history']?.toString() ?? '';
    final historicoAtual = historicoBruto.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(jsonDecode(historicoBruto));
    historicoAtual.add(novaEntrada.toMap());

    var sincronizado = false;
    try {
      await _firestore
          .collection(FirestoreColecoes.projetos)
          .doc(projetoId)
          .set({
            'status': novoStatus.name,
            'history': historicoAtual,
          }, SetOptions(merge: true));
      sincronizado = true;
    } catch (e) {
      debugPrint(
        'ProjetoService: status/histórico salvos apenas localmente (offline?): $e',
      );
      if (exigirSincronizacao) rethrow;
    }

    await _dbHelper.atualizarStatusEHistoricoProjeto(
      projetoId,
      novoStatus: novoStatus.name,
      historicoCompleto: historicoAtual,
      sincronizado: sincronizado,
    );
  }
}
