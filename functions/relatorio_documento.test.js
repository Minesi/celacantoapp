const test = require("node:test");
const assert = require("node:assert/strict");
const {
  construirDocumento,
  extrairConclusao,
  pontosExigidos,
  rotulosDosPontos,
  situacao,
  montarAssinaturas,
} = require("./relatorio_documento");

function projetoFixture() {
  return {
    id: "PRJ-1",
    cnpjEmpresa: "11222333000181",
    tipoProjeto: "HVAC",
    sistemaId: "SYS-1",
    area: "Bloco A",
    salas: [{
      id: "S1",
      nome: "SALA 01",
      area: 10,
      volume: 30,
      grau: "d",
      handlingUnitId: "HU1",
      handlingUnitIdsAdicionais: ["HU2"],
      filtros: [{ tipo: "h14", quantidade: 2, marca: "Trox", modelo: "TFP", dimensoes: "610x610x48" }],
    }],
    handlingUnits: [{ id: "HU1", nome: "UTA-01", filtros: [] }, { id: "HU2", nome: "UTA-02", filtros: [] }],
    ensaiosSelecionados: ["pressao", "contagemParticulas"],
    ferramentasEscaneadas: {},
    pontosLeitura: [
      { salaId: "S1", ensaioTipo: "pressao", numeroPonto: 1, valor05um: "12.5" },
      { salaId: "S1", ensaioTipo: "pressao", numeroPonto: 2, valor05um: "13" },
    ],
    dataCriacao: "2026-09-01T12:00:00Z",
    operadorResponsavel: "redator@example.com",
    history: [
      { campo: "status", valorNovo: "pronto_para_campo", usuario: "redator@example.com", dataHora: "2026-09-01T12:00:00Z" },
      { campo: "status", valorNovo: "em_revisao", usuario: "tecnico@example.com", dataHora: "2026-09-02T12:00:00Z" },
      { campo: "status", valorNovo: "aprovado", usuario: "supervisor@example.com", dataHora: "2026-09-03T12:00:00Z", detalhes: { conclusao: { cumpre: true, comentarios: "Tudo conforme." } } },
    ],
    paralelismo: { resultado: "Linhas paralelas", fotoUrl: "" },
  };
}

test("reconstrói o relatório e ignora qualquer documento enviado pelo cliente", () => {
  const documento = construirDocumento({
    projeto: projetoFixture(),
    nomeEmpresa: "VET & CIA",
    sistemaNome: "HVAC 04",
    dataEmissao: "2026-09-30T12:00:00Z",
    resumosPorEnsaio: { pressao: "Resumo autorizado" },
    usuariosPorEmail: {
      "redator@example.com": { nome: "Redator", perfil: "redator" },
      "tecnico@example.com": { nome: "Técnico", perfil: "tecnico" },
      "supervisor@example.com": { nome: "Supervisor", perfil: "supervisor" },
    },
    documento: { blocos: [{ tipo: "paragrafo", texto: "MALICIOSO" }] },
    conclusao: extrairConclusao(projetoFixture()),
  });

  assert.equal(documento.titulo, "RELATÓRIO DE QUALIFICAÇÃO DE DESEMPENHO – Sistema de Tratamento e Distribuição de Ar-Condicionado (HVAC) – HVAC 04");
  assert.equal(JSON.stringify(documento).includes("MALICIOSO"), false);
  assert.equal(JSON.stringify(documento).includes("Resumo autorizado"), true);
  const tabelaResumo = documento.blocos.find((bloco) => bloco.tipo === "tabela" && bloco.cabecalho.includes("Situação"));
  assert.deepEqual(tabelaResumo.linhas.map((linha) => linha.slice(0, 2)), [
    ["1", "Diferencial de Pressão entre Salas"],
    ["2", "Contagem de Partículas Não Viáveis \"Em repouso\" e \"Em operação\""],
  ]);
  assert.deepEqual(tabelaResumo.linhas[0].slice(3), ["2/2", "Realizado"]);
  assert.equal(JSON.stringify(documento).includes("CUMPRE"), true);
});

test("não cria seção avulsa de Paralelismo sem registro legado", () => {
  const projeto = projetoFixture();
  projeto.paralelismo = null;
  const documento = construirDocumento({ projeto, nomeEmpresa: "EMPRESA", sistemaNome: "HVAC 04" });

  assert.equal(documento.blocos.some((bloco) => bloco.tipo === "titulo" && bloco.texto.includes("Paralelismo do Fluxo de Ar")), false);
});

test("mantém cálculo e rótulos de pontos do app", () => {
  const sala = { grau: "D", filtros: [{ tipo: "h14", quantidade: 2 }] };
  assert.equal(pontosExigidos(sala, "pressao"), 2);
  assert.deepEqual(rotulosDosPontos(sala, "pressao"), ["Filtro 1 (H14)", "Filtro 2 (H14)"]);
  assert.deepEqual(rotulosDosPontos({ grau: "a", filtros: [] }, "recuperacaoParticulas"), ["Inicial", "Gerada", "Final"]);
});

test("extrai conclusão somente do histórico de aprovação", () => {
  const projeto = projetoFixture();
  assert.deepEqual(extrairConclusao(projeto), { cumpre: true, comentarios: "Tudo conforme." });
  projeto.history = projectHistoryWithoutApproval(projeto.history);
  assert.equal(extrairConclusao(projeto), null);
});

test("monta assinaturas a partir das transições auditadas", () => {
  const projeto = projetoFixture();
  const assinaturas = montarAssinaturas(projeto, {
    "redator@example.com": { nome: "Redator", perfil: "redator" },
    "tecnico@example.com": { nome: "Técnico", perfil: "tecnico" },
    "supervisor@example.com": { nome: "Supervisor", perfil: "supervisor" },
  }, "2026-09-30T12:00:00Z", "outro@example.com");

  assert.deepEqual(assinaturas.map((item) => [item.papel, item.nome, item.funcao]), [
    ["Elaborado por", "Redator", "Elaborador"],
    ["Executado por", "Técnico", "Técnico"],
    ["Revisado por", "Supervisor", "Supervisor"],
    ["Aprovado por", "Supervisor", "Supervisor"],
  ]);
  assert.equal(assinaturas[0].data, "2026-09-01T12:00:00Z");
  assert.equal(assinaturas[2].data, "2026-09-03T12:00:00Z");
});

test("situação cobre os estados do resumo", () => {
  assert.equal(situacao(0, 0), "N.A");
  assert.equal(situacao(0, 2), "Pendente");
  assert.equal(situacao(1, 2), "Parcial");
  assert.equal(situacao(2, 2), "Realizado");
});

test("relatório de Fluxo Laminar inclui os oito ensaios com resultados preenchidos", () => {
  const tipos = [
    "avaliacaoFiltragem",
    "velocidadeFluxo",
    "integridadeFiltros",
    "nivelRuido",
    "luminosidade",
    "paralelismoFluxo",
    "visualizacaoFluxo",
    "contagemParticulas",
  ];
  const pontosPorTipo = {
    avaliacaoFiltragem: 2,
    velocidadeFluxo: 4,
    integridadeFiltros: 2,
    nivelRuido: 3,
    luminosidade: 4,
    paralelismoFluxo: 1,
    visualizacaoFluxo: 1,
    contagemParticulas: 4,
  };
  const pontosLeitura = [];
  for (const tipo of tipos) {
    const estados = tipo === "contagemParticulas" ? ["repouso", "operacao"] : [null];
    for (const estado of estados) {
      for (let numeroPonto = 1; numeroPonto <= pontosPorTipo[tipo]; numeroPonto++) {
        pontosLeitura.push({
          salaId: "S1",
          ensaioTipo: tipo,
          numeroPonto,
          estado,
          valor05um: tipo === "visualizacaoFluxo" || tipo === "paralelismoFluxo" ? "Conforme" : "1.00",
          valor5um: tipo === "contagemParticulas" ? "2" : "",
        });
      }
    }
  }

  const projeto = {
    ...projetoFixture(),
    tipoProjeto: "Fluxo Laminar",
    ensaiosSelecionados: tipos,
    salas: [{
      id: "S1",
      nome: "SALA FL-01",
      area: 12,
      volume: 36,
      grau: "d",
      handlingUnitId: "HU1",
      filtros: [{ tipo: "h14", quantidade: 2, marca: "Trox", modelo: "TFP", dimensoes: "610x610x48" }],
      configEnsaios: {
        velocidadeFluxo: { pontos: "2" },
        nivelRuido: { pontos: "3" },
        luminosidade: { pontos: "4" },
        paralelismoFluxo: { pontos: "1" },
        contagemParticulas: { pontos: "4" },
      },
    }],
    handlingUnits: [{ id: "HU1", nome: "FL-01", numero: "01", filtros: [] }],
    ferramentasEscaneadas: {
      "Manômetro": [{ tag: "MAN-FL-01", numeroSerie: "SN-MAN-01", numeroCertificado: "CERT-MAN-01", validade: "12/2030" }],
      "Anemômetro": [{ tag: "ANE-FL-01", numeroSerie: "SN-ANE-01", numeroCertificado: "CERT-ANE-01", validade: "12/2030" }],
      "Fotômetro": [{ tag: "FOT-FL-01", numeroSerie: "SN-FOT-01", numeroCertificado: "CERT-FOT-01", validade: "12/2030" }],
      "Decibelímetro": [{ tag: "DEC-FL-01", numeroSerie: "SN-DEC-01", numeroCertificado: "CERT-DEC-01", validade: "12/2030" }],
      "Luxímetro": [{ tag: "LUX-FL-01", numeroSerie: "SN-LUX-01", numeroCertificado: "CERT-LUX-01", validade: "12/2030" }],
      "Máquina de Fumaça": [{ tag: "MF-FL-01", numeroSerie: "SN-MF-01", numeroCertificado: "N/A", validade: "N/A" }],
      "Contador de Partículas": [{ tag: "CP-FL-01", numeroSerie: "SN-CP-01", numeroCertificado: "CERT-CP-01", validade: "12/2030" }],
    },
    pontosLeitura,
    paralelismo: { resultado: "Linhas de fluxo paralelas, sem turbulência ou refluxo.", fotoUrl: "" },
  };

  const documento = construirDocumento({
    projeto,
    nomeEmpresa: "EMPRESA FLUXO TESTE",
    sistemaNome: "FL-01",
    dataEmissao: "2026-10-07T12:00:00Z",
    conclusao: { cumpre: true, comentarios: "Todos os critérios atendidos." },
  });
  const tabelaResumo = documento.blocos.find((bloco) => bloco.tipo === "tabela" && bloco.cabecalho.includes("Situação"));

  assert.deepEqual(tabelaResumo.linhas.map((linha) => linha[1]), [
    "Avaliação do Sistema de Filtragem",
    "Velocidade e Uniformidade do Fluxo de Ar",
    "Integridade e Estanqueidade dos Filtros HEPA",
    "Nível de Ruído",
    "Luminosidade",
    "Paralelismo do Fluxo de Ar",
    "Visualização do Fluxo de Ar",
    "Contagem de Partículas Não Viáveis \"Em repouso\" e \"Em operação\"",
  ]);
  assert.deepEqual(tabelaResumo.linhas.map((linha) => [linha[3], linha[4]]), [
    ["2/2", "Realizado"],
    ["4/4", "Realizado"],
    ["2/2", "Realizado"],
    ["3/3", "Realizado"],
    ["4/4", "Realizado"],
    ["1/1", "Realizado"],
    ["1/1", "Realizado"],
    ["8/8", "Realizado"],
  ]);
  const tabelaContagem = documento.blocos.find((bloco) => bloco.tipo === "tabela" && bloco.cabecalho.includes("Estado"));
  assert.deepEqual(tabelaContagem.linhas.map((linha) => linha[1]), [
    "Repouso", "Repouso", "Repouso", "Repouso",
    "Operação", "Operação", "Operação", "Operação",
  ]);
});

function projectHistoryWithoutApproval(history) {
  return history.filter((entrada) => entrada.valorNovo !== "aprovado");
}