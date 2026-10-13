const nodemailer = require("nodemailer");

const REMETENTE_PADRAO = "djmikenapoleao@gmail.com";
const CONTENT_TYPE_DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

function criarTransportador() {
  const senha = String(process.env.SMTP_APP_PASSWORD || "").trim();
  if (!senha) throw new Error("SMTP_APP_PASSWORD nao configurada.");

  const porta = Number(process.env.SMTP_PORT || 465);
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || "smtp.gmail.com",
    port: porta,
    secure: process.env.SMTP_SECURE === undefined ? porta === 465 : process.env.SMTP_SECURE === "true",
    auth: {
      user: process.env.SMTP_USER || REMETENTE_PADRAO,
      pass: senha,
    },
  });
}

async function enviarRelatorioEmail({
  destinatario,
  assunto,
  texto,
  nomeArquivo,
  conteudo,
  transportador,
}) {
  const email = String(destinatario || "").trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error("Destinatario de e-mail invalido.");
  if (!Buffer.isBuffer(conteudo) || conteudo.length === 0) throw new Error("Anexo de relatorio vazio.");

  const remetente = process.env.SMTP_FROM || REMETENTE_PADRAO;
  const cliente = transportador || criarTransportador();
  return cliente.sendMail({
    from: remetente,
    to: email,
    subject: String(assunto || "Relatorio Celacanto"),
    text: String(texto || "Segue o relatorio Celacanto em anexo."),
    attachments: [{
      filename: String(nomeArquivo || "relatorio.docx"),
      content: conteudo,
      contentType: CONTENT_TYPE_DOCX,
    }],
  });
}

module.exports = {
  CONTENT_TYPE_DOCX,
  REMETENTE_PADRAO,
  criarTransportador,
  enviarRelatorioEmail,
};
