const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");
const {
  condicoesDeEnsaios,
  instrumentosUtilizados,
  normalizarTagsTemplate,
  placeholdersDeResultados,
} = require("./modelo_cliente");

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

test("separa resultados de velocidade, integridade e paralelismo", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "velocidadeFluxo", filtroIndice: "1", valor05um: "0,46" },
      { ensaioTipo: "integridadeFiltros", valor05um: "0,006" },
      { ensaioTipo: "paralelismoFluxo", valor05um: "3" },
      { ensaioTipo: "paralelismoFluxo", valor05um: "5" },
    ],
    resultadosEnsaios: [
      {
        ensaioTipo: "velocidadeFluxo",
        dados: { media: "0.46", desvioPadraoRelativo: "12.5" },
      },
    ],
  });

  assert.equal(dados.res_vel, "0,46");
  assert.equal(dados.cal_res_vel, "12,5%");
  assert.equal(dados.res_media_vel, "0,46");
  assert.equal(dados.cal_res_media_vel, "12,5%");
  assert.equal(dados.cal_res_int, "0,006%");
  assert.equal(dados.res_para, "3");
  assert.equal(dados.cal_res_para, "5°");
  assert.equal(dados.cal_res_para_1, "3°");
  assert.equal(dados.cal_res_para_2, "5°");
  assert.equal(dados.res_vel_p1_f1, "0,46");
  assert.equal(dados.res_vel_p1_f2, "-");
  assert.equal(dados.res_vel.includes("|"), false);
  assert.equal(dados.cal_res_vel.includes("|"), false);
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

test("modelo Fluxo Laminar não exibe o registro estruturado dos ensaios", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  normalizarTagsTemplate(zip);
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({
    "NOME DO CLIENTE": "CLIENTE",
    ...condicoesDeEnsaios({ ensaiosSelecionados: [] }),
  });
  const texto = doc.getZip().file("word/document.xml").asText().replace(/<[^>]+>/g, "");
  for (const removido of ["REGISTRO ESTRUTURADO DOS ENSAIOS", "MAQUINAS", "SALAS E FILTROS", "PONTOS DE LEITURA"]) {
    assert.equal(texto.includes(removido), false, removido);
  }
  assert.equal(texto.includes("{#handlingUnits}"), false);
  assert.equal(texto.includes("{/pontosPorEnsaio}"), false);
});

test("modelo Fluxo Laminar usa tags exclusivas para cada resultado", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  const documento = zip.file("word/document.xml").asText();
  const cabecalho = zip.file("word/header1.xml").asText();

  for (const tag of [
    "{res_vel}",
    "{cal_res_vel}",
    "{res_media_vel}",
    "{cal_res_media_vel}",
    "{res_int}",
    "{cal_res_int}",
    "{res_vis}",
    "{res_para}",
    "{cal_res_para}",
  ]) {
    assert.match(documento, new RegExp(tag.replace(/[{}]/g, "\\$&")), tag);
  }
  assert.match(cabecalho, /\{CODIGO SEQUENCIAL\}/);
  for (const tagAntiga of ["{RESULTADO}", "{CALCULO RESULTADO}", "{Resultado 1}", "{Calculo resultado 1}"]) {
    assert.equal(documento.includes(tagAntiga), false, tagAntiga);
  }
  assert.equal(documento.includes("REGISTRO ESTRUTURADO DOS ENSAIOS"), false);
  assert.equal((documento.match(/<w:pageBreakBefore\/>/g) || []).length >= 11, true);
});

test("modelo Fluxo Laminar renderiza unidades e codigo nos campos corretos", () => {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "fluxo_laminar.docx")));
  normalizarTagsTemplate(zip);
  const pontosLeitura = [
    { ensaioTipo: "avaliacaoFiltragem", filtroIndice: "1", valor05um: "0.45" },
    { ensaioTipo: "velocidadeFluxo", filtroIndice: "1", valor05um: "0.46" },
    { ensaioTipo: "integridadeFiltros", filtroIndice: "1", valor05um: "0.006" },
    { ensaioTipo: "nivelRuido", valor05um: "60" },
    { ensaioTipo: "luminosidade", valor05um: "500" },
    { ensaioTipo: "contagemParticulas", valor05um: "100", valor5um: "5", estado: "repouso" },
    { ensaioTipo: "contagemParticulas", valor05um: "120", valor5um: "6", estado: "operacao" },
    { ensaioTipo: "visualizacaoFluxo", valor05um: "Fluxo descendente conforme" },
    { ensaioTipo: "paralelismoFluxo", valor05um: "3" },
    { ensaioTipo: "paralelismoFluxo", valor05um: "5" },
  ];
  const valores = placeholdersDeResultados({
    pontosLeitura,
    resultadosEnsaios: [{ ensaioTipo: "velocidadeFluxo", dados: { media: "0.46", desvioPadraoRelativo: "12.5" } }],
  });
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({
    ...condicoesDeEnsaios({
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
    }),
    "CODIGO SEQUENCIAL": "PRJ-TESTE-001",
    ...valores,
  });
  const documento = doc.getZip().file("word/document.xml").asText().replace(/<[^>]+>/g, "");
  const cabecalho = doc.getZip().file("word/header1.xml").asText().replace(/<[^>]+>/g, "");
  for (const esperado of ["0,46", "12,5%", "Cálculo: 12,5%", "0,006%", "3°", "5°", "Fluxo descendente conforme"]) {
    assert.equal(documento.includes(esperado), true, esperado);
  }
  assert.equal(cabecalho.includes("PRJ-TESTE-001"), true);
  assert.equal(documento.includes("REGISTRO ESTRUTURADO DOS ENSAIOS"), false);
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
