import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  final token = base64UrlEncode(List<int>.generate(24, (_) => Random.secure().nextInt(256)));
  final boundary = 'celacanto_${DateTime.now().microsecondsSinceEpoch}';
  final uri = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/'
    '${Uri.encodeComponent(bucket)}/o'
    '?uploadType=multipart&name=${Uri.encodeComponent(caminhoStorage)}',
  );
  final metadata = utf8.encode(
    '${jsonEncode({
      'name': caminhoStorage,
      'contentType': contentType,
      'metadata': {'firebaseStorageDownloadTokens': token},
    })}\r\n',
  );
  final prefixo = utf8.encode(
    '--$boundary\r\n'
    'Content-Type: application/json; charset=UTF-8\r\n\r\n',
  );
  final separador = utf8.encode(
    '--$boundary\r\nContent-Type: $contentType\r\n\r\n',
  );
  final sufixo = utf8.encode('\r\n--$boundary--\r\n');
  final client = HttpClient();

  try {
    final request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $idToken',
    );
    request.headers.contentType = ContentType(
      'multipart',
      'related',
      parameters: {'boundary': boundary},
    );
    request.contentLength = prefixo.length + metadata.length + separador.length + bytes.length + sufixo.length;
    request.add(prefixo);
    request.add(metadata);
    request.add(separador);
    request.add(bytes);
    request.add(sufixo);

    final response = await request.close().timeout(const Duration(seconds: 30));
    final resposta = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detalhe = resposta.length > 300 ? resposta.substring(0, 300) : resposta;
      throw StateError(
        'Falha no upload da evidência (${response.statusCode}): $detalhe',
      );
    }

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

