import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celacantoapp/offline_authorization_service.dart';

class _MemoryStorage implements OfflineAuthorizationStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

OfflineAuthorizationService _service(_MemoryStorage storage) {
  return OfflineAuthorizationService.forTesting(
    storage: storage,
    keyDerivation: Pbkdf2.hmacSha256(iterations: 1, bits: 256),
  );
}

OfflineAuthorizationContext _context({String projetoId = 'projeto-1', String ferramentaTag = 'TAG-1'}) {
  return OfflineAuthorizationContext(
    projetoId: projetoId,
    salaId: 'sala-1',
    ensaioTipo: 'pressao',
    ferramentaTipo: 'manometro',
    ferramentaTag: ferramentaTag,
    justificativa: 'Uso excepcional registrado pelo tecnico.',
  );
}

Future<String> _signedToken(OfflineAuthorizationService service, OfflineAuthorizationContext context) async {
  await service.criarChaveSupervisor(supervisorUid: 'supervisor-1', pin: '123456');
  final request = await service.emitirSolicitacao(contexto: context);
  return service.assinarSolicitacao(
    supervisorUid: 'supervisor-1',
    supervisorNome: 'Supervisor',
    supervisorEmail: 'supervisor@example.com',
    pin: '123456',
    requestToken: request,
  );
}

void main() {
  test('assina e verifica uma autorizacao com o mesmo contexto', () async {
    final service = _service(_MemoryStorage());
    final context = _context();
    final responseToken = await _signedToken(service, context);

    final envelope = await service.verificarAutorizacao(
      responseToken: responseToken,
      contextoEsperado: context,
    );

    expect(envelope.supervisorUid, 'supervisor-1');
    expect(envelope.supervisorNome, 'Supervisor');
  });

  test('rejeita contexto alterado depois da assinatura', () async {
    final service = _service(_MemoryStorage());
    final responseToken = await _signedToken(service, _context());

    await expectLater(
      service.verificarAutorizacao(
        responseToken: responseToken,
        contextoEsperado: _context(ferramentaTag: 'TAG-ALTERADA'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita solicitacao expirada', () async {
    final service = _service(_MemoryStorage());
    final context = _context();
    final agora = DateTime.now().toUtc();
    final request = OfflineAuthorizationRequest(
      nonce: 'nonce-expirado',
      contexto: context,
      emitidaEm: agora.subtract(const Duration(minutes: 10)),
      expiraEm: agora.subtract(const Duration(minutes: 5)),
    );
    final envelope = OfflineAuthorizationEnvelope(
      supervisorUid: 'supervisor-1',
      supervisorNome: 'Supervisor',
      supervisorEmail: 'supervisor@example.com',
      requestToken: request.toToken(),
      assinatura: base64UrlEncode([0]),
    ).toToken();

    await expectLater(
      service.verificarAutorizacao(responseToken: envelope, contextoEsperado: context),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita reutilizacao do mesmo nonce', () async {
    final service = _service(_MemoryStorage());
    final context = _context();
    final responseToken = await _signedToken(service, context);

    await service.verificarAutorizacao(responseToken: responseToken, contextoEsperado: context);
    await expectLater(
      service.verificarAutorizacao(responseToken: responseToken, contextoEsperado: context),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita chave publica ausente no dispositivo', () async {
    final signer = _service(_MemoryStorage());
    final context = _context();
    final responseToken = await _signedToken(signer, context);
    final verifier = _service(_MemoryStorage());

    await expectLater(
      verifier.verificarAutorizacao(responseToken: responseToken, contextoEsperado: context),
      throwsA(isA<FormatException>()),
    );
  });

  test('exige projeto para emitir solicitacao offline', () async {
    final service = _service(_MemoryStorage());

    await expectLater(
      service.emitirSolicitacao(contexto: _context(projetoId: '')),
      throwsA(isA<FormatException>()),
    );
  });
}
