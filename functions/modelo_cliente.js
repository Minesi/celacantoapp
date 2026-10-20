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
  return condicoesDeAnexos(ANEXOS_MODELO, visiveis);
}

// Ordem dos anexos do modelo de Pesagem (paralelismo antes da contagem e da visualização).
const ANEXOS_PESAGEM = [
  "avaliacaoFiltragem",
  "velocidade",
  "integridade",
  "ruido",
  "luminosidade",
  "paralelismo",
  "contagem",
  "visualizacao",
  "calibracao",
  "assinaturas",
  "conclusao",
];

function condicoesDePesagem(projeto) {
  const selecionados = new Set(Array.isArray(projeto.ensaiosSelecionados) ? projeto.ensaiosSelecionados : []);
  const paralelismo = projeto.paralelismo || {};
  const visiveis = {
    avaliacaoFiltragem: selecionados.has("avaliacaoFiltragem"),
    velocidade: selecionados.has("velocidadeFluxo"),
    integridade: selecionados.has("integridadeFiltros"),
    ruido: selecionados.has("nivelRuido"),
    luminosidade: selecionados.has("luminosidade"),
    paralelismo: selecionados.has("paralelismoFluxo")
      || Boolean(String(paralelismo.resultado || "").trim() || String(paralelismo.fotoUrl || "").trim()),
    contagem: selecionados.has("contagemParticulas"),
    visualizacao: selecionados.has("visualizacaoFluxo"),
    calibracao: true,
    assinaturas: true,
    conclusao: true,
  };
  return condicoesDeAnexos(ANEXOS_PESAGEM, visiveis);
}

function condicoesDeAnexos(ordem, visiveis) {
  const condicoes = {};
  let numero = 0;
  for (const anexo of ordem) {
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

// Limite da Contagem por estado: valor da elaboração (por estado, depois geral) ou o padrão.
function criterioContagem(configuracao, estado, campo, padrao) {
  return numeroParaCalculo(configuracao[`${campo}_${estado}`]) ?? numeroParaCalculo(configuracao[campo]) ?? padrao;
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

function placeholdersDeResultados({ pontosLeitura = [], resultadosEnsaios = [], paralelismo = {}, salas = [] } = {}) {
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

  return { ...saida, ...placeholdersPesagem({ pontosLeitura: pontos, resultadosEnsaios: resultados, salas }) };
}

// Campos do modelo de Pesagem; os do Fluxo Laminar continuam em placeholdersDeResultados.
// Área em m² a partir de "LARGURA x ALTURA" em milímetros; null sem dimensões válidas.
function areaDoFiltroM2(dimensoes) {
  const partes = /(\d+(?:[.,]\d+)?)\s*[xX×]\s*(\d+(?:[.,]\d+)?)/.exec(String(dimensoes || ''));
  if (!partes) return null;
  const largura = Number(partes[1].replace(',', '.'));
  const altura = Number(partes[2].replace(',', '.'));
  return largura > 0 && altura > 0 ? (largura / 1000) * (altura / 1000) : null;
}

function placeholdersPesagem({ pontosLeitura = [], resultadosEnsaios = [], salas = [] } = {}) {
  const pontos = listaNormalizada(pontosLeitura);
  const resultados = listaNormalizada(resultadosEnsaios);
  const porTipo = (tipo) => pontos.filter((ponto) => ponto && ponto.ensaioTipo === tipo);
  const resultadoDoTipo = (tipo) => resultados.find((resultado) => resultado && resultado.ensaioTipo === tipo) || null;
  const textoConforme = (valor) => (valor === true ? 'Conforme' : valor === false ? 'Não conforme' : '-');
  const marca = (condicao) => (condicao ? 'X' : '');
  const formatadoOuTraco = (valor, casas = 3) => (
    valor === undefined || valor === null || valor === '' || !Number.isFinite(Number(valor))
      ? '-'
      : Number(valor).toLocaleString('pt-BR', { maximumFractionDigits: casas })
  );
  const saida = {};

  for (const [sufixo, estado] of [['rep', 'repouso'], ['op', 'operacao']]) {
    const pontosDoEstado = porTipo('nivelRuido')
      .filter((ponto) => valorTexto(ponto.estado).toLowerCase() === estado)
      .sort((a, b) => (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0));
    for (let indice = 0; indice < 5; indice++) {
      saida[`res_ruido_${sufixo}_${indice + 1}`] = valorPrimarioDoPonto(pontosDoEstado[indice]) || '-';
    }
    const media = mediaNumerica(pontosDoEstado.map(valorPrimarioDoPonto));
    saida[`media_ruido_${sufixo}`] = media === null ? '-' : formatarNumeroRelatorio(media);
    const valoresRuido = pontosDoEstado.map((ponto) => numeroParaCalculo(valorPrimarioDoPonto(ponto)));
    saida[`resultado_ruido_${sufixo}`] = valoresRuido.length === 0
      ? '-'
      : (valoresRuido.every((valor) => valor !== null && valor <= 85) ? 'Conforme' : 'N\u00e3o conforme');
  }

  const pontosIntegridade = porTipo('integridadeFiltros');
  for (let indice = 0; indice < 4; indice++) {
    const concentracao = numeroParaCalculo(valorPrimarioDoPonto(pontosIntegridade[indice]));
    saida[`int_resultado_${indice + 1}`] = concentracao === null
      ? '-'
      : (concentracao <= 0.01 ? 'Conforme' : 'Não conforme');
  }
  const unidadesDeFiltro = (salas || []).flatMap((sala) =>
    (sala.filtros || []).flatMap((filtro) =>
      Array.from({ length: Number(filtro.quantidade) || 0 }, () => ({
        ...filtro,
        salaNome: sala.nome || '',
        mediaEsperada: sala.configEnsaios?.velocidadeFluxo?.mediaEsperada,
        localizacoes: sala.configEnsaios?.velocidadeFluxo?.localizacoes,
      }))));
  saida.avaliacaoFiltros = porTipo('avaliacaoFiltragem')
    .sort((a, b) => (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0))
    .map((ponto, indice) => {
      const filtro = unidadesDeFiltro[indice] || {};
      const perda = numeroParaCalculo(valorPrimarioDoPonto(ponto));
      return {
        tipo: valorTexto(filtro.tipo) || '-',
        modelo: valorTexto(filtro.modelo) || '-',
        dimensoes: valorTexto(filtro.dimensoes) || '-',
        quantidade: '1',
        criterio: '\u2264 500',
        perda: valorPrimarioDoPonto(ponto) || '-',
        resultado: perda === null ? '-' : (perda <= 500 ? 'Conforme' : 'N\u00e3o conforme'),
      };
    });

  saida.integridadeFiltros = porTipo('integridadeFiltros')
    .sort((a, b) => (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0))
    .map((ponto, indice) => {
      const filtro = unidadesDeFiltro[indice] || {};
      const valor = numeroParaCalculo(valorPrimarioDoPonto(ponto));
      return {
        sala: valorTexto(filtro.salaNome) || '-',
        numero: String(indice + 1),
        dimensoes: valorTexto(filtro.dimensoes) || '-',
        concentracaoGerada: '-',
        criterio: '< 0,01%',
        valor: valorPrimarioDoPonto(ponto) || '-',
        resultado: valor === null ? '-' : (valor <= 0.01 ? 'Conforme' : 'N\u00e3o conforme'),
      };
    });

  const pontosVelocidade = porTipo('velocidadeFluxo')
    .sort((a, b) => (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0));
  const pontosPorFiltro = unidadesDeFiltro.length > 0
    ? Math.max(1, Math.round(pontosVelocidade.length / unidadesDeFiltro.length))
    : 1;
  saida.velocidadeFiltros = unidadesDeFiltro.map((unidade, indice) => {
    const pontosDoFiltro = pontosVelocidade.slice(indice * pontosPorFiltro, (indice + 1) * pontosPorFiltro);
    const valores = pontosDoFiltro
      .map((ponto) => numeroParaCalculo(valorPrimarioDoPonto(ponto)))
      .filter((valor) => valor !== null);
    const media = valores.length > 0 ? valores.reduce((soma, valor) => soma + valor, 0) / valores.length : null;
    const desvioRelativo = media && valores.length > 1
      ? Math.sqrt(valores.reduce((soma, valor) => soma + (valor - media) ** 2, 0) / (valores.length - 1)) / media * 100
      : 0;
    const area = areaDoFiltroM2(unidade.dimensoes);
    const vazao = media !== null && area !== null ? media * area * 3600 : null;
    const conforme = media !== null && media >= 0.36 && media <= 0.54 && desvioRelativo <= 15;
    const mediaEsperada = numeroParaCalculo(unidade.mediaEsperada);
    const localizacoesDoFiltro = String(unidade.localizacoes || '').split(',').map((texto) => texto.trim()).filter(Boolean);
    return {
      filtro: valorTexto(unidade.tipo) || '-',
      pontos: pontosDoFiltro.map((ponto, i) => ({
        ponto: localizacoesDoFiltro[i] || `Ponto ${i + 1}`,
        valor: formatadoOuTraco(numeroParaCalculo(valorPrimarioDoPonto(ponto)), 3),
      })),
      mediaEsperada: formatadoOuTraco(mediaEsperada, 3),
      mediaMs: formatadoOuTraco(media, 3),
      criterioDesvio: '\u2264 15%',
      desvioCalculado: formatadoOuTraco(media === null ? null : desvioRelativo, 2),
      area: formatadoOuTraco(area, 4),
      vazao: formatadoOuTraco(vazao, 1),
      criterio: '0,36 a 0,54',
      resultado: media === null ? '-' : (conforme ? 'Conforme' : 'N\u00e3o conforme'),
    };
  });

  const pontosParalelismo = porTipo('paralelismoFluxo')
    .sort((a, b) => (Number.parseInt(a.numeroPonto, 10) || 0) - (Number.parseInt(b.numeroPonto, 10) || 0));
  const distanciasParalelismo = listaNormalizada(dadosDoResultado(resultadoDoTipo('paralelismoFluxo')).paralelismo);
  saida.paralelismoPontos = pontosParalelismo.map((ponto, indice) => {
    const distancia = mapaNormalizado(distanciasParalelismo[indice]);
    return {
      numero: String(indice + 1),
      L: valorTexto(distancia.distanciaL) || '-',
      X: valorTexto(distancia.distanciaX) || '-',
      angulo: formatadoOuTraco(numeroParaCalculo(valorPrimarioDoPonto(ponto)), 2),
      criterio: '\u2264 14 \u00ba',
    };
  });

  const valoresLuminosidade = porTipo('luminosidade').map((ponto) => numeroParaCalculo(valorPrimarioDoPonto(ponto)));
  saida.resultado_lum = valoresLuminosidade.length === 0
    ? '-'
    : (valoresLuminosidade.every((valor) => valor !== null && valor >= 500) ? 'Conforme' : 'N\u00e3o conforme');

  const pontosContagem = porTipo('contagemParticulas');
  const salaContagem = (salas || []).find((sala) => String(sala.id) === valorTexto(pontosContagem[0]?.salaId))
    || (salas || [])[0] || {};
  saida.area_contagem = formatadoOuTraco(salaContagem.area, 2);
  saida.grau_contagem = valorTexto(salaContagem.grau) || '-';
  const limitesContagem = (estado) => {
    const grauC = estado === 'operacao' ? { max05: 3520000, max5: 29000 } : { max05: 352000, max5: 2900 };
    const configuracao = salaContagem.configEnsaios?.contagemParticulas || {};
    return {
      max05: criterioContagem(configuracao, estado, 'criterioMax', grauC.max05),
      max5: criterioContagem(configuracao, estado, 'criterioMax5um', grauC.max5),
    };
  };
  for (const [sufixo, estado] of [['rep', 'repouso'], ['op', 'operacao']]) {
    const doEstado = pontosContagem.filter((ponto) => valorTexto(ponto.estado).toLowerCase() === estado);
    const limites = limitesContagem(estado);
    const valores05 = doEstado.map((ponto) => numeroParaCalculo(valorPrimarioDoPonto(ponto)));
    const valores5 = doEstado.map((ponto) => numeroParaCalculo(valorTexto(ponto.valor5um)));
    saida[`criterio_${sufixo}_05`] = String(limites.max05);
    saida[`criterio_${sufixo}_5`] = String(limites.max5);
    saida[`media_cont_${sufixo}_05`] = formatadoOuTraco(mediaNumerica(valores05), 0);
    saida[`media_cont_${sufixo}_5`] = formatadoOuTraco(mediaNumerica(valores5), 0);
    saida[`resultado_cont_${sufixo}`] = doEstado.length === 0
      ? '-'
      : (valores05.every((valor) => valor !== null && valor <= limites.max05)
        && valores5.every((valor) => valor !== null && valor <= limites.max5) ? 'Conforme' : 'N\u00e3o conforme');
  }

  const salasContagem = salas || [];
  saida.contagemLinhas = salasContagem.flatMap((sala) => {
    const pontosDaSala = pontosContagem.filter((ponto) => String(ponto.salaId) === String(sala.id));
    const configuracao = sala.configEnsaios?.contagemParticulas || {};
    return [['repouso', 'Repouso'], ['operacao', 'Opera\u00e7\u00e3o']].map(([estado, rotulo]) => {
      const doEstado = pontosDaSala.filter((ponto) => valorTexto(ponto.estado).toLowerCase() === estado);
      const grauC = estado === 'operacao' ? { max05: 3520000, max5: 29000 } : { max05: 352000, max5: 2900 };
      return {
        equipamento: valorTexto(sala.maquina) || valorTexto(sala.nome) || '-',
        area: formatadoOuTraco(sala.area, 2),
        classe: `${valorTexto(sala.grau) || '-'} (${rotulo})`,
        criterio05: String(criterioContagem(configuracao, estado, 'criterioMax', grauC.max05)),
        criterio5: String(criterioContagem(configuracao, estado, 'criterioMax5um', grauC.max5)),
        media05: formatadoOuTraco(mediaNumerica(doEstado.map(valorPrimarioDoPonto)), 0),
        media5: formatadoOuTraco(mediaNumerica(doEstado.map((ponto) => valorTexto(ponto.valor5um))), 0),
      };
    });
  });

  const configVisualizacao = (salas || [])
    .map((sala) => sala.configEnsaios?.visualizacaoFluxo || {})
    .find((config) => config.tipoFumaca || config.sentidoFluxo) || {};
  saida.tipo_fumaca = valorTexto(configVisualizacao.tipoFumaca) || 'Glicerina';
  saida.sentido_fluxo = valorTexto(configVisualizacao.sentidoFluxo) || 'Unidirecional';

  const conformidadeDoTipo = (tipo) => {
    const conformes = resultados
      .filter((resultado) => resultado && resultado.ensaioTipo === tipo)
      .map((resultado) => resultado.conforme);
    if (conformes.length === 0) return null;
    if (conformes.includes(false)) return false;
    return conformes.every((valor) => valor === true) ? true : null;
  };
  const ensaiosDoRelatorio = {
    AVALIACAO: 'avaliacaoFiltragem',
    VELOCIDADE: 'velocidadeFluxo',
    INTEGRIDADE: 'integridadeFiltros',
    RUIDO: 'nivelRuido',
    LUMINOSIDADE: 'luminosidade',
    PARALELISMO: 'paralelismoFluxo',
    CONTAGEM: 'contagemParticulas',
    VISUALIZACAO: 'visualizacaoFluxo',
  };
  for (const [sufixo, tipo] of Object.entries(ensaiosDoRelatorio)) {
    const conforme = conformidadeDoTipo(tipo);
    saida[`marca_conf_${sufixo}`] = conforme === true ? 'X' : '';
    saida[`marca_nconf_${sufixo}`] = conforme === false ? 'X' : '';
  }

  const integridade = mapaNormalizado(dadosDoResultado(resultadoDoTipo('integridadeFiltros')).integridade);
  const parcial = mapaNormalizado(integridade.parcial);
  const acoes = listaNormalizada(integridade.acoesCorretivas).map(valorTexto);
  saida.int_parcial_assentamento = textoConforme(parcial.assentamento);
  saida.int_parcial_estrutura = textoConforme(parcial.estrutura);
  saida.int_parcial_meio = textoConforme(parcial.meioFiltrante);
  saida.int_acao_aperto = marca(acoes.includes('Reaperto dos parafusos de fixação'));
  saida.int_acao_reparo = marca(acoes.includes('Reparo do filtro'));
  saida.int_acao_gaxeta = marca(acoes.includes('Troca da gaxeta'));
  saida.int_acao_troca = marca(acoes.includes('Troca do filtro'));
  saida.int_reparo_x = valorTexto(integridade.reparoX) || '-';
  saida.int_reparo_y = valorTexto(integridade.reparoY) || '-';
  saida.int_reparo_area = valorTexto(integridade.reparoAreaCm2) || '-';
  saida.int_novo_ensaio = textoConforme(integridade.novoEnsaioConforme);

  const visualizacao = resultadoDoTipo('visualizacaoFluxo');
  const dadosVisualizacao = dadosDoResultado(visualizacao);
  const verificacoes = listaNormalizada(dadosVisualizacao.verificacoesVisualizacao);
  saida.vis_1 = textoConforme(verificacoes[0]);
  saida.vis_2 = textoConforme(verificacoes[1]);
  saida.vis_tempo = valorTexto(dadosVisualizacao.tempoDissipacao) || '-';
  saida.vis_resultado = textoConforme(visualizacao ? visualizacao.conforme : null);

  const distancias = listaNormalizada(dadosDoResultado(resultadoDoTipo('paralelismoFluxo')).paralelismo);
  for (let indice = 0; indice < 4; indice++) {
    const ponto = mapaNormalizado(distancias[indice]);
    saida[`par_L_${indice + 1}`] = valorTexto(ponto.distanciaL) || '-';
    saida[`par_X_${indice + 1}`] = valorTexto(ponto.distanciaX) || '-';
  }

  const vazoes = listaNormalizada(dadosDoResultado(resultadoDoTipo('velocidadeFluxo')).vazaoPorFiltro);
  for (let indice = 0; indice < 5; indice++) {
    const filtro = mapaNormalizado(vazoes[indice]);
    saida[`media_f_${indice + 1}`] = formatadoOuTraco(filtro.mediaMs);
    saida[`area_f_${indice + 1}`] = formatadoOuTraco(filtro.areaM2, 4);
    saida[`vaz_f_${indice + 1}`] = formatadoOuTraco(filtro.vazaoM3h);
  }

  const sufixosExecucao = {
    AVALIACAO: 'avaliacaoFiltragem',
    VELOCIDADE: 'velocidadeFluxo',
    INTEGRIDADE: 'integridadeFiltros',
    RUIDO: 'nivelRuido',
    LUMINOSIDADE: 'luminosidade',
    PARALELISMO: 'paralelismoFluxo',
    CONTAGEM: 'contagemParticulas',
    VISUALIZACAO: 'visualizacaoFluxo',
  };
  for (const [sufixo, tipo] of Object.entries(sufixosExecucao)) {
    saida[`DATA EXECUCAO ${sufixo}`] = dataDoRegistro(resultadoDoTipo(tipo)?.dataHora);
  }

  return saida;
}

function dataDoRegistro(valor) {
  if (!valor) return '-';
  const data = typeof valor.toDate === 'function' ? valor.toDate() : new Date(valor);
  return Number.isNaN(data.getTime()) ? '-' : data.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
}

module.exports = {
  ANEXOS_MODELO,
  ANEXOS_PESAGEM,
  condicoesDeEnsaios,
  condicoesDePesagem,
  instrumentosUtilizados,
  normalizarTagsTemplate,
  placeholdersDeResultados,
};
