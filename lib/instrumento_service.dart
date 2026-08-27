// lib/instrumento_service.dart
// Centraliza o acesso híbrido (SQLite local + Firestore) aos instrumentos,
// antes duplicado entre gestao_ferramentas_page.dart e novo_projeto_page.dart.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'firestore_colecoes.dart';
import 'instrumento_model.dart';

class InstrumentoService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Reconstrói um InstrumentoModel a partir de uma linha do SQLite, com valores
  /// de reserva parametrizáveis para reproduzir o comportamento de cada tela.
  InstrumentoModel _daMapaSqlite(
    Map<String, dynamic> map, {
    required String dominioPadrao,
    String tagPadrao = '',
    String tipoPadrao = '',
    String numeroSeriePadrao = '',
    String numeroCertificadoPadrao = '',
    String validadePadrao = '',
  }) {
    final validadeStr = map['validade']?.toString() ?? validadePadrao;
    return InstrumentoModel(
      id: map['id']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? tipoPadrao,
      tag: map['tag']?.toString() ?? tagPadrao,
      numeroSerie: map['numeroSerie']?.toString() ?? numeroSeriePadrao,
      numeroCertificado: map['numeroCertificado']?.toString() ?? numeroCertificadoPadrao,
      validade: validadeStr,
      // Sempre recalcula comparando com a data atual, nunca confia apenas no flag salvo
      estaValido: InstrumentoModel.validadeEhValida(validadeStr),
      dominioEmpresa: map['dominio_empresa']?.toString() ?? dominioPadrao,
    );
  }

  Future<void> _salvarNoCacheLocal(InstrumentoModel instrumento, bool estaValido) async {
    final mapa = instrumento.toMap();
    mapa['estaValido'] = estaValido ? 1 : 0;
    await _dbHelper.insertInstrumento(mapa);
  }

  /// Carrega o cache local (chamando [aoCarregarCacheLocal] para resposta visual imediata)
  /// e, se possível, atualiza com os dados da nuvem filtrando pelo domínio da empresa,
  /// persistindo o resultado de volta no cache local.
  Future<List<InstrumentoModel>> listarPorDominio(
    String dominio, {
    void Function(List<InstrumentoModel> listaLocal)? aoCarregarCacheLocal,
  }) async {
    List<InstrumentoModel> listaAtual = [];

    try {
      final dadosLocais = await _dbHelper.getInstrumentos();
      listaAtual = dadosLocais
          .map((map) => _daMapaSqlite(map, dominioPadrao: dominio))
          .where((inst) => inst.dominioEmpresa == dominio)
          .toList();
      aoCarregarCacheLocal?.call(listaAtual);

      final snapshotNuvem = await _firestore
          .collection(FirestoreColecoes.instrumentos)
          .where('dominio_empresa', isEqualTo: dominio)
          .get();

      if (snapshotNuvem.docs.isNotEmpty) {
        final listaNuvem = <InstrumentoModel>[];
        for (final doc in snapshotNuvem.docs) {
          final inst = InstrumentoModel.fromFirestore(doc.data(), doc.id);
          final validadeOk = InstrumentoModel.validadeEhValida(inst.validade);
          final instAtualizado = InstrumentoModel(
            id: inst.id,
            tipo: inst.tipo,
            tag: inst.tag,
            numeroSerie: inst.numeroSerie,
            numeroCertificado: inst.numeroCertificado,
            validade: inst.validade,
            estaValido: validadeOk,
            dominioEmpresa: inst.dominioEmpresa,
          );
          listaNuvem.add(instAtualizado);
          await _salvarNoCacheLocal(instAtualizado, validadeOk);
        }
        listaAtual = listaNuvem;
      }
    } catch (e) {
      debugPrint("InstrumentoService: modo offline ativo ou erro de sincronização: $e");
    }

    return listaAtual;
  }

  /// Busca um instrumento pela TAG: primeiro no cache local, depois na nuvem.
  Future<InstrumentoModel?> buscarPorTag(
    String tag, {
    required String dominioPadrao,
    String tipoPadrao = '',
  }) async {
    final tagFormatada = tag.trim().toUpperCase();

    try {
      final db = await _dbHelper.database;
      final localRes = await db.query('instrumentos', where: 'tag = ?', whereArgs: [tagFormatada], limit: 1);

      if (localRes.isNotEmpty) {
        return _daMapaSqlite(
          localRes.first,
          dominioPadrao: dominioPadrao,
          tagPadrao: tagFormatada,
          tipoPadrao: tipoPadrao,
          numeroSeriePadrao: 'S/N',
          numeroCertificadoPadrao: 'N/A',
          validadePadrao: '01/2000',
        );
      }

      final nuvemRes = await _firestore
          .collection(FirestoreColecoes.instrumentos)
          .where('tag', isEqualTo: tagFormatada)
          .limit(1)
          .get();

      if (nuvemRes.docs.isNotEmpty) {
        return InstrumentoModel.fromFirestore(nuvemRes.docs.first.data(), nuvemRes.docs.first.id);
      }
    } catch (e) {
      debugPrint("InstrumentoService: erro na busca por TAG: $e");
    }

    return null;
  }
}
