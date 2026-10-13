const crypto = require("crypto");
const test = require("node:test");
const assert = require("node:assert/strict");
const offlineAuthorization = require("./offline_authorization");

function criarToken({ agoraMs = Date.now(), alterarPayload = false } = {}) {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");
  const solicitacao = {
    versao: 1,
    nonce: "nonce-1",
    emitidaEm: agoraMs - 1000,
    expiraEm: agoraMs + 5 * 60 * 1000,
    contexto: {
      projetoId: "projeto-1",
      salaId: "sala-1",
      ensaioTipo: "pressao",
      ferramentaTipo: "manometro",
      ferramentaTag: "TAG-1",
      justificativa: "Uso excepcional registrado pelo tecnico.",
    },
  };
  const requestToken = offlineAuthorization.codificarToken(solicitacao);
  const payload = Buffer.from(JSON.stringify(solicitacao), "utf8");
  const assinatura = crypto.sign(null, payload, privateKey).toString("base64url");
  const envelope = offlineAuthorization.codificarToken({
    versao: 1,
    supervisorUid: "supervisor-1",
    supervisorNome: "Supervisor",
    supervisorEmail: "supervisor@example.com",
    solicitacao: requestToken,
    assinatura,
  });
  if (alterarPayload) {
    const alterado = { ...solicitacao, contexto: { ...solicitacao.contexto, projetoId: "projeto-2" } };
    const requestAlterado = offlineAuthorization.codificarToken(alterado);
    const envelopeAlterado = offlineAuthorization.codificarToken({
      ...JSON.parse(Buffer.from(envelope, "base64url").toString("utf8")),
      solicitacao: requestAlterado,
    });
    return { token: envelopeAlterado, publicKey };
  }
  return { token: envelope, publicKey };
}

test("verifica token Ed25519 e chave publica Base64 padrão", () => {
  const { token, publicKey } = criarToken();
  const publicKeyBase64 = offlineAuthorization.codificarChavePublica(publicKey);
  const analisado = offlineAuthorization.verificarToken(token, publicKeyBase64);

  assert.equal(analisado.supervisorUid, "supervisor-1");
  assert.equal(analisado.contexto.projetoId, "projeto-1");
});

test("rejeita payload alterado depois da assinatura", () => {
  const { token, publicKey } = criarToken({ alterarPayload: true });
  const publicKeyBase64 = offlineAuthorization.codificarChavePublica(publicKey);

  assert.throws(
    () => offlineAuthorization.verificarToken(token, publicKeyBase64),
    /Assinatura offline invalida/,
  );
});

test("rejeita solicitacao expirada", () => {
  const agoraMs = Date.now();
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");
  const solicitacao = {
    versao: 1,
    nonce: "nonce-expirado",
    emitidaEm: agoraMs - 10 * 60 * 1000,
    expiraEm: agoraMs - 5 * 60 * 1000,
    contexto: { projetoId: "projeto-1", justificativa: "Motivo" },
  };
  const payload = Buffer.from(JSON.stringify(solicitacao), "utf8");
  const envelope = offlineAuthorization.codificarToken({
    versao: 1,
    supervisorUid: "supervisor-1",
    solicitacao: offlineAuthorization.codificarToken(solicitacao),
    assinatura: crypto.sign(null, payload, privateKey).toString("base64url"),
  });

  assert.throws(
    () => offlineAuthorization.verificarToken(
      envelope,
      offlineAuthorization.codificarChavePublica(publicKey),
      agoraMs,
    ),
    /Solicitacao expirada/,
  );

  assert.doesNotThrow(() => offlineAuthorization.verificarToken(
    envelope,
    offlineAuthorization.codificarChavePublica(publicKey),
    agoraMs,
    offlineAuthorization.MAX_RECONCILIACAO_ATRASO_MS,
  ));
});
