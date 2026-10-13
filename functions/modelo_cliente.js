// Condições dos modelos do cliente (.docx): quais testes/anexos aparecem e a numeração dos anexos visíveis.

// Ordem dos anexos do modelo Fluxo Laminar; anexos sem ensaio no app ficam sempre ocultos.
const ANEXOS_MODELO = [
  "avaliacaoFiltragem",
  "velocidade",
  "integridade",
  "ruido",
  "luminosidade",
  "contagem",
  "visualizacao",
  "paralelismo",
  "calibracao",
  "assinaturas",
  "conclusao",
];

const FERRAMENTAS_POR_ENSAIO = Object.freeze({
  avaliacaoFiltragem: ["Manômetro"],
  velocidadeFluxo: ["Anemômetro"],
  integridadeFiltros: ["Fotômetro"],
  nivelRuido: ["Decibelímetro"],
  luminosidade: ["Luxímetro"],
  paralelismoFluxo: ["Máquina de Fumaça"],
  visualizacaoFluxo: ["Máquina de Fumaça"],
  contagemParticulas: ["Contador de Partículas"],
  recuperacaoParticulas: ["Contador de Partículas"],
  quedaEnergia: ["Contador de Partículas"],
  vazaoInsuflacao: ["Balômetro"],
  perdaCargaFiltros: ["Manômetro"],
  pressao: ["Manômetro"],
  estanqueidade: ["Balômetro"],
});

function condicoesDeEnsaios(projeto) {
  const selecionados = new Set(Array.isArray(projeto.ensaiosSelecionados) ? projeto.ensaiosSelecionados : []);
  const paralelismo = projeto.paralelismo || {};
  const visiveis = {
    avaliacaoFiltragem: selecionados.has("avaliacaoFiltragem"),
    velocidade: selecionados.has("velocidadeFluxo"),
    integridade: selecionados.has("integridadeFiltros"),
    ruido: selecionados.has("nivelRuido"),
    luminosidade: selecionados.has("luminosidade"),
    contagem: selecionados.has("contagemParticulas"),
    visualizacao: selecionados.has("visualizacaoFluxo"),
    paralelismo: selecionados.has("paralelismoFluxo")
      || Boolean(String(paralelismo.resultado || "").trim() || String(paralelismo.fotoUrl || "").trim()),
    calibracao: true,
    assinaturas: true,
    conclusao: true,
  };
  const condicoes = {};
  let numero = 0;
  for (const anexo of ANEXOS_MODELO) {
    const visivel = visiveis[anexo] === true;
    condicoes[`ens_${anexo}`] = visivel;
    condicoes[`anexo_${anexo}`] = visivel ? String(++numero) : "";
  }
  return condicoes;
}

function valorTexto(valor) {
  return valor === null || valor === undefined ? "" : String(valor).trim();
}

function listaNormalizada(valor) {
  if (Array.isArray(valor)) return valor;
  if (typeof valor !== "string" || !valor.trim()) return [];
  try {
    const lista = JSON.parse(valor);
    return Array.isArray(lista) ? lista : [];
  } catch (_) {
    return [];
  }
}

function mapaNormalizado(valor) {
  if (valor && typeof valor === "object" && !Array.isArray(valor)) return valor;
  if (typeof valor !== "string" || !valor.trim()) return {};
  try {
    const mapa = JSON.parse(valor);
    return mapa && typeof mapa === "object" && !Array.isArray(mapa) ? mapa : {};
  } catch (_) {
    return {};
  }
}

function removerAcentos(texto) {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function nomeNormalizado(valor) {
  return removerAcentos(valorTexto(valor)).toLowerCase().replace(/\s+/g, " ");
}

function tiposEvidenciados(projeto, resultadosEnsaios, pontosLeitura) {
  const tipos = new Set();
  for (const registro of [...listaNormalizada(resultadosEnsaios), ...listaNormalizada(pontosLeitura)]) {
    const tipo = valorTexto(registro && registro.ensaioTipo);
    if (tipo) tipos.add(tipo);
  }

  const tagsPorTipo = new Map();
  for (const entrada of listaNormalizada(projeto.history)) {
    const detalhes = mapaNormalizado(entrada && entrada.detalhes);
    const campo = valorTexto(entrada && entrada.campo);
    const tipoDoCampo = campo.match(/^ensaio:[^:]+:(.+)$/)?.[1] || "";
    const tipo = valorTexto(detalhes.ensaioTipo) || tipoDoCampo;
    if (!tipo || (!tipoDoCampo && !detalhes.ensaioTipo)) continue;
    tipos.add(tipo);
    const ferramentas = mapaNormalizado(detalhes.ferramentas);
    for (const [tipoFerramenta, tags] of Object.entries(ferramentas)) {
      const chave = nomeNormalizado(tipoFerramenta);
      const tagsConhecidas = tagsPorTipo.get(chave) || new Set();
      for (const tag of listaNormalizada(tags)) {
        const valor = valorTexto(tag && typeof tag === "object" ? tag.tag : tag);
        if (valor) tagsConhecidas.add(nomeNormalizado(valor));
      }
      tagsPorTipo.set(chave, tagsConhecidas);
    }
  }

  const paralelismo = mapaNormalizado(projeto.paralelismo);
  if (valorTexto(paralelismo.resultado) || valorTexto(paralelismo.fotoUrl)) tipos.add("paralelismoFluxo");
  return { tipos, tagsPorTipo };
}

function instrumentosUtilizados(projeto = {}, resultadosEnsaios = projeto.resultadosEnsaios, pontosLeitura = projeto.pontosLeitura) {
  const { tipos, tagsPorTipo } = tiposEvidenciados(projeto, resultadosEnsaios, pontosLeitura);
  const ferramentas = mapaNormalizado(projeto.ferramentasEscaneadas);
  const ferramentasDisponiveis = Object.entries(ferramentas).map(([tipo, lista]) => ({
    tipo,
    tipoNormalizado: nomeNormalizado(tipo),
    instrumentos: listaNormalizada(lista),
  }));
  const tiposExecutados = new Set([...tipos].map(nomeNormalizado));
  const vistos = new Map();
  const utilizados = [];

  for (const [ensaioTipo, tiposFerramenta] of Object.entries(FERRAMENTAS_POR_ENSAIO)) {
    if (!tiposExecutados.has(nomeNormalizado(ensaioTipo))) continue;
    for (const tipoFerramenta of tiposFerramenta) {
      const fonte = ferramentasDisponiveis.find((item) => item.tipoNormalizado === nomeNormalizado(tipoFerramenta));
      if (!fonte) continue;
      const tagsDoEnsaio = tagsPorTipo.get(fonte.tipoNormalizado);
      for (const bruto of fonte.instrumentos) {
        const instrumento = bruto && typeof bruto === "object" ? bruto : {};
        const tag = valorTexto(instrumento.tag);
        if (tagsDoEnsaio && tagsDoEnsaio.size > 0 && !tagsDoEnsaio.has(nomeNormalizado(tag))) continue;
        const tipo = valorTexto(instrumento.tipo) || fonte.tipo;
        const numeroSerie = valorTexto(instrumento.numeroSerie);
        const certificado = valorTexto(instrumento.numeroCertificado);
        const chave = tag
          ? `tag:${nomeNormalizado(tag)}`
          : `dados:${nomeNormalizado(tipo)}|${nomeNormalizado(numeroSerie)}|${nomeNormalizado(certificado)}`;
        const existente = vistos.get(chave);
        if (existente) {
          if (!existente.ensaios.includes(ensaioTipo)) existente.ensaios.push(ensaioTipo);
          continue;
        }
        const utilizado = {
          ...instrumento,
          tipo,
          nome: tipo,
          tag,
          numeroSerie,
          numeroCertificado: certificado,
          certificado,
          validade: valorTexto(instrumento.validade),
          ensaios: [ensaioTipo],
        };
        vistos.set(chave, utilizado);
        utilizados.push(utilizado);
      }
    }
  }
  return utilizados;
}

function normalizarTagsTemplate(zip) {
  const arquivo = zip.file("word/document.xml");
  if (!arquivo) return 0;

  const xml = arquivo.asText();
  let corrigidos = 0;
  const xmlCorrigido = xml.replace(/(<w:p\b[^>]*>)([\s\S]*?)(<\/w:p>)/g, (paragrafo, abertura, corpo, fechamento) => {
    let textoAnterior = "";
    const corpoCorrigido = corpo.replace(/(<w:t\b[^>]*>)([\s\S]*?)(<\/w:t>)/g, (textoCompleto, inicio, texto, fim) => {
      const indice = texto.indexOf("CONFORME}");
      if (indice >= 0 && /\(\s*$/.test(textoAnterior + texto.slice(0, indice)) && !texto.slice(0, indice).includes("{")) {
        texto = `${texto.slice(0, indice)}{${texto.slice(indice)}`;
        corrigidos++;
      }
      textoAnterior += texto;
      return `${inicio}${texto}${fim}`;
    });
    return `${abertura}${corpoCorrigido}${fechamento}`;
  });

  if (corrigidos > 0) zip.file("word/document.xml", xmlCorrigido);
  return corrigidos;
}

module.exports = { ANEXOS_MODELO, condicoesDeEnsaios, instrumentosUtilizados, normalizarTagsTemplate };
