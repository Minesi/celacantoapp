const test = require("node:test");
const assert = require("node:assert/strict");
const { perfilDoClaim } = require("./perfil_claims");

test("perfil do claim vem do documento válido e é nulo para perfis desconhecidos", () => {
  assert.equal(perfilDoClaim({ perfil: "admin" }), "admin");
  assert.equal(perfilDoClaim({ perfil: " Tecnico " }), "tecnico");
  assert.equal(perfilDoClaim({ perfil: "hacker" }), null);
  assert.equal(perfilDoClaim({}), null);
  assert.equal(perfilDoClaim(null), null);
});
