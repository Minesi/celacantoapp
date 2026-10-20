const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");
const {
  condicoesDeEnsaios,
  condicoesDePesagem,
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

function renderizarPesagem(projeto) {
  const zip = new PizZip(fs.readFileSync(path.join(__dirname, "templates", "pesagem.docx")));
  normalizarTagsTemplate(zip);
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render({ "NOME DO CLIENTE": "CLIENTE", ...condicoesDePesagem(projeto) });
  const xml = doc.getZip().file("word/document.xml").asText();
  return xml.replace(/<[^>]+>/g, "");
}

test("pesagem mostra somente os anexos dos ensaios selecionados e renumera", () => {
  const texto = renderizarPesagem({ ensaiosSelecionados: ["integridadeFiltros", "contagemParticulas"] });
  assert.match(texto, /ANEXO 1 - INTEGRIDADE E ESTANQUEIDADE/);
  assert.match(texto, /ANEXO 2 - ENSAIO DE CONTAGEM/);
  assert.match(texto, /Anexo 3 – Verificação da Calibração/);
  assert.doesNotMatch(texto, /AVALIAÇÃO DO SISTEMA DE FILTRAGEM/);
  assert.doesNotMatch(texto, /VELOCIDADE E UNIFORMIDADE/);
  assert.doesNotMatch(texto, /Avaliação do Sistema de Filtragem/);
  assert.match(texto, /Contagem de Partículas Não Viáveis “Em repouso”/);
  assert.match(texto, /Integridade e Estanqueidade dos Filtros HEPA/);
  assert.doesNotMatch(texto, /Visualização do Fluxo de Ar/);
});

test("tabela de testes segue a ordem dos anexos e inclui visualização quando selecionada", () => {
  const texto = renderizarPesagem({ ensaiosSelecionados: ["nivelRuido", "luminosidade", "visualizacaoFluxo"] });
  const posicao = (trecho) => texto.indexOf(trecho);
  assert.ok(posicao("Nível de Ruído") >= 0);
  assert.ok(posicao("Nível de Ruído") < posicao("Luminosidade"));
  assert.match(texto, /Visualização do Fluxo de Ar/);
  assert.ok(posicao("Visualização do Fluxo de Ar") < posicao("VISUALIZAÇÃO DO FLUXO DE AR"));
});

test("contagem usa limite por estado da elaboração e cai no padrão do Grau C", () => {
  const salas = [{
    id: "S1",
    nome: "SALA",
    area: 10,
    grau: "c",
    configEnsaios: { contagemParticulas: { criterioMax_repouso: "100000", criterioMax_operacao: "" } },
  }];
  const saida = placeholdersDeResultados({ pontosLeitura: [], resultadosEnsaios: [], salas });
  const [repouso, operacao] = saida.contagemLinhas;
  assert.equal(repouso.criterio05, "100000");
  assert.equal(repouso.criterio5, "2900");
  assert.equal(operacao.criterio05, "3520000");
  assert.equal(operacao.criterio5, "29000");
});

test("pesagem mostra paralelismo com resultado mesmo sem ensaio selecionado", () => {
  const condicoes = condicoesDePesagem({ ensaiosSelecionados: [], paralelismo: { resultado: "3°" } });
  assert.equal(condicoes.ens_paralelismo, true);
  assert.equal(condicoes.anexo_paralelismo, "1");
});

test("pesagem sem ensaios selecionados mantem somente calibracao, registro e conclusao", () => {
  const texto = renderizarPesagem({ ensaiosSelecionados: [] });
  assert.doesNotMatch(texto, /ANEXO \d/);
  assert.match(texto, /Anexo 1 – Verificação da Calibração/);
  assert.match(texto, /Anexo 2 - Registro de Assinaturas/);
  assert.doesNotMatch(texto, /Visualização do Fluxo de Ar/);
  assert.match(texto, /Anexo 3 - Conclusão/);
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

test("placeholders do Pesagem separam o ruído por estado e calculam vazão e integridade", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "nivelRuido", numeroPonto: 1, estado: "repouso", valor05um: "70" },
      { ensaioTipo: "nivelRuido", numeroPonto: 1, estado: "operacao", valor05um: "72" },
      { ensaioTipo: "integridadeFiltros", numeroPonto: 1, valor05um: "0.005" },
    ],
    resultadosEnsaios: [
      { ensaioTipo: "velocidadeFluxo", dados: { vazaoPorFiltro: [{ mediaMs: 0.46, areaM2: 0.9125, vazaoM3h: 1511.1 }] } },
      {
        ensaioTipo: "integridadeFiltros",
        dados: {
          integridade: {
            parcial: { assentamento: true, estrutura: false, meioFiltrante: true },
            acoesCorretivas: ["Troca do filtro"],
            reparoX: "120",
            novoEnsaioConforme: true,
          },
        },
      },
      { ensaioTipo: "visualizacaoFluxo", conforme: true, dados: { verificacoesVisualizacao: [true, true], tempoDissipacao: "12" } },
      { ensaioTipo: "paralelismoFluxo", dados: { paralelismo: [{ numeroPonto: 1, distanciaL: "900", distanciaX: "225" }] } },
    ],
  });

  assert.equal(dados.res_ruido_rep_1, "70");
  assert.equal(dados.res_ruido_op_1, "72");
  assert.equal(dados.media_ruido_op, "72");
  assert.equal(dados.media_f_1, "0,46");
  assert.equal(dados.area_f_1, "0,9125");
  assert.equal(dados.vaz_f_1, "1.511,1");
  assert.equal(dados.vaz_f_2, "-");
  assert.equal(dados.int_resultado_1, "Conforme");
  assert.equal(dados.int_parcial_estrutura, "Não conforme");
  assert.equal(dados.int_acao_troca, "X");
  assert.equal(dados.int_acao_aperto, "");
  assert.equal(dados.int_reparo_x, "120");
  assert.equal(dados.int_novo_ensaio, "Conforme");
  assert.equal(dados.vis_1, "Conforme");
  assert.equal(dados.vis_tempo, "12");
  assert.equal(dados.vis_resultado, "Conforme");
  assert.equal(dados.par_L_1, "900");
  assert.equal(dados.par_X_1, "225");
});

test("data de execução do Pesagem usa o fuso de São Paulo", () => {
  const dados = placeholdersDeResultados({
    resultadosEnsaios: [{ ensaioTipo: "velocidadeFluxo", dataHora: "2026-10-07T02:30:00Z" }],
  });
  assert.equal(dados["DATA EXECUCAO VELOCIDADE"], "06/10/2026");
  assert.equal(dados["DATA EXECUCAO RUIDO"], "-");
});

test("avaliação da Pesagem gera uma linha por unidade de filtro com perda e resultado", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "avaliacaoFiltragem", numeroPonto: 1, valor05um: "120" },
      { ensaioTipo: "avaliacaoFiltragem", numeroPonto: 2, valor05um: "600" },
    ],
    salas: [{ filtros: [{ tipo: "H14", quantidade: 2, modelo: "M-1", dimensoes: "1250 x 730" }] }],
  });
  assert.deepEqual(dados.avaliacaoFiltros, [
    { tipo: "H14", modelo: "M-1", dimensoes: "1250 x 730", quantidade: "1", criterio: "\u2264 500", perda: "120", resultado: "Conforme" },
    { tipo: "H14", modelo: "M-1", dimensoes: "1250 x 730", quantidade: "1", criterio: "\u2264 500", perda: "600", resultado: "N\u00e3o conforme" },
  ]);
});

test("integridade da Pesagem lista cada filtro com sala e resultado", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [{ ensaioTipo: "integridadeFiltros", numeroPonto: 1, valor05um: "0.005" }],
    salas: [{ nome: "Sala 210", filtros: [{ tipo: "H14", quantidade: 1, dimensoes: "1250 x 730" }] }],
  });
  assert.deepEqual(dados.integridadeFiltros, [
    { sala: "Sala 210", numero: "1", dimensoes: "1250 x 730", concentracaoGerada: "-", criterio: "< 0,01%", valor: "0.005", resultado: "Conforme" },
  ]);
});

test("velocidade da Pesagem calcula média, área e vazão por filtro", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 1, valor05um: "0.46" },
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 2, valor05um: "0.46" },
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 3, valor05um: "0.46" },
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 4, valor05um: "0.46" },
    ],
    salas: [{ nome: "Sala 210", filtros: [{ tipo: "H14", quantidade: 2, dimensoes: "1250 x 730" }] }],
  });
  assert.deepEqual(dados.velocidadeFiltros[0], {
    filtro: "H14",
    pontos: [
      { ponto: "Ponto 1", valor: "0,46" },
      { ponto: "Ponto 2", valor: "0,46" },
    ],
    mediaEsperada: "-",
    mediaMs: "0,46",
    criterioDesvio: "\u2264 15%",
    desvioCalculado: "0",
    area: "0,9125",
    vazao: "1.511,1",
    criterio: "0,36 a 0,54",
    resultado: "Conforme",
  });
  assert.equal(dados.velocidadeFiltros.length, 2);
});

test("pontos da velocidade usam a localização digitada pelo elaborador", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 1, valor05um: "0.46" },
      { ensaioTipo: "velocidadeFluxo", numeroPonto: 2, valor05um: "0.44" },
    ],
    salas: [{
      nome: "Sala 210",
      configEnsaios: { velocidadeFluxo: { localizacoes: "P1 (centro), P2 (borda)" } },
      filtros: [{ tipo: "H14", quantidade: 1, dimensoes: "1250 x 730" }],
    }],
  });
  assert.deepEqual(dados.velocidadeFiltros[0].pontos.map((p) => p.ponto), ["P1 (centro)", "P2 (borda)"]);
});

test("contagem da Pesagem separa repouso e operação com limites do Grau C", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "contagemParticulas", numeroPonto: 1, estado: "repouso", valor05um: "100", valor5um: "5", salaId: "S1" },
      { ensaioTipo: "contagemParticulas", numeroPonto: 1, estado: "operacao", valor05um: "4000000", valor5um: "30000", salaId: "S1" },
    ],
    salas: [{ id: "S1", nome: "Sala 210", area: 0.79, grau: "C" }],
  });
  assert.equal(dados.criterio_rep_05, "352000");
  assert.equal(dados.criterio_op_5, "29000");
  assert.equal(dados.resultado_cont_rep, "Conforme");
  assert.equal(dados.resultado_cont_op, "Não conforme");
  assert.equal(dados.area_contagem, "0,79");
  assert.equal(dados.grau_contagem, "C");
});

test("visualização da Pesagem usa fumaça e sentido padrão quando não configurados", () => {
  const dados = placeholdersDeResultados({ salas: [{ id: "S1" }] });
  assert.equal(dados.tipo_fumaca, "Glicerina");
  assert.equal(dados.sentido_fluxo, "Unidirecional");
});

test("contagem da Pesagem gera uma linha por sala e estado", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "contagemParticulas", numeroPonto: 1, estado: "repouso", valor05um: "100", valor5um: "5", salaId: "S1" },
      { ensaioTipo: "contagemParticulas", numeroPonto: 1, estado: "repouso", valor05um: "200", valor5um: "6", salaId: "S2" },
    ],
    salas: [
      { id: "S1", nome: "Sala 1", maquina: "CABINE A", area: 0.79, grau: "C" },
      { id: "S2", nome: "Sala 2", maquina: "CABINE B", area: 1.2, grau: "C" },
    ],
  });
  assert.equal(dados.contagemLinhas.length, 4);
  assert.deepEqual(dados.contagemLinhas[0], {
    equipamento: "CABINE A", area: "0,79", classe: "C (Repouso)", criterio05: "352000", criterio5: "2900", media05: "100", media5: "5",
  });
  assert.equal(dados.contagemLinhas[2].equipamento, "CABINE B");
  assert.equal(dados.contagemLinhas[2].media05, "200");
});

test("contagem da Pesagem mostra a segunda sala declarada mesmo sem medição", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [
      { ensaioTipo: "contagemParticulas", numeroPonto: 1, estado: "repouso", valor05um: "100", valor5um: "5", salaId: "S1" },
    ],
    salas: [
      { id: "S1", nome: "Sala 1", maquina: "CABINE A", area: 0.79, grau: "C" },
      { id: "S2", nome: "Sala 2", maquina: "CABINE B", area: 1.2, grau: "C" },
    ],
  });
  assert.equal(dados.contagemLinhas.length, 4);
  assert.equal(dados.contagemLinhas[2].equipamento, "CABINE B");
  assert.equal(dados.contagemLinhas[2].media05, "-");
});

test("resultado geral de cada ensaio marca conforme ou não conforme", () => {
  const dados = placeholdersDeResultados({
    resultadosEnsaios: [
      { ensaioTipo: "velocidadeFluxo", conforme: true },
      { ensaioTipo: "integridadeFiltros", conforme: false },
    ],
  });
  assert.equal(dados.marca_conf_VELOCIDADE, "X");
  assert.equal(dados.marca_nconf_VELOCIDADE, "");
  assert.equal(dados.marca_conf_INTEGRIDADE, "");
  assert.equal(dados.marca_nconf_INTEGRIDADE, "X");
  assert.equal(dados.marca_conf_RUIDO, "");
});

test("luminosidade da Pesagem exige todos os pontos a 500 lux ou mais", () => {
  const pontos = [600, 550, 480].map((valor, i) => ({ ensaioTipo: "luminosidade", numeroPonto: i + 1, valor05um: String(valor) }));
  assert.equal(placeholdersDeResultados({ pontosLeitura: pontos }).resultado_lum, "Não conforme");
  assert.equal(placeholdersDeResultados({ pontosLeitura: pontos.slice(0, 2) }).resultado_lum, "Conforme");
});

test("ruído da Pesagem informa resultado por estado", () => {
  const repouso = [1, 2, 3, 4, 5].map((n) => ({ ensaioTipo: "nivelRuido", numeroPonto: n, estado: "repouso", valor05um: "80" }));
  const operacao = [1, 2, 3, 4, 5].map((n) => ({ ensaioTipo: "nivelRuido", numeroPonto: n, estado: "operacao", valor05um: n === 3 ? "90" : "80" }));
  const dados = placeholdersDeResultados({ pontosLeitura: [...repouso, ...operacao] });
  assert.equal(dados.resultado_ruido_rep, "Conforme");
  assert.equal(dados.resultado_ruido_op, "Não conforme");
});

test("paralelismo da Pesagem lista cada ponto com L, X e ângulo", () => {
  const dados = placeholdersDeResultados({
    pontosLeitura: [{ ensaioTipo: "paralelismoFluxo", numeroPonto: 1, valor05um: "14.04" }],
    resultadosEnsaios: [{ ensaioTipo: "paralelismoFluxo", dados: { paralelismo: [{ numeroPonto: 1, distanciaL: "900", distanciaX: "225" }] } }],
  });
  assert.deepEqual(dados.paralelismoPontos, [{ numero: "1", L: "900", X: "225", angulo: "14,04", criterio: "\u2264 14 \u00ba" }]);
});
