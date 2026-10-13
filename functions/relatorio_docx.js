// functions/relatorio_docx.js
// Renderiza em .docx o relatório montado pelo app (lista de blocos: titulo/paragrafo/lista/tabela/imagem).
const {
  AlignmentType, BorderStyle, Document, Footer, Header, HeadingLevel, ImageRun, LevelFormat, Packer,
  PageNumber, Paragraph, ShadingType, Table, TableCell, TableRow, TextRun, WidthType,
} = require("docx");

const HOSTS_IMAGEM_PERMITIDOS = new Set(["firebasestorage.googleapis.com", "storage.googleapis.com"]);
const LARGURA_IMAGEM_PX = 420;
const MAX_BYTES_IMAGEM = 10 * 1024 * 1024;

function tamanhoDaImagem(buffer) {
  // PNG: largura/altura no cabeçalho IHDR.
  if (buffer.length > 24 && buffer.readUInt32BE(0) === 0x89504e47) {
    return { tipo: "png", largura: buffer.readUInt32BE(16), altura: buffer.readUInt32BE(20) };
  }
  // JPEG: procura o marcador SOF0..SOF15 (exceto DHT/JPG/DAC).
  if (buffer.length > 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buffer.length) {
      if (buffer[i] !== 0xff) { i++; continue; }
      const marcador = buffer[i + 1];
      const tamanho = buffer.readUInt16BE(i + 2);
      if (marcador >= 0xc0 && marcador <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marcador)) {
        return { tipo: "jpg", altura: buffer.readUInt16BE(i + 5), largura: buffer.readUInt16BE(i + 7) };
      }
      i += 2 + tamanho;
    }
    return { tipo: "jpg", largura: 4, altura: 3 };
  }
  return null;
}

async function baixarImagem(url) {
  let endereco;
  try {
    endereco = new URL(url);
  } catch (_) {
    return null;
  }
  if (endereco.protocol !== "https:" || !HOSTS_IMAGEM_PERMITIDOS.has(endereco.hostname)) return null;
  try {
    const resposta = await fetch(endereco, { signal: AbortSignal.timeout(20000) });
    if (!resposta.ok) return null;
    const buffer = Buffer.from(await resposta.arrayBuffer());
    return buffer.length > MAX_BYTES_IMAGEM ? null : buffer;
  } catch (erro) {
    console.warn("Falha ao baixar imagem do relatorio:", erro.message);
    return null;
  }
}

const bordaTabela = { style: BorderStyle.SINGLE, size: 4, color: "808080" };
const bordas = { top: bordaTabela, bottom: bordaTabela, left: bordaTabela, right: bordaTabela };

function celula(texto, cabecalho) {
  return new TableCell({
    borders: bordas,
    shading: cabecalho ? { type: ShadingType.CLEAR, color: "auto", fill: "D9E2F3" } : undefined,
    children: String(texto ?? "").split("\n").map((linha) => new Paragraph({
      children: [new TextRun({ text: linha, bold: cabecalho, size: 18 })],
    })),
  });
}

function tabela(bloco) {
  const cabecalho = (bloco.cabecalho || []).map(String);
  const linhas = (bloco.linhas || []).map((l) => (Array.isArray(l) ? l : []));
  const colunas = Math.max(cabecalho.length, ...linhas.map((l) => l.length), 1);
  const completar = (l) => [...l, ...Array(Math.max(0, colunas - l.length)).fill("")];
  const rows = [];
  if (cabecalho.length) rows.push(new TableRow({ tableHeader: true, children: completar(cabecalho).map((c) => celula(c, true)) }));
  linhas.forEach((l) => rows.push(new TableRow({ children: completar(l).map((c) => celula(c, false)) })));
  if (!rows.length) rows.push(new TableRow({ children: [celula("-", false)] }));
  return new Table({ width: { size: 100, type: WidthType.PERCENTAGE }, rows });
}

async function renderizarDocx(documento) {
  const filhos = [];
  let instanciaLista = 0;

  filhos.push(new Paragraph({
    heading: HeadingLevel.TITLE,
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: String(documento.titulo || "Relatório"), bold: true })],
  }));

  for (const bloco of documento.blocos || []) {
    switch (bloco.tipo) {
      case "titulo":
        filhos.push(new Paragraph({
          heading: bloco.nivel === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_1,
          spacing: { before: 240, after: 120 },
          children: [new TextRun({ text: String(bloco.texto || "") })],
        }));
        break;
      case "paragrafo": {
        const runs = [];
        if (bloco.rotulo) runs.push(new TextRun({ text: `${bloco.rotulo} `, bold: true }));
        if (bloco.texto) runs.push(new TextRun({ text: String(bloco.texto) }));
        filhos.push(new Paragraph({ spacing: { after: 120 }, alignment: AlignmentType.JUSTIFIED, children: runs }));
        break;
      }
      case "lista": {
        instanciaLista++;
        for (const item of bloco.itens || []) {
          filhos.push(new Paragraph({
            alignment: AlignmentType.JUSTIFIED,
            ...(bloco.numerada
              ? { numbering: { reference: "numerada", level: 0, instance: instanciaLista } }
              : { bullet: { level: 0 } }),
            children: [new TextRun({ text: String(item) })],
          }));
        }
        break;
      }
      case "tabela":
        filhos.push(tabela(bloco));
        filhos.push(new Paragraph({ children: [] }));
        break;
      case "imagem": {
        const buffer = await baixarImagem(String(bloco.url || ""));
        const dimensoes = buffer ? tamanhoDaImagem(buffer) : null;
        if (buffer && dimensoes) {
          const altura = Math.round(LARGURA_IMAGEM_PX * (dimensoes.altura / Math.max(dimensoes.largura, 1)));
          filhos.push(new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new ImageRun({
              type: dimensoes.tipo,
              data: buffer,
              transformation: { width: LARGURA_IMAGEM_PX, height: Math.min(altura, 700) },
            })],
          }));
        } else {
          filhos.push(new Paragraph({ children: [new TextRun({ text: "(imagem indisponível ou pendente de envio)", italics: true })] }));
        }
        filhos.push(new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: String(bloco.legenda || ""), italics: true, size: 18 })],
        }));
        break;
      }
      default:
        break;
    }
  }

  const doc = new Document({
    styles: { default: { document: { run: { font: "Arial", size: 20 } } } },
    numbering: {
      config: [{
        reference: "numerada",
        levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.START }],
      }],
    },
    sections: [{
      headers: {
        default: new Header({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: String(documento.cabecalho || ""), size: 16, color: "555555" })],
          })],
        }),
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.RIGHT,
            children: [new TextRun({ children: ["Página ", PageNumber.CURRENT, " de ", PageNumber.TOTAL_PAGES], size: 16 })],
          })],
        }),
      },
      children: filhos,
    }],
  });

  return Packer.toBuffer(doc);
}

module.exports = { renderizarDocx, tamanhoDaImagem };
