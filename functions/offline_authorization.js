const crypto = require("crypto");

const VERSAO = 1;
const MAX_CLOCK_SKEW_MS = 2 * 60 * 1000;
const MAX_VALIDADE_MS = 15 * 60 * 1000;
const MAX_RECONCILIACAO_ATRASO_MS = 30 * 24 * 60 * 60 * 1000;
const SPKI_ED25519_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

function decodificarBase64Url(valor, campo) {
  if (typeof valor !== "string" || valor.length === 0 || !/^[A-Za-z0-9+/_=-]+$/.test(valor)) {
    throw new Error(`${campo} em Base64 invalido.`);
  }
  let normalizado = valor.replace(/-/g, "+").replace(/_/g, "/");
  normalizado += "=".repeat((4 - normalizado.length % 4) % 4);
  return Buffer.from(normalizado, "base64");
}

function decodificarToken(token, campo) {
  const texto = decodificarBase64Url(token, campo).toString("utf8");
  try {
    return { texto, valor: JSON.parse(texto) };
  } catch (erro) {
    throw new Error(`${campo} JSON invalido.`, { cause: erro });
  }
}

function textoObrigatorio(valor, campo) {
  if (typeof valor !== "string" || valor.trim() === "") throw new Error(`${campo} obrigatorio.`);
  return valor;
}

function contextoDaSolicitacao(contexto) {
  if (!contexto || typeof contexto !== "object" || Array.isArray(contexto)) {
    throw new Error("Contexto da solicitacao ausente.");
  }
  return {
    projetoId: textoObrigatorio(contexto.projetoId, "projetoId"),
    salaId: typeof contexto.salaId === "string" ? contexto.salaId : "",
    ensaioTipo: typeof contexto.ensaioTipo === "string" ? contexto.ensaioTipo : "",
    ferramentaTipo: typeof contexto.ferramentaTipo === "string" ? contexto.ferramentaTipo : "",
    ferramentaTag: typeof contexto.ferramentaTag === "string" ? contexto.ferramentaTag : "",
    justificativa: textoObrigatorio(contexto.justificativa, "justificativa"),
  };
}

function analisarToken(token, agoraMs = Date.now(), toleranciaExpiracaoMs = 0) {
  const envelopeDecodificado = decodificarToken(token, "Autorizacao");
  const envelope = envelopeDecodificado.valor;
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope) || envelope.versao !== VERSAO) {
    throw new Error("Versao da autorizacao invalida.");
  }

  const requestToken = textoObrigatorio(envelope.solicitacao, "solicitacao");
  const requestDecodificado = decodificarToken(requestToken, "Solicitacao");
  const request = requestDecodificado.valor;
  if (!request || typeof request !== "object" || Array.isArray(request) || request.versao !== VERSAO) {
    throw new Error("Versao da solicitacao invalida.");
  }

  const nonce = textoObrigatorio(request.nonce, "nonce");
  const emitidaEm = Number(request.emitidaEm);
  const expiraEm = Number(request.expiraEm);
  if (!Number.isSafeInteger(emitidaEm) || !Number.isSafeInteger(expiraEm)) {
    throw new Error("Datas da solicitacao invalidas.");
  }
  if (emitidaEm > agoraMs + MAX_CLOCK_SKEW_MS) throw new Error("Solicitacao emitida no futuro.");
  if (expiraEm <= agoraMs && agoraMs - expiraEm > toleranciaExpiracaoMs) {
    throw new Error("Solicitacao expirada.");
  }
  if (expiraEm <= emitidaEm || expiraEm - emitidaEm > MAX_VALIDADE_MS) {
    throw new Error("Validade da solicitacao invalida.");
  }

  const assinatura = decodificarBase64Url(textoObrigatorio(envelope.assinatura, "assinatura"), "assinatura");
  if (assinatura.length !== 64) throw new Error("Assinatura Ed25519 invalida.");

  return {
    envelope,
    request,
    requestToken,
    requestPayload: Buffer.from(requestDecodificado.texto, "utf8"),
    nonce,
    contexto: contextoDaSolicitacao(request.contexto),
    assinatura,
    supervisorUid: textoObrigatorio(envelope.supervisorUid, "supervisorUid"),
  };
}

function chavePublicaEd25519(publicKeyBase64) {
  const chave = decodificarBase64Url(publicKeyBase64, "publicKey");
  if (chave.length !== 32) throw new Error("Chave publica Ed25519 invalida.");
  return crypto.createPublicKey({
    key: Buffer.concat([SPKI_ED25519_PREFIX, chave]),
    format: "der",
    type: "spki",
  });
}

function verificarToken(token, publicKeyBase64, agoraMs = Date.now(), toleranciaExpiracaoMs = 0) {
  const analisado = analisarToken(token, agoraMs, toleranciaExpiracaoMs);
  const publicKey = chavePublicaEd25519(publicKeyBase64);
  const valido = crypto.verify(null, analisado.requestPayload, publicKey, analisado.assinatura);
  if (!valido) throw new Error("Assinatura offline invalida.");
  return analisado;
}

function codificarToken(valor) {
  return Buffer.from(JSON.stringify(valor), "utf8").toString("base64url");
}

function codificarChavePublica(publicKey) {
  const der = publicKey.export({ type: "spki", format: "der" });
  return der.subarray(der.length - 32).toString("base64");
}

module.exports = {
  MAX_CLOCK_SKEW_MS,
  MAX_VALIDADE_MS,
  MAX_RECONCILIACAO_ATRASO_MS,
  analisarToken,
  verificarToken,
  codificarToken,
  codificarChavePublica,
};
