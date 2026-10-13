const test = require("node:test");
const assert = require("node:assert/strict");
const totp = require("./totp");
const policy = require("./liberacao_policy");

const segredoRfc = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

 test("TOTP segue os vetores RFC 6238 com SHA-1", () => {
  const vetores = [
    [59000, "287082"],
    [1111111109000, "081804"],
    [1111111111000, "050471"],
    [1234567890000, "005924"],
    [2000000000000, "279037"],
    [20000000000000, "353130"],
  ];

  for (const [tempo, codigo] of vetores) {
    assert.equal(totp.codigoDoPasso(segredoRfc, totp.passoAtual(tempo)), codigo);
    assert.equal(totp.verificarCodigo(segredoRfc, codigo, tempo), totp.passoAtual(tempo));
  }
});

test("TOTP aceita apenas a janela de um periodo e rejeita formato invalido", () => {
  const passoAtual = 100;
  const agoraMs = passoAtual * 30 * 1000;
  const codigoAnterior = totp.codigoDoPasso(segredoRfc, passoAtual - 1);
  const codigoDistante = totp.codigoDoPasso(segredoRfc, passoAtual - 2);

  assert.equal(totp.verificarCodigo(segredoRfc, codigoAnterior, agoraMs), passoAtual - 1);
  assert.equal(totp.verificarCodigo(segredoRfc, codigoDistante, agoraMs), null);
  assert.equal(totp.verificarCodigo(segredoRfc, "12345", agoraMs), null);
  assert.equal(totp.verificarCodigo(segredoRfc, "abcdef", agoraMs), null);
});

test("politica bloqueia a quinta falha dentro de dez minutos e reinicia depois", () => {
  const inicioMs = 1_000_000;
  const tentativas = { falhas: policy.MAX_FALHAS_LIBERACAO, inicioMs };

  assert.equal(policy.limiteDeTentativas(tentativas, inicioMs + policy.JANELA_FALHAS_MS - 1).bloqueado, true);
  assert.equal(policy.limiteDeTentativas(tentativas, inicioMs + policy.JANELA_FALHAS_MS).bloqueado, false);
  assert.deepEqual(policy.registrarFalha(tentativas, inicioMs + policy.JANELA_FALHAS_MS), {
    falhas: 1,
    inicioMs: inicioMs + policy.JANELA_FALHAS_MS,
  });
});

test("politica rejeita reutilizacao do mesmo passo ou de passo anterior", () => {
  assert.equal(policy.passoPodeSerUsado(10, 10), false);
  assert.equal(policy.passoPodeSerUsado(10, 9), false);
  assert.equal(policy.passoPodeSerUsado(10, 11), true);
  assert.equal(policy.passoPodeSerUsado(undefined, 1), true);
});
