// lib/teste_catalogo_service.dart
// Catálogo de testes do domínio (resumo + tabela por tipo de teste), híbrido SQLite + Firestore
// no mesmo padrão de sistema_service.dart, para ser compartilhado entre usuários da empresa.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'ensaio_model.dart';
import 'firestore_colecoes.dart';
import 'teste_catalogo_model.dart';

class TesteCatalogoService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Retorna um registro por tipo de teste do catálogo padrão (criando localmente os que faltarem),
  /// indexado por `TipoEnsaio.name`.
  Future<Map<String, TesteCatalogoModel>> listarPorDominio(String dominio) async {
    try {
      final snapshotNuvem = await _firestore
          .collection(FirestoreColecoes.testesCatalogo)
          .where('dominio', isEqualTo: dominio)
          .get();
      for (final doc in snapshotNuvem.docs) {
        await _dbHelper.insertTesteCatalogo(TesteCatalogoModel.fromMap(doc.data()).toMap());
      }
    } catch (e) {
      debugPrint('TesteCatalogoService: modo offline ativo ou erro de sincronização: $e');
    }

    final locais = {
      for (final m in await _dbHelper.getTestesCatalogoPorDominio(dominio))
        m['tipoEnsaio'].toString(): TesteCatalogoModel.fromMap(m),
    };

    for (final ensaio in EnsaioModel.catalogoPadrao()) {
      if (locais.containsKey(ensaio.tipo.name)) continue;
      final novo = TesteCatalogoModel(tipoEnsaio: ensaio.tipo.name, dominioEmpresa: dominio);
      await _dbHelper.insertTesteCatalogo(novo.toMap());
      locais[novo.tipoEnsaio] = novo;
    }
    return locais;
  }

  Future<TesteCatalogoModel?> buscarPorTipo(String dominio, String tipoEnsaio) async {
    final mapa = await _dbHelper.getTesteCatalogo(dominio, tipoEnsaio);
    return mapa == null ? null : TesteCatalogoModel.fromMap(mapa);
  }

  Future<void> salvar(TesteCatalogoModel teste) async {
    final atualizado = teste.copyWith(atualizadoEm: DateTime.now());
    await _dbHelper.insertTesteCatalogo(atualizado.toMap());
    try {
      await _firestore
          .collection(FirestoreColecoes.testesCatalogo)
          .doc(atualizado.id)
          .set(atualizado.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('TesteCatalogoService: teste ${atualizado.id} salvo apenas localmente: $e');
    }
  }
}
