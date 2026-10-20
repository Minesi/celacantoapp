import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

Future<String> enviarImagemStorage({
  required String caminhoArquivo,
  required String caminhoStorage,
}) async {
  final arquivo = File(caminhoArquivo);
  if (!await arquivo.exists()) {
    throw StateError('Arquivo de evidência não encontrado.');
  }

  final contentType = _contentTypeDaExtensao(caminhoArquivo);
  if (!Platform.isWindows && !Platform.isLinux) {
    final referencia = FirebaseStorage.instance.ref(caminhoStorage);
    await referencia.putFile(
      arquivo,
      SettableMetadata(contentType: contentType),
    );
    return referencia.getDownloadURL();
  }

  return _enviarPorHttps(
    arquivo: arquivo,
    caminhoStorage: caminhoStorage,
    contentType: contentType,
  );
}

Future<String> _enviarPorHttps({
  required File arquivo,
  required String caminhoStorage,
  required String contentType,
}) async {
  final usuario = FirebaseAuth.instance.currentUser;
  if (usuario == null) throw StateError('Usuário não autenticado.');

  final idToken = await usuario.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw StateError('Token de autenticação indisponível.');
  }

  final bucket = Firebase.app().options.storageBucket;
  if (bucket == null || bucket.isEmpty) {
    throw StateError('Bucket do Firebase Storage não configurado.');
  }

  final bytes = await arquivo.readAsBytes();
  final uri = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/'
    '${Uri.encodeComponent(bucket)}/o'
    '?uploadType=media&name=${Uri.encodeComponent(caminhoStorage)}',
  );
  final client = HttpClient();

  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close().timeout(const Duration(seconds: 30));
    final resposta = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detalhe = resposta.length > 300 ? resposta.substring(0, 300) : resposta;
      throw StateError(
        'Falha no upload da evidência (${response.statusCode}): $detalhe',
      );
    }

    final dados = jsonDecode(resposta) as Map<String, dynamic>;
    final token = (dados['downloadTokens'] ?? '').toString().split(',').first;
    if (token.isEmpty) throw StateError('Storage não retornou token de download.');

    return 'https://firebasestorage.googleapis.com/v0/b/'
      '${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(caminhoStorage)}'
      '?alt=media&token=$token';
  } finally {
    client.close(force: true);
  }
}

String _contentTypeDaExtensao(String caminho) {
  final extensao = caminho.toLowerCase();
  if (extensao.endsWith('.png')) return 'image/png';
  if (extensao.endsWith('.webp')) return 'image/webp';
  if (extensao.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

