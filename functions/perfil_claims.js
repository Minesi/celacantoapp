// Perfil gravado como custom claim "perfil" no token de autenticação (usado pelas regras do Storage).
const PERFIS_VALIDOS = new Set(["admin", "tecnico", "supervisor", "redator"]);

function perfilDoClaim(dados) {
  const perfil = String((dados || {}).perfil || "").trim().toLowerCase();
  return PERFIS_VALIDOS.has(perfil) ? perfil : null;
}

module.exports = { perfilDoClaim };
