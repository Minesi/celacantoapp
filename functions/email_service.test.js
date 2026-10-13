const assert = require("node:assert/strict");
const test = require("node:test");
const { CONTENT_TYPE_DOCX, REMETENTE_PADRAO, enviarRelatorioEmail } = require("./email_service");

test("envia o DOCX ao destinatario com remetente e anexo definidos", async () => {
  const conteudo = Buffer.from("docx-falso");
  let mensagem;
  const transportador = {
    sendMail: async (opcoes) => {
      mensagem = opcoes;
      return { messageId: "teste" };
    },
  };

  const resultado = await enviarRelatorioEmail({
    destinatario: "solicitante@empresa.com",
    assunto: "Relatorio aprovado",
    texto: "Segue o relatorio.",
    nomeArquivo: "Relatorio_123.docx",
    conteudo,
    transportador,
  });

  assert.equal(resultado.messageId, "teste");
  assert.equal(mensagem.from, REMETENTE_PADRAO);
  assert.equal(mensagem.to, "solicitante@empresa.com");
  assert.equal(mensagem.subject, "Relatorio aprovado");
  assert.equal(mensagem.attachments[0].filename, "Relatorio_123.docx");
  assert.equal(mensagem.attachments[0].contentType, CONTENT_TYPE_DOCX);
  assert.deepEqual(mensagem.attachments[0].content, conteudo);
});

test("rejeita destinatario invalido antes de acessar o SMTP", async () => {
  let acessouTransportador = false;
  const transportador = {
    sendMail: async () => {
      acessouTransportador = true;
    },
  };

  await assert.rejects(
    enviarRelatorioEmail({
      destinatario: "sem-email",
      conteudo: Buffer.from("docx"),
      transportador,
    }),
    /Destinatario de e-mail invalido/,
  );
  assert.equal(acessouTransportador, false);
});
