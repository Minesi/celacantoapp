import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_functions_client.dart';

abstract interface class OfflineAuthorizationStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});
}

class _FlutterSecureAuthorizationStorage implements OfflineAuthorizationStorage {
  const _FlutterSecureAuthorizationStorage(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) => _storage.write(key: key, value: value);
}

class OfflineAuthorizationContext {
  final String projetoId;
  final String salaId;
  final String ensaioTipo;
  final String ferramentaTipo;
  final String ferramentaTag;
  final String justificativa;

  const OfflineAuthorizationContext({
    required this.projetoId,
    required this.salaId,
    required this.ensaioTipo,
    required this.ferramentaTipo,
    required this.ferramentaTag,
    required this.justificativa,
  });

  Map<String, dynamic> toMap() => {
        'projetoId': projetoId,
        'salaId': salaId,
        'ensaioTipo': ensaioTipo,
        'ferramentaTipo': ferramentaTipo,
        'ferramentaTag': ferramentaTag,
        'justificativa': justificativa,
      };

  bool correspondeA(OfflineAuthorizationContext outro) {
    return projetoId == outro.projetoId &&
        salaId == outro.salaId &&
        ensaioTipo == outro.ensaioTipo &&
        ferramentaTipo == outro.ferramentaTipo &&
        ferramentaTag == outro.ferramentaTag &&
        justificativa == outro.justificativa;
  }
}

class OfflineAuthorizationRequest {
  final String nonce;
  final OfflineAuthorizationContext contexto;
  final DateTime emitidaEm;
  final DateTime expiraEm;

  const OfflineAuthorizationRequest({
    required this.nonce,
    required this.contexto,
    required this.emitidaEm,
    required this.expiraEm,
  });

  Map<String, dynamic> toMap() => {
        'versao': 1,
        'nonce': nonce,
        'emitidaEm': emitidaEm.toUtc().millisecondsSinceEpoch,
        'expiraEm': expiraEm.toUtc().millisecondsSinceEpoch,
        'contexto': contexto.toMap(),
      };

  String get payload => jsonEncode(toMap());

  String toToken() => _codificar(payload);

  static OfflineAuthorizationRequest fromToken(String token) {
    final mapa = jsonDecode(_decodificar(token));
    if (mapa is! Map<String, dynamic> || mapa['versao'] != 1) {
      throw FormatException('Solicitação offline inválida.');
    }
    final contexto = mapa['contexto'];
    if (contexto is! Map<String, dynamic>) {
      throw FormatException('Contexto da solicitação ausente.');
    }
    return OfflineAuthorizationRequest(
      nonce: _textoObrigatorio(mapa['nonce'], 'nonce'),
      emitidaEm: DateTime.fromMillisecondsSinceEpoch(_numeroObrigatorio(mapa['emitidaEm']), isUtc: true),
      expiraEm: DateTime.fromMillisecondsSinceEpoch(_numeroObrigatorio(mapa['expiraEm']), isUtc: true),
      contexto: OfflineAuthorizationContext(
        projetoId: _textoObrigatorio(contexto['projetoId'], 'projetoId'),
        salaId: _texto(contexto['salaId']),
        ensaioTipo: _texto(contexto['ensaioTipo']),
        ferramentaTipo: _texto(contexto['ferramentaTipo']),
        ferramentaTag: _texto(contexto['ferramentaTag']),
        justificativa: _textoObrigatorio(contexto['justificativa'], 'justificativa'),
      ),
    );
  }
}

class OfflineAuthorizationEnvelope {
  final String supervisorUid;
  final String supervisorNome;
  final String supervisorEmail;
  final String requestToken;
  final String assinatura;

  const OfflineAuthorizationEnvelope({
    required this.supervisorUid,
    required this.supervisorNome,
    required this.supervisorEmail,
    required this.requestToken,
    required this.assinatura,
  });

  Map<String, dynamic> toMap() => {
        'versao': 1,
        'supervisorUid': supervisorUid,
        'supervisorNome': supervisorNome,
        'supervisorEmail': supervisorEmail,
        'solicitacao': requestToken,
        'assinatura': assinatura,
      };

  String toToken() => _codificar(jsonEncode(toMap()));

  static OfflineAuthorizationEnvelope fromToken(String token) {
    final mapa = jsonDecode(_decodificar(token));
    if (mapa is! Map<String, dynamic> || mapa['versao'] != 1) {
      throw FormatException('Autorização offline inválida.');
    }
    return OfflineAuthorizationEnvelope(
      supervisorUid: _textoObrigatorio(mapa['supervisorUid'], 'supervisorUid'),
      supervisorNome: _texto(mapa['supervisorNome']),
      supervisorEmail: _texto(mapa['supervisorEmail']),
      requestToken: _textoObrigatorio(mapa['solicitacao'], 'solicitacao'),
      assinatura: _textoObrigatorio(mapa['assinatura'], 'assinatura'),
    );
  }
}

class OfflineAuthorizationService {
  static final OfflineAuthorizationService instance = OfflineAuthorizationService._();

  static const _publicKeysStorageKey = 'offline_authorization_public_keys_v1';
  static const _consumedNoncesStorageKey = 'offline_authorization_consumed_nonces_v1';
  static const _privateKeyPrefix = 'offline_authorization_private_v1_';
  static const _pinIterations = 150000;
  static const _validadeMaxima = Duration(minutes: 15);

  final OfflineAuthorizationStorage _storage;
  final Ed25519 _signatureAlgorithm;
  final AesGcm _encryptionAlgorithm;
  final Pbkdf2 _keyDerivation;
  final Random _random;

  OfflineAuthorizationService._({
    OfflineAuthorizationStorage? storage,
    Ed25519? signatureAlgorithm,
    AesGcm? encryptionAlgorithm,
    Pbkdf2? keyDerivation,
    Random? random,
  })  : _storage = storage ?? const _FlutterSecureAuthorizationStorage(FlutterSecureStorage()),
        _signatureAlgorithm = signatureAlgorithm ?? Ed25519(),
        _encryptionAlgorithm = encryptionAlgorithm ?? AesGcm.with256bits(),
        _keyDerivation = keyDerivation ??
            Pbkdf2.hmacSha256(iterations: _pinIterations, bits: 256),
        _random = random ?? Random.secure();

  OfflineAuthorizationService.forTesting({
    required OfflineAuthorizationStorage storage,
    Ed25519? signatureAlgorithm,
    AesGcm? encryptionAlgorithm,
    Pbkdf2? keyDerivation,
    Random? random,
  }) : this._(
          storage: storage,
          signatureAlgorithm: signatureAlgorithm,
          encryptionAlgorithm: encryptionAlgorithm,
          keyDerivation: keyDerivation,
          random: random,
        );

  Future<String> criarChaveSupervisor({
    required String supervisorUid,
    required String pin,
  }) async {
    _exigirPlataformaSegura();
    _validarPin(pin);
    if (supervisorUid.trim().isEmpty) throw FormatException('Supervisor inválido.');

    final seed = _bytesAleatorios(32);
    final salt = _bytesAleatorios(16);
    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final encryptionKey = await _keyDerivation.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final secretBox = await _encryptionAlgorithm.encrypt(seed, secretKey: encryptionKey);

    await _storage.write(
      key: _privateKeyPrefix + supervisorUid,
      value: jsonEncode({
        'publicKey': _codificarChavePublica(publicKey.bytes),
        'salt': _codificarBytes(salt),
        'secretBox': _codificarBytes(secretBox.concatenation()),
      }),
    );
    await _salvarChavePublica(supervisorUid, publicKey.bytes);
    return _codificarChavePublica(publicKey.bytes);
  }

  Future<String> emitirSolicitacao({
    required OfflineAuthorizationContext contexto,
    Duration validade = const Duration(minutes: 5),
  }) async {
    _validarContexto(contexto);
    if (validade <= Duration.zero || validade > _validadeMaxima) {
      throw FormatException('A validade da solicitação offline deve estar entre 1 segundo e 15 minutos.');
    }
    final agora = DateTime.now().toUtc();
    return OfflineAuthorizationRequest(
      nonce: _codificarBytes(_bytesAleatorios(16)),
      contexto: contexto,
      emitidaEm: agora,
      expiraEm: agora.add(validade),
    ).toToken();
  }

  Future<String> assinarSolicitacao({
    required String supervisorUid,
    required String supervisorNome,
    required String supervisorEmail,
    required String pin,
    required String requestToken,
  }) async {
    _exigirPlataformaSegura();
    _validarPin(pin);
    final solicitacao = OfflineAuthorizationRequest.fromToken(requestToken);
    _exigirSolicitacaoVigente(solicitacao);
    final keyPair = await _carregarChavePrivada(supervisorUid, pin);
    final assinatura = await _signatureAlgorithm.sign(
      utf8.encode(solicitacao.payload),
      keyPair: keyPair,
    );
    return OfflineAuthorizationEnvelope(
      supervisorUid: supervisorUid,
      supervisorNome: supervisorNome,
      supervisorEmail: supervisorEmail,
      requestToken: requestToken,
      assinatura: _codificarBytes(assinatura.bytes),
    ).toToken();
  }

  Future<OfflineAuthorizationEnvelope> verificarAutorizacao({
    required String responseToken,
    required OfflineAuthorizationContext contextoEsperado,
  }) async {
    _exigirPlataformaSegura();
    final envelope = OfflineAuthorizationEnvelope.fromToken(responseToken);
    final solicitacao = OfflineAuthorizationRequest.fromToken(envelope.requestToken);
    _exigirSolicitacaoVigente(solicitacao);
    if (!solicitacao.contexto.correspondeA(contextoEsperado)) {
      throw FormatException('A autorização não corresponde ao contexto solicitado.');
    }

    final publicKeyBytes = await _lerChavePublica(envelope.supervisorUid);
    if (publicKeyBytes == null) {
      throw FormatException('Chave do supervisor não está sincronizada neste dispositivo.');
    }
    final assinatura = Signature(
      _decodificarBytes(envelope.assinatura),
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
    final valida = await _signatureAlgorithm.verify(
      utf8.encode(solicitacao.payload),
      signature: assinatura,
    );
    if (!valida) throw FormatException('Assinatura offline inválida.');

    final consumidos = await _lerNoncesConsumidos();
    if (consumidos.contains(solicitacao.nonce)) {
      throw FormatException('Esta autorização offline já foi utilizada.');
    }
    consumidos.add(solicitacao.nonce);
    await _storage.write(key: _consumedNoncesStorageKey, value: jsonEncode(consumidos.toList()));
    return envelope;
  }

  Future<void> sincronizarChavesOnline() async {
    _exigirPlataformaSegura();
    final resposta = await chamarCallable('listarChavesAutorizacaoOffline', {});
    final chaves = resposta['chaves'];
    if (chaves is! List) return;
    for (final item in chaves) {
      if (item is! Map) continue;
      final uid = item['uid']?.toString() ?? '';
      final chave = item['publicKey']?.toString() ?? '';
      if (uid.isEmpty || chave.isEmpty) continue;
      await _salvarChavePublica(uid, _decodificarBytes(chave));
    }
  }

  Future<Map<String, dynamic>> reconciliarAutorizacao({required String responseToken}) {
    return chamarCallable('validarAutorizacaoOffline', {'token': responseToken});
  }

  Future<String?> publicKeyLocal(String supervisorUid) async {
    return _storage.read(key: _privateKeyPrefix + supervisorUid).then((valor) {
      if (valor == null) return null;
      final mapa = jsonDecode(valor);
      return mapa is Map ? mapa['publicKey']?.toString() : null;
    });
  }

  Future<SimpleKeyPair> _carregarChavePrivada(String supervisorUid, String pin) async {
    final valor = await _storage.read(key: _privateKeyPrefix + supervisorUid);
    if (valor == null) throw StateError('Autorização offline ainda não configurada.');
    final mapa = jsonDecode(valor);
    if (mapa is! Map<String, dynamic>) throw StateError('Chave offline corrompida.');
    final salt = _decodificarBytes(mapa['salt']?.toString() ?? '');
    final secretBox = SecretBox.fromConcatenation(
      _decodificarBytes(mapa['secretBox']?.toString() ?? ''),
      nonceLength: _encryptionAlgorithm.nonceLength,
      macLength: _encryptionAlgorithm.macAlgorithm.macLength,
    );
    final encryptionKey = await _keyDerivation.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final seed = await _encryptionAlgorithm.decrypt(secretBox, secretKey: encryptionKey);
    return _signatureAlgorithm.newKeyPairFromSeed(seed);
  }

  Future<void> _salvarChavePublica(String uid, List<int> chave) async {
    final chaves = await _lerChavesPublicas();
    chaves[uid] = _codificarChavePublica(chave);
    await _storage.write(key: _publicKeysStorageKey, value: jsonEncode(chaves));
  }

  Future<List<int>?> _lerChavePublica(String uid) async {
    final chaves = await _lerChavesPublicas();
    final valor = chaves[uid];
    return valor == null ? null : _decodificarBytes(valor.toString());
  }

  Future<Map<String, dynamic>> _lerChavesPublicas() async {
    final valor = await _storage.read(key: _publicKeysStorageKey);
    if (valor == null || valor.isEmpty) return {};
    final mapa = jsonDecode(valor);
    return mapa is Map ? Map<String, dynamic>.from(mapa) : {};
  }

  Future<Set<String>> _lerNoncesConsumidos() async {
    final valor = await _storage.read(key: _consumedNoncesStorageKey);
    if (valor == null || valor.isEmpty) return {};
    final lista = jsonDecode(valor);
    return lista is List ? lista.map((item) => item.toString()).toSet() : {};
  }

  void _exigirPlataformaSegura() {
    if (kIsWeb) throw UnsupportedError('Autorização offline não está disponível na Web.');
  }

  void _exigirSolicitacaoVigente(OfflineAuthorizationRequest solicitacao) {
    final agora = DateTime.now().toUtc();
    if (solicitacao.emitidaEm.isAfter(agora.add(const Duration(minutes: 2)))) {
      throw FormatException('A solicitação offline foi emitida no futuro.');
    }
    if (!agora.isBefore(solicitacao.expiraEm)) {
      throw FormatException('A solicitação de autorização expirou.');
    }
    final validade = solicitacao.expiraEm.difference(solicitacao.emitidaEm);
    if (validade <= Duration.zero || validade > _validadeMaxima) {
      throw FormatException('A validade da solicitação offline é inválida.');
    }
  }

  void _validarPin(String pin) {
    if (pin.length < 6 || pin.length > 32) {
      throw FormatException('O PIN da autorização offline deve ter entre 6 e 32 caracteres.');
    }
  }

  void _validarContexto(OfflineAuthorizationContext contexto) {
    if (contexto.projetoId.trim().isEmpty) {
      throw FormatException('Projeto é obrigatório para autorização offline.');
    }
    if (contexto.justificativa.trim().isEmpty) {
      throw FormatException('Justificativa é obrigatória para autorização offline.');
    }
  }

  List<int> _bytesAleatorios(int quantidade) {
    return List<int>.generate(quantidade, (_) => _random.nextInt(256));
  }
}

String _codificar(String texto) => base64UrlEncode(utf8.encode(texto));

String _decodificar(String texto) => utf8.decode(base64Url.decode(texto));

String _codificarBytes(List<int> bytes) => base64UrlEncode(bytes);

String _codificarChavePublica(List<int> bytes) => base64Encode(bytes);

List<int> _decodificarBytes(String texto) {
  var normalizado = texto.replaceAll('-', '+').replaceAll('_', '/');
  normalizado += '=' * ((4 - normalizado.length % 4) % 4);
  return base64Decode(normalizado);
}

String _texto(dynamic valor) => valor?.toString() ?? '';

String _textoObrigatorio(dynamic valor, String campo) {
  final texto = _texto(valor);
  if (texto.isEmpty) throw FormatException('Campo obrigatório ausente: $campo.');
  return texto;
}

int _numeroObrigatorio(dynamic valor) {
  if (valor is int) return valor;
  final numero = int.tryParse(_texto(valor));
  if (numero == null) throw FormatException('Data inválida na autorização offline.');
  return numero;
}
