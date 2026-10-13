// Reconstrói o relatório estruturado a partir dos dados autoritativos do Firestore.
// Este módulo não acessa Firebase para permanecer determinístico e fácil de testar.

const PRE_REQUISITOS_ACESSO = [
  "Se for aplicável, seguir os procedimentos estabelecidos em relação ao acesso à sala (ou zona) limpa, inclusive aqueles relativos à paramentação;",
  "Os equipamentos e instrumentos a serem utilizados no teste devem ser limpos antes de ingressar em qualquer ambiente de sala (ou zona) limpa;",
  "O sistema e todos os equipamentos que compõem o sistema devem estar em operação para que sejam feitas as devidas medições;",
];

const TEXTOS = {
  empresaExecutora: "Celacanto Análises e Qualificações Ltda.",
  secoes: {
    objetivo: "Objetivo",
    referencia: "Referência",
    definicoes: "Definições",
    escopo: "Escopo",
    responsabilidades: "Responsabilidades",
    anexos: "Anexos",
    testes: "Testes",
    tabelaTestesResumo: "Tabela de Testes (Resumo)",
    documentacaoApoio: "Documentação de Apoio",
    paralelismoFluxoAr: "Paralelismo do Fluxo de Ar",
    registroAssinaturas: "Registro de Assinaturas",
    conclusaoQualificacao: "Conclusão da Qualificação de Desempenho",
  },
  titulo: "RELATÓRIO DE QUALIFICAÇÃO DE DESEMPENHO – {DESCRICAO_SISTEMA} – {SISTEMA}",
  notaConfidencialidade:
    "Nota: Este documento, incluindo seus registros/anexos, tem caráter confidencial e seu conteúdo pertence à {EMPRESA}. Qualquer uso não autorizado ou replicação deste documento, ou parte dele, é expressamente proibido.",
  objetivo:
    "Este relatório de Qualificação de Desempenho (QD) do {DESCRICAO_SISTEMA} tem como principal objetivo estabelecer evidências documentadas de que o equipamento apresenta desempenho de forma confiável e reprodutível.",
  referencias: [
    "ANVISA – Resolução da Diretoria Colegiada – RDC n° 658, de 22 de março de 2022. Regulamento Técnico das Boas Práticas de Fabricação de Medicamentos;",
    "Instrução Normativa Nº 35, de 21 de agosto de 2019 - Dispõe sobre as Boas Práticas de Fabricação Complementares a Medicamentos Estéreis;",
    "Instrução Normativa Nº 138, de 30 de março de 2022 - Dispõe sobre as diretrizes complementares à qualificação e validação;",
    "ABNT NBR ISO 14644 – Salas Limpas e Ambientes Controlados Associados.",
  ],
  definicoes: [
    ["Aerossol de ensaio", "Suspensão gasosa de partículas sólidas e/ou líquidas, com distribuição e concentração conhecidas e de tamanhos controlados."],
    ["AHU", "Unidade de Tratamento de Ar (Air Handling Unit)"],
    ["Área Limpa", "Área com controle ambiental definido em termos de contaminação por partículas viáveis e não viáveis, projetada, construída e utilizada de forma a reduzir a introdução, geração e retenção de contaminantes em seu interior."],
    ["°C", "Grau Celsius"],
    ["Classificação", "Grau (ou processo de especificar ou determinar o grau de limpeza do ar em suspensão, aplicável a uma sala limpa, a qual representa a concentração máxima admissível (em partículas por m³ de ar) para os tamanhos de partículas considerados."],
    ["Concentração de Partículas", "Quantidade de partículas individuais por unidade de volume de ar."],
    ["Contador de Partículas", "Instrumento que tenha a capacidade de mostrar e armazenar a contagem e o tamanho de partículas discretas (com discriminação de tamanho) para um volume específico de ar."],
    ["Desafio de aerossol", "Desafio de um filtro ou de um sistema de filtros instalados, por meio de um aerossol de ensaio."],
    ["∆P", "Diferencial de Pressão"],
    ["Em operação", "Condição na qual a área está em funcionamento para uma operação definida e com um número especificado de pessoas presentes."],
    ["Em repouso", "Condição na qual a instalação está completa, com equipamentos de produção instalados, mas sem a presença de pessoal."],
    ["Fluxo de ar não unidirecional", "Distribuição na qual o ar insuflado na zona limpa mistura-se com o ar interno, por indução."],
    ["Fluxo de ar unidirecional", "Fluxo de ar controlado através de toda a seção transversal de uma zona limpa, com uma velocidade constante e linhas de fluxo aproximadamente paralelas."],
    ["Fotômetro de aerossol", "Indicador de concentração de massa de partículas em suspensão no ar por espalhamento de luz, o qual usa um compartimento óptico de espalhamento frontal de luz para efetuar a medição."],
    ["Gerador de aerossol", "Equipamento capaz de gerar material particulado com faixa de tamanho apropriado (por exemplo, de 0,05 µm a 2 µm) em uma concentração constante, o qual possa ser produzido térmica, hidráulica, pneumática, acústica ou eletrostaticamente."],
    ["HEPA", "High Efficiency Particulate Air Filters"],
    ["HVAC", "Aquecimento, Ventilação e Ar Condicionado (em inglês: Heating, Ventilation and Air Conditioning)"],
    ["Hz", "Hertz"],
    ["Instalação", "Sala limpa ou uma ou mais zonas limpas, incluindo todas as estruturas associadas, sistemas de tratamento de ar, serviços e utilidades."],
    ["LxAxP", "Largura x Altura x Profundidade"],
    ["m³/h", "Metro cúbico por hora"],
    ["N.A", "Não Aplicável"],
    ["N.D", "Não Disponível"],
    ["Pa", "Pascal"],
    ["P.A.O / D.O.P", "Fluido utilizado para testes de integridade e estanqueidade de filtros através de gerador de aerossóis."],
    ["Partícula", "Porção de matéria sólida ou líquida que, para o propósito de classificação de limpeza do ar, enquadra-se em uma distribuição cumulativa baseada em um tamanho limiar (limite inferior) no intervalo de 0,1 µm a 5 µm."],
    ["Sala Limpa", "Sala na qual a concentração de partículas em suspensão no ar é controlada; é construída e utilizada de maneira a minimizar a introdução, geração e retenção de partículas dentro da sala, na qual outros parâmetros relevantes, como, por exemplo, temperatura, umidade e pressão, são controlados conforme necessário."],
    ["Sistema de Filtragem", "Sistema composto por filtro, moldura e outro sistema de apoio ou suporte."],
    ["TAE", "Tomada de Ar Externo"],
    ["TAG", "Termo usado para identificação"],
    ["Tamanho de partículas", "Diâmetro de uma esfera de referência que produza uma resposta equivalente ao da partícula medida por um instrumento que classifica tamanho de partículas."],
    ["Taxa de troca de ar", "Taxa de volume de ar trocado, expresso como o número de trocas de ar por unidade de tempo, a qual é calculada através da divisão do volume do ar fornecido na unidade de tempo pelo volume do ambiente."],
    ["UFC", "Unidade Formadora de Colônia."],
    ["Uniformidade do fluxo de ar", "Condição de fluxo de ar unidirecional, no qual as leituras de velocidade ponto a ponto estão dentro da média percentual definida para a velocidade média de fluxo de ar."],
    ["Varredura", "Método para descobrir vazamentos nas unidades filtrantes e partes de unidades, no qual a abertura de entrada da sonda de um fotômetro de aerossol ou de um contador de partículas discretas é movida em faixas sobrepostas através da área de ensaio definida."],
    ["Vazamento admissível", "Penetração máxima permitida através de um vazamento, detectável durante a varredura de uma instalação, utilizando um contador de partículas ou fotômetro de aerossol."],
  ],
  escopoAplicacao: "Este documento aplica-se ao {DESCRICAO_SISTEMA} {SISTEMA}, que atende a área {AREA}, da {EMPRESA}.",
  escopoEstrategia: [
    "A qualificação de Desempenho é um item auditável de qualidade prioritária ao {DESCRICAO_SISTEMA} pertinente. A qualificação de Desempenho será executada verificando todos os requerimentos aplicáveis descritos no documento aprovado pela {EMPRESA}.",
    "Os testes estão descritos neste relatório e são executados verificando e/ou testando o sistema instalado, para documentar que o sistema, componentes e utilidades estejam conforme as especificações pré-estabelecidas. Os testes executados no equipamento/sistema são documentados neste relatório e os resultados como: Cumpre ou Não cumpre.",
    "Os dados registrados na documentação dos testes incluídos neste relatório constituem a execução da qualificação de Desempenho.",
    "A conformidade de toda a informação prevista é verificada antes de executar o trabalho. Toda a documentação requerida (relatórios e folhas de testes) deverá ser conservada conjuntamente no arquivo da {EMPRESA}.",
  ],
  escopoMetodo: [
    "A QD testa e avalia especificamente cada função do equipamento, para assegurar que a atividade executada (segundo foi qualificado na qualificação de operação) estará apropriadamente ajustada e configurada segundo as faixas de desempenho operacional, especificações designadas e recomendadas para alcançar o objetivo de obter um processo controlado e adequado às necessidades.",
    "Durante a execução da qualificação de Desempenho, verifica-se o desempenho do equipamento, assegurando que o mesmo atenda aos critérios estabelecidos.",
  ],
  responsabilidades: [
    ["Elaborador", "Elaborar o relatório de qualificação; planejar e acompanhar as atividades de estudo com o setor responsável para agilizar a informação; conduzir as atividades sobre o equipamento definidas neste relatório; registrar todo o processo de forma a evidenciar a confiabilidade do equipamento; garantir que toda a documentação do equipamento esteja completa; documentar qualquer não conformidade durante a execução do relatório; reportar e avaliar os resultados; concluir o processo de qualificação com base neste relatório."],
    ["Executor (Técnico)", "Executar os testes em campo conforme os procedimentos deste relatório e registrar os resultados e evidências obtidos."],
    ["Revisor", "Revisar este relatório de qualificação, garantir as condições e recursos para execução das atividades de qualificação."],
    ["Aprovador", "Aprovar este relatório de qualificação após avaliar os resultados obtidos."],
  ],
  anexosObjetivo: "Este anexo tem como objetivo descrever os instrumentos utilizados na qualificação bem como sua calibração.",
  anexosMetodologia: "Verificar se os instrumentos utilizados na qualificação e instalados no sistema de tratamento de ar estão com calibração vigente.",
  anexosCriterio: "Todos os instrumentos devem estar com calibração vigente e possuírem seus devidos certificados.",
  testesIntroducao: "A seguir são apresentados os testes selecionados para esta qualificação, com sua proposta, pré-requisitos, descrição e critério de aceitação.",
  tabelaResumoIntroducao: "A tabela abaixo resume os testes realizados nesta qualificação e seu resultado.",
  documentacaoMotivo: [
    "Requalificação periódica;",
    "A requalificação ocorrerá anualmente ou mediante alguma mudança no equipamento/utilidades/componentes que possa afetar o desempenho do mesmo e/ou status de \"qualificado\" do equipamento, sendo esta mudança previamente avaliada por Controle de Mudança.",
    "Desta forma, qualquer necessidade de alteração no processo, equipamento, procedimento, entre outras a serem avaliadas, será aberto um controle de mudanças, sendo este submetido à avaliação e autorização. O mesmo deverá ser citado no relatório final.",
  ],
  documentacaoRegistros: "Durante a qualificação do equipamento, qualquer documento que seja gerado relativo ao equipamento em questão, que não seja algum dos documentos já citados anteriormente neste relatório, deverá ser citado junto ao relatório final.",
  paralelismoProposta: "Verificar, por meio de visualização (ex.: fumaça/névoa), que as linhas de fluxo de ar unidirecional se mantêm aproximadamente paralelas em toda a zona de trabalho, sem turbulências ou refluxos que comprometam a proteção do produto.",
  paralelismoCriterio: "Linhas de fluxo de ar aproximadamente paralelas, sem turbulência ou refluxo nas zonas críticas.",
  assinaturasIntroducao: "Este registro identifica os participantes na elaboração, execução, revisão e aprovação da qualificação de Desempenho.",
  conclusaoObjetivo: "O objetivo desta seção é apresentar a conclusão da qualificação de Desempenho.",
  conclusaoMetodologia: "Analisar o resultado dos testes realizados conforme critério de aceitação de cada teste proposto.",
  conclusaoCriterio: "Todos os critérios de aceitação/especificação de cada um dos testes realizados devem ter sido atendidos para que o resultado seja \"Cumpre\".",
  conclusaoPerguntaExecucao: "De acordo com os resultados apresentados neste relatório pode-se concluir que a qualificação de Desempenho do {SISTEMA} foi adequadamente executada conforme os critérios de aceitação para cada teste individualmente, atendendo as especificações e requerimentos definidos no referido relatório?",
  conclusaoPerguntaQualificado: "Pode-se considerar que o {SISTEMA} está \"Qualificado\" em seu Desempenho?",
  ensaios: {
    avaliacaoFiltragem: {
      nome: "Avaliação do Sistema de Filtragem",
      proposta: "Verificar o desempenho do sistema de filtragem instalado no equipamento de fluxo laminar e registrar as leituras correspondentes a cada filtro.",
      criterioAceitacao: "Conforme especificação do equipamento e do projeto.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Confirmar a identificação e a condição de instalação de cada filtro;",
        "Realizar as leituras com manômetro calibrado nos pontos definidos para o sistema de filtragem;",
        "Registrar cada leitura vinculada ao filtro correspondente;",
        "Comparar os resultados obtidos com o critério aprovado para o equipamento.",
      ],
    },
    velocidadeFluxo: {
      nome: "Velocidade e Uniformidade do Fluxo de Ar",
      proposta: "Verificar a velocidade e a uniformidade do fluxo de ar unidirecional na zona de trabalho do equipamento de fluxo laminar.",
      criterioAceitacao: "Conforme especificação do equipamento e do projeto.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Realizar as leituras nos pontos definidos para cada filtro utilizando anemômetro calibrado;",
        "Registrar a frequência de operação do equipamento, quando aplicável;",
        "Calcular a média e a dispersão das leituras e comparar com o critério aprovado;",
        "Registrar qualquer turbulência, desvio ou condição anormal observada durante o teste.",
      ],
    },
    vazaoInsuflacao: {
      nome: "Vazão de Ar de Insuflação e Número de Trocas / Renovações de Ar",
      proposta: "Verificar a vazão de ar de insuflação no interior de cada sala. Utilizando a vazão total da sala determina-se o número de trocas / renovações de ar de cada sala limpa.",
      criterioAceitacao: "Conforme especificação de cada sala.",
      preRequisitos: [...PRE_REQUISITOS_ACESSO, "Garantir que os equipamentos de processo permaneçam em operação durante a execução do teste."],
      descricao: [
        "Verificar a vazão de insuflação da sala utilizando um medidor de vazão do tipo balômetro calibrado com capa coletora/coifa de captura;",
        "Realizar a medição colocando o coletor abaixo do difusor de insuflação, aplicando a moldura do coletor contra uma área plana de modo a evitar leituras com variações devido às fugas de ar;",
        "É necessário que a abertura do coletor seja colocada de maneira a cobrir toda a área do difusor de insuflação;",
        "Registrar os valores de vazão encontrados e calcular a vazão total da sala (QT = ΣQd);",
        "Calcular o número de trocas de ar: NT = QT / VS, onde NT = número de trocas (t/h), QT = vazão total (m³/h) e VS = volume da sala (m³);",
        "Comparar os resultados obtidos com os critérios de aceitação e registrar na tabela de resultados.",
      ],
    },
    perdaCargaFiltros: {
      nome: "Perda de Carga dos Filtros HEPA",
      proposta: "Verificar se os filtros HEPA estão com sua perda de carga dentro da sua especificação e por inspeção visual o estado de conservação dos filtros, abrangendo manta e estrutura.",
      criterioAceitacao: "≤ 500 Pa",
      preRequisitos: [
        "Se for aplicável, seguir os procedimentos estabelecidos em relação ao acesso à sala (ou zona) limpa, inclusive aqueles relativos à paramentação;",
        "Os filtros devem estar instalados.",
      ],
      descricao: [
        "Realizar as medições dos filtros HEPA;",
        "Realizar a coleta de dados de número de série dos filtros HEPA, quando disponível;",
        "Realizar a inspeção visual dos filtros HEPA verificando a integridade da manta filtrante e estrutura de sustentação;",
        "Realizar a inspeção visual dos filtros HEPA verificando se os filtros estão corretamente instalados.",
      ],
    },
    integridadeFiltros: {
      nome: "Integridade e Estanqueidade dos Filtros HEPA",
      proposta: "Verificar se o sistema de filtragem está corretamente instalado e que não tenha desenvolvido vazamentos durante o uso, abrangendo meio filtrante, selante, moldura do filtro, vedação, quadros de fixação e estrutura de sustentação.",
      criterioAceitacao: "O vazamento máximo de aerossol de desafio (P.A.O/D.O.P) encontrado a jusante do filtro não deve ser maior que 0,01% da concentração gerada a montante do mesmo.",
      preRequisitos: ["Os testes de Vazão de Ar de Insuflação e Perda de Carga dos Filtros HEPA devem estar concluídos;", ...PRE_REQUISITOS_ACESSO],
      descricao: [
        "Para execução do teste utilizar um fotômetro de aerossol calibrado e um gerador de aerossol (P.A.O ou D.O.P);",
        "Introduzir o aerossol de desafio antes dos filtros HEPA de maneira a produzir uma concentração uniforme para cada filtro;",
        "Ajustar a concentração do aerossol de desafio de 1 a 100 mg/m³ de ar e medir a concentração a montante do filtro;",
        "Fazer a varredura do filtro cobrindo toda a área filtrante, o perímetro e a vedação, a aproximadamente 5 cm/s e a 2,5 cm da face a jusante;",
        "Ao localizar vazamentos, manter a sonda fixa para obter a leitura máxima e registrá-la. Se o vazamento for menor que 0,01%, registrar < 0,01%;",
        "Reparos: realizar com silicone neutro asséptico; área total de reparos ≤ 3% da área de face do filtro e menor dimensão de qualquer reparo ≤ 3,8 cm; após a cura, repetir a verificação no ponto reparado.",
      ],
    },
    nivelRuido: {
      nome: "Nível de Ruído",
      proposta: "Verificar se o nível de ruído produzido pelo equipamento de fluxo laminar está adequado à especificação aplicável.",
      criterioAceitacao: "Conforme especificação do equipamento e do projeto.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Realizar as leituras nos pontos definidos utilizando decibelímetro calibrado;",
        "Registrar a condição de operação do equipamento e as condições ambientais relevantes;",
        "Comparar as leituras com o critério aprovado e registrar a situação do teste.",
      ],
    },
    luminosidade: {
      nome: "Luminosidade",
      proposta: "Verificar se a iluminação da zona de trabalho do equipamento de fluxo laminar atende à especificação aplicável.",
      criterioAceitacao: "Conforme especificação do equipamento e do projeto.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Realizar as leituras nos pontos definidos utilizando luxímetro calibrado;",
        "Registrar a condição de operação e a posição de cada leitura;",
        "Comparar os resultados com o critério aprovado e registrar a situação do teste.",
      ],
    },
    paralelismoFluxo: {
      nome: "Paralelismo do Fluxo de Ar",
      proposta: "Verificar, por meio de visualização com fumaça ou névoa, que as linhas de fluxo se mantêm aproximadamente paralelas na zona de trabalho.",
      criterioAceitacao: "Linhas de fluxo aproximadamente paralelas, sem turbulência ou refluxo nas zonas críticas.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Introduzir fumaça ou névoa na zona de trabalho utilizando máquina de fumaça;",
        "Observar o sentido e o comportamento das linhas de fluxo em toda a zona crítica;",
        "Registrar o resultado e anexar evidência fotográfica quando disponível.",
      ],
    },
    pressao: {
      nome: "Diferencial de Pressão entre Salas",
      proposta: "Verificar a capacidade da instalação como um todo, em manter as diferenças de pressão e o sentido de fluxo especificado em projeto.",
      criterioAceitacao: "Conforme especificação de cada sala.",
      preRequisitos: ["Os testes de Vazão de Ar de Insuflação, Perda de Carga e Integridade e Estanqueidade dos Filtros HEPA devem estar concluídos;", ...PRE_REQUISITOS_ACESSO, "Todas as portas devem estar fechadas e as aberturas e passagens em condições normais de operação."],
      descricao: [
        "Verificar o diferencial de pressão entre salas utilizando um manômetro digital calibrado;",
        "Utilizar a mesma tomada de pressão estática usada pela área no monitoramento de rotina;",
        "Zerar o manômetro digital sempre antes da utilização;",
        "Medir a diferença de pressão entre a sala mais interna e as adjacentes, até o último ambiente em relação ao ambiente externo.",
      ],
    },
    visualizacaoFluxo: {
      nome: "Visualização do Fluxo de Ar",
      proposta: "Verificar o sentido correto do fluxo de ar entre as salas classificadas.",
      criterioAceitacao: "Sentido correto do fluxo de ar, sem refluxo incompatível com a proteção requerida.",
      preRequisitos: PRE_REQUISITOS_ACESSO,
      descricao: [
        "Visualizar o sentido do fluxo de ar com fumaça ou névoa;",
        "Registrar o sentido observado e qualquer refluxo ou turbulência identificada.",
      ],
    },
    contagemParticulas: {
      nome: "Contagem de Partículas Não Viáveis \"Em repouso\" e \"Em operação\"",
      proposta: "Verificar se a contagem de partículas não viáveis de cada sala (ou zona) limpa atende à classificação de limpeza especificada em projeto, nos estados de ocupação \"Em repouso\" e \"Em operação\".",
      criterioAceitacao: "Cada sala deve estar de acordo com a classificação estabelecida no projeto de tratamento de ar.",
      preRequisitos: ["Os testes de Vazão, Perda de Carga, Integridade e Estanqueidade dos Filtros HEPA e Diferencial de Pressão devem estar concluídos;", ...PRE_REQUISITOS_ACESSO, "Verificar se a área está adequadamente sinalizada e se a limpeza dos ambientes e equipamentos está adequada."],
      descricao: [
        "Utilizar um contador de partículas calibrado;",
        "O número mínimo de pontos de amostragem segue a ABNT NBR ISO 14644-1:2019 (arredondado para cima e ≥ 2);",
        "Os tamanhos de partículas especificados para este teste são de 0,5 µm e 5,0 µm;",
        "Posicionar a sonda próxima às posições de trabalho, a cerca de 1,20 m do piso quando aplicável, com a abertura voltada para o fluxo de ar;",
        "Anexar as fitas impressas pelo contador de partículas e transcrever os valores na tabela de resultados;",
        "O resultado deve ser padronizado em número de partículas por metro cúbico de ar.",
      ],
    },
    recuperacaoParticulas: {
      nome: "Recuperação",
      proposta: "Verificar o tempo de recuperação de cada sala.",
      criterioAceitacao: "O tempo de recuperação da classificação da área à condição de repouso deve ser ≤ 15 minutos.",
      preRequisitos: [],
      descricao: [],
    },
    quedaEnergia: {
      nome: "Queda de Energia",
      proposta: "Verificar o comportamento de cada sala durante a queda e o restabelecimento de energia.",
      criterioAceitacao: "Cada sala deve estar de acordo com a classificação estabelecida no projeto de tratamento de ar.",
      preRequisitos: [],
      descricao: [],
    },
    estanqueidade: {
      nome: "Estanqueidade",
      proposta: "Verificar a ausência de vazamento relevante ao desempenho da limpeza da instalação.",
      criterioAceitacao: "Vazamento ≤ 0,01% da concentração gerada a montante.",
      preRequisitos: [],
      descricao: [],
    },
  },
};

// Mantém a mesma ordem de EnsaioModel.catalogoPadrao(). Os oito primeiros
// ensaios aplicáveis ao Fluxo Laminar precisam existir também na emissão estruturada.
const CATALOGO = [
  { tipo: "avaliacaoFiltragem", ferramentasNecessarias: ["Manômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar"] },
  { tipo: "velocidadeFluxo", ferramentasNecessarias: ["Anemômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar"] },
  { tipo: "vazaoInsuflacao", ferramentasNecessarias: ["Balômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["HVAC"] },
  { tipo: "perdaCargaFiltros", ferramentasNecessarias: ["Manômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["HVAC"] },
  { tipo: "integridadeFiltros", ferramentasNecessarias: ["Fotômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: [] },
  { tipo: "nivelRuido", ferramentasNecessarias: ["Decibelímetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar"] },
  { tipo: "luminosidade", ferramentasNecessarias: ["Luxímetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar"] },
  { tipo: "paralelismoFluxo", ferramentasNecessarias: ["Máquina de Fumaça"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar"] },
  { tipo: "pressao", ferramentasNecessarias: ["Manômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["HVAC"] },
  { tipo: "visualizacaoFluxo", ferramentasNecessarias: ["Máquina de Fumaça"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["Fluxo Laminar", "HVAC"] },
  { tipo: "contagemParticulas", ferramentasNecessarias: ["Contador de Partículas"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: [] },
  { tipo: "recuperacaoParticulas", ferramentasNecessarias: ["Contador de Partículas"], aplicavelGraus: ["a", "b", "c"], aplicavelTiposProjeto: ["HVAC"] },
  { tipo: "quedaEnergia", ferramentasNecessarias: ["Contador de Partículas"], aplicavelGraus: ["a", "b", "c"], aplicavelTiposProjeto: ["HVAC"] },
  { tipo: "estanqueidade", ferramentasNecessarias: ["Balômetro"], aplicavelGraus: ["a", "b", "c", "d"], aplicavelTiposProjeto: ["HVAC"], selecionavel: false },
];

const FUNCAO_POR_PERFIL = {
  admin: "Administrador",
  supervisor: "Supervisor",
  tecnico: "Técnico",
  redator: "Elaborador",
};

function texto(valor) {
  return valor === null || valor === undefined ? "" : String(valor);
}

function ou(valor) {
  const resultado = texto(valor).trim();
  return resultado || "-";
}

function numero(valor, padrao = 0) {
  const resultado = typeof valor === "number" ? valor : Number.parseFloat(texto(valor).replace(",", "."));
  return Number.isFinite(resultado) ? resultado : padrao;
}

function numeroInteiro(valor, padrao = 0) {
  const resultado = typeof valor === "number" ? valor : Number.parseInt(texto(valor), 10);
  return Number.isFinite(resultado) ? resultado : padrao;
}

function numeroDart(valor) {
  const resultado = numero(valor);
  if (!Number.isFinite(resultado)) return texto(valor);
  return Number.isInteger(resultado) ? resultado.toFixed(1) : String(resultado);
}

function dataComoDate(valor) {
  if (!valor) return null;
  if (valor instanceof Date) return Number.isNaN(valor.getTime()) ? null : valor;
  if (typeof valor.toDate === "function") return dataComoDate(valor.toDate());
  if (typeof valor === "object" && Number.isFinite(valor._seconds)) return new Date(valor._seconds * 1000 + (valor._nanoseconds || 0) / 1e6);
  if (typeof valor === "number") return new Date(valor);
  const resultado = new Date(valor);
  return Number.isNaN(resultado.getTime()) ? null : resultado;
}

function formatarData(valor) {
  const data = dataComoDate(valor);
  if (!data) return "-";
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(data);
}

function preencherVariaveis(valor, variaveis) {
  return texto(valor).replace(/\{([A-Z_]+)\}/g, (completo, nome) => variaveis[nome] === undefined ? completo : variaveis[nome]);
}

function descricaoDoSistema(tipoProjeto) {
  switch (tipoProjeto) {
    case "HVAC": return "Sistema de Tratamento e Distribuição de Ar-Condicionado (HVAC)";
    case "Fluxo Laminar": return "Equipamento de Fluxo Laminar";
    case "Cabine de Segurança Biológica": return "Cabine de Segurança Biológica";
    case "Capela de Exaustão": return "Capela de Exaustão";
    case "Pesagem": return "Cabine de Pesagem";
    default: return tipoProjeto;
  }
}

function normalizarGrau(valor) {
  const grau = texto(valor).trim().toLowerCase();
  return ["a", "b", "c", "d"].includes(grau) ? grau : "d";
}

function normalizarTipoFiltro(valor) {
  const tipo = texto(valor).trim().toLowerCase();
  return { grosso: "g4", fino: "f9", absoluto: "h14" }[tipo] || tipo || "g4";
}

function listaIdsAdicionais(valor) {
  if (Array.isArray(valor)) return valor.map(texto);
  if (typeof valor === "string" && valor.trim()) {
    try {
      const lista = JSON.parse(valor);
      return Array.isArray(lista) ? lista.map(texto) : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

function idsMaquinasDaSala(sala) {
  return [texto(sala.handlingUnitId), ...listaIdsAdicionais(sala.handlingUnitIdsAdicionais)].filter(Boolean);
}

function filtrosDaSala(sala) {
  return Array.isArray(sala && sala.filtros) ? sala.filtros : [];
}

function unidadesDeFiltro(sala) {
  const unidades = [];
  for (const filtro of filtrosDaSala(sala)) {
    const quantidade = Math.max(0, numeroInteiro(filtro.quantidade));
    for (let i = 0; i < quantidade; i++) unidades.push(filtro);
  }
  return unidades;
}

function descricaoFiltro(filtro) {
  const tipo = normalizarTipoFiltro(filtro.tipo).toUpperCase();
  const quantidade = numeroInteiro(filtro.quantidade);
  const marcaModelo = [texto(filtro.marca), texto(filtro.modelo)].filter((item) => item.length > 0).join(" ");
  const detalhes = [marcaModelo, texto(filtro.dimensoes)].filter((item) => item.length > 0).join(", ");
  return `${quantidade}× ${tipo}${detalhes ? ` (${detalhes})` : ""}`;
}

function totalFiltros(sala) {
  return filtrosDaSala(sala).reduce((total, filtro) => total + Math.max(0, numeroInteiro(filtro.quantidade)), 0);
}

function ehEnsaioPorFiltro(tipo) {
  return ["avaliacaoFiltragem", "velocidadeFluxo", "estanqueidade", "pressao", "integridadeFiltros", "vazaoInsuflacao", "perdaCargaFiltros"].includes(tipo);
}

function pontosExigidos(sala, tipo) {
  const minimoUm = totalFiltros(sala) > 0 ? totalFiltros(sala) : 1;
  const configuracao = sala && sala.configEnsaios && sala.configEnsaios[tipo] || {};
  const pontosConfigurados = Number.parseInt(texto(configuracao.pontos), 10) || 0;
  if (tipo === "avaliacaoFiltragem") return minimoUm;
  if (tipo === "velocidadeFluxo") return minimoUm * (pontosConfigurados > 0 ? pontosConfigurados : 1);
  if (["nivelRuido", "luminosidade", "paralelismoFluxo"].includes(tipo)) return pontosConfigurados > 0 ? pontosConfigurados : 1;
  if (tipo === "contagemParticulas") return pontosConfigurados > 0 ? pontosConfigurados : minimoUm;
  if (tipo === "recuperacaoParticulas" || tipo === "quedaEnergia") return 3;
  if (tipo === "visualizacaoFluxo") return 1;
  return minimoUm;
}

function pontosExigidosParaExecucao(sala, tipo) {
  const pontos = pontosExigidos(sala, tipo);
  return tipo === "contagemParticulas" ? pontos * 2 : pontos;
}

function rotulosDosPontos(sala, tipo) {
  const total = pontosExigidos(sala, tipo);
  if (tipo === "recuperacaoParticulas" || tipo === "quedaEnergia") return ["Inicial", "Gerada", "Final"];
  if (tipo === "visualizacaoFluxo") return ["Sentido do fluxo"];
  const unidades = ehEnsaioPorFiltro(tipo) ? unidadesDeFiltro(sala) : [];
  return Array.from({ length: total }, (_, indice) => {
    const filtro = unidades[indice];
    if (tipo === "velocidadeFluxo" && filtro) {
      const pontosPorFiltro = Number.parseInt(texto(sala.configEnsaios && sala.configEnsaios[tipo] && sala.configEnsaios[tipo].pontos), 10) || 1;
      const numeroFiltro = Math.floor(indice / pontosPorFiltro) + 1;
      const indiceFiltro = (indice % pontosPorFiltro) + 1;
      return `F${numeroFiltro} (${normalizarTipoFiltro(filtro.tipo).toUpperCase()}) – Ponto ${indiceFiltro}`;
    }
    return filtro ? `Filtro ${indice + 1} (${normalizarTipoFiltro(filtro.tipo).toUpperCase()})` : `Ponto ${indice + 1}`;
  });
}

function situacao(feitos, exigidos) {
  if (exigidos === 0) return "N.A";
  if (feitos === 0) return "Pendente";
  return feitos >= exigidos ? "Realizado" : "Parcial";
}

function titulo(textoTitulo, nivel = 1) {
  return { tipo: "titulo", texto: textoTitulo, nivel };
}

function paragrafo(textoParagrafo, rotulo = null) {
  return { tipo: "paragrafo", texto: textoParagrafo, rotulo };
}

function lista(itens, numerada = false) {
  return { tipo: "lista", itens, numerada };
}

function tabela(cabecalho, linhas) {
  return { tipo: "tabela", cabecalho, linhas };
}

function imagem(url, legenda) {
  return { tipo: "imagem", url, legenda };
}

function historico(projeto) {
  return Array.isArray(projeto.history) ? projeto.history : [];
}

function valorNovoDaEntrada(entrada) {
  return texto(entrada && entrada.valorNovo);
}

function primeiraEntrada(projeto, predicado) {
  return historico(projeto).find(predicado) || null;
}

function ultimaEntrada(projeto, predicado) {
  const entradas = historico(projeto).filter(predicado);
  return entradas.length ? entradas[entradas.length - 1] : null;
}

function extrairAprovacao(projeto) {
  return ultimaEntrada(projeto, (entrada) => entrada.campo === "status" && valorNovoDaEntrada(entrada) === "aprovado");
}

function booleano(valor) {
  if (valor === true || valor === false) return valor;
  if (typeof valor === "string") {
    if (valor.toLowerCase() === "true") return true;
    if (valor.toLowerCase() === "false") return false;
  }
  return null;
}

function extrairConclusao(projeto) {
  const aprovacao = extrairAprovacao(projeto);
  const detalhes = aprovacao && aprovacao.detalhes && typeof aprovacao.detalhes === "object" ? aprovacao.detalhes : {};
  const conclusao = detalhes.conclusao && typeof detalhes.conclusao === "object" ? detalhes.conclusao : null;
  const cumpre = conclusao ? booleano(conclusao.cumpre) : null;
  if (cumpre === null) return null;
  return { cumpre, comentarios: texto(conclusao.comentarios) };
}

function usuarioPorEmail(usuariosPorEmail, email) {
  const chave = texto(email).trim().toLowerCase();
  return usuariosPorEmail && usuariosPorEmail[chave] ? usuariosPorEmail[chave] : {};
}

function assinatura(papel, email, data, usuariosPorEmail) {
  const endereco = texto(email).trim();
  const usuario = usuarioPorEmail(usuariosPorEmail, endereco);
  const nome = texto(usuario.nome).trim() || endereco;
  return {
    papel,
    nome,
    funcao: FUNCAO_POR_PERFIL[texto(usuario.perfil).toLowerCase()] || "",
    data,
  };
}

function montarAssinaturas(projeto, usuariosPorEmail, dataEmissao, emailRevisor) {
  const elaboracao = primeiraEntrada(projeto, (entrada) => entrada.campo === "status" && valorNovoDaEntrada(entrada) === "pronto_para_campo");
  const execucao = ultimaEntrada(projeto, (entrada) => valorNovoDaEntrada(entrada).startsWith("em_revisao"));
  const aprovacao = extrairAprovacao(projeto);
  const revisor = texto(aprovacao && aprovacao.usuario).trim() || texto(emailRevisor).trim();
  const dataRevisao = aprovacao && aprovacao.dataHora ? aprovacao.dataHora : dataEmissao;
  return [
    assinatura("Elaborado por", elaboracao && elaboracao.usuario || projeto.operadorResponsavel, elaboracao && elaboracao.dataHora || projeto.dataCriacao, usuariosPorEmail),
    assinatura("Executado por", execucao && execucao.usuario, execucao && execucao.dataHora, usuariosPorEmail),
    assinatura("Revisado por", revisor, dataRevisao, usuariosPorEmail),
    assinatura("Aprovado por", revisor, dataRevisao, usuariosPorEmail),
  ];
}

function agruparPontos(projeto) {
  const grupos = {};
  for (const ponto of Array.isArray(projeto.pontosLeitura) ? projeto.pontosLeitura : []) {
    const chave = `${texto(ponto.salaId)}|${texto(ponto.ensaioTipo)}`;
    if (!grupos[chave]) grupos[chave] = [];
    grupos[chave].push(ponto);
  }
  return grupos;
}

function valorDoPonto(pontos, numeroPonto) {
  return pontos.find((ponto) => numero(ponto.numeroPonto, Number.NaN) === numeroPonto) || null;
}

function nomeEnsaio(tipo) {
  return TEXTOS.ensaios[tipo] ? TEXTOS.ensaios[tipo].nome : tipo;
}

function construirDocumento({
  projeto,
  nomeEmpresa,
  sistemaNome,
  dataEmissao = new Date(),
  pontosPorChave,
  resumosPorEnsaio = {},
  usuariosPorEmail = {},
  conclusao = null,
  emailRevisor = "",
}) {
  const documentoProjeto = projeto || {};
  const salas = Array.isArray(documentoProjeto.salas) ? documentoProjeto.salas : [];
  const handlingUnits = Array.isArray(documentoProjeto.handlingUnits) ? documentoProjeto.handlingUnits : [];
  const ferramentas = documentoProjeto.ferramentasEscaneadas && typeof documentoProjeto.ferramentasEscaneadas === "object"
    ? documentoProjeto.ferramentasEscaneadas
    : {};
  const pontos = pontosPorChave || agruparPontos(documentoProjeto);
  const tiposSelecionados = Array.isArray(documentoProjeto.ensaiosSelecionados) ? documentoProjeto.ensaiosSelecionados : [];
  const ensaiosSelecionados = CATALOGO.filter((ensaio) => tiposSelecionados.includes(ensaio.tipo));
  const variaveis = {
    EMPRESA: ou(nomeEmpresa),
    CNPJ: ou(documentoProjeto.cnpjEmpresa),
    SISTEMA: ou(sistemaNome),
    AREA: ou(documentoProjeto.area),
    TIPO_PROJETO: ou(documentoProjeto.tipoProjeto),
    DESCRICAO_SISTEMA: descricaoDoSistema(texto(documentoProjeto.tipoProjeto)),
    DATA: formatarData(dataEmissao),
  };
  const t = (valor) => preencherVariaveis(valor, variaveis);
  const blocos = [];
  let secao = 0;
  const secaoTitulo = (valor) => blocos.push(titulo(`${++secao}. ${valor}`));
  const salasDoEnsaio = (ensaio) => salas.filter((sala) => ensaio.aplicavelGraus.includes(normalizarGrau(sala.grau)));
  const progressoDoEnsaio = (ensaio) => {
    let feitos = 0;
    let exigidos = 0;
    for (const sala of salasDoEnsaio(ensaio)) {
      exigidos += pontosExigidosParaExecucao(sala, ensaio.tipo);
      const grupo = pontos[`${texto(sala.id)}|${ensaio.tipo}`] || [];
      feitos += grupo.filter((ponto) => texto(ponto.valor05um).trim().length > 0).length;
    }
    return { feitos, exigidos };
  };
  const tabelaSalas = (salasTabela) => tabela(
    ["Sala", "Grau", "Área (m²)", "Volume (m³)", "Filtros"],
    salasTabela.map((sala) => [
      texto(sala.nome),
      normalizarGrau(sala.grau).toUpperCase(),
      numeroDart(sala.area),
      numeroDart(sala.volume),
      filtrosDaSala(sala).length ? filtrosDaSala(sala).map(descricaoFiltro).join("; ") : "-",
    ])
  );
  const tabelaResultados = (ensaio) => {
    const ehContagem = ensaio.tipo === "contagemParticulas";
    const criterio = TEXTOS.ensaios[ensaio.tipo] ? TEXTOS.ensaios[ensaio.tipo].criterioAceitacao : "-";
    const linhas = [];
    for (const sala of salasDoEnsaio(ensaio)) {
      const rotulos = rotulosDosPontos(sala, ensaio.tipo);
      const grupo = pontos[`${texto(sala.id)}|${ensaio.tipo}`] || [];
      const estados = ehContagem ? ["repouso", "operacao"] : [""];
      for (const estado of estados) {
        for (let i = 0; i < rotulos.length; i++) {
          const ponto = grupo.find((item) =>
            numero(item.numeroPonto, Number.NaN) === i + 1
            && (!ehContagem || texto(item.estado).toLowerCase() === estado)
          ) || null;
          const valor = texto(ponto && ponto.valor05um).trim();
          const valor5 = texto(ponto && ponto.valor5um).trim();
          linhas.push([
            texto(sala.nome),
            ...(ehContagem ? [estado === "repouso" ? "Repouso" : "Operação"] : []),
            rotulos[i],
            valor || "—",
            ...(ehContagem ? [valor5 || "—"] : []),
            criterio,
          ]);
        }
      }
    }
    return tabela(
      ehContagem ? ["Sala", "Estado", "Ponto", "0,5 µm", "5,0 µm", "Critério de aceitação"] : ["Sala", "Ponto", "Valor encontrado", "Critério de aceitação"],
      linhas
    );
  };

  // Identificação, textos do modelo e anexos.
  blocos.push(tabela(["Informações gerais", ""], [
    ["Empresa", variaveis.EMPRESA],
    ["CNPJ", variaveis.CNPJ],
    ["Tipo de projeto", variaveis.TIPO_PROJETO],
    ["Nome / TAG do sistema", variaveis.SISTEMA],
    ["Área", variaveis.AREA],
    ["Nº do relatório", texto(documentoProjeto.id)],
    ["Data de emissão", variaveis.DATA],
  ]));
  blocos.push(paragrafo(t(TEXTOS.notaConfidencialidade)));

  secaoTitulo(TEXTOS.secoes.objetivo);
  blocos.push(paragrafo(t(TEXTOS.objetivo)));
  secaoTitulo(TEXTOS.secoes.referencia);
  blocos.push(lista(TEXTOS.referencias.map(t), true));
  secaoTitulo(TEXTOS.secoes.definicoes);
  blocos.push(tabela(["Termo", "Descrição"], TEXTOS.definicoes));
  secaoTitulo(TEXTOS.secoes.escopo);
  blocos.push(paragrafo(t(TEXTOS.escopoAplicacao)));
  blocos.push(titulo("Estratégia de qualificação", 2));
  blocos.push(lista(TEXTOS.escopoEstrategia.map(t)));
  blocos.push(titulo("Método da qualificação de Desempenho", 2));
  blocos.push(lista(TEXTOS.escopoMetodo.map(t)));
  secaoTitulo(TEXTOS.secoes.responsabilidades);
  for (const [papel, descricao] of TEXTOS.responsabilidades) blocos.push(paragrafo(descricao, `${papel}:`));

  secaoTitulo(TEXTOS.secoes.anexos);
  blocos.push(paragrafo(TEXTOS.anexosObjetivo, "Objetivo:"));
  blocos.push(paragrafo(TEXTOS.anexosMetodologia, "Metodologia:"));
  blocos.push(paragrafo(TEXTOS.anexosCriterio, "Critério de aceitação:"));
  blocos.push(titulo("Instrumentos utilizados e certificados de calibração", 2));
  const instrumentos = Object.entries(ferramentas).flatMap(([tipoFerramenta, listaInstrumentos]) =>
    (Array.isArray(listaInstrumentos) ? listaInstrumentos : []).map((instrumento) => [
      tipoFerramenta,
      ou(instrumento.tag),
      ou(instrumento.numeroSerie),
      ou(instrumento.numeroCertificado),
      ou(instrumento.validade),
    ])
  );
  blocos.push(instrumentos.length
    ? tabela(["Instrumento", "TAG", "Nº de série", "Nº do certificado", "Validade da calibração"], instrumentos)
    : paragrafo("Nenhum instrumento registrado em campo."));
  blocos.push(titulo("Evidências fotográficas", 2));
  const urlsVistas = new Set();
  const evidencias = [];
  for (const ensaio of ensaiosSelecionados) {
    for (const sala of salas) {
      for (const ponto of pontos[`${texto(sala.id)}|${ensaio.tipo}`] || []) {
        const url = texto(ponto.fotoEvidenciaUrl);
        if (!url || urlsVistas.has(url)) continue;
        urlsVistas.add(url);
        evidencias.push(imagem(url, `${nomeEnsaio(ensaio.tipo)} – ${texto(sala.nome)}`));
      }
    }
  }
  blocos.push(...(evidencias.length ? evidencias : [paragrafo("Nenhuma evidência fotográfica anexada.")]));

  secaoTitulo(TEXTOS.secoes.testes);
  if (!ensaiosSelecionados.length) {
    blocos.push(paragrafo("Nenhum teste selecionado."));
  } else {
    blocos.push(paragrafo(TEXTOS.testesIntroducao));
    ensaiosSelecionados.forEach((ensaio, indice) => {
      const textoEnsaio = TEXTOS.ensaios[ensaio.tipo];
      blocos.push(titulo(`${secao}.${indice + 1}. ${nomeEnsaio(ensaio.tipo)}`, 2));
      if (textoEnsaio) {
        blocos.push(paragrafo(textoEnsaio.proposta, "Proposta:"));
        blocos.push(paragrafo(textoEnsaio.criterioAceitacao, "Critério de aceitação:"));
        if (textoEnsaio.preRequisitos.length) {
          blocos.push(paragrafo("", "Pré-requisitos:"));
          blocos.push(lista(textoEnsaio.preRequisitos));
        }
        if (textoEnsaio.descricao.length) {
          blocos.push(paragrafo("", "Descrição do teste:"));
          blocos.push(lista(textoEnsaio.descricao, true));
        }
      }
      const resumo = texto(resumosPorEnsaio[ensaio.tipo]).trim();
      if (resumo) blocos.push(paragrafo(resumo, "Observações:"));
    });
  }

  secaoTitulo(TEXTOS.secoes.tabelaTestesResumo);
  if (!ensaiosSelecionados.length) {
    blocos.push(paragrafo("Nenhum teste selecionado."));
  } else {
    blocos.push(paragrafo(TEXTOS.tabelaResumoIntroducao));
    blocos.push(tabela(["Teste", "Nome do teste", "Critério de aceitação", "Pontos", "Situação"], ensaiosSelecionados.map((ensaio, indice) => {
      const progresso = progressoDoEnsaio(ensaio);
      return [
        String(indice + 1),
        nomeEnsaio(ensaio.tipo),
        TEXTOS.ensaios[ensaio.tipo] ? TEXTOS.ensaios[ensaio.tipo].criterioAceitacao : "-",
        `${progresso.feitos}/${progresso.exigidos}`,
        situacao(progresso.feitos, progresso.exigidos),
      ];
    })));
  }

  secaoTitulo(TEXTOS.secoes.documentacaoApoio);
  blocos.push(titulo("Motivo da qualificação", 2));
  blocos.push(lista(TEXTOS.documentacaoMotivo));
  blocos.push(titulo("Registros", 2));
  blocos.push(paragrafo(TEXTOS.documentacaoRegistros));

  const registro = documentoProjeto.paralelismo && typeof documentoProjeto.paralelismo === "object" ? documentoProjeto.paralelismo : null;
  if (registro) {
    secaoTitulo(TEXTOS.secoes.paralelismoFluxoAr);
    blocos.push(paragrafo(TEXTOS.paralelismoProposta, "Proposta:"));
    blocos.push(paragrafo(TEXTOS.paralelismoCriterio, "Critério de aceitação:"));
    blocos.push(paragrafo(texto(registro.resultado).trim() ? texto(registro.resultado).trim() : "Não registrado.", "Resultado:"));
    if (texto(registro.fotoUrl)) blocos.push(imagem(texto(registro.fotoUrl), "Paralelismo do fluxo de ar"));
  }

  secaoTitulo("Máquinas, Salas e Resultados dos Testes");
  blocos.push(titulo("Máquinas e salas atendidas", 2));
  if (!handlingUnits.length) blocos.push(paragrafo("Nenhuma máquina cadastrada."));
  for (const maquina of handlingUnits) {
    blocos.push(paragrafo(
      Array.isArray(maquina.filtros) && maquina.filtros.length ? maquina.filtros.map(descricaoFiltro).join("; ") : "Sem filtros internos.",
      `${texto(maquina.nome)} –`
    ));
    blocos.push(tabelaSalas(salas.filter((sala) => idsMaquinasDaSala(sala).includes(texto(maquina.id)))));
  }
  const idsMaquinas = new Set(handlingUnits.map((maquina) => texto(maquina.id)));
  const orfas = salas.filter((sala) => !idsMaquinasDaSala(sala).some((id) => idsMaquinas.has(id)));
  if (orfas.length) {
    blocos.push(paragrafo("", "Salas sem máquina vinculada:"));
    blocos.push(tabelaSalas(orfas));
  }
  ensaiosSelecionados.forEach((ensaio, indice) => {
    blocos.push(titulo(`TESTE ${indice + 1} – ${nomeEnsaio(ensaio.tipo).toUpperCase()}`, 2));
    const instrumentosDoEnsaio = ensaio.ferramentasNecessarias.flatMap((tipoFerramenta) =>
      (Array.isArray(ferramentas[tipoFerramenta]) ? ferramentas[tipoFerramenta] : []).map((instrumento) => [
        tipoFerramenta,
        ou(instrumento.tag),
        ou(instrumento.numeroCertificado),
        ou(instrumento.validade),
      ])
    );
    if (instrumentosDoEnsaio.length) blocos.push(tabela(["Instrumento", "TAG", "Certificado", "Validade"], instrumentosDoEnsaio));
    blocos.push(tabelaResultados(ensaio));
    const progresso = progressoDoEnsaio(ensaio);
    blocos.push(paragrafo(situacao(progresso.feitos, progresso.exigidos), "Situação do teste:"));
  });

  secaoTitulo(TEXTOS.secoes.registroAssinaturas);
  blocos.push(paragrafo(TEXTOS.assinaturasIntroducao));
  blocos.push(tabela(["Papel", "Nome", "Função", "Empresa", "Data", "Assinatura"], montarAssinaturas(documentoProjeto, usuariosPorEmail, dataEmissao, emailRevisor).map((assinaturaAtual) => [
    assinaturaAtual.papel,
    ou(assinaturaAtual.nome),
    ou(assinaturaAtual.funcao),
    TEXTOS.empresaExecutora,
    formatarData(assinaturaAtual.data),
    "",
  ])));

  secaoTitulo(TEXTOS.secoes.conclusaoQualificacao);
  const marcar = (sim) => sim === null || sim === undefined ? "( ) Sim  ( ) Não" : sim ? "(X) Sim  ( ) Não" : "( ) Sim  (X) Não";
  blocos.push(paragrafo(TEXTOS.conclusaoObjetivo, "Objetivo:"));
  blocos.push(paragrafo(TEXTOS.conclusaoMetodologia, "Metodologia:"));
  blocos.push(paragrafo(TEXTOS.conclusaoCriterio, "Critério de aceitação:"));
  blocos.push(tabela(["Discussão dos resultados", "Resposta"], [
    [t(TEXTOS.conclusaoPerguntaExecucao), marcar(conclusao && conclusao.cumpre)],
    [t(TEXTOS.conclusaoPerguntaQualificado), marcar(conclusao && conclusao.cumpre)],
  ]));
  blocos.push(paragrafo(!conclusao || !texto(conclusao.comentarios).trim() ? "-" : texto(conclusao.comentarios).trim(), "Comentários:"));
  blocos.push(paragrafo(!conclusao ? "A definir na emissão." : conclusao.cumpre ? "CUMPRE" : "NÃO CUMPRE", "Conclusão geral da qualificação de Desempenho:"));

  const tituloDocumento = t(TEXTOS.titulo);
  return { titulo: tituloDocumento, cabecalho: tituloDocumento, blocos };
}

module.exports = {
  CATALOGO,
  TEXTOS,
  agruparPontos,
  construirDocumento,
  extrairAprovacao,
  extrairConclusao,
  formatarData,
  montarAssinaturas,
  pontosExigidos,
  pontosExigidosParaExecucao,
  rotulosDosPontos,
  situacao,
};