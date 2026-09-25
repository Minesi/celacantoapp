// lib/sistema_service.dart
// Centraliza o acesso híbrido (SQLite local + Firestore) aos sistemas (ex.: "HDA04"),
// no mesmo padrão de empresa_service.dart. Sistema é reutilizável entre relatórios do mesmo cliente.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'firestore_colecoes.dart';
import 'sistema_model.dart';

class SistemaService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Linhas locais anteriores à migração ficam sem 'dominio_empresa'; são sempre incluídas
  // para não sumirem da tela após este filtro por domínio (mesmo critério de empresa_service.dart).
  List<Map<String, dynamic>> _filtrarPorDominio(List<Map<String, dynamic>> lista, String dominio) {
    return lista.where((s) {
      final dominioLinha = (s['dominio_empresa'] ?? '').toString();
      return dominioLinha.isEmpty || dominioLinha == dominio;
    }).toList();
  }

  /// Sincroniza os sistemas do domínio a partir do Firestore para o cache local
  /// e retorna a lista local já atualizada, convertida para SistemaModel.
  Future<List<SistemaModel>> listarPorDominio(String dominio) async {
    try {
      final snapshotNuvem = await _firestore
          .collection(FirestoreColecoes.sistemas)
          .where('dominio', isEqualTo: dominio)
          .get();

      for (final doc in snapshotNuvem.docs) {
        final sistema = SistemaModel.fromFirestore(doc.data(), doc.id);
        await _dbHelper.insertSistema(sistema.toMap());
      }
    } catch (e) {
      debugPrint("SistemaService: modo offline ativo ou erro de sincronização: $e");
    }

    final dadosLocais = await _dbHelper.getSistemas();
    return _filtrarPorDominio(dadosLocais, dominio).map((m) => SistemaModel.fromMap(m)).toList();
  }

  /// Cria um novo sistema no Firestore e reflete no cache local com o ID gerado.
  Future<SistemaModel> criarSistema(SistemaModel sistema) async {
    final docRef = await _firestore.collection(FirestoreColecoes.sistemas).add(sistema.toFirestore());
    final sistemaComId = SistemaModel(
      id: docRef.id,
      nome: sistema.nome,
      areasAtendidas: sistema.areasAtendidas,
      dominioEmpresa: sistema.dominioEmpresa,
    );
    await _dbHelper.insertSistema(sistemaComId.toMap());
    return sistemaComId;
  }
}
