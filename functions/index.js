// functions/index.js
// Cloud Function HTTPS callable que gera o relatorio .docx final a partir do template base
// (Storage: templates/<templateId>.docx) mesclado com os dados estruturados do projeto
// (sistema, salas, handling units/filtros, instrumentos, leituras). Nucleo gratuito do
// docxtemplater/pizzip - sem modulo de imagem (fotos de evidencia ficam como links, nao
// embutidas no corpo do documento).
// A partir do firebase-functions v6 a raiz exporta a API v2; a função continua 1st Gen via /v1.
const functions = require("firebase-functions/v1");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
// firebase-admin v14 removeu admin.storage()/admin.firestore(): usar os submódulos.
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");
const totp = require("./totp");
const liberacaoPolicy = require("./liberacao_policy");
const offlineAuthorization = require("./offline_authorization");
const { renderizarDocx } = require("./relatorio_docx");
const { construirDocumento, extrairConclusao } = require("./relatorio_documento");
const { condicoesDeEnsaios, instrumentosUtilizados, normalizarTagsTemplate } = require("./modelo_cliente");
const { enviarRelatorioEmail, REMETENTE_PADRAO } = require("./email_service");

initializeApp();

const CONTENT_TYPE_DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

// Compatibilidade com o esquema legado de leituras (usado pelos 5 templates atuais).
const MAX_SLOTS_LEITURA = 10;
const MAX_LINHAS_FERRAMENTA = 6;
const MAX_LEITURAS_POR_LINHA = 2;

exports.cadastrarUsuario = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  const perfilSolicitante = await exigirSupervisor(context);
  const nome = String((data || {}).nome || "").trim();
  const cpf = String((data || {}).cpf || "").trim();
  const email = String((data || {}).email || "").trim().toLowerCase();
  const senha = String((data || {}).senha || "");
  const perfil = String((data || {}).perfil || "tecnico").trim().toLowerCase();
  const perfisValidos = new Set(["admin", "tecnico", "supervisor", "redator"]);

  if (!nome || !cpf || !email || !senha || !perfisValidos.has(perfil)) {
    throw new functions.https.HttpsError("invalid-argument", "Informe nome, CPF, e-mail, senha e perfil válidos.");
  }
  if (senha.length < 8 || !/[A-Z]/.test(senha) || !/[a-z]/.test(senha) || !/[!@#$&*~•]/.test(senha)) {
    throw new functions.https.HttpsError("invalid-argument", "A senha não atende aos requisitos mínimos.");
  }
  if (perfil === "admin" && perfilSolicitante.perfil !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Apenas administradores podem criar administradores.");
  }

  let novoUsuario;
  try {
    novoUsuario = await getAuth().createUser({ email, password: senha, displayName: nome });
    await getFirestore().collection("usuarios").doc(novoUsuario.uid).set({
      uid: novoUsuario.uid,
      nome,
      cpf,
      email,
      perfil,
      dominio_empresa: dominioDoEmail(email),
    });
    return { uid: novoUsuario.uid };
  } catch (erro) {
    if (novoUsuario) {
      try {
        await getAuth().deleteUser(novoUsuario.uid);
      } catch (erroExclusao) {
        console.error("Falha ao remover conta criada sem perfil:", erroExclusao);
      }
    }
    if (erro.code === "auth/email-already-exists") {
      throw new functions.https.HttpsError("already-exists", "Este e-mail já está cadastrado.");
    }
    console.error("Falha ao cadastrar usuário:", erro);
    throw new functions.https.HttpsError("internal", "Não foi possível cadastrar o usuário.");
  }
});

exports.excluirMinhaConta = functions.runWith({ invoker: "public" }).https.onCall(async (_data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");

  const authTime = Number(context.auth.token.auth_time);
  const idadeAutenticacaoMs = Date.now() - authTime * 1000;
  if (!Number.isFinite(authTime) || idadeAutenticacaoMs < 0 || idadeAutenticacaoMs > 5 * 60 * 1000) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Confirme sua senha novamente antes de excluir a conta."
    );
  }

  const db = getFirestore();
  const uid = context.auth.uid;
  const usuarioRef = db.collection("usuarios").doc(uid);
  const usuarioSnapshot = await usuarioRef.get();
  const usuario = usuarioSnapshot.exists ? usuarioSnapshot.data() || {} : {};
  const email = String(usuario.email || context.auth.token.email || "").trim().toLowerCase();
  const dominio = String(usuario.dominio_empresa || dominioDoEmail(email)).trim().toLowerCase();

  if (usuario.perfil === "admin") {
    if (!dominio) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Não foi possível confirmar o domínio do administrador."
      );
    }
    const administradores = await db.collection("usuarios").where("perfil", "==", "admin").get();
    const existeOutroAdministrador = administradores.docs.some((doc) => {
      if (doc.id === uid) return false;
      const outro = doc.data() || {};
      const dominioOutro = String(outro.dominio_empresa || dominioDoEmail(outro.email)).trim().toLowerCase();
      return dominioOutro === dominio;
    });
    if (!existeOutroAdministrador) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Cadastre outro administrador antes de excluir esta conta."
      );
    }
  }

  const refsParaExcluir = [
    usuarioRef,
    db.collection("totp_segredos").doc(uid),
    db.collection("autorizacao_chaves_offline").doc(uid),
    db.collection("liberacoes_tentativas").doc(uid),
  ];
  const batch = db.batch();
  refsParaExcluir.forEach((ref) => batch.delete(ref));
  await batch.commit();

  try {
    await getAuth().deleteUser(uid);
  } catch (erro) {
    if (erro.code !== "auth/user-not-found") {
      console.error("Falha ao remover usuário do Auth após limpar os dados:", erro);
      throw new functions.https.HttpsError("internal", "Não foi possível concluir a exclusão da conta.");
    }
  }

  return { ok: true };
});
// Callable precisa de invoker público no IAM; a autenticação é validada abaixo via context.auth.
exports.gerarRelatorioDocx = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  const perfilSolicitante = await exigirSupervisor(context);

  const { templateId, projeto } = data || {};
  if (!templateId || !projeto || !projeto.id) {
    throw new functions.https.HttpsError("invalid-argument", "Informe templateId e o objeto do projeto (com id).");
  }

  const projetoId = String(projeto.id).trim();
  const idSeguro = projetoId.replace(/[^A-Za-z0-9_-]/g, "");
  if (!idSeguro || idSeguro !== projetoId) {
    throw new functions.https.HttpsError("invalid-argument", "Informe um projetoId válido.");
  }

  const emailSolicitante = context.auth.token.email || perfilSolicitante.email || "";
  const acesso = await carregarProjetoAprovado(projetoId, perfilSolicitante, emailSolicitante);
  const templateEsperado = templateIdParaProjeto(acesso.projeto.tipoProjeto);
  if (String(templateId).trim() !== templateEsperado) {
    throw new functions.https.HttpsError("invalid-argument", "O template não corresponde ao tipo do projeto.");
  }
  if (!extrairConclusao(acesso.projeto)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "A conclusão da aprovação não está disponível para gerar o relatorio."
    );
  }

  let etapa = "acesso ao Storage";
  try {
    const projetoParaTemplate = await enriquecerProjetoParaTemplate(
      acesso.projeto,
      acesso.empresa,
      emailSolicitante,
    );
    return await gerarDocx(templateEsperado, projetoParaTemplate, (novaEtapa) => { etapa = novaEtapa; });
  } catch (erro) {
    if (erro instanceof functions.https.HttpsError) throw erro;
    console.error(`gerarRelatorioDocx falhou na etapa "${etapa}":`, erro);
    throw new functions.https.HttpsError("internal", `Falha na etapa: ${etapa}.`);
  }
});

exports.enviarRelatorioEmail = functions
  .runWith({ invoker: "public", memory: "512MB", timeoutSeconds: 180, secrets: ["SMTP_APP_PASSWORD"] })
  .https.onCall(async (data, context) => {
    const perfilSolicitante = await exigirSupervisor(context);
    const projetoId = String((data || {}).projetoId || "").trim();
    const idSeguro = projetoId.replace(/[^A-Za-z0-9_-]/g, "");
    if (!idSeguro || idSeguro !== projetoId) {
      throw new functions.https.HttpsError("invalid-argument", "Informe um projetoId válido.");
    }

    const emailSolicitante = String(context.auth.token.email || perfilSolicitante.email || "").trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(emailSolicitante)) {
      throw new functions.https.HttpsError("failed-precondition", "O usuário solicitante não possui e-mail válido.");
    }

    const acesso = await carregarProjetoAprovado(projetoId, perfilSolicitante, emailSolicitante);
    const projeto = acesso.projeto;
    if (!extrairConclusao(projeto)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "A conclusão da aprovação não está disponível para enviar o relatorio."
      );
    }

    const tipoProjeto = String(projeto.tipoProjeto || "");
    const templateId = templateIdParaProjeto(tipoProjeto);
    const db = getFirestore();
    const auditoriaRef = db.collection("relatorios_email").doc();
    await auditoriaRef.set({
      projetoId,
      destinatario: emailSolicitante,
      remetente: process.env.SMTP_FROM || REMETENTE_PADRAO,
      templateId,
      tipoProjeto,
      status: "iniciando",
      solicitadoPorUid: context.auth.uid,
      solicitadoPor: emailSolicitante,
      dataHora: FieldValue.serverTimestamp(),
    });

    try {
      let buffer;
      let caminho = "";
      if (templateId === "fluxo_laminar" || templateId === "pesagem") {
        const projetoParaTemplate = await enriquecerProjetoParaTemplate(projeto, acesso.empresa, emailSolicitante);
        const gerado = await gerarDocx(templateId, projetoParaTemplate, () => {});
        caminho = gerado.caminho;
        [buffer] = await getStorage().bucket().file(caminho).download();
      } else {
        const documento = await carregarDocumentoRelatorio(projetoId, perfilSolicitante, emailSolicitante);
        buffer = await renderizarDocx(documento);
      }

      const resultado = await enviarRelatorioEmail({
        destinatario: emailSolicitante,
        assunto: `Relatório Celacanto - ${tipoProjeto || "projeto"} - ${projetoId}`,
        texto: `Segue o relatório aprovado do projeto ${projetoId}.`,
        nomeArquivo: `Relatorio_${projetoId}.docx`,
        conteudo: buffer,
      });
      try {
        await auditoriaRef.update({
          status: "enviado",
          caminho,
          messageId: String(resultado.messageId || ""),
          enviadoEm: FieldValue.serverTimestamp(),
        });
      } catch (erroAuditoria) {
        console.error("E-mail enviado, mas a auditoria não foi atualizada:", erroAuditoria);
        return { ok: true, destinatario: emailSolicitante, auditoriaRegistrada: false };
      }
      return { ok: true, destinatario: emailSolicitante, auditoriaRegistrada: true };
    } catch (erro) {
      try {
        await auditoriaRef.update({
          status: "falhou",
          erro: String(erro.message || erro).slice(0, 500),
          falhouEm: FieldValue.serverTimestamp(),
        });
      } catch (erroAuditoria) {
        console.error("Falha ao registrar erro do envio de relatório:", erroAuditoria);
      }
      console.error("Falha ao enviar relatório por e-mail:", erro);
      throw new functions.https.HttpsError("internal", "Não foi possível enviar o relatório por e-mail.");
    }
  });

const MAX_BLOCOS_RELATORIO = 5000;

// Relatório montado pelo próprio sistema (sem template): os blocos são reconstruídos
// a partir do projeto aprovado, nunca aceitos do cliente.
exports.gerarRelatorioSistema = functions
  .runWith({ invoker: "public", memory: "512MB", timeoutSeconds: 120 })
  .https.onCall(async (data, context) => {
    const perfilSolicitante = await exigirSupervisor(context);

    const { projetoId } = data || {};
    const idSeguro = String(projetoId || "").replace(/[^A-Za-z0-9_-]/g, "");
    if (!idSeguro) throw new functions.https.HttpsError("invalid-argument", "Informe projetoId.");

    const documento = await carregarDocumentoRelatorio(
      String(projetoId),
      perfilSolicitante,
      context.auth.token.email || ""
    );
    if (documento.blocos.length > MAX_BLOCOS_RELATORIO) {
      throw new functions.https.HttpsError("invalid-argument", "Documento grande demais.");
    }

    let etapa = "renderizacao do documento";
    try {
      const buffer = await renderizarDocx(documento);
      etapa = "gravacao no Storage";
      const caminho = `relatorios/${idSeguro}/Relatorio_${idSeguro}_${Date.now()}.docx`;
      const bucket = getStorage().bucket();
      // Token de download do Firebase Storage: dispensa a permissão IAM signBlob exigida por getSignedUrl.
      const token = crypto.randomUUID();
      await bucket.file(caminho).save(buffer, {
        contentType: CONTENT_TYPE_DOCX,
        metadata: { metadata: { firebaseStorageDownloadTokens: token } },
      });
      const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(caminho)}?alt=media&token=${token}`;
      return { url, caminho };
    } catch (erro) {
      console.error(`gerarRelatorioSistema falhou na etapa "${etapa}":`, erro);
      throw new functions.https.HttpsError("internal", `Falha na etapa: ${etapa}.`);
    }
  });

async function carregarProjetoAprovado(projetoId, perfilSolicitante, emailSolicitante) {
  const db = getFirestore();
  const projetoSnapshot = await db.collection("projetos").doc(projetoId).get();
  if (!projetoSnapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Projeto nao encontrado.");
  }

  const projeto = { ...projetoSnapshot.data(), id: projetoId };
  if (projeto.status !== "aprovado") {
    throw new functions.https.HttpsError("failed-precondition", "O projeto precisa estar aprovado para gerar o relatorio.");
  }

  const dominioSolicitante = String(
    perfilSolicitante.dominio_empresa || dominioDoEmail(emailSolicitante)
  ).trim().toLowerCase();
  const empresaSnapshot = await db.collection("empresas")
    .where("cnpj", "==", String(projeto.cnpjEmpresa || ""))
    .limit(1)
    .get();
  if (empresaSnapshot.empty) {
    throw new functions.https.HttpsError("not-found", "Empresa do projeto nao encontrada.");
  }
  const empresaDoc = empresaSnapshot.docs[0];
  const empresa = empresaDoc.data() || {};
  const dominioEmpresa = String(empresa.dominio || empresa.dominio_empresa || empresaDoc.id).trim().toLowerCase();
  if (!dominioSolicitante || !dominioEmpresa || dominioEmpresa !== dominioSolicitante) {
    throw new functions.https.HttpsError("permission-denied", "O projeto nao pertence ao dominio do usuario.");
  }

  return { projeto, empresa, dominioSolicitante };
}

async function carregarDocumentoRelatorio(projetoId, perfilSolicitante, emailSolicitante) {
  const db = getFirestore();
  const acesso = await carregarProjetoAprovado(projetoId, perfilSolicitante, emailSolicitante);
  const { projeto, empresa, dominioSolicitante } = acesso;

  const sistemaSnapshot = projeto.sistemaId
    ? await db.collection("sistemas").doc(String(projeto.sistemaId)).get()
    : null;
  const sistema = sistemaSnapshot && sistemaSnapshot.exists ? sistemaSnapshot.data() || {} : {};
  const sistemaNome = String(sistema.nome || projeto.sistemaId || "");

  const catalogoSnapshot = await db.collection("testes_catalogo")
    .where("dominio", "==", dominioSolicitante)
    .get();
  const resumosPorEnsaio = {};
  for (const documentoCatalogo of catalogoSnapshot.docs) {
    const item = documentoCatalogo.data() || {};
    const tipo = String(item.tipoEnsaio || "");
    if (tipo) resumosPorEnsaio[tipo] = String(item.resumo || "");
  }

  const emails = new Set([
    String(projeto.operadorResponsavel || "").toLowerCase(),
    String(emailSolicitante || "").toLowerCase(),
  ]);
  for (const entrada of Array.isArray(projeto.history) ? projeto.history : []) {
    if (entrada && entrada.usuario) emails.add(String(entrada.usuario).toLowerCase());
  }
  const usuariosPorEmail = {};
  await Promise.all([...emails].filter(Boolean).map(async (email) => {
    const usuarioSnapshot = await db.collection("usuarios").where("email", "==", email).limit(1).get();
    if (!usuarioSnapshot.empty) usuariosPorEmail[email] = usuarioSnapshot.docs[0].data() || {};
  }));

  const conclusao = extrairConclusao(projeto);
  if (!conclusao) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "A conclusão da aprovação não está disponível para gerar o relatorio."
    );
  }

  return construirDocumento({
    projeto,
    nomeEmpresa: empresa.nome_fantasia || empresa.nomeFantasia || projeto.cnpjEmpresa,
    sistemaNome,
    dataEmissao: new Date(),
    pontosPorChave: undefined,
    resumosPorEnsaio,
    usuariosPorEmail,
    conclusao,
    emailRevisor: emailSolicitante,
  });
}

async function enriquecerProjetoParaTemplate(projeto, empresa, emailRevisor) {
  const sistemaSnapshot = projeto.sistemaId
    ? await getFirestore().collection("sistemas").doc(String(projeto.sistemaId)).get()
    : null;
  const sistema = sistemaSnapshot && sistemaSnapshot.exists ? sistemaSnapshot.data() || {} : {};
  return {
    ...projeto,
    nomeEmpresa: empresa.nome_fantasia || empresa.nomeFantasia || projeto.cnpjEmpresa,
    sistemaNome: sistema.nome || projeto.sistemaId || "",
    revisorEmail: emailRevisor,
  };
}

function templateIdParaProjeto(tipoProjeto) {
  const tipoNormalizado = String(tipoProjeto || "").trim().toLowerCase();
  if (tipoNormalizado.includes("fluxo")) return "fluxo_laminar";
  if (tipoNormalizado.includes("ar comprimido")) return "modelo_ar_comprimido";
  if (tipoNormalizado.includes("cabine") || tipoNormalizado.includes("capela")) return "modelo_cabine_exaustao";
  if (tipoNormalizado.includes("hvac")) return "modelo_relatorio_hvac";
  if (tipoNormalizado.includes("pesagem")) return "pesagem";
  return "modelo_teste";
}

async function gerarDocx(templateId, projeto, marcarEtapa) {
  const bucket = getStorage().bucket();
  const nomeTemplate = `${templateId}.docx`;
  const caminhoLocal = path.join(__dirname, "templates", nomeTemplate);
  let templateBuffer;

  if (fs.existsSync(caminhoLocal)) {
    templateBuffer = fs.readFileSync(caminhoLocal);
  } else {
    const templateFile = bucket.file(`templates/${nomeTemplate}`);
    const [existeTemplate] = await templateFile.exists();
    if (!existeTemplate) {
      throw new functions.https.HttpsError("not-found", `Template "${templateId}" nao encontrado no pacote nem no Storage.`);
    }
    [templateBuffer] = await templateFile.download();
  }

  marcarEtapa("montagem dos dados");
  const dadosMerge = await montarDadosMerge(projeto);

  marcarEtapa("leitura do template");
  const zip = new PizZip(templateBuffer);
  normalizarTagsTemplate(zip);
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
  const token = crypto.randomUUID();
  await arquivoGerado.save(bufferGerado, {
    contentType: CONTENT_TYPE_DOCX,
    metadata: { metadata: { firebaseStorageDownloadTokens: token } },
  });

  marcarEtapa("assinatura da URL de download");
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(nomeArquivo)}?alt=media&token=${token}`;

  return { url, caminho: nomeArquivo };
}

// Traduz o payload estruturado do app (ProjetoModel + salas/handlingUnits/instrumentos/leituras)
// para as tags esperadas pelos templates .docx: placeholders escalares em {MAIUSCULO},
// placeholders de instrumento {TAG_<FERRAMENTA>} (com/sem acento, por compatibilidade),
// esquema legado de leituras ({VALOR_N}/{EQUIP_VALOR_N} ou agrupado por ferramenta no HVAC)
// e os novos loops {#salas}/{#handlingUnits}/{#filtros} adicionados na secao final dos templates.
async function nomeDoUsuario(email) {
  if (!email) return "";
  const snapshot = await getFirestore().collection("usuarios").where("email", "==", email.toLowerCase()).limit(1).get();
  return snapshot.empty ? email : (snapshot.docs[0].data().nome || email);
}

async function montarDadosMerge(projeto) {
  const historico = Array.isArray(projeto.history) ? projeto.history : [];
  const usuarioDoHistorico = (valorNovo) => historico.find((entrada) => entrada.valorNovo === valorNovo)?.usuario || "";
  const pontosLeitura = pontosUnicos(projeto.pontosLeitura);
  const resultadosEnsaios = resultadosUnicos(projeto.resultadosEnsaios);
  const instrumentos = instrumentosUtilizados(projeto, resultadosEnsaios, pontosLeitura);
  const equipamento = (projeto.handlingUnits || []).map((handlingUnit) => handlingUnit.nome).find(Boolean)
    || instrumentos.map((instrumento) => instrumento.tag).find(Boolean)
    || "";
  const elaborador = projeto.elaboradorEmail || usuarioDoHistorico("pronto_para_campo");
  const tecnico = projeto.tecnicoEmail || usuarioDoHistorico("em_revisao");
  const revisor = projeto.revisorEmail || "";
  const [nomeElaborador, nomeTecnico, nomeRevisor] = await Promise.all([
    nomeDoUsuario(elaborador),
    nomeDoUsuario(tecnico),
    nomeDoUsuario(revisor),
  ]);

  const salas = (projeto.salas || []).map((sala) => mapearSala(sala, projeto.handlingUnits));
  const handlingUnits = (projeto.handlingUnits || []).map((handlingUnit) => mapearHandlingUnit(handlingUnit, projeto.salas));
  const dados = {
    PROJETO: projeto.tipoProjeto || "",
    EMPRESA: projeto.nomeEmpresa || "",
    CNPJ: projeto.cnpjEmpresa || "",
    SISTEMA: projeto.sistemaNome || "",
    AREA: projeto.area || "",
    "NOME DO CLIENTE": projeto.nomeEmpresa || "",
    "AREA QUE O EQUIP ESTA INSTALADO": projeto.area || "",
    "NUMERO OU TAG DO EQUIPAMENTO": equipamento,
    "TAG OU NUMERO DO EQUIPAMENTO": equipamento,
    ELABORADOR: nomeElaborador,
    TECNICO: nomeTecnico,
    "QUEM REVISA O RELATÓRIO": nomeRevisor,
    "QUEM REVISOU O RELATÓRIO": nomeRevisor,
    EDITAVEL: "",
    "VAI DEPENDER DE QUANTO TECNICOS EXECUTARAM O SERVIÇO": "",
    "VAI PUXAR DOS EQUIP DE CIMA": "",
    DATA_GERACAO: new Date().toLocaleDateString("pt-BR"),
    salas,
    handlingUnits,
    pontosLeitura,
    resultadosEnsaios,
    instrumentosUtilizados: instrumentos,
  };

  aplicarPlaceholdersDeInstrumentos(dados, instrumentos);
  aplicarPlaceholdersDeInstrumentosPorEnsaio(dados, instrumentos);
  aplicarPlaceholdersDeLeituras(dados, projeto.leiturasOcr || [], projeto.tipoProjeto || "");
  Object.assign(dados, condicoesDeEnsaios(projeto));
  aplicarPlaceholdersDeEnsaios(dados, projeto, {
    salas,
    handlingUnits,
    pontosLeitura,
    resultadosEnsaios,
    instrumentosUtilizados: instrumentos,
    nomeElaborador,
    nomeTecnico,
    nomeRevisor,
  });

  return dados;
}

function listaNormalizada(valor) {
  if (Array.isArray(valor)) return valor;
  if (typeof valor === "string" && valor.trim()) {
    try {
      const lista = JSON.parse(valor);
      return Array.isArray(lista) ? lista : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

function mapaNormalizado(valor) {
  if (valor && typeof valor === "object" && !Array.isArray(valor)) return valor;
  if (typeof valor === "string" && valor.trim()) {
    try {
      const mapa = JSON.parse(valor);
      return mapa && typeof mapa === "object" && !Array.isArray(mapa) ? mapa : {};
    } catch (_) {
      return {};
    }
  }
  return {};
}

function dataEmMilissegundos(valor) {
  if (!valor) return 0;
  if (valor instanceof Date) return valor.getTime();
  if (typeof valor.toDate === "function") return dataEmMilissegundos(valor.toDate());
  if (typeof valor === "object" && Number.isFinite(valor._seconds)) {
    return valor._seconds * 1000 + Math.floor((valor._nanoseconds || 0) / 1000000);
  }
  const milissegundos = Date.parse(String(valor));
  return Number.isFinite(milissegundos) ? milissegundos : 0;
}

function dataFormatada(valor, fallback = "") {
  const milissegundos = dataEmMilissegundos(valor) || dataEmMilissegundos(fallback);
  return milissegundos > 0 ? new Date(milissegundos).toLocaleDateString("pt-BR") : "";
}

function validadeDoTeste(instanteBase, meses) {
  const quantidadeMeses = Number.parseInt(meses, 10);
  if (!Number.isFinite(quantidadeMeses) || quantidadeMeses <= 0 || !instanteBase) return "";
  const data = new Date(instanteBase);
  data.setMonth(data.getMonth() + quantidadeMeses);
  return dataFormatada(data);
}

function resultadosUnicos(valor) {
  const unicos = new Map();
  for (const bruto of listaNormalizada(valor)) {
    if (!bruto || typeof bruto !== "object") continue;
    const resultado = {
      ...bruto,
      salaId: bruto.salaId?.toString() || "",
      ensaioTipo: bruto.ensaioTipo?.toString() || "",
      conforme: bruto.conforme === true || bruto.conforme === 1 || valorTexto(bruto.conforme).toLowerCase() === "true"
        ? true
        : bruto.conforme === false || bruto.conforme === 0 || valorTexto(bruto.conforme).toLowerCase() === "false"
          ? false
          : null,
      dados: mapaNormalizado(bruto.dados),
    };
    const chave = `${resultado.salaId}|${resultado.ensaioTipo}`;
    const anterior = unicos.get(chave);
    if (!anterior || dataEmMilissegundos(resultado.dataHora) >= dataEmMilissegundos(anterior.dataHora)) {
      unicos.set(chave, resultado);
    }
  }
  return [...unicos.values()];
}

function pontosUnicos(valor) {
  const unicos = new Map();
  for (const bruto of listaNormalizada(valor)) {
    if (!bruto || typeof bruto !== "object") continue;
    const ponto = {
      ...bruto,
      salaId: bruto.salaId?.toString() || "",
      ensaioTipo: bruto.ensaioTipo?.toString() || "",
      numeroPonto: Number.parseInt(bruto.numeroPonto, 10) || 0,
    };
    const estado = valorTexto(ponto.estado).toLowerCase();
    const chave = `${ponto.salaId}|${ponto.ensaioTipo}|${ponto.numeroPonto}|${estado}`;
    const anterior = unicos.get(chave);
    if (!anterior || dataEmMilissegundos(ponto.dataHoraCaptura) >= dataEmMilissegundos(anterior.dataHoraCaptura)) {
      unicos.set(chave, ponto);
    }
  }
  return [...unicos.values()];
}

function mapearFiltros(filtros) {
  return listaNormalizada(filtros)
    .filter((filtro) => Number(filtro.quantidade || 0) > 0)
    .map((filtro) => ({
      tipo: (filtro.tipo || "").toString().toUpperCase(),
      quantidade: Number(filtro.quantidade),
      marca: filtro.marca || "",
      modelo: filtro.modelo || "",
      dimensoes: filtro.dimensoes || "",
    }));
}

function idsMaquinasDaSala(sala) {
  return [sala.handlingUnitId, ...listaNormalizada(sala.handlingUnitIdsAdicionais)].filter(Boolean);
}

function mapearSala(sala, handlingUnits) {
  const filtros = mapearFiltros(sala.filtros);
  const maquinas = idsMaquinasDaSala(sala)
    .map((id) => (handlingUnits || []).find((h) => h.id === id))
    .filter(Boolean);
  return {
    id: sala.id || "",
    nome: sala.nome || "",
    area: sala.area ?? "",
    volume: sala.volume ?? "",
    grau: (sala.grau || "").toString().toUpperCase(),
    configEnsaios: mapaNormalizado(sala.configEnsaios),
    // Templates antigos usam {qtdDifusores}; saidas da sala agora sao os filtros.
    qtdDifusores: filtros.length > 0 ? filtros.reduce((soma, f) => soma + f.quantidade, 0) : (sala.qtdDifusores ?? ""),
    maquina: maquinas.map((m) => m.nome || "").join(", "),
    filtrosResumo: resumirFiltros(filtros),
    filtros,
  };
}

function mapearHandlingUnit(handlingUnit, salas) {
  const filtros = mapearFiltros(handlingUnit.filtros);
  return {
    id: handlingUnit.id || "",
    nome: handlingUnit.nome || "",
    numero: handlingUnit.numero || "",
    temFiltroTerminalTexto: handlingUnit.temFiltroTerminal ? "Sim" : "Nao",
    qtdFiltrosTerminais: handlingUnit.temFiltroTerminal ? (handlingUnit.qtdFiltrosTerminais ?? 0) : "-",
    filtrosResumo: resumirFiltros(filtros),
    filtros,
    salas: (salas || [])
      .filter((sala) => idsMaquinasDaSala(sala).includes(handlingUnit.id))
      .map((sala) => sala.nome || ""),
  };
}

function resumirFiltros(filtros) {
  return filtros.map((filtro) => {
    const identificacao = [filtro.tipo, filtro.modelo, filtro.dimensoes].filter(Boolean).join(" / ");
    return `${filtro.quantidade}x ${identificacao || "filtro"}`;
  }).join("; ") || "-";
}

function removerAcentos(texto) {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function aplicarPlaceholdersDeInstrumentos(dados, instrumentosUtilizadosProjeto) {
  const porTipo = new Map();
  for (const instrumento of instrumentosUtilizadosProjeto || []) {
    const nomeFerramenta = instrumento.tipo || instrumento.nome || "";
    if (!nomeFerramenta) continue;
    const lista = porTipo.get(nomeFerramenta) || [];
    lista.push(instrumento);
    porTipo.set(nomeFerramenta, lista);
  }
  porTipo.forEach((instrumentos, nomeFerramenta) => {
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

function aplicarPlaceholdersDeInstrumentosPorEnsaio(dados, instrumentosUtilizadosProjeto) {
  const sufixos = {
    avaliacaoFiltragem: "AVALIACAO",
    velocidadeFluxo: "VELOCIDADE",
    integridadeFiltros: "INTEGRIDADE",
    nivelRuido: "RUIDO",
    luminosidade: "LUMINOSIDADE",
    contagemParticulas: "CONTAGEM",
    visualizacaoFluxo: "VISUALIZACAO",
    paralelismoFluxo: "PARALELISMO",
  };
  for (const [ensaioTipo, sufixo] of Object.entries(sufixos)) {
    const instrumentos = (instrumentosUtilizadosProjeto || []).filter((instrumento) =>
      Array.isArray(instrumento.ensaios) && instrumento.ensaios.includes(ensaioTipo));
    dados[`NOME DO INSTRUMENTO_${sufixo}`] = linhasUnicas(instrumentos.map((instrumento) => instrumento.tipo));
    dados[`TAG INSTRUMENTO_${sufixo}`] = linhasUnicas(instrumentos.map((instrumento) => instrumento.tag));
    dados[`NUMERO DE SERIE_${sufixo}`] = linhasUnicas(instrumentos.map((instrumento) => instrumento.numeroSerie));
    dados[`CERTIFICADO DE CALIBRAÇÃO_${sufixo}`] = linhasUnicas(instrumentos.map((instrumento) => instrumento.numeroCertificado));
    dados[`VALIDADE DA CALIBRAÇÃO_${sufixo}`] = linhasUnicas(instrumentos.map((instrumento) => instrumento.validade));
  }
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

function valorTexto(valor) {
  return valor === null || valor === undefined ? "" : String(valor).trim();
}

function valorOuTraco(valor) {
  return valorTexto(valor) || "-";
}

function linhasUnicas(valores) {
  return [...new Set(valores.map(valorTexto).filter(Boolean))].join("\n") || "-";
}

function formatarNumeroRelatorio(valor) {
  const numero = Number.parseFloat(valorTexto(valor).replace(",", "."));
  if (!Number.isFinite(numero)) return valorTexto(valor);
  return numero.toLocaleString("pt-BR", { maximumFractionDigits: 3 });
}

function unidadesDeFiltroParaMerge(sala) {
  const unidades = [];
  for (const filtro of sala && Array.isArray(sala.filtros) ? sala.filtros : []) {
    const quantidade = Number.parseInt(filtro.quantidade, 10) || 0;
    for (let indice = 0; indice < quantidade; indice++) unidades.push(filtro);
  }
  return unidades;
}

function formatarPontoParaMerge(ponto, sala) {
  const numero = Number.parseInt(ponto.numeroPonto, 10) || 0;
  const filtroIndice = Number.parseInt(ponto.filtroIndice, 10) || 0;
  const unidades = unidadesDeFiltroParaMerge(sala);
  const filtro = filtroIndice > 0 ? unidades[filtroIndice - 1] : null;
  if (!filtro) return numero > 0 ? `Ponto ${numero}` : "Ponto";
  return `Filtro ${filtroIndice} (${valorTexto(filtro.tipo).toUpperCase()})`;
}

function pontoPrimario(ponto) {
  return valorOuTraco(ponto && (ponto.valor05um ?? ponto.valor));
}

function pontoSecundario(ponto) {
  return valorOuTraco(ponto && ponto.valor5um);
}

function mediaDosPontos(pontos) {
  const valores = pontos
    .map((ponto) => Number.parseFloat(valorTexto(ponto && ponto.valor05um).replace(",", ".")))
    .filter(Number.isFinite);
  if (valores.length === 0) return "";
  return formatarNumeroRelatorio(valores.reduce((soma, valor) => soma + valor, 0) / valores.length);
}

function dataDaTransicao(historico, valorNovo, fallback) {
  const entrada = [...historico].reverse().find((item) => item && item.campo === "status" && item.valorNovo === valorNovo);
  return dataFormatada(entrada && entrada.dataHora, fallback);
}

function aplicarPlaceholdersDeEnsaios(dados, projeto, contexto) {
  const salas = contexto.salas || [];
  const handlingUnits = contexto.handlingUnits || [];
  const pontosLeitura = pontosUnicos(contexto.pontosLeitura);
  const resultadosEnsaios = contexto.resultadosEnsaios || [];
  const salasPorId = new Map(salas.map((sala) => [valorTexto(sala.id), sala]));
  const tiposSelecionados = Array.isArray(projeto.ensaiosSelecionados) ? projeto.ensaiosSelecionados : [];
  const tipos = [...new Set([
    ...tiposSelecionados,
    ...resultadosEnsaios.map((resultado) => resultado.ensaioTipo),
    ...pontosLeitura.map((ponto) => ponto.ensaioTipo),
  ].filter(Boolean))];
  const resultadosPorTipo = (tipo) => resultadosEnsaios.filter((resultado) => resultado.ensaioTipo === tipo);
  const pontosPorTipo = (tipo) => pontosLeitura
    .filter((ponto) => ponto.ensaioTipo === tipo)
    .sort((a, b) => {
      const estadoA = tipo === "contagemParticulas"
        ? (valorTexto(a.estado).toLowerCase() === "operacao" ? 1 : 0)
        : 0;
      const estadoB = tipo === "contagemParticulas"
        ? (valorTexto(b.estado).toLowerCase() === "operacao" ? 1 : 0)
        : 0;
      const salaA = salas.findIndex((sala) => valorTexto(sala.id) === valorTexto(a.salaId));
      const salaB = salas.findIndex((sala) => valorTexto(sala.id) === valorTexto(b.salaId));
      return estadoA - estadoB
        || (salaA < 0 ? Number.MAX_SAFE_INTEGER : salaA) - (salaB < 0 ? Number.MAX_SAFE_INTEGER : salaB)
        || (a.numeroPonto || 0) - (b.numeroPonto || 0);
    });
  const salasDosRegistros = (tipo) => {
    const ids = new Set([
      ...resultadosPorTipo(tipo).map((resultado) => valorTexto(resultado.salaId)),
      ...pontosPorTipo(tipo).map((ponto) => valorTexto(ponto.salaId)),
    ]);
    return salas.filter((sala) => ids.has(valorTexto(sala.id)));
  };

  const tipoPrincipal = [
    "avaliacaoFiltragem",
    "velocidadeFluxo",
    "integridadeFiltros",
    "nivelRuido",
    "luminosidade",
    "contagemParticulas",
    "visualizacaoFluxo",
    "paralelismoFluxo",
  ].find((tipo) => tipos.includes(tipo)) || tipos[0] || "";
  const pontosPrincipais = pontosPorTipo(tipoPrincipal);
  const resultadosPrincipais = resultadosPorTipo(tipoPrincipal);
  const salasPrincipais = salasDosRegistros(tipoPrincipal);
  const resultadoPrimeiro = resultadosPrincipais[0] || null;
  const dadosResultado = resultadoPrimeiro ? resultadoPrimeiro.dados : {};
  const resultadosComConformidade = resultadosEnsaios.filter((resultado) => resultado.conforme !== null);
  const conformeGeral = resultadosComConformidade.some((resultado) => resultado.conforme === false)
    ? false
    : resultadosComConformidade.length > 0 && resultadosComConformidade.every((resultado) => resultado.conforme === true)
      ? true
      : null;
  const pontosFormatados = pontosPrincipais.map((ponto) => ({
    ...ponto,
    rotulo: formatarPontoParaMerge(ponto, salasPorId.get(valorTexto(ponto.salaId))),
  }));
  const historico = Array.isArray(projeto.history) ? projeto.history : [];
  const dataCriacao = projeto.dataCriacao || new Date().toISOString();
  const instantesTestes = [
    ...resultadosEnsaios.map((resultado) => dataEmMilissegundos(resultado.dataHora)),
    ...pontosLeitura.map((ponto) => dataEmMilissegundos(ponto.dataHoraCaptura)),
  ].filter((instante) => instante > 0);
  const ultimoTeste = instantesTestes.length > 0 ? Math.max(...instantesTestes) : dataEmMilissegundos(dataCriacao);
  const instrumentos = contexto.instrumentosUtilizados || instrumentosUtilizados(projeto, resultadosEnsaios, pontosLeitura);
  const filtros = salas.flatMap((sala) => Array.isArray(sala.filtros) ? sala.filtros : []);
  const maquinasDasSalas = salas
    .flatMap((sala) => idsMaquinasDaSala(sala))
    .map((id) => handlingUnits.find((handlingUnit) => valorTexto(handlingUnit.id) === valorTexto(id)))
    .filter(Boolean);
  const maquinas = maquinasDasSalas.length > 0 ? maquinasDasSalas : handlingUnits;
  const paralelismo = mapaNormalizado(projeto.paralelismo);
  const conclusao = extrairConclusao(projeto);
  const valoresVelocidade = resultadosPorTipo("velocidadeFluxo").map((resultado) => {
    const resultadoDados = resultado.dados || {};
    const media = resultadoDados.media === undefined ? "" : formatarNumeroRelatorio(resultadoDados.media);
    const desvio = resultadoDados.desvioPadraoRelativo === undefined || resultadoDados.desvioPadraoRelativo === null
      ? ""
      : `${formatarNumeroRelatorio(resultadoDados.desvioPadraoRelativo)}%`;
    return [media, desvio].filter(Boolean).join(" | ");
  }).filter(Boolean);
  const criterio = linhasUnicas(resultadosEnsaios.map((resultado) => {
    const sala = salasPorId.get(valorTexto(resultado.salaId));
    return resultado.dados.criterio || sala?.configEnsaios?.[resultado.ensaioTipo]?.criterio || "";
  }));
  const mediaRuido = resultadosPorTipo("nivelRuido").map((resultado) => resultado.dados.media).find((valor) => valor !== undefined)
    || mediaDosPontos(pontosPorTipo("nivelRuido"));
  const estadosContagem = linhasUnicas(pontosPorTipo("contagemParticulas").map((ponto) => ponto.estado));
  const graus = linhasUnicas(salas.map((sala) => sala.grau));

  dados["AREA QUE O EQUIP ESTA INSTALADO"] = projeto.area || "";
  dados["nome do sistema"] = projeto.sistemaNome || projeto.sistemaId || "";
  dados["DATA DO TESTE "] = dataFormatada(resultadoPrimeiro && resultadoPrimeiro.dataHora, dataCriacao);
  dados["DATA DO TESTE"] = dados["DATA DO TESTE "];
  dados["DATA ELABORACAO"] = dataDaTransicao(historico, "pronto_para_campo", dataCriacao);
  dados["DATA ELABORADOR"] = dados["DATA ELABORACAO"];
  dados["VALIDADE DO TESTE"] = validadeDoTeste(ultimoTeste, projeto.validadeTestesMeses);
  dados["DATA SUPERVISAO"] = dataDaTransicao(historico, "em_revisao", dataCriacao);
  dados["NOME DO TECNICO"] = contexto.nomeTecnico || projeto.tecnicoEmail || "";
  dados["SUPERVISOR"] = contexto.nomeRevisor || projeto.revisorEmail || "";
  dados["NOME SUPERVISOR"] = dados["SUPERVISOR"];
  dados["ASSINATURA ELABORADOR"] = contexto.nomeElaborador || "";
  dados["NOME DA MAQUINA"] = linhasUnicas(maquinas.map((maquina) => maquina.nome));
  dados["NUMERO DA MAQUINA"] = linhasUnicas(maquinas.map((maquina) => maquina.numero));
  dados["NOME FILTRO"] = linhasUnicas(filtros.map((filtro) => filtro.tipo));
  dados["MODELO FILTRO"] = linhasUnicas(filtros.map((filtro) => filtro.modelo));
  dados["DIMENSOES FILTRO"] = linhasUnicas(filtros.map((filtro) => filtro.dimensoes));
  dados["NOME DO INSTRUMENTO"] = linhasUnicas(instrumentos.map((instrumento) => instrumento.tipo));
  dados["TAG INSTRUMENTO"] = linhasUnicas(instrumentos.map((instrumento) => instrumento.tag));
  dados["NUMERO DE SERIE"] = linhasUnicas(instrumentos.map((instrumento) => instrumento.numeroSerie));
  dados["CERTIFICADO DE CALIBRAÇÃO"] = linhasUnicas(instrumentos.map((instrumento) => instrumento.numeroCertificado));
  dados["VALIDADE DA CALIBRAÇÃO"] = linhasUnicas(instrumentos.map((instrumento) => instrumento.validade));
  dados.instrumentosUtilizados = instrumentos.map((instrumento) => ({
    nome: instrumento.tipo || "",
    tipo: instrumento.tipo || "",
    tag: instrumento.tag || "",
    numeroSerie: instrumento.numeroSerie || "",
    certificado: instrumento.numeroCertificado || "",
    validade: instrumento.validade || "",
  }));
  dados["CRITERIO"] = criterio;
  dados["FREQUENCIA MAQUINA"] = dadosResultado.frequencia || "";
  dados["VAZAO"] = dadosResultado.vazao || dadosResultado.vazaoCriterio || "";
  dados["AREA SALA"] = linhasUnicas(salasPrincipais.map((sala) => sala.area));
  dados["OBS TECNICO"] = linhasUnicas(resultadosPrincipais.map((resultado) => resultado.observacoes));
  dados["GRAU1"] = graus === "-" ? graus : `${graus} (Repouso)`;
  dados["GRAU2"] = graus === "-" ? graus : `${graus} (Operação)`;
  dados["EDITAVEL"] = estadosContagem === "-" ? "" : estadosContagem;
  dados["CONFORME"] = conformeGeral === true ? "X" : "";
  dados["NCONFORME"] = conformeGeral === false ? "X" : "";
  dados["RESULTADO"] = linhasUnicas([
    ...pontosPorTipo("visualizacaoFluxo").map(pontoPrimario),
    ...pontosPorTipo("paralelismoFluxo").map(pontoPrimario),
    paralelismo.resultado,
  ]);
  dados["CALCULO RESULTADO"] = linhasUnicas([
    ...valoresVelocidade,
    paralelismo.calculo,
  ]);
  dados["Resultado 1"] = valoresVelocidade.join("\n") || pontoPrimario(pontosFormatados[0]);
  dados["Calculo resultado 1"] = dados["CALCULO RESULTADO"];
  dados["MEDIA RESULTADO"] = valorOuTraco(mediaRuido);

  const salasIntegridade = salasDosRegistros("integridadeFiltros");
  const pontosIntegridade = pontosPorTipo("integridadeFiltros");
  dados["SALA"] = linhasUnicas(salasIntegridade.map((sala) => sala.nome));
  for (let indice = 0; indice < 4; indice++) {
    const ponto = pontosIntegridade[indice];
    dados[`PONTO${indice + 1}`] = ponto
      ? formatarPontoParaMerge(ponto, salasPorId.get(valorTexto(ponto.salaId)))
      : "-";
  }

  const pontosContagem = pontosPorTipo("contagemParticulas");
  const pontosContagemRepouso = pontosContagem.filter(
    (ponto) => valorTexto(ponto.estado).toLowerCase() === "repouso",
  );
  const pontosContagemOperacao = pontosContagem.filter(
    (ponto) => valorTexto(ponto.estado).toLowerCase() === "operacao",
  );
  for (let indice = 0; indice < 6; indice++) {
    const numero = indice + 1;
    const ponto = pontosFormatados[indice];
    dados[`PONTO ${numero}`] = ponto ? ponto.rotulo : "-";
    dados[`RESULTADO ${numero}`] = ponto ? pontoPrimario(ponto) : "-";
    dados[`RESULTADO${numero}`] = ponto ? pontoPrimario(pontosPorTipo("nivelRuido")[indice]) : "-";
    const pontosDoEstado = numero <= 3 ? pontosContagemRepouso : pontosContagemOperacao;
    const indiceDoEstado = numero <= 3 ? numero - 1 : numero - 4;
    const pontoContagem = pontosDoEstado[indiceDoEstado];
    dados[`RESULTADO${numero}.1`] = pontoContagem ? pontoPrimario(pontoContagem) : "-";
    dados[`RESULTADO${numero}.2`] = pontoContagem ? pontoSecundario(pontoContagem) : "-";
  }

  dados["SUPERVISORS"] = conclusao && conclusao.cumpre === true ? "X" : "";
  dados["SUPERVISORN"] = conclusao && conclusao.cumpre === false ? "X" : "";
  dados["COMENT ELABORADOR"] = conclusao ? conclusao.comentarios || "" : "";
  dados.resultadosPorEnsaio = resultadosEnsaios.map((resultado) => ({
    ...resultado,
    sala: salasPorId.get(valorTexto(resultado.salaId))?.nome || "",
    conformeTexto: resultado.conforme === true ? "Conforme" : resultado.conforme === false ? "Nao conforme" : "Nao informado",
    resumo: Object.entries(resultado.dados || {})
      .filter(([, valor]) => valor !== null && valor !== undefined && valorTexto(valor))
      .map(([chave, valor]) => `${chave}: ${valorTexto(valor)}`)
      .join("; ") || "-",
  }));
  dados.pontosPorEnsaio = pontosLeitura.map((ponto) => {
    const sala = salasPorId.get(valorTexto(ponto.salaId));
    return {
      ...ponto,
      sala: sala?.nome || "",
      rotulo: formatarPontoParaMerge(ponto, sala),
      valorPrincipal: pontoPrimario(ponto),
      valorSecundario: pontoSecundario(ponto),
    };
  });
}

// --- Liberacao do tecnico por codigo TOTP (Google/Microsoft Authenticator) ---
// Segredos ficam em totp_segredos/{uid}, inacessivel ao app pelas regras do Firestore.

const EMISSOR_TOTP = "Celacanto";

async function perfilDoUsuario(uid) {
  const doc = await getFirestore().collection("usuarios").doc(uid).get();
  return doc.exists ? doc.data() : null;
}

function dominioDoEmail(email) {
  const partes = (email || "").toLowerCase().split("@");
  return partes.length === 2 ? partes[1] : "";
}

function ehSupervisor(perfil) {
  return perfil && (perfil.perfil === "supervisor" || perfil.perfil === "admin");
}

async function exigirSupervisor(context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");
  const perfil = await perfilDoUsuario(context.auth.uid);
  if (!ehSupervisor(perfil)) {
    throw new functions.https.HttpsError("permission-denied", "Apenas supervisores/admins usam o autenticador.");
  }
  return perfil;
}

exports.configurarAutenticador = functions.runWith({ invoker: "public" }).https.onCall(async (_data, context) => {
  const perfil = await exigirSupervisor(context);
  const email = context.auth.token.email || perfil.email || "";
  const segredo = totp.gerarSegredoBase32();
  // Fica pendente ate o supervisor confirmar um codigo; o segredo ativo anterior continua valendo.
  await getFirestore().collection("totp_segredos").doc(context.auth.uid).set(
    { segredoPendente: segredo, pendenteDesde: FieldValue.serverTimestamp() },
    { merge: true }
  );
  return {
    segredo,
    uri: totp.montarUriOtpauth({ segredoBase32: segredo, conta: email, emissor: EMISSOR_TOTP }),
  };
});

exports.confirmarAutenticador = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  const perfil = await exigirSupervisor(context);
  const ref = getFirestore().collection("totp_segredos").doc(context.auth.uid);
  const doc = await ref.get();
  const pendente = doc.exists ? doc.data().segredoPendente : null;
  if (!pendente) throw new functions.https.HttpsError("failed-precondition", "Nenhuma configuracao pendente.");

  const passo = totp.verificarCodigo(pendente, String((data || {}).codigo || "").trim());
  if (passo === null) throw new functions.https.HttpsError("invalid-argument", "Codigo incorreto.");

  await ref.set({
    segredo: pendente,
    confirmado: true,
    ultimoPasso: passo,
    dominio: perfil.dominio_empresa || dominioDoEmail(context.auth.token.email),
    configuradoEm: FieldValue.serverTimestamp(),
  });
  await getFirestore().collection("usuarios").doc(context.auth.uid).set({ totpAtivo: true }, { merge: true });
  return { ok: true };
});

exports.registrarChaveAutorizacaoOffline = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  const perfil = await exigirSupervisor(context);
  const chave = String((data || {}).publicKey || "").trim();
  const chaveBytes = Buffer.from(chave, "base64");
  if (chaveBytes.length !== 32) {
    throw new functions.https.HttpsError("invalid-argument", "A chave pública offline é inválida.");
  }

  const email = context.auth.token.email || perfil.email || "";
  const dominio = perfil.dominio_empresa || dominioDoEmail(email);
  await getFirestore().collection("autorizacao_chaves_offline").doc(context.auth.uid).set({
    uid: context.auth.uid,
    nome: perfil.nome || email,
    email,
    dominio,
    publicKey: chaveBytes.toString("base64"),
    ativo: true,
    atualizadoEm: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.listarChavesAutorizacaoOffline = functions.runWith({ invoker: "public" }).https.onCall(async (_data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");
  const perfilSolicitante = await perfilDoUsuario(context.auth.uid);
  if (!perfilSolicitante) throw new functions.https.HttpsError("permission-denied", "Perfil não encontrado.");
  const dominio = perfilSolicitante.dominio_empresa || dominioDoEmail(context.auth.token.email);
  const snapshot = await getFirestore()
    .collection("autorizacao_chaves_offline")
    .where("dominio", "==", dominio)
    .where("ativo", "==", true)
    .get();

  return {
    chaves: snapshot.docs.map((doc) => {
      const chave = doc.data();
      return {
        uid: doc.id,
        nome: chave.nome || "",
        email: chave.email || "",
        publicKey: chave.publicKey || "",
      };
    }),
  };
});

exports.validarAutorizacaoOffline = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");

  const token = String((data || {}).token || "").trim();
  if (!token) throw new functions.https.HttpsError("invalid-argument", "Token de autorizacao offline obrigatorio.");

  let analisado;
  let chaveRegistrada;
  const agoraMs = Date.now();
  try {
    const toleranciaReconciliacao = offlineAuthorization.MAX_RECONCILIACAO_ATRASO_MS;
    const envelopeSemVerificacao = offlineAuthorization.analisarToken(token, agoraMs, toleranciaReconciliacao);
    const chaveDoc = await getFirestore().collection("autorizacao_chaves_offline")
      .doc(envelopeSemVerificacao.supervisorUid)
      .get();
    chaveRegistrada = chaveDoc.data() || {};
    if (!chaveDoc.exists || chaveRegistrada.ativo !== true) {
      throw new functions.https.HttpsError("failed-precondition", "Chave do supervisor nao esta ativa.");
    }
    analisado = offlineAuthorization.verificarToken(
      token,
      chaveRegistrada.publicKey,
      agoraMs,
      toleranciaReconciliacao,
    );
  } catch (erro) {
    if (erro instanceof functions.https.HttpsError) throw erro;
    console.error("Falha ao validar autorizacao offline:", erro);
    throw new functions.https.HttpsError("permission-denied", "Autorizacao offline invalida ou expirada.");
  }

  const db = getFirestore();
  const tecnico = (await perfilDoUsuario(context.auth.uid)) || {};
  const supervisor = (await perfilDoUsuario(analisado.supervisorUid)) || {};
  const dominioTecnico = tecnico.dominio_empresa || dominioDoEmail(context.auth.token.email);
  const dominioSupervisor = supervisor.dominio_empresa || dominioDoEmail(analisado.envelope.supervisorEmail);
  const dominioChave = chaveRegistrada.dominio || dominioSupervisor;
  if (!ehSupervisor(supervisor) || !dominioTecnico || dominioTecnico !== dominioSupervisor || dominioTecnico !== dominioChave) {
    throw new functions.https.HttpsError("permission-denied", "Supervisor fora do dominio autorizado.");
  }

  const nonceRef = db.collection("autorizacao_offline_nonces").doc(analisado.nonce);
  const resultado = await db.runTransaction(async (tx) => {
    const nonceDoc = await tx.get(nonceRef);
    if (nonceDoc.exists) return { jaRegistrada: true, registro: nonceDoc.data() };

    const liberacaoRef = db.collection("liberacoes").doc();
    const registro = {
      tecnicoUid: context.auth.uid,
      tecnicoEmail: context.auth.token.email || tecnico.email || "",
      supervisorUid: analisado.supervisorUid,
      supervisorNome: supervisor.nome || supervisor.email || "",
      supervisorEmail: supervisor.email || "",
      metodo: "offline_assinada",
      status: "reconciliada",
      nonce: analisado.nonce,
      projetoId: analisado.contexto.projetoId,
      salaId: analisado.contexto.salaId,
      ensaioTipo: analisado.contexto.ensaioTipo,
      ferramentaTipo: analisado.contexto.ferramentaTipo,
      ferramentaTag: analisado.contexto.ferramentaTag,
      justificativa: analisado.contexto.justificativa,
      solicitacao: analisado.requestToken,
      assinatura: analisado.envelope.assinatura,
      dominio: dominioTecnico,
      dataHora: FieldValue.serverTimestamp(),
    };
    tx.create(nonceRef, {
      ...registro,
      reconciliadoEm: FieldValue.serverTimestamp(),
    });
    tx.create(liberacaoRef, registro);
    return { jaRegistrada: false, registro };
  });

  if (resultado.jaRegistrada && (
    resultado.registro?.tecnicoUid !== context.auth.uid ||
    resultado.registro?.supervisorUid !== analisado.supervisorUid
  )) {
    throw new functions.https.HttpsError("already-exists", "Esta autorizacao offline ja foi reconciliada por outro usuario.");
  }

  return {
    ok: true,
    jaRegistrada: resultado.jaRegistrada,
    supervisorUid: analisado.supervisorUid,
    supervisorNome: supervisor.nome || supervisor.email || "",
    supervisorEmail: supervisor.email || "",
  };
});

exports.validarCodigoLiberacao = functions.runWith({ invoker: "public" }).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Autenticacao necessaria.");
  const db = getFirestore();
  const uid = context.auth.uid;
  const codigo = String((data || {}).codigo || "").trim();
  const motivo = String((data || {}).motivo || "").slice(0, 500);
  const auditoriaBruta = data && data.auditoria && typeof data.auditoria === "object" ? data.auditoria : {};
  const campoAuditoria = (nome, limite = 200) => String(auditoriaBruta[nome] || "").slice(0, limite);
  const projetoId = campoAuditoria("projetoId");
  const justificativa = campoAuditoria("justificativa", 500) || motivo;

  if (!/^\d{6}$/.test(codigo)) {
    throw new functions.https.HttpsError("invalid-argument", "Informe um código de 6 dígitos.");
  }
  if (!projetoId || !justificativa) {
    throw new functions.https.HttpsError("invalid-argument", "Projeto e justificativa são obrigatórios.");
  }

  // Limita tentativas por usuario: sem isso, 6 digitos seriam vulneraveis a forca bruta.
  const refTentativas = db.collection("liberacoes_tentativas").doc(uid);
  const tentativas = (await refTentativas.get()).data() || {};
  const agora = Date.now();
  const limiteTentativas = liberacaoPolicy.limiteDeTentativas(tentativas, agora);
  if (limiteTentativas.bloqueado) {
    throw new functions.https.HttpsError("resource-exhausted", "Muitas tentativas. Aguarde alguns minutos.");
  }

  const solicitante = (await perfilDoUsuario(uid)) || {};
  const dominio = solicitante.dominio_empresa || dominioDoEmail(context.auth.token.email);
  const segredos = await db.collection("totp_segredos")
    .where("confirmado", "==", true)
    .where("dominio", "==", dominio)
    .get();

  for (const docSegredo of segredos.docs) {
    const passo = totp.verificarCodigo(docSegredo.data().segredo, codigo, agora);
    if (passo === null) continue;

    const supervisor = await perfilDoUsuario(docSegredo.id);
    if (!ehSupervisor(supervisor)) continue;

    // Impede reutilizar o mesmo codigo (ou um anterior) do mesmo supervisor.
    const aceito = await db.runTransaction(async (tx) => {
      const atual = await tx.get(docSegredo.ref);
      if (!liberacaoPolicy.passoPodeSerUsado(atual.data().ultimoPasso, passo)) return false;
      tx.update(docSegredo.ref, { ultimoPasso: passo });
      return true;
    });
    if (!aceito) continue;

    await db.collection("liberacoes").add({
      tecnicoUid: uid,
      tecnicoEmail: context.auth.token.email || "",
      supervisorUid: docSegredo.id,
      supervisorNome: supervisor.nome || "",
      supervisorEmail: supervisor.email || "",
      motivo,
      metodo: "totp",
      projetoId,
      salaId: campoAuditoria("salaId"),
      ensaioTipo: campoAuditoria("ensaioTipo"),
      ferramentaTipo: campoAuditoria("ferramentaTipo"),
      ferramentaTag: campoAuditoria("ferramentaTag"),
      justificativa,
      dominio,
      dataHora: FieldValue.serverTimestamp(),
    });
    await refTentativas.delete();
    return {
      supervisorNome: supervisor.nome || supervisor.email || "",
      supervisorEmail: supervisor.email || "",
      supervisorUid: docSegredo.id,
    };
  }

  await refTentativas.set(liberacaoPolicy.registrarFalha(tentativas, agora));
  throw new functions.https.HttpsError("permission-denied", "Codigo invalido ou expirado.");
});
