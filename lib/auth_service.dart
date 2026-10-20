// lib/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'cloud_functions_client.dart';
import 'firestore_colecoes.dart';
import 'usuario_model.dart';
import 'offline_authorization_service.dart';

// redator = equipe de elaboração/estrutura prévia do relatório (antes de ir a campo)
enum PerfilUsuario { admin, tecnico, supervisor, redator }

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
          .collection(FirestoreColecoes.usuarios)
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      return resultado.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Falha ao verificar existência do e-mail: $e');
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
        await _sincronizarPerfilClaim();
        return await _buscarPerfilDoFirestore(userCredential.user!.uid);
      }
    } on FirebaseAuthException catch (e) {
      // --- TRATAMENTO OFFLINE ---
      // Só usa a sessão em cache quando o Firebase não pôde nem responder (falha de rede).
      // Uma rejeição real de credencial (senha errada, conta desabilitada, etc.) nunca cai aqui.
      final foiFalhaDeRede = e.code == 'network-request-failed' || e.code == 'timeout';
      if (foiFalhaDeRede && _auth.currentUser != null && _auth.currentUser!.email == email.trim().toLowerCase()) {
        return await _buscarPerfilDoFirestore(_auth.currentUser!.uid);
      }
      debugPrint('Falha de login: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Falha de login (erro inesperado): $e');
    }
    return null;
  }

  /// Registra o claim 'perfil' no servidor; falha não impede o login.
  Future<void> _sincronizarPerfilClaim() async {
    try {
      await chamarCallable('atualizarMeuPerfilClaim', {});
    } catch (e) {
      debugPrint('Falha ao sincronizar perfil no token: $e');
    }
  }

  /// Método auxiliar interno para buscar o perfil no Firestore (usa cache se offline)
  Future<UsuarioLogado?> _buscarPerfilDoFirestore(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection(FirestoreColecoes.usuarios).doc(uid).get();

      if (doc.exists && doc.data() != null) {
        final usuario = UsuarioModel.fromFirestore(
          doc.data() as Map<String, dynamic>, 
          doc.id
        );
        return UsuarioLogado(nome: usuario.nome, perfil: usuario.perfil);
      }
    } catch (e) {
      debugPrint('Falha ao buscar perfil no Firestore: $e');
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
      final resultado = await chamarCallable(
        'cadastrarUsuario',
        {
          'nome': nome.trim(),
          'cpf': cpf.trim(),
          'email': emailTratado,
          'senha': senha,
          'perfil': perfil.name,
        },
      );
      final uid = resultado['uid']?.toString();
      if (uid == null || uid.isEmpty) return false;

      final dbHelper = DatabaseHelper();
      try {
        // A conta e o perfil já foram criados no servidor; o cache local é apenas apoio offline.
        await dbHelper.insertUsuario({
          'nome': nome.trim(),
          'cpf': cpf.trim(),
          'email': emailTratado,
          'perfil': perfil.name,
          'dominio_empresa': dominio,
        });
      } catch (e) {
        debugPrint('Usuário criado no servidor, mas não foi cacheado localmente: $e');
      }

      return true;
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
          .collection(FirestoreColecoes.usuarios)
          .where('email', isEqualTo: emailTratado)
          .limit(1)
          .get();

      if (resultado.docs.isNotEmpty) {
        return resultado.docs.first.data();
      }
    } catch (e) {
      debugPrint('Falha ao buscar dados do usuário no Firestore: $e');
    }

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
          'perfil': usuarioLocal.first['perfil'] ?? 'tecnico',
          'dominio_empresa': usuarioLocal.first['dominio_empresa'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Falha ao buscar dados do usuário no cache local: $e');
    }

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
      debugPrint('Falha ao atualizar senha: $e');
      return false;
    }
  }

  Future<bool> excluirMinhaConta({required String senhaAtual}) async {
    final usuarioAtual = _auth.currentUser;
    final emailUsuario = usuarioAtual?.email?.trim().toLowerCase();
    if (usuarioAtual == null || emailUsuario == null || emailUsuario.isEmpty) return false;

    try {
      final credential = EmailAuthProvider.credential(email: emailUsuario, password: senhaAtual);
      await usuarioAtual.reauthenticateWithCredential(credential);
      await usuarioAtual.getIdToken(true);
      await chamarCallable('excluirMinhaConta', {});
    } catch (e) {
      debugPrint('Falha ao excluir conta no servidor: $e');
      return false;
    }

    try {
      final dbHelper = DatabaseHelper();
      final usuariosLocais = await dbHelper.getUsuarios();
      for (final usuario in usuariosLocais) {
        final emailLocal = (usuario['email'] ?? '').toString().trim().toLowerCase();
        final idLocal = usuario['id'];
        if (emailLocal == emailUsuario && idLocal is int) {
          await dbHelper.deleteUsuario(idLocal);
        }
      }
      await OfflineAuthorizationService.instance.removerDadosLocais(usuarioAtual.uid);
    } catch (e) {
      debugPrint('Conta excluída, mas não foi possível limpar todo o cache local: $e');
    }

    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Conta excluída, mas o logout local falhou: $e');
    }
    return true;
  }

  /// 6. Envia um e-mail de recuperação/redefinição de senha do Firebase Auth
  Future<bool> enviarEmailRecuperacao(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
      return true; // E-mail enviado com sucesso
    } catch (e) {
      debugPrint('Falha ao enviar e-mail de recuperação: $e');
      return false;
    }
  }
}