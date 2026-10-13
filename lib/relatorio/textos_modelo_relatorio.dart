// lib/relatorio/textos_modelo_relatorio.dart
// Textos-modelo do relatório de qualificação (extraídos do antigo modelo_relatorio_hvac.docx).
// Variáveis entre chaves são substituídas por [preencherVariaveis] na montagem do documento.
import '../ensaio_model.dart';

enum SecaoModelo {
  objetivo('Objetivo'),
  referencia('Referência'),
  definicoes('Definições'),
  escopo('Escopo'),
  responsabilidades('Responsabilidades'),
  anexos('Anexos'),
  testes('Testes'),
  tabelaTestesResumo('Tabela de Testes (Resumo)'),
  documentacaoApoio('Documentação de Apoio'),
  paralelismoFluxoAr('Paralelismo do Fluxo de Ar'),
  registroAssinaturas('Registro de Assinaturas'),
  conclusaoQualificacao('Conclusão da Qualificação de Desempenho');

  final String titulo;
  const SecaoModelo(this.titulo);
}

class TextoEnsaioModelo {
  final String nome;
  final String proposta;
  final String criterioAceitacao;
  final List<String> preRequisitos;
  final List<String> descricao;

  const TextoEnsaioModelo({
    required this.nome,
    required this.proposta,
    required this.criterioAceitacao,
    this.preRequisitos = const [],
    this.descricao = const [],
  });
}

String preencherVariaveis(String texto, Map<String, String> variaveis) =>
    texto.replaceAllMapped(RegExp(r'\{([A-Z_]+)\}'), (m) => variaveis[m.group(1)] ?? m.group(0)!);

class TextosModeloRelatorio {
  static const String empresaExecutora = 'Celacanto Análises e Qualificações Ltda.';

  static String descricaoDoSistema(String tipoProjeto) {
    switch (tipoProjeto) {
      case EnsaioModel.tipoHvac:
        return 'Sistema de Tratamento e Distribuição de Ar-Condicionado (HVAC)';
      case EnsaioModel.tipoFluxoLaminar:
        return 'Equipamento de Fluxo Laminar';
      case EnsaioModel.tipoCabineSegurancaBiologica:
        return 'Cabine de Segurança Biológica';
      case EnsaioModel.tipoCapelaExaustao:
        return 'Capela de Exaustão';
      case EnsaioModel.tipoPesagem:
        return 'Cabine de Pesagem';
      default:
        return tipoProjeto;
    }
  }

  static const String titulo = 'RELATÓRIO DE QUALIFICAÇÃO DE DESEMPENHO – {DESCRICAO_SISTEMA} – {SISTEMA}';

  static const String notaConfidencialidade =
      'Nota: Este documento, incluindo seus registros/anexos, tem caráter confidencial e seu conteúdo pertence à '
      '{EMPRESA}. Qualquer uso não autorizado ou replicação deste documento, ou parte dele, é expressamente proibido.';

  static const String objetivo =
      'Este relatório de Qualificação de Desempenho (QD) do {DESCRICAO_SISTEMA} tem como principal objetivo '
      'estabelecer evidências documentadas de que o equipamento apresenta desempenho de forma confiável e reprodutível.';

  static const List<String> referencias = [
    'ANVISA – Resolução da Diretoria Colegiada – RDC n° 658, de 22 de março de 2022. Regulamento Técnico das Boas '
        'Práticas de Fabricação de Medicamentos;',
    'Instrução Normativa Nº 35, de 21 de agosto de 2019 - Dispõe sobre as Boas Práticas de Fabricação '
        'Complementares a Medicamentos Estéreis;',
    'Instrução Normativa Nº 138, de 30 de março de 2022 - Dispõe sobre as diretrizes complementares à '
        'qualificação e validação;',
    'ABNT NBR ISO 14644 – Salas Limpas e Ambientes Controlados Associados.',
  ];

  static const List<(String, String)> definicoes = [
    ('Aerossol de ensaio',
        'Suspensão gasosa de partículas sólidas e/ou líquidas, com distribuição e concentração conhecidas e de tamanhos controlados.'),
    ('AHU', 'Unidade de Tratamento de Ar (Air Handling Unit)'),
    ('Área Limpa',
        'Área com controle ambiental definido em termos de contaminação por partículas viáveis e não viáveis, projetada, '
            'construída e utilizada de forma a reduzir a introdução, geração e retenção de contaminantes em seu interior.'),
    ('°C', 'Grau Celsius'),
    ('Classificação',
        'Grau (ou processo de especificar ou determinar o grau) de limpeza do ar em suspensão, aplicável a uma sala limpa, a '
            'qual representa a concentração máxima admissível (em partículas por m³ de ar) para os tamanhos de partículas considerados.'),
    ('Concentração de Partículas', 'Quantidade de partículas individuais por unidade de volume de ar.'),
    ('Contador de Partículas',
        'Instrumento que tenha a capacidade de mostrar e armazenar a contagem e o tamanho de partículas discretas (com '
            'discriminação de tamanho) para um volume específico de ar.'),
    ('Desafio de aerossol', 'Desafio de um filtro ou de um sistema de filtros instalados, por meio de um aerossol de ensaio.'),
    ('∆P', 'Diferencial de Pressão'),
    ('Em operação',
        'Condição na qual a área está em funcionamento para uma operação definida e com um número especificado de pessoas presentes.'),
    ('Em repouso',
        'Condição na qual a instalação está completa, com equipamentos de produção instalados, mas sem a presença de pessoal.'),
    ('Fluxo de ar não unidirecional', 'Distribuição na qual o ar insuflado na zona limpa mistura-se com o ar interno, por indução.'),
    ('Fluxo de ar unidirecional',
        'Fluxo de ar controlado através de toda a seção transversal de uma zona limpa, com uma velocidade constante e linhas '
            'de fluxo aproximadamente paralelas.'),
    ('Fotômetro de aerossol',
        'Indicador de concentração de massa de partículas em suspensão no ar por espalhamento de luz, o qual usa um '
            'compartimento óptico de espalhamento frontal de luz para efetuar a medição.'),
    ('Gerador de aerossol',
        'Equipamento capaz de gerar material particulado com faixa de tamanho apropriado (por exemplo, de 0,05 µm a 2 µm) em '
            'uma concentração constante, o qual possa ser produzido térmica, hidráulica, pneumática, acústica ou eletrostaticamente.'),
    ('HEPA', 'High Efficiency Particulate Air Filters'),
    ('HVAC', 'Aquecimento, Ventilação e Ar Condicionado (em inglês: Heating, Ventilation and Air Conditioning)'),
    ('Hz', 'Hertz'),
    ('Instalação',
        'Sala limpa ou uma ou mais zonas limpas, incluindo todas as estruturas associadas, sistemas de tratamento de ar, '
            'serviços e utilidades.'),
    ('LxAxP', 'Largura x Altura x Profundidade'),
    ('m³/h', 'Metro cúbico por hora'),
    ('N.A', 'Não Aplicável'),
    ('N.D', 'Não Disponível'),
    ('Pa', 'Pascal'),
    ('P.A.O / D.O.P', 'Fluido utilizado para testes de integridade e estanqueidade de filtros através de gerador de aerossóis.'),
    ('Partícula',
        'Porção de matéria sólida ou líquida que, para o propósito de classificação de limpeza do ar, enquadra-se em uma '
            'distribuição cumulativa baseada em um tamanho limiar (limite inferior) no intervalo de 0,1 µm a 5 µm.'),
    ('Sala Limpa',
        'Sala na qual a concentração de partículas em suspensão no ar é controlada; é construída e utilizada de maneira a '
            'minimizar a introdução, geração e retenção de partículas dentro da sala, na qual outros parâmetros relevantes, como, '
            'por exemplo, temperatura, umidade e pressão, são controlados conforme necessário.'),
    ('Sistema de Filtragem', 'Sistema composto por filtro, moldura e outro sistema de apoio ou suporte.'),
    ('TAE', 'Tomada de Ar Externo'),
    ('TAG', 'Termo usado para identificação'),
    ('Tamanho de partículas',
        'Diâmetro de uma esfera de referência que produza uma resposta equivalente ao da partícula medida por um instrumento '
            'que classifica tamanho de partículas.'),
    ('Taxa de troca de ar',
        'Taxa de volume de ar trocado, expresso como o número de trocas de ar por unidade de tempo, a qual é calculada através '
            'da divisão do volume do ar fornecido na unidade de tempo pelo volume do ambiente.'),
    ('UFC', 'Unidade Formadora de Colônia.'),
    ('Uniformidade do fluxo de ar',
        'Condição de fluxo de ar unidirecional, no qual as leituras de velocidade ponto a ponto estão dentro da média '
            'percentual definida para a velocidade média de fluxo de ar.'),
    ('Varredura',
        'Método para descobrir vazamentos nas unidades filtrantes e partes de unidades, no qual a abertura de entrada da sonda '
            'de um fotômetro de aerossol ou de um contador de partículas discretas é movida em faixas sobrepostas através da área '
            'de ensaio definida.'),
    ('Vazamento admissível',
        'Penetração máxima permitida através de um vazamento, detectável durante a varredura de uma instalação, utilizando um '
            'contador de partículas ou fotômetro de aerossol.'),
  ];

  static const String escopoAplicacao =
      'Este documento aplica-se ao {DESCRICAO_SISTEMA} {SISTEMA}, que atende a área {AREA}, da {EMPRESA}.';

  static const List<String> escopoEstrategia = [
    'A qualificação de Desempenho é um item auditável de qualidade prioritária ao {DESCRICAO_SISTEMA} pertinente. A '
        'qualificação de Desempenho será executada verificando todos os requerimentos aplicáveis descritos no documento '
        'aprovado pela {EMPRESA}.',
    'Os testes estão descritos neste relatório e são executados verificando e/ou testando o sistema instalado, para '
        'documentar que o sistema, componentes e utilidades estejam conforme as especificações pré-estabelecidas. Os testes '
        'executados no equipamento/sistema são documentados neste relatório e os resultados como: Cumpre ou Não cumpre.',
    'Os dados registrados na documentação dos testes incluídos neste relatório constituem a execução da qualificação de '
        'Desempenho.',
    'A conformidade de toda a informação prevista é verificada antes de executar o trabalho. Toda a documentação requerida '
        '(relatórios e folhas de testes) deverá ser conservada conjuntamente no arquivo da {EMPRESA}.',
  ];

  static const List<String> escopoMetodo = [
    'A QD testa e avalia especificamente cada função do equipamento, para assegurar que a atividade executada (segundo foi '
        'qualificado na qualificação de operação) estará apropriadamente ajustada e configurada segundo as faixas de desempenho '
        'operacional, especificações designadas e recomendadas para alcançar o objetivo de obter um processo controlado e '
        'adequado às necessidades.',
    'Durante a execução da qualificação de Desempenho, verifica-se o desempenho do equipamento, assegurando que o mesmo '
        'atenda aos critérios estabelecidos.',
  ];

  static const List<(String, String)> responsabilidades = [
    ('Elaborador',
        'Elaborar o relatório de qualificação; planejar e acompanhar as atividades de estudo com o setor responsável para '
            'agilizar a informação; conduzir as atividades sobre o equipamento definidas neste relatório; registrar todo o '
            'processo de forma a evidenciar a confiabilidade do equipamento; garantir que toda a documentação do equipamento '
            'esteja completa; documentar qualquer não conformidade durante a execução do relatório; reportar e avaliar os '
            'resultados; concluir o processo de qualificação com base neste relatório.'),
    ('Executor (Técnico)',
        'Executar os testes em campo conforme os procedimentos deste relatório e registrar os resultados e evidências obtidos.'),
    ('Revisor', 'Revisar este relatório de qualificação, garantir as condições e recursos para execução das atividades de qualificação.'),
    ('Aprovador', 'Aprovar este relatório de qualificação após avaliar os resultados obtidos.'),
  ];

  static const String anexosObjetivo =
      'Este anexo tem como objetivo descrever os instrumentos utilizados na qualificação bem como sua calibração.';
  static const String anexosMetodologia =
      'Verificar se os instrumentos utilizados na qualificação e instalados no sistema de tratamento de ar estão com '
      'calibração vigente.';
  static const String anexosCriterio =
      'Todos os instrumentos devem estar com calibração vigente e possuírem seus devidos certificados.';

  static const String testesIntroducao =
      'A seguir são apresentados os testes selecionados para esta qualificação, com sua proposta, pré-requisitos, '
      'descrição e critério de aceitação.';

  static const String tabelaResumoIntroducao =
      'A tabela abaixo resume os testes realizados nesta qualificação e seu resultado.';

  static const List<String> documentacaoMotivo = [
    'Requalificação periódica;',
    'A requalificação ocorrerá anualmente ou mediante alguma mudança no equipamento/utilidades/componentes que possa afetar '
        'o desempenho do mesmo e/ou status de "qualificado" do equipamento, sendo esta mudança previamente avaliada por '
        'Controle de Mudança.',
    'Desta forma, qualquer necessidade de alteração no processo, equipamento, procedimento, entre outras a serem avaliadas, '
        'será aberto um controle de mudanças, sendo este submetido à avaliação e autorização. O mesmo deverá ser citado no '
        'relatório final.',
  ];
  static const String documentacaoRegistros =
      'Durante a qualificação do equipamento, qualquer documento que seja gerado relativo ao equipamento em questão, que não '
      'seja algum dos documentos já citados anteriormente neste relatório, deverá ser citado junto ao relatório final.';

  // Não havia texto no modelo HVAC: redação inicial, a validar com o cliente.
  static const String paralelismoProposta =
      'Verificar, por meio de visualização (ex.: fumaça/névoa), que as linhas de fluxo de ar unidirecional se mantêm '
      'aproximadamente paralelas em toda a zona de trabalho, sem turbulências ou refluxos que comprometam a proteção do produto.';
  static const String paralelismoCriterio =
      'Linhas de fluxo de ar aproximadamente paralelas, sem turbulência ou refluxo nas zonas críticas.';

  static const String assinaturasIntroducao =
      'Este registro identifica os participantes na elaboração, execução, revisão e aprovação da qualificação de Desempenho.';

  static const String conclusaoObjetivo = 'O objetivo desta seção é apresentar a conclusão da qualificação de Desempenho.';
  static const String conclusaoMetodologia =
      'Analisar o resultado dos testes realizados conforme critério de aceitação de cada teste proposto.';
  static const String conclusaoCriterio =
      'Todos os critérios de aceitação/especificação de cada um dos testes realizados devem ter sido atendidos para que o '
      'resultado seja "Cumpre".';
  static const String conclusaoPerguntaExecucao =
      'De acordo com os resultados apresentados neste relatório pode-se concluir que a qualificação de Desempenho do '
      '{SISTEMA} foi adequadamente executada conforme os critérios de aceitação para cada teste individualmente, atendendo '
      'as especificações e requerimentos definidos no referido relatório?';
  static const String conclusaoPerguntaQualificado =
      'Pode-se considerar que o {SISTEMA} está "Qualificado" em seu Desempenho?';

  static const List<String> _preRequisitosAcesso = [
    'Se for aplicável, seguir os procedimentos estabelecidos em relação ao acesso à sala (ou zona) limpa, inclusive aqueles '
        'relativos à paramentação;',
    'Os equipamentos e instrumentos a serem utilizados no teste devem ser limpos antes de ingressar em qualquer ambiente de '
        'sala (ou zona) limpa;',
    'O sistema e todos os equipamentos que compõem o sistema devem estar em operação para que sejam feitas as devidas medições;',
  ];

  static const Map<TipoEnsaio, TextoEnsaioModelo> ensaios = {
    TipoEnsaio.avaliacaoFiltragem: TextoEnsaioModelo(
      nome: 'Avaliação do Sistema de Filtragem',
      proposta: 'Verificar o desempenho do sistema de filtragem instalado no equipamento de fluxo laminar e registrar as leituras correspondentes a cada filtro.',
      criterioAceitacao: 'Conforme especificação do equipamento e do projeto.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Confirmar a identificação e a condição de instalação de cada filtro;',
        'Realizar as leituras com manômetro calibrado nos pontos definidos para o sistema de filtragem;',
        'Registrar cada leitura vinculada ao filtro correspondente;',
        'Comparar os resultados obtidos com o critério aprovado para o equipamento.',
      ],
    ),
    TipoEnsaio.velocidadeFluxo: TextoEnsaioModelo(
      nome: 'Velocidade e Uniformidade do Fluxo de Ar',
      proposta: 'Verificar a velocidade e a uniformidade do fluxo de ar unidirecional na zona de trabalho do equipamento de fluxo laminar.',
      criterioAceitacao: 'Conforme especificação do equipamento e do projeto.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Realizar as leituras nos pontos definidos para cada filtro utilizando anemômetro calibrado;',
        'Registrar a frequência de operação do equipamento, quando aplicável;',
        'Calcular a média e a dispersão das leituras e comparar com o critério aprovado;',
        'Registrar qualquer turbulência, desvio ou condição anormal observada durante o teste.',
      ],
    ),
    TipoEnsaio.vazaoInsuflacao: TextoEnsaioModelo(
      nome: 'Vazão de Ar de Insuflação e Número de Trocas / Renovações de Ar',
      proposta: 'Verificar a vazão de ar de insuflação no interior de cada sala. Utilizando a vazão total da sala determina-se '
          'o número de trocas / renovações de ar de cada sala limpa.',
      criterioAceitacao: 'Conforme especificação de cada sala.',
      preRequisitos: [
        ..._preRequisitosAcesso,
        'Garantir que os equipamentos de processo permaneçam em operação durante a execução do teste.',
      ],
      descricao: [
        'Verificar a vazão de insuflação da sala utilizando um medidor de vazão do tipo balômetro calibrado com capa '
            'coletora/coifa de captura;',
        'Realizar a medição colocando o coletor abaixo do difusor de insuflação, aplicando a moldura do coletor contra uma área '
            'plana de modo a evitar leituras com variações devido às fugas de ar;',
        'É necessário que a abertura do coletor seja colocada de maneira a cobrir toda a área do difusor de insuflação;',
        'Registrar os valores de vazão encontrados e calcular a vazão total da sala (QT = ΣQd);',
        'Calcular o número de trocas de ar: NT = QT / VS, onde NT = número de trocas (t/h), QT = vazão total (m³/h) e '
            'VS = volume da sala (m³);',
        'Comparar os resultados obtidos com os critérios de aceitação e registrar na tabela de resultados.',
      ],
    ),
    TipoEnsaio.perdaCargaFiltros: TextoEnsaioModelo(
      nome: 'Perda de Carga dos Filtros HEPA',
      proposta: 'Verificar se os filtros HEPA estão com sua perda de carga dentro da sua especificação e por inspeção visual o '
          'estado de conservação dos filtros, abrangendo manta e estrutura.',
      criterioAceitacao: '≤ 500 Pa',
      preRequisitos: [
        'Se for aplicável, seguir os procedimentos estabelecidos em relação ao acesso à sala (ou zona) limpa, inclusive '
            'aqueles relativos à paramentação;',
        'Os filtros devem estar instalados.',
      ],
      descricao: [
        'Realizar as medições dos filtros HEPA;',
        'Realizar a coleta de dados de número de série dos filtros HEPA, quando disponível;',
        'Realizar a inspeção visual dos filtros HEPA verificando a integridade da manta filtrante e estrutura de sustentação;',
        'Realizar a inspeção visual dos filtros HEPA verificando se os filtros estão corretamente instalados.',
      ],
    ),
    TipoEnsaio.integridadeFiltros: TextoEnsaioModelo(
      nome: 'Integridade e Estanqueidade dos Filtros HEPA',
      proposta: 'Verificar se o sistema de filtragem está corretamente instalado e que não tenha desenvolvido vazamentos durante '
          'o uso, abrangendo meio filtrante, selante, moldura do filtro, vedação, quadros de fixação e estrutura de sustentação.',
      criterioAceitacao: 'O vazamento máximo de aerossol de desafio (P.A.O/D.O.P) encontrado a jusante do filtro não deve ser '
          'maior que 0,01% da concentração gerada a montante do mesmo.',
      preRequisitos: [
        'Os testes de Vazão de Ar de Insuflação e Perda de Carga dos Filtros HEPA devem estar concluídos;',
        ..._preRequisitosAcesso,
      ],
      descricao: [
        'Para execução do teste utilizar um fotômetro de aerossol calibrado e um gerador de aerossol (P.A.O ou D.O.P);',
        'Introduzir o aerossol de desafio antes dos filtros HEPA de maneira a produzir uma concentração uniforme para cada filtro;',
        'Ajustar a concentração do aerossol de desafio de 1 a 100 mg/m³ de ar e medir a concentração a montante do filtro;',
        'Fazer a varredura do filtro cobrindo toda a área filtrante, o perímetro e a vedação, a aproximadamente 5 cm/s e a '
            '2,5 cm da face a jusante;',
        'Ao localizar vazamentos, manter a sonda fixa para obter a leitura máxima e registrá-la. Se o vazamento for menor que '
            '0,01%, registrar < 0,01%;',
        'Reparos: realizar com silicone neutro asséptico; área total de reparos ≤ 3% da área de face do filtro e menor dimensão '
            'de qualquer reparo ≤ 3,8 cm; após a cura, repetir a verificação no ponto reparado.',
      ],
    ),
    TipoEnsaio.nivelRuido: TextoEnsaioModelo(
      nome: 'Nível de Ruído',
      proposta: 'Verificar se o nível de ruído produzido pelo equipamento de fluxo laminar está adequado à especificação aplicável.',
      criterioAceitacao: 'Conforme especificação do equipamento e do projeto.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Realizar as leituras nos pontos definidos utilizando decibelímetro calibrado;',
        'Registrar a condição de operação do equipamento e as condições ambientais relevantes;',
        'Comparar as leituras com o critério aprovado e registrar a situação do teste.',
      ],
    ),
    TipoEnsaio.luminosidade: TextoEnsaioModelo(
      nome: 'Luminosidade',
      proposta: 'Verificar se a iluminação da zona de trabalho do equipamento de fluxo laminar atende à especificação aplicável.',
      criterioAceitacao: 'Conforme especificação do equipamento e do projeto.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Realizar as leituras nos pontos definidos utilizando luxímetro calibrado;',
        'Registrar a condição de operação e a posição de cada leitura;',
        'Comparar os resultados com o critério aprovado e registrar a situação do teste.',
      ],
    ),
    TipoEnsaio.paralelismoFluxo: TextoEnsaioModelo(
      nome: 'Paralelismo do Fluxo de Ar',
      proposta: 'Verificar, por meio de visualização com fumaça ou névoa, que as linhas de fluxo se mantêm aproximadamente paralelas na zona de trabalho.',
      criterioAceitacao: 'Linhas de fluxo aproximadamente paralelas, sem turbulência ou refluxo nas zonas críticas.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Introduzir fumaça ou névoa na zona de trabalho utilizando máquina de fumaça;',
        'Observar o sentido e o comportamento das linhas de fluxo em toda a zona crítica;',
        'Registrar o resultado e anexar evidência fotográfica quando disponível.',
      ],
    ),
    TipoEnsaio.pressao: TextoEnsaioModelo(
      nome: 'Diferencial de Pressão entre Salas',
      proposta: 'Verificar a capacidade da instalação como um todo, em manter as diferenças de pressão e o sentido de fluxo '
          'especificado em projeto.',
      criterioAceitacao: 'Conforme especificação de cada sala.',
      preRequisitos: [
        'Os testes de Vazão de Ar de Insuflação, Perda de Carga e Integridade e Estanqueidade dos Filtros HEPA devem estar '
            'concluídos;',
        ..._preRequisitosAcesso,
        'Todas as portas devem estar fechadas e as aberturas e passagens em condições normais de operação.',
      ],
      descricao: [
        'Verificar o diferencial de pressão entre salas utilizando um manômetro digital calibrado;',
        'Utilizar a mesma tomada de pressão estática usada pela área no monitoramento de rotina;',
        'Zerar o manômetro digital sempre antes da utilização;',
        'Medir a diferença de pressão entre a sala mais interna e as adjacentes, até o último ambiente em relação ao '
            'ambiente externo.',
      ],
    ),
    TipoEnsaio.visualizacaoFluxo: TextoEnsaioModelo(
      nome: 'Visualização do Fluxo de Ar',
      proposta: 'Verificar o sentido correto do fluxo de ar entre as salas classificadas.',
      criterioAceitacao: 'Sentido correto do fluxo de ar, sem refluxo incompatível com a proteção requerida.',
      preRequisitos: _preRequisitosAcesso,
      descricao: [
        'Visualizar o sentido do fluxo de ar com fumaça ou névoa;',
        'Registrar o sentido observado e qualquer refluxo ou turbulência identificada.',
      ],
    ),
    TipoEnsaio.contagemParticulas: TextoEnsaioModelo(
      nome: 'Contagem de Partículas Não Viáveis "Em repouso" e "Em operação"',
      proposta: 'Verificar se a contagem de partículas não viáveis de cada sala (ou zona) limpa atende à classificação de '
          'limpeza especificada em projeto, nos estados de ocupação "Em repouso" e "Em operação".',
      criterioAceitacao: 'Cada sala deve estar de acordo com a classificação estabelecida no projeto de tratamento de ar.',
      preRequisitos: [
        'Os testes de Vazão, Perda de Carga, Integridade e Estanqueidade dos Filtros HEPA e Diferencial de Pressão devem estar '
            'concluídos;',
        ..._preRequisitosAcesso,
        'Verificar se a área está adequadamente sinalizada e se a limpeza dos ambientes e equipamentos está adequada.',
      ],
      descricao: [
        'Utilizar um contador de partículas calibrado;',
        'O número mínimo de pontos de amostragem segue a ABNT NBR ISO 14644-1:2019 (arredondado para cima e ≥ 2);',
        'Os tamanhos de partículas especificados para este teste são de 0,5 µm e 5,0 µm;',
        'Posicionar a sonda próxima às posições de trabalho, a cerca de 1,20 m do piso quando aplicável, com a abertura '
            'voltada para o fluxo de ar;',
        'Anexar as fitas impressas pelo contador de partículas e transcrever os valores na tabela de resultados;',
        'O resultado deve ser padronizado em número de partículas por metro cúbico de ar.',
      ],
    ),
    TipoEnsaio.recuperacaoParticulas: TextoEnsaioModelo(
      nome: 'Recuperação',
      proposta: 'Verificar o tempo de recuperação de cada sala.',
      criterioAceitacao: 'O tempo de recuperação da classificação da área à condição de repouso deve ser ≤ 15 minutos.',
    ),
    TipoEnsaio.quedaEnergia: TextoEnsaioModelo(
      nome: 'Queda de Energia',
      proposta: 'Verificar o comportamento de cada sala durante a queda e o restabelecimento de energia.',
      criterioAceitacao: 'Cada sala deve estar de acordo com a classificação estabelecida no projeto de tratamento de ar.',
    ),
    TipoEnsaio.estanqueidade: TextoEnsaioModelo(
      nome: 'Estanqueidade',
      proposta: 'Verificar a ausência de vazamento relevante ao desempenho da limpeza da instalação.',
      criterioAceitacao: 'Vazamento ≤ 0,01% da concentração gerada a montante.',
    ),
  };
}
