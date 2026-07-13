// lib/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'usuario_model.dart';

enum PerfilUsuario { operador, supervisor, admin }

class UsuarioLogado {
  final String nome;
  final PerfilUsuario perfil;
  UsuarioLogado({required this.nome, required this.perfil});
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // --- ATENÇÃO: Instâncias declaradas no escopo correto da classe ---
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Método utilitário para extrair o domínio corporativo pós-@ de forma higienizada
  String extrairDominio(String email) {
    if (!email.contains('@')) return '';
    return email.trim().toLowerCase().split('@').last;
  }

  /// 1. Verifica se o e-mail já está cadastrado no Firestore
  Future<bool> verificarSeEmailExiste(String email) async {
    try {
      final resultado = await _firestore
          .collection('usuarios')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      return resultado.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 2. Realiza o login (Suporta validação via Cache Offline se já logado antes)
  Future<UsuarioLogado?> loginLocal(String email, String senha) async {
    try {
      // 1. Tenta autenticar contra o servidor do Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: senha,
      );

      if (userCredential.user != null) {
        return await _buscarPerfilDoFirestore(userCredential.user!.uid);
      }
    } catch (e) {
      // --- TRATAMENTO OFFLINE ---
      if (_auth.currentUser != null && _auth.currentUser!.email == email.trim().toLowerCase()) {
        return await _buscarPerfilDoFirestore(_auth.currentUser!.uid);
      }
    }
    return null;
  }

  /// Método auxiliar interno para buscar o perfil no Firestore (usa cache se offline)
  Future<UsuarioLogado?> _buscarPerfilDoFirestore(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('usuarios').doc(uid).get();

      if (doc.exists && doc.data() != null) {
        final usuario = UsuarioModel.fromFirestore(
          doc.data() as Map<String, dynamic>, 
          doc.id
        );
        return UsuarioLogado(nome: usuario.nome, perfil: usuario.perfil);
      }
    } catch (_) {
      // Falha silenciosa para fallback
    }
    return null;
  }

  /// 3. Cadastra um novo usuário no Firebase Auth, salva o perfil no Firestore e mantém o registro local
  Future<bool> cadastrarUsuario({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
    required PerfilUsuario perfil,
  }) async {
    final emailTratado = email.trim().toLowerCase();
    final dominio = extrairDominio(emailTratado);

    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailTratado,
        password: senha,
      );

      if (userCredential.user == null) {
        return false;
      }

      final novoUsuario = UsuarioModel(
        uid: userCredential.user!.uid,
        nome: nome.trim(),
        cpf: cpf.trim(),
        email: emailTratado,
        perfil: perfil,
        dominioEmpresa: dominio,
      );

      await _firestore.collection('usuarios').doc(userCredential.user!.uid).set(novoUsuario.toMap());

      final dbHelper = DatabaseHelper();
      await dbHelper.insertUsuario({
        'nome': novoUsuario.nome,
        'cpf': novoUsuario.cpf,
        'email': novoUsuario.email,
        'senha': senha,
        'perfil': novoUsuario.perfil.name,
        'dominio_empresa': novoUsuario.dominioEmpresa,
      });

      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return false;
      }
      debugPrint('Falha ao criar usuário no Firebase Auth: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Falha ao criar usuário no Firebase Auth: $e');
      return false;
    }
  }

  /// 4. Recupera os dados completos do usuário logado (usado na PerfilPage)
  Future<Map<String, dynamic>?> buscarDadosUsuario(String email) async {
    final emailTratado = email.trim().toLowerCase();

    try {
      final resultado = await _firestore
          .collection('usuarios')
          .where('email', isEqualTo: emailTratado)
          .limit(1)
          .get();

      if (resultado.docs.isNotEmpty) {
        return resultado.docs.first.data();
      }
    } catch (_) {}

    try {
      final dbHelper = DatabaseHelper();
      final usuariosLocais = await dbHelper.getUsuarios();
      final usuarioLocal = usuariosLocais.where((u) {
        final emailBanco = (u['email'] ?? '').toString().toLowerCase();
        return emailBanco == emailTratado;
      }).toList();

      if (usuarioLocal.isNotEmpty) {
        return {
          'nome': usuarioLocal.first['nome'] ?? '',
          'cpf': usuarioLocal.first['cpf'] ?? '',
          'email': usuarioLocal.first['email'] ?? '',
          'perfil': usuarioLocal.first['perfil'] ?? 'operador',
          'dominio_empresa': usuarioLocal.first['dominio_empresa'] ?? '',
        };
      }
    } catch (_) {}

    return null;
  }

  /// 5. Atualiza a senha do usuário logado diretamente na infraestrutura do Firebase
  Future<bool> atualizarSenha({
    required String emailUsuario,
    required String senhaAtual,
    required String novaSenha,
  }) async {
    try {
      User? usuarioAtual = _auth.currentUser;
      if (usuarioAtual != null && usuarioAtual.email == emailUsuario) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: emailUsuario,
          password: senhaAtual,
        );
        
        await usuarioAtual.reauthenticateWithCredential(credential);
        await usuarioAtual.updatePassword(novaSenha);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  /// 6. Envia um e-mail de recuperação/redefinição de senha do Firebase Auth
  Future<bool> enviarEmailRecuperacao(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
      return true; // E-mail enviado com sucesso
    } catch (e) {
      // Você pode tratar erros específicos aqui se quiser (ex: usuário não encontrado)
      return false;
    }
  }
}