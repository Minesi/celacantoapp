// lib/usuario_service.dart
// Centraliza o acesso híbrido (SQLite local + Firestore) aos usuários,
// no mesmo padrão de instrumento_service.dart.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'firestore_colecoes.dart';
import 'usuario_model.dart';

class UsuarioService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Linhas locais anteriores à migração que criou 'dominio_empresa' ficam sem esse campo;
  // são sempre incluídas para não sumirem da tela após este filtro por domínio.
  List<Map<String, dynamic>> _filtrarPorDominio(List<Map<String, dynamic>> lista, String dominio) {
    return lista.where((u) {
      final dominioLinha = (u['dominio_empresa'] ?? '').toString();
      return dominioLinha.isEmpty || dominioLinha == dominio;
    }).toList();
  }

  /// Sincroniza os usuários do domínio a partir do Firestore para o cache local
  /// e retorna a lista local já atualizada (mesmo formato de Map usado pelo SQLite).
  Future<List<Map<String, dynamic>>> listarPorDominio(String dominio) async {
    try {
      final snapshotNuvem = await _firestore
          .collection(FirestoreColecoes.usuarios)
          .where('dominio_empresa', isEqualTo: dominio)
          .get();

      for (final doc in snapshotNuvem.docs) {
        final usuario = UsuarioModel.fromFirestore(doc.data(), doc.id);
        // Mapa manual: UsuarioModel.toMap() inclui 'uid', que não é coluna da tabela local 'usuarios'
        await _dbHelper.insertUsuario({
          'nome': usuario.nome,
          'cpf': usuario.cpf,
          'email': usuario.email,
          'perfil': usuario.perfil.name,
          'dominio_empresa': usuario.dominioEmpresa,
        });
      }
    } catch (e) {
      debugPrint("UsuarioService: modo offline ativo ou erro de sincronização: $e");
    }

    final dadosLocais = await _dbHelper.getUsuarios();
    return _filtrarPorDominio(dadosLocais, dominio);
  }
}
