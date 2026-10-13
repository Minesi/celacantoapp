const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");
const { condicoesDeEnsaios, instrumentosUtilizados, normalizarTagsTemplate } = require("./modelo_cliente");

function renderizarFluxoLaminar(projeto) {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  normalizarTagsTemplate(zip);
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({ "NOME DO CLIENTE": "CLIENTE", ...condicoesDeEnsaios(projeto) });
  const xml = doc.getZip().file("word/document.xml").asText();
  return xml.replace(/<[^>]+>/g, "");
}

test("numera em sequência somente os anexos visíveis", () => {
  const condicoes = condicoesDeEnsaios({ ensaiosSelecionados: ["integridadeFiltros"] });
  assert.equal(condicoes.ens_integridade, true);
  assert.equal(condicoes.ens_contagem, false);
  assert.equal(condicoes.ens_paralelismo, false);
  assert.equal(condicoes.anexo_integridade, "1");
  assert.equal(condicoes.anexo_calibracao, "2");
  assert.equal(condicoes.anexo_assinaturas, "3");
  assert.equal(condicoes.anexo_conclusao, "4");
});

test("mapeia todos os ensaios do Fluxo Laminar para suas seções", () => {
  const condicoes = condicoesDeEnsaios({
    ensaiosSelecionados: [
      "avaliacaoFiltragem",
      "velocidadeFluxo",
      "integridadeFiltros",
      "nivelRuido",
      "luminosidade",
      "contagemParticulas",
      "visualizacaoFluxo",
      "paralelismoFluxo",
    ],
  });
  for (const anexo of ["avaliacaoFiltragem", "velocidade", "integridade", "ruido", "luminosidade", "contagem", "visualizacao", "paralelismo"]) {
    assert.equal(condicoes[`ens_${anexo}`], true, anexo);
    assert.notEqual(condicoes[`anexo_${anexo}`], "", anexo);
  }
});

test("seleciona somente ferramentas de ensaios executados e remove TAG repetida", () => {
  const instrumentos = instrumentosUtilizados({
    ferramentasEscaneadas: {
      "Máquina de Fumaça": [
        { tipo: "Máquina de Fumaça", tag: "MF-01", numeroCertificado: "CERT-MF", validade: "12/2027" },
      ],
      Fotômetro: [
        { tipo: "Fotômetro", tag: "FOT-01", numeroCertificado: "CERT-FOT", validade: "12/2027" },
      ],
      Manômetro: [
        { tipo: "Manômetro", tag: "MAN-01", numeroCertificado: "CERT-MAN", validade: "12/2027" },
      ],
    },
    resultadosEnsaios: [{ ensaioTipo: "visualizacaoFluxo" }, { ensaioTipo: "integridadeFiltros" }],
    paralelismo: { resultado: "Linhas paralelas" },
  });

  assert.deepEqual(instrumentos.map((instrumento) => instrumento.tag), ["FOT-01", "MF-01"]);
  assert.deepEqual(instrumentos.find((instrumento) => instrumento.tag === "MF-01").ensaios, [
    "paralelismoFluxo",
    "visualizacaoFluxo",
  ]);
});

test("modelo Fluxo Laminar com 1 teste mostra apenas a integridade", () => {
  const texto = renderizarFluxoLaminar({ ensaiosSelecionados: ["integridadeFiltros"] });
  assert.match(texto, /Integridade e Estanqueidade dos Filtros HEPA/);
  assert.match(texto, /ANEXO 1 - INTEGRIDADE E ESTANQUEIDADE/);
  assert.match(texto, /Anexo 2 – Verificação da Calibração/);
  assert.match(texto, /Anexo 4 - Conclusão de Qualificação/);
  for (const ausente of [
    "Avaliação do Sistema de Filtragem",
    "VELOCIDADE E UNIFORMIDADE",
    "NÍVEL DE RUÍDO",
    "INTENSIDADE LUMINOSA",
    "Contagem de Partículas Não Viáveis",
    "VISUALIZAÇÃO DO FLUXO DE AR",
    "PARALELISMO DO FLUXO DE AR",
  ]) {
    assert.equal(texto.toUpperCase().includes(ausente.toUpperCase()), false, `não deveria conter "${ausente}"`);
  }
  assert.doesNotMatch(texto, /\{[#/]?(ens|anexo)_/);
});

test("modelo Fluxo Laminar inclui contagem e paralelismo quando selecionados", () => {
  const texto = renderizarFluxoLaminar({
    ensaiosSelecionados: ["integridadeFiltros", "contagemParticulas"],
    paralelismo: { resultado: "Linhas paralelas" },
  });
  assert.match(texto, /ANEXO 1 - INTEGRIDADE/);
  assert.match(texto, /ANEXO 2 - ENSAIO DE CONTAGEM/);
  assert.match(texto, /ANEXO 3 - PARALELISMO/);
  assert.match(texto, /Anexo 4 – Verificação da Calibração/);
  assert.match(texto, /Contagem de Partículas Não Viáveis “Em operação”/);
  assert.equal(texto.includes("NÍVEL DE RUÍDO"), false);
});

test("modelo Fluxo Laminar renderiza tabelas estruturadas com múltiplos itens", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  normalizarTagsTemplate(zip);
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({
    "NOME DO CLIENTE": "CLIENTE",
    ...condicoesDeEnsaios({ ensaiosSelecionados: [] }),
    handlingUnits: [
      { nome: "HU-A", numero: "1", temFiltroTerminalTexto: "Sim", filtrosResumo: "2x H14", salas: "SALA-A" },
      { nome: "HU-B", numero: "2", temFiltroTerminalTexto: "Nao", filtrosResumo: "1x F9", salas: "SALA-B" },
    ],
    salas: [
      { nome: "SALA-A", area: 10, volume: 30, maquina: "HU-A", filtrosResumo: "2x H14" },
      { nome: "SALA-B", area: 12, volume: 36, maquina: "HU-B", filtrosResumo: "1x F9" },
    ],
    resultadosPorEnsaio: [
      { ensaioTipo: "velocidadeFluxo", sala: "SALA-A", conformeTexto: "Conforme", resumo: "media: 0,45" },
      { ensaioTipo: "integridadeFiltros", sala: "SALA-B", conformeTexto: "Nao conforme", resumo: "criterio: 0,01%" },
    ],
    pontosPorEnsaio: [
      { ensaioTipo: "velocidadeFluxo", sala: "SALA-A", rotulo: "Filtro 1 (H14)", valorPrincipal: "0,45", valorSecundario: "-", estado: "Em repouso" },
      { ensaioTipo: "velocidadeFluxo", sala: "SALA-A", rotulo: "Filtro 2 (H14)", valorPrincipal: "0,47", valorSecundario: "-", estado: "Em repouso" },
    ],
  });
  const texto = doc.getZip().file("word/document.xml").asText().replace(/<[^>]+>/g, "");
  for (const esperado of ["HU-A", "HU-B", "SALA-A", "SALA-B", "Filtro 1 (H14)", "Filtro 2 (H14)", "Nao conforme"]) {
    assert.equal(texto.includes(esperado), true, esperado);
  }
  assert.equal(texto.includes("{#handlingUnits}"), false);
  assert.equal(texto.includes("{/pontosPorEnsaio}"), false);
});

test("modelo Fluxo Laminar repete a linha de calibração uma vez por instrumento", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  normalizarTagsTemplate(zip);
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({
    "NOME DO CLIENTE": "CLIENTE",
    ...condicoesDeEnsaios({ ensaiosSelecionados: [] }),
    instrumentosUtilizados: [
      { nome: "Fotômetro", tag: "FOT-01", certificado: "CERT-FOT", validade: "12/2027" },
      { nome: "Máquina de Fumaça", tag: "MF-01", certificado: "N/A", validade: "N/A" },
    ],
  });
  const texto = doc.getZip().file("word/document.xml").asText().replace(/<[^>]+>/g, "");
  assert.equal((texto.match(/FOT-01/g) || []).length, 1);
  assert.equal((texto.match(/MF-01/g) || []).length, 1);
  assert.equal((texto.match(/CERT-FOT/g) || []).length, 1);
  assert.equal(texto.includes("{#instrumentosUtilizados}"), false);
  assert.equal(texto.includes("{/instrumentosUtilizados}"), false);
});

test("modelo Fluxo Laminar restringe as tags do primeiro anexo ao ensaio de avaliação", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  const xml = zip.file("word/document.xml").asText();
  const textoDosParagrafos = (xml.match(/<w:p\b[\s\S]*?<\/w:p>/g) || [])
    .map((paragrafo) => [...paragrafo.matchAll(/<w:t\b[^>]*>([\s\S]*?)<\/w:t>/g)]
      .map((match) => match[1])
      .join(""))
    .join("\n");

  assert.match(textoDosParagrafos, /\{TAG INSTRUMENTO_AVALIACAO\}/);
  assert.match(textoDosParagrafos, /\{CERTIFICADO DE CALIBRAÇÃO_AVALIACAO\}/);
  assert.equal(textoDosParagrafos.includes("{TAG INSTRUMENTO}"), false);
  assert.equal(textoDosParagrafos.includes("{CERTIFICADO DE CALIBRAÇÃO}"), false);
});
