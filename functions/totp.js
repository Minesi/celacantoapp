// functions/totp.js
// TOTP (RFC 6238, SHA-1, 6 digitos, 30 s) compativel com Google/Microsoft Authenticator.
const crypto = require("crypto");

const PERIODO_S = 30;
const DIGITOS = 6;
const ALFABETO_BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function gerarSegredoBase32(bytes = 20) {
  const buffer = crypto.randomBytes(bytes);
  let bits = "";
  for (const byte of buffer) bits += byte.toString(2).padStart(8, "0");
  let saida = "";
  for (let i = 0; i + 5 <= bits.length; i += 5) {
    saida += ALFABETO_BASE32[parseInt(bits.slice(i, i + 5), 2)];
  }
  return saida;
}

function decodificarBase32(texto) {
  let bits = "";
  for (const caractere of texto.replace(/=+$/, "").toUpperCase()) {
    const valor = ALFABETO_BASE32.indexOf(caractere);
    if (valor < 0) throw new Error("Segredo base32 invalido.");
    bits += valor.toString(2).padStart(5, "0");
  }
  const bytes = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(bytes);
}

function codigoDoPasso(segredoBase32, passo) {
  const contador = Buffer.alloc(8);
  contador.writeBigUInt64BE(BigInt(passo));
  const hmac = crypto.createHmac("sha1", decodificarBase32(segredoBase32)).update(contador).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const binario = (hmac.readUInt32BE(offset) & 0x7fffffff) % 10 ** DIGITOS;
  return binario.toString().padStart(DIGITOS, "0");
}

function passoAtual(agoraMs = Date.now()) {
  return Math.floor(agoraMs / 1000 / PERIODO_S);
}

// Retorna o passo que casou (janela de +-1 periodo para diferenca de relogio) ou null.
function verificarCodigo(segredoBase32, codigo, agoraMs = Date.now(), janela = 1) {
  if (!/^\d{6}$/.test(codigo || "")) return null;
  const atual = passoAtual(agoraMs);
  for (let delta = -janela; delta <= janela; delta++) {
    const esperado = codigoDoPasso(segredoBase32, atual + delta);
    if (crypto.timingSafeEqual(Buffer.from(esperado), Buffer.from(codigo))) return atual + delta;
  }
  return null;
}

function montarUriOtpauth({ segredoBase32, conta, emissor }) {
  const rotulo = encodeURIComponent(`${emissor}:${conta}`);
  const parametros = new URLSearchParams({
    secret: segredoBase32,
    issuer: emissor,
    algorithm: "SHA1",
    digits: String(DIGITOS),
    period: String(PERIODO_S),
  });
  return `otpauth://totp/${rotulo}?${parametros.toString()}`;
}

module.exports = { gerarSegredoBase32, verificarCodigo, montarUriOtpauth, codigoDoPasso, passoAtual };
