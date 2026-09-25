// functions/index.js
// Cloud Function HTTPS callable que gera o relatorio .docx final a partir do template base
// (Storage: templates/<templateId>.docx) mesclado com os dados estruturados do projeto
// (sistema, salas, handling units/filtros, instrumentos, leituras). Nucleo gratuito do
// docxtemplater/pizzip - sem modulo de imagem (fotos de evidencia ficam como links, nao
// embutidas no corpo do documento).
// A partir do firebase-functions v6 a raiz exporta a API v2; a função continua 1st Gen via /v1.
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");

admin.initializeApp();

const CONTENT_TYPE_DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const URL_EXPIRACAO_MS = 7 * 24 * 60 * 60 * 1000; // 7 dias

// Compatibilidade com o esquema legado de leituras (usado pelos 5 templates atuais).
const MAX_SLOTS_LEITURA = 10;
const MAX_LINHAS_FERRAMENTA = 6;
const MAX_LEITURAS_POR_LINHA = 2;

// Callable precisa de invoker público no IAM; a autenticação é validada abaixo via context.auth.
exports.gerarRelatorioDocx = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");
  }

  const { templateId, projeto } = data || {};
  if (!templateId || !projeto || !projeto.id) {
    throw new functions.https.HttpsError("invalid-argument", "Informe templateId e o objeto do projeto (com id).");
  }

  let etapa = "acesso ao Storage";
  try {
    return await gerarDocx(templateId, projeto, (novaEtapa) => { etapa = novaEtapa; });
  } catch (erro) {
    if (erro instanceof functions.https.HttpsError) throw erro;
    console.error(`gerarRelatorioDocx falhou na etapa "${etapa}":`, erro);
    throw new functions.https.HttpsError("internal", `Falha na etapa: ${etapa}.`);
  }
});

async function gerarDocx(templateId, projeto, marcarEtapa) {
  const bucket = admin.storage().bucket();

  const templateFile = bucket.file(`templates/${templateId}.docx`);
  const [existeTemplate] = await templateFile.exists();
  if (!existeTemplate) {
    throw new functions.https.HttpsError("not-found", `Template "${templateId}" nao encontrado no Storage.`);
  }

  const [templateBuffer] = await templateFile.download();
  marcarEtapa("montagem dos dados");
  const dadosMerge = montarDadosMerge(projeto);

  marcarEtapa("leitura do template");
  const zip = new PizZip(templateBuffer);
  const doc = new Docxtemplater(zip, {
    paragraphLoop: true,
    linebreaks: true,
    nullGetter: () => "",
  });

  try {
    doc.render(dadosMerge);
  } catch (erro) {
    console.error("Falha ao renderizar o template:", JSON.stringify(erro, null, 2));
    throw new functions.https.HttpsError(
      "internal",
      "Falha ao gerar o relatorio: verifique se os placeholders do template correspondem aos dados enviados."
    );
  }

  const bufferGerado = doc.getZip().generate({ type: "nodebuffer" });
  const nomeArquivo = `relatorios/${projeto.id}/Relatorio_${projeto.id}_${Date.now()}.docx`;
  const arquivoGerado = bucket.file(nomeArquivo);

  marcarEtapa("gravação do relatório no Storage");
  await arquivoGerado.save(bufferGerado, { contentType: CONTENT_TYPE_DOCX });

  marcarEtapa("assinatura da URL de download");
  const [url] = await arquivoGerado.getSignedUrl({
    action: "read",
    expires: Date.now() + URL_EXPIRACAO_MS,
  });

  return { url, caminho: nomeArquivo };
}

// Traduz o payload estruturado do app (ProjetoModel + salas/handlingUnits/instrumentos/leituras)
// para as tags esperadas pelos templates .docx: placeholders escalares em {MAIUSCULO},
// placeholders de instrumento {TAG_<FERRAMENTA>} (com/sem acento, por compatibilidade),
// esquema legado de leituras ({VALOR_N}/{EQUIP_VALOR_N} ou agrupado por ferramenta no HVAC)
// e os novos loops {#salas}/{#handlingUnits}/{#filtros} adicionados na secao final dos templates.
function montarDadosMerge(projeto) {
  const dados = {
    PROJETO: projeto.tipoProjeto || "",
    EMPRESA: projeto.nomeEmpresa || "",
    CNPJ: projeto.cnpjEmpresa || "",
    SISTEMA: projeto.sistemaNome || "",
    AREA: projeto.area || "",
    DATA_GERACAO: new Date().toLocaleDateString("pt-BR"),
    salas: (projeto.salas || []).map((sala) => mapearSala(sala, projeto.handlingUnits)),
    handlingUnits: (projeto.handlingUnits || []).map(mapearHandlingUnit),
  };

  aplicarPlaceholdersDeInstrumentos(dados, projeto.ferramentasEscaneadas || {});
  aplicarPlaceholdersDeLeituras(dados, projeto.leiturasOcr || [], projeto.tipoProjeto || "");

  return dados;
}

function mapearSala(sala, handlingUnits) {
  const filtros = (sala.filtros || []).map((filtro) => ({
    tipo: (filtro.tipo || "").toString().toUpperCase(),
    quantidade: filtro.quantidade ?? 0,
  }));
  const maquina = (handlingUnits || []).find((h) => h.id === sala.handlingUnitId);
  return {
    nome: sala.nome || "",
    area: sala.area ?? "",
    volume: sala.volume ?? "",
    grau: (sala.grau || "").toString().toUpperCase(),
    // Templates antigos usam {qtdDifusores}; saidas da sala agora sao os filtros.
    qtdDifusores: filtros.length > 0 ? filtros.reduce((soma, f) => soma + Number(f.quantidade || 0), 0) : (sala.qtdDifusores ?? ""),
    maquina: maquina ? maquina.nome || "" : "",
    filtros,
  };
}

function mapearHandlingUnit(handlingUnit) {
  return {
    nome: handlingUnit.nome || "",
    temFiltroTerminalTexto: handlingUnit.temFiltroTerminal ? "Sim" : "Nao",
    qtdFiltrosTerminais: handlingUnit.temFiltroTerminal ? (handlingUnit.qtdFiltrosTerminais ?? 0) : "-",
    filtros: (handlingUnit.filtros || []).map((filtro) => ({
      tipo: (filtro.tipo || "").toString().toUpperCase(),
      quantidade: filtro.quantidade ?? 0,
    })),
  };
}

function removerAcentos(texto) {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function aplicarPlaceholdersDeInstrumentos(dados, ferramentasEscaneadas) {
  Object.entries(ferramentasEscaneadas).forEach(([nomeFerramenta, instrumentos]) => {
    const sufixoComAcento = nomeFerramenta.toUpperCase().replace(/ /g, "_");
    const sufixoSemAcento = removerAcentos(sufixoComAcento);

    (instrumentos || []).forEach((instrumento, i) => {
      // O 1o instrumento de cada tipo mantem o placeholder original (templates existentes);
      // instrumentos adicionais do mesmo tipo usam sufixo numerico (_2, _3...).
      const sufixoIndice = i === 0 ? "" : `_${i + 1}`;

      [sufixoComAcento, sufixoSemAcento].forEach((sufixoTag) => {
        dados[`EQUIPAMENTO_${sufixoTag}${sufixoIndice}`] = instrumento.tipo || "";
        dados[`TAG_${sufixoTag}${sufixoIndice}`] = instrumento.tag || "";
        dados[`SERIE_${sufixoTag}${sufixoIndice}`] = instrumento.numeroSerie || "";
        dados[`CERTIFICADO_${sufixoTag}${sufixoIndice}`] = instrumento.numeroCertificado || "";
        dados[`VALIDADE_${sufixoTag}${sufixoIndice}`] = instrumento.validade || "";
      });
    });
  });
}

function aplicarPlaceholdersDeLeituras(dados, leiturasOcr, tipoProjeto) {
  const usaModeloAgrupado = tipoProjeto.trim().toLowerCase().includes("hvac");

  if (!usaModeloAgrupado) {
    for (let i = 0; i < MAX_SLOTS_LEITURA; i++) {
      const leitura = leiturasOcr[i];
      dados[`VALOR_${i + 1}`] = leitura ? leitura.valorCapturado || "" : "-";
      dados[`EQUIP_VALOR_${i + 1}`] = leitura ? leitura.equipamento || "" : "-";
    }
    return;
  }

  const ferramentasEmOrdem = [];
  const leiturasPorFerramenta = {};
  leiturasOcr.forEach((leitura) => {
    if (!leiturasPorFerramenta[leitura.equipamento]) {
      leiturasPorFerramenta[leitura.equipamento] = [];
      ferramentasEmOrdem.push(leitura.equipamento);
    }
    leiturasPorFerramenta[leitura.equipamento].push(leitura);
  });

  for (let linha = 0; linha < MAX_LINHAS_FERRAMENTA; linha++) {
    const numeroLinha = linha + 1;
    const nomeFerramenta = ferramentasEmOrdem[linha];
    const leiturasDaLinha = nomeFerramenta ? leiturasPorFerramenta[nomeFerramenta] : [];

    dados[`EQUIP_VALOR_${numeroLinha}`] = nomeFerramenta || "-";
    for (let n = 0; n < MAX_LEITURAS_POR_LINHA; n++) {
      const leitura = leiturasDaLinha[n];
      dados[`VALOR_${numeroLinha}_${n + 1}`] = leitura ? leitura.valorCapturado || "" : "-";
    }
  }
}

