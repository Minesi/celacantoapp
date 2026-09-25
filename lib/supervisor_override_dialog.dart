// lib/supervisor_override_dialog.dart
// Diálogo reutilizável para autorizações excepcionais que exigem credenciais de supervisor/admin
// (ex.: instrumento com calibração vencida, teste encerrado incompleto, resultado já lançado).
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'firestore_colecoes.dart';

// Valida a senha sem substituir a sessão (Firebase Auth) do usuário atualmente logado no app.
// Retorna o UID do usuário quando as credenciais são válidas.
Future<String?> _uidDasCredenciais(String email, String senha) async {
  // O SDK desktop (Windows/Linux) falha com "internal-error" em FirebaseApps secundários.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    return _uidDasCredenciaisViaRest(email, senha);
  }

  FirebaseApp? appTemporario;
  try {
    appTemporario = await Firebase.initializeApp(
      name: 'verificacao_liberacao_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final authTemporario = FirebaseAuth.instanceFor(app: appTemporario);
    final credencial =
        await authTemporario.signInWithEmailAndPassword(email: email.trim().toLowerCase(), password: senha);
    return credencial.user?.uid;
  } catch (e) {
    debugPrint('Falha na verificação de credenciais de liberação: $e');
    return null;
  } finally {
    if (appTemporario != null) {
      await appTemporario.delete();
    }
  }
}

Future<String?> _uidDasCredenciaisViaRest(String email, String senha) async {
  final client = HttpClient();
  try {
    final uri = Uri.https(
      'identitytoolkit.googleapis.com',
      '/v1/accounts:signInWithPassword',
      {'key': Firebase.app().options.apiKey},
    );
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'email': email.trim().toLowerCase(), 'password': senha, 'returnSecureToken': false}));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final corpo = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      debugPrint('Liberação recusada pelo Firebase Auth (REST ${response.statusCode}): $corpo');
      return null;
    }
    return (jsonDecode(corpo) as Map<String, dynamic>)['localId']?.toString();
  } catch (e) {
    debugPrint('Falha na verificação de credenciais de liberação (REST): $e');
    return null;
  } finally {
    client.close();
  }
}

Future<String?> _perfilPorUid(String uid) async {
  try {
    final doc = await FirebaseFirestore.instance.collection(FirestoreColecoes.usuarios).doc(uid).get();
    return doc.data()?['perfil']?.toString();
  } catch (e) {
    debugPrint('Falha ao buscar perfil do supervisor por UID: $e');
    return null;
  }
}

/// Mostra o diálogo de liberação e retorna `true` se um supervisor/admin autorizou a exceção
/// (senha validada de fato contra o Firebase Auth), ou `false` se cancelado/recusado.
Future<bool> solicitarLiberacaoSupervisor({
  required BuildContext context,
  required String titulo,
  required String mensagem,
}) async {
  final authService = AuthService();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  bool autorizado = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensagem),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail do Supervisor', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: senhaController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha de Liberação', prefixIcon: Icon(Icons.lock)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              showDialog(
                context: dialogContext,
                barrierDismissible: false,
                builder: (ctx) => const Center(child: CircularProgressIndicator()),
              );

              final email = emailController.text.trim();
              final uid = await _uidDasCredenciais(email, senhaController.text);
              final perfil = uid == null
                  ? null
                  : (await _perfilPorUid(uid) ?? (await authService.buscarDadosUsuario(email))?['perfil']?.toString());
              final perfilAutorizado = perfil == 'supervisor' || perfil == 'admin';
              if (uid != null && !perfilAutorizado) {
                debugPrint('Liberação negada: perfil de "$email" = ${perfil ?? 'usuário não encontrado'}');
              }

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(); // fecha o indicador de carregamento

              if (perfilAutorizado) {
                autorizado = true;
                Navigator.of(dialogContext).pop(); // fecha o diálogo de liberação
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Liberação autorizada pelo Supervisor!'), backgroundColor: Colors.orange),
                );
              } else {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Credenciais inválidas ou usuário sem nível de Supervisor!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
            child: const Text('Autorizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );

  // Controllers não são descartados aqui: o diálogo ainda os usa durante a animação de saída.
  return autorizado;
}
