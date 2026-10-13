const MAX_FALHAS_LIBERACAO = 5;
const JANELA_FALHAS_MS = 10 * 60 * 1000;

function limiteDeTentativas(tentativas = {}, agora = Date.now()) {
  const dentroDaJanela = Boolean(tentativas.inicioMs && agora - tentativas.inicioMs < JANELA_FALHAS_MS);
  const bloqueado = dentroDaJanela && (tentativas.falhas || 0) >= MAX_FALHAS_LIBERACAO;
  return { bloqueado, dentroDaJanela };
}

function registrarFalha(tentativas = {}, agora = Date.now()) {
  const { dentroDaJanela } = limiteDeTentativas(tentativas, agora);
  return {
    falhas: dentroDaJanela ? (tentativas.falhas || 0) + 1 : 1,
    inicioMs: dentroDaJanela ? tentativas.inicioMs : agora,
  };
}

function passoPodeSerUsado(ultimoPasso, passo) {
  return (ultimoPasso || 0) < passo;
}

module.exports = {
  MAX_FALHAS_LIBERACAO,
  JANELA_FALHAS_MS,
  limiteDeTentativas,
  registrarFalha,
  passoPodeSerUsado,
};
