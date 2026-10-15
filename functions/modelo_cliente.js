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

function decodificarTextoXml(texto) {
  return texto
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function codificarTextoXml(texto) {
  return texto
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function normalizarTagsFragmentadas(xml) {
  let corrigidos = 0;
  const xmlCorrigido = xml.replace(/(<w:p\b[^>]*>)([\s\S]*?)(<\/w:p>)/g, (paragrafo, abertura, corpo, fechamento) => {
    const trechos = [];
    corpo.replace(/(<w:t\b[^>]*>)([\s\S]*?)(<\/w:t>)/g, (textoCompleto, inicio, texto, fim) => {
      trechos.push({ inicio, texto: decodificarTextoXml(texto), fim });
      return textoCompleto;
    });
    for (let indice = 0; indice < trechos.length; indice++) {
      const aberturaTag = trechos[indice].texto.lastIndexOf("{");
      if (aberturaTag < 0 || trechos[indice].texto.indexOf("}", aberturaTag) >= 0) continue;
      let combinado = trechos[indice].texto;
      let ultimo = indice;
      while (ultimo + 1 < trechos.length && combinado.length <= 120 && ultimo - indice < 20) {
        ultimo++;
        combinado += trechos[ultimo].texto;
        const fechamentoTag = combinado.indexOf("}", aberturaTag);
        if (fechamentoTag < 0) continue;
        const tag = combinado.slice(aberturaTag, fechamentoTag + 1);
        if (!/^\{[#/]?[A-Za-zÀ-Ú0-9_ .#/-]+\}$/.test(tag)) break;
        trechos[indice].texto = combinado;
        for (let proximo = indice + 1; proximo <= ultimo; proximo++) trechos[proximo].texto = "";
        corrigidos++;
        break;
      }
    }
    let indiceTrecho = 0;
    const corpoCorrigido = corpo.replace(/(<w:t\b[^>]*>)([\s\S]*?)(<\/w:t>)/g, (textoCompleto, inicio, _texto, fim) => {
      const trecho = trechos[indiceTrecho++];
      return `${inicio}${codificarTextoXml(trecho.texto)}${fim}`;
    });
    return `${abertura}${corpoCorrigido}${fechamento}`;
  });
  return { xml: xmlCorrigido, corrigidos };
}

function normalizarTagsTemplate(zip) {
  const arquivo = zip.file("word/document.xml");
  if (!arquivo) return 0;

  const normalizado = normalizarTagsFragmentadas(arquivo.asText());
  let corrigidos = normalizado.corrigidos;
  const xmlCorrigido = normalizado.xml.replace(/(<w:p\b[^>]*>)([\s\S]*?)(<\/w:p>)/g, (paragrafo, abertura, corpo, fechamento) => {
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

function numeroParaCalculo(valor) {
  const numero = Number.parseFloat(
    valorTexto(valor).replace(',', '.').replace('%', '').replace('°', ''),
  );
  return Number.isFinite(numero) ? numero : null;
}

function formatarNumeroRelatorio(valor) {
  const numero = numeroParaCalculo(valor);
  if (numero === null) return valorTexto(valor);
  return numero.toLocaleString('pt-BR', { maximumFractionDigits: 3 });
}

function formatarPercentual(valor) {
  const numero = numeroParaCalculo(valor);
  return numero === null ? '' : `${formatarNumeroRelatorio(numero)}%`;
}

function formatarAngulo(valor) {
  const numero = numeroParaCalculo(valor);
  return numero === null ? '' : `${formatarNumeroRelatorio(numero)}°`;
}

function valoresUnicosFormatados(valores) {
  return [...new Set(valores.map(valorTexto).filter(Boolean))].join('\n');
}

function mediaNumerica(valores) {
  const numeros = valores.map(numeroParaCalculo).filter((valor) => valor !== null);
  if (numeros.length === 0) return null;
  return numeros.reduce((soma, valor) => soma + valor, 0) / numeros.length;
}

function desvioPadraoRelativo(valores) {
  const numeros = valores.map(numeroParaCalculo).filter((valor) => valor !== null);
  if (numeros.length === 0) return null;
  const media = mediaNumerica(numeros);
  if (media === null || media === 0) return null;
  const somaQuadrados = numeros.reduce((soma, valor) => soma + (valor - media) ** 2, 0);
  const desvio = numeros.length > 1 ? Math.sqrt(somaQuadrados / (numeros.length - 1)) : 0;
  return desvio / media * 100;
}

function dadosDoResultado(resultado) {
  return mapaNormalizado(resultado && resultado.dados);
}

function valorPrimarioDoPonto(ponto) {
  return valorTexto(ponto && (ponto.valor05um ?? ponto.valor));
}

function placeholdersDeResultados({ pontosLeitura = [], resultadosEnsaios = [], paralelismo = {} } = {}) {
  const pontos = listaNormalizada(pontosLeitura);
  const resultados = listaNormalizada(resultadosEnsaios);
  const porTipo = (tipo) => pontos.filter((ponto) => ponto && ponto.ensaioTipo === tipo);
  const resultadosPorTipo = (tipo) => resultados.filter((resultado) => resultado && resultado.ensaioTipo === tipo);
  const saida = {};

  for (let indice = 0; indice < 3; indice++) {
    const numero = indice + 1;
    saida[`res_aval_${numero}`] = valorPrimarioDoPonto(porTipo('avaliacaoFiltragem')[indice]) || '-';
  }

  const pontosVelocidade = porTipo('velocidadeFluxo');
  const resultadosVelocidade = resultadosPorTipo('velocidadeFluxo');
  const valoresVelocidade = pontosVelocidade.map(valorPrimarioDoPonto).filter(Boolean);
  const mediasVelocidade = resultadosVelocidade
    .map((resultado) => dadosDoResultado(resultado).media)
    .map(numeroParaCalculo)
    .filter((valor) => valor !== null);
  const desviosVelocidade = resultadosVelocidade
    .map((resultado) => dadosDoResultado(resultado).desvioPadraoRelativo)
    .map(numeroParaCalculo)
    .filter((valor) => valor !== null);
  const mediaVelocidade = mediasVelocidade.length > 0 ? mediaNumerica(mediasVelocidade) : mediaNumerica(valoresVelocidade);
  const desvioVelocidade = desviosVelocidade.length > 0
    ? mediaNumerica(desviosVelocidade)
    : desvioPadraoRelativo(valoresVelocidade);
  saida.res_vel = mediaVelocidade === null ? '-' : formatarNumeroRelatorio(mediaVelocidade);
  saida.cal_res_vel = desvioVelocidade === null ? '-' : formatarPercentual(desvioVelocidade);
  saida.res_media_vel = saida.res_vel;
  saida.cal_res_media_vel = saida.cal_res_vel;

  const porFiltro = new Map();
  for (const ponto of pontosVelocidade) {
    const filtro = Number.parseInt(ponto.filtroIndice, 10) || 1;
    const indicePonto = (porFiltro.get(filtro) || 0) + 1;
    porFiltro.set(filtro, indicePonto);
    if (indicePonto <= 3 && filtro <= 5) {
      saida[`res_vel_p${indicePonto}_f${filtro}`] = valorPrimarioDoPonto(ponto) || '-';
    }
  }
  for (let ponto = 1; ponto <= 3; ponto++) {
    for (let filtro = 1; filtro <= 5; filtro++) {
      const chave = `res_vel_p${ponto}_f${filtro}`;
      if (!(chave in saida)) saida[chave] = '-';
    }
  }

  const pontosIntegridade = porTipo('integridadeFiltros');
  for (let indice = 0; indice < 4; indice++) {
    const numero = indice + 1;
    saida[`res_int_${numero}`] = valorPrimarioDoPonto(pontosIntegridade[indice]) || '-';
  }
  const mediaIntegridade = mediaNumerica(pontosIntegridade.map(valorPrimarioDoPonto));
  saida.res_int = valoresUnicosFormatados(pontosIntegridade.map(valorPrimarioDoPonto)) || '-';
  saida.cal_res_int = mediaIntegridade === null ? '-' : formatarPercentual(mediaIntegridade);

  const pontosRuido = porTipo('nivelRuido');
  const resultadoRuido = resultadosPorTipo('nivelRuido')[0];
  const mediaRuido = dadosDoResultado(resultadoRuido).media ?? mediaNumerica(pontosRuido.map(valorPrimarioDoPonto));
  for (let indice = 0; indice < 5; indice++) {
    saida[`res_ruido_${indice + 1}`] = valorPrimarioDoPonto(pontosRuido[indice]) || '-';
  }
  saida.media_ruido = mediaRuido === null ? '-' : formatarNumeroRelatorio(mediaRuido);

  const pontosLuminosidade = porTipo('luminosidade');
  const resultadoLuminosidade = resultadosPorTipo('luminosidade')[0];
  const mediaLuminosidade = dadosDoResultado(resultadoLuminosidade).media
    ?? mediaNumerica(pontosLuminosidade.map(valorPrimarioDoPonto));
  for (let indice = 0; indice < 5; indice++) {
    saida[`res_lum_${indice + 1}`] = valorPrimarioDoPonto(pontosLuminosidade[indice]) || '-';
  }
  saida.media_lum = mediaLuminosidade === null ? '-' : formatarNumeroRelatorio(mediaLuminosidade);

  const pontosContagem = porTipo('contagemParticulas').sort((a, b) => {
    const estadoA = valorTexto(a.estado).toLowerCase() === 'operacao' ? 1 : 0;
    const estadoB = valorTexto(b.estado).toLowerCase() === 'operacao' ? 1 : 0;
    return estadoA - estadoB
      || (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0);
  });
  for (let indice = 0; indice < 6; indice++) {
    const ponto = pontosContagem[indice];
    saida[`res_cont_${indice + 1}_05`] = valorPrimarioDoPonto(ponto) || '-';
    saida[`res_cont_${indice + 1}_5`] = valorTexto(ponto && ponto.valor5um) || '-';
  }

  const pontoVisualizacao = porTipo('visualizacaoFluxo')[0];
  saida.res_vis = valorPrimarioDoPonto(pontoVisualizacao) || '-';

  const pontosParalelismo = porTipo('paralelismoFluxo');
  const resultadoParalelismo = valorTexto(paralelismo && paralelismo.resultado);
  const calculoParalelismo = valorTexto(paralelismo && paralelismo.calculo);
  const angulosParalelismo = pontosParalelismo
    .map(valorPrimarioDoPonto)
    .map(numeroParaCalculo)
    .filter((valor) => valor !== null);
  const anguloLegado = numeroParaCalculo(calculoParalelismo);
  const maiorAngulo = angulosParalelismo.length > 0
    ? Math.max(...angulosParalelismo)
    : anguloLegado;
  saida.cal_res_para = formatarAngulo(maiorAngulo) || '-';
  for (let indice = 0; indice < 4; indice++) {
    const numero = indice + 1;
    const valor = valorPrimarioDoPonto(pontosParalelismo[indice]) || (indice === 0 ? resultadoParalelismo : '');
    saida[`res_para${indice === 0 ? '' : `_${numero}`}`] = valor || '-';
    const angulo = numeroParaCalculo(valor) === null ? anguloLegado : numeroParaCalculo(valor);
    saida[`cal_res_para_${numero}`] = formatarAngulo(angulo) || '-';
  }

  return saida;
}

module.exports = {
  ANEXOS_MODELO,
  condicoesDeEnsaios,
  instrumentosUtilizados,
  normalizarTagsTemplate,
  placeholdersDeResultados,
};
