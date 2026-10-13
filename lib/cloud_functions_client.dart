// lib/cloud_functions_client.dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Chama uma Cloud Function callable. No Windows/Linux o plugin cloud_functions não tem
/// implementação nativa: usa o protocolo HTTPS de callable (POST {data} com ID token).
Future<Map<String, dynamic>> chamarCallable(
  String nome,
  Map<String, dynamic> payload, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) {
    final resultado = await FirebaseFunctions.instance
        .httpsCallable(nome, options: HttpsCallableOptions(timeout: timeout))
        .call(payload);
    return Map<String, dynamic>.from(resultado.data as Map);
  }

  final usuario = FirebaseAuth.instance.currentUser;
  if (usuario == null) throw Exception('Usuário não autenticado.');
  final token = await usuario.getIdToken();
  final projectId = Firebase.app().options.projectId;

  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.https('us-central1-$projectId.cloudfunctions.net', '/$nome'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(jsonEncode({'data': payload}));
    final response = await request.close().timeout(timeout);
    final texto = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> corpo;
    try {
      corpo = jsonDecode(texto) as Map<String, dynamic>;
    } on FormatException {
      debugPrint('$nome respondeu HTTP ${response.statusCode} sem JSON: '
          '${texto.length > 300 ? texto.substring(0, 300) : texto}');
      throw FirebaseFunctionsException(code: 'http-${response.statusCode}', message: 'HTTP ${response.statusCode}');
    }
    if (response.statusCode != 200 || corpo['error'] != null) {
      final erro = corpo['error'] as Map<String, dynamic>? ?? {};
      throw FirebaseFunctionsException(
        code: erro['status']?.toString().toLowerCase().replaceAll('_', '-') ?? 'http-${response.statusCode}',
        message: erro['message']?.toString() ?? 'HTTP ${response.statusCode}',
      );
    }
    return Map<String, dynamic>.from(corpo['result'] as Map);
  } finally {
    client.close();
  }
}
