# 📝 Transcrição da Reunião — Levantamento de Requisitos do Relatório de Testes

**Fonte:** `docs/meeting.m4a` (transcrição automática bruta em [meeting_literal.txt](meeting_literal.txt))
**Duração aproximada:** 01:13:04
**Assunto:** Levantamento de regras de negócio para a funcionalidade de elaboração de relatórios de testes (contagem de partículas, vazão, pressão, integridade de filtros etc.) do aplicativo.

> ⚠️ **Nota sobre a qualidade da transcrição:** o áudio foi transcrito automaticamente (Whisper), sem separação de locutores (diarização). Por isso, os turnos de fala abaixo não são atribuídos a nomes específicos — o texto foi reorganizado por tópico e limpo de fragmentação, mas o conteúdo é fiel ao reconhecimento automático original. Trechos em que o reconhecimento falhou de forma severa (repetições sem sentido, ruído, palavras incompreensíveis) estão marcados como `[trecho inaudível/ruído de transcrição]`. Nomes próprios citados na conversa: **Camila**, **Lucas**, **Vinicius**, **Gerson**.

---

## 1. Abertura — objetivo da reunião (00:00–00:20)

A conversa começa definindo o objetivo do encontro: estruturar a próxima etapa do relatório de testes. É necessário criar uma aba onde seja possível colocar o nome das salas, junto com a quantidade de filtros e de difusores de cada uma, além do grau (classificação) da sala.

## 2. Cadastro do projeto e das salas (00:20–02:00)

Ao assumir um novo projeto/empresa, o primeiro dado a preencher é a **quantidade de salas**, seguida do **tamanho** de cada uma — informado como área e volume. A ideia inicial é ter uma visão geral do projeto e, na sequência, uma aba específica para colocar a área e o volume de cada sala.

## 3. Seleção de ensaios e resumos automáticos (02:00–04:12)

É necessária uma tela em que se selecione **quais salas** serão testadas e, a partir disso, o sistema puxe automaticamente os **resumos** de cada ensaio (ex.: contagem de partículas, estanqueidade e pressão são citados como exemplos). Ao selecionar o ensaio, o aplicativo deve puxar automaticamente todos os resumos relacionados a ele — cada ensaio já tem, em tese, um conjunto de equipamentos/ferramentas necessários pré-determinados, mesmo que isso ainda não esteja formalizado como relatório (poderia ser levantado com a equipe interna, "as meninas").

## 4. Identificação de ferramentas por QR code (03:39–07:09)

Regra de negócio central: **todos os equipamentos serão "tagueados"** com um QR code. O técnico, pelo aplicativo, escaneia o QR code do instrumento antes de iniciar um teste e o sistema associa automaticamente todos os resultados daquele teste ao instrumento lido (ex.: se leu o "balômetro zero", todos os resultados do teste ficam vinculados ao balômetro zero).

Exceções à regra "um instrumento por teste":
- Em ambientes grandes, pode ser necessário usar **mais de um instrumento do mesmo tipo** (ex.: 3 contadores de partículas diferentes) dentro do mesmo teste.
- Um mesmo instrumento pode ser usado em **testes/salas diferentes** no mesmo atendimento (ex.: um manômetro faz um teste em uma sala e outro manômetro faz um teste em outra sala/academia), especialmente em clientes pequenos, onde normalmente **um único conjunto de instrumentos** é suficiente. Para clientes grandes, pode ser necessário mais de um.
- Ficou em aberto se essa quantidade (1, 2 ou 3 instrumentos) deveria seguir uma regra automática baseada no porte do cliente (pequeno/médio/grande) — ponto a validar depois.

## 5. Quantidade de salas, difusores e volume (07:09–09:00)

Cada sala deve ter registrado quantos difusores possui (exemplo dado: sala de circulação com 7 difusores → o técnico deve preencher o resultado 7 vezes). O volume da sala também precisa aparecer para o técnico. Esse cálculo é usado para o **número de trocas de ar** — o app deve apenas capturar a leitura do display do equipamento (vazão) e calcular o número de trocas automaticamente, sem digitação manual do técnico.

Também foi discutida a diferença entre **filtro na máquina (handling unit)** — ex.: G4, F9, absoluto — e **filtro terminal**, que fica direto na sala (não na máquina). Quando existe filtro terminal, é necessário abrir um campo adicional para ele; quando não existe, o campo não deve aparecer.

## 6. Estrutura da primeira página do relatório: empresa, sistema e área (09:00–12:15)

Definição da hierarquia de campos da capa do relatório:
1. **Empresa** — herdada automaticamente do cadastro do projeto (tela "novo projeto").
2. **Sistema** — selecionado por menu suspenso (ex.: "HDA04"), pois se repete e não deve ser digitado toda vez.
3. **Área** atendida por aquele sistema.
4. A partir da área, o sistema puxa o **resumo dos testes/ensaios**.
5. Depois, a **quantidade de salas**, cada uma com nome, volume e área.

A ideia é que sistema e área fiquem em menus de seleção (não digitação livre), já que se repetem entre relatórios do mesmo cliente.

## 7. Cálculo de pontos de contagem de partículas por área (12:15–17:38)

Regra de norma técnica: a quantidade de **pontos de teste** (leituras) de contagem de partículas depende da área da sala — segue uma tabela da norma até um determinado limite (citado ~1.000 m²) e, acima disso, uma fórmula. Exemplo usado: uma sala de 10 m² exige 5 pontos de teste obrigatórios.

Regra de negócio definida para o app:
- Calculado o número de pontos exigidos pela norma (ex.: 5), o técnico é **obrigado a realizar exatamente essa quantidade** de leituras — nem mais, nem menos.
- O app **não deixa avançar** para o próximo teste enquanto não completar o número de pontos definido.
- Se o técnico não conseguir concluir todos os pontos em campo, ele deve poder **"encerrar"** o teste incompleto, mas isso dispara um pop-up avisando que nem todos os testes foram finalizados e solicitando que ele **entre em contato com o supervisor**.
- Sem autorização do supervisor, o técnico fica travado e não consegue prosseguir/finalizar.
- Regra similar já existe hoje para instrumentos vencidos: se a ferramenta estiver fora da validade de calibração, o app barra o uso e exige liberação do supervisor.
- Da mesma forma, o técnico não deve conseguir avançar de um teste para o próximo (ex.: do teste de tranquilidade para o de pressão) sem finalizar o teste atual.
- Também foi reforçado que o técnico só consegue **iniciar o relatório em campo** se todos os dados prévios das ferramentas/máquina já tiverem sido preenchidos previamente (ou seja, o relatório "nasce" praticamente pronto para o técnico, faltando só os resultados de campo).

## 8. Dados da máquina (handling unit) e filtros (17:38–22:00)

Antes de chegar ao técnico, é necessário levantar com o **cliente** (não com o técnico) a lista de máquinas (handling units) e, para cada uma, a quantidade de filtros (podendo ser 4, 7, 8, 9, 14 filtros etc.) e se há filtro terminal na sala. Campos previstos:
- Nome/identificação da máquina.
- Quantidade de filtros/difusores (contam como o mesmo campo).
- Caixa de seleção "filtro terminal?" — se marcada, abre um sub-formulário perguntando a quantidade de filtros terminais; se não marcada, esse campo não aparece.
- Tipo de filtro: **grosso, fino e absoluto** (ex.: G4, F9, filtro absoluto).

Ao final dessa etapa, o relatório já sobe para o técnico com tudo preenchido, restando a ele apenas registrar os resultados de campo (o "chek-list").

## 9. Tabelas de testes, vazão e critérios (22:00–24:00)

As **tabelas** do relatório correspondem, tecnicamente, aos **testes/ensaios realizados** (ex.: vazão). Cada tipo de teste tem sua própria tabela de critérios, e a quantidade de difusores precisa estar definida antes de montar a tabela. Foi levantado que cada tabela pode ter um único resultado esperado por ponto ou vários (depende do tipo de teste/ensaio) — esse detalhamento ficou pendente de confirmação técnica ponto a ponto.

## 10. Resultado por difusor/filtro (24:00–30:00)

O número indicado ao lado do resultado (ex.: "1", "2") não representa a quantidade de filtros, e sim a **numeração/identificação de cada filtro individual** dentro da sala — ou seja, se uma sala tem 2 filtros, deve haver 2 campos de resultado (filtro 1 e filtro 2), e assim por diante para cada sala do relatório.

## 11. Cálculo de número de trocas e critério de conformidade (28:00–33:00)

O número de trocas é calculado automaticamente a partir da vazão total encontrada (soma dos resultados) e do volume da sala. O relatório indica **conforme/não conforme** de acordo com o critério esperado (variável conforme a sala/projeto, definido previamente na aba de configuração). Todos esses critérios devem poder ser editados na etapa de configuração do relatório.

> Nota: por volta de 00:28:16–00:28:40 o reconhecimento automático apresenta ruído severo (`[trecho inaudível/ruído de transcrição]`), sem impacto aparente no conteúdo de negócio discutido antes e depois.

## 12. Campos de observação e reparo de filtros (33:00–37:00)

Campos como **piso/vazamento de filtro** e **observações** também são de preenchimento do técnico em campo, já que dependem do que ele encontra no local. Foi discutido o teste de **integridade de filtros** (fotômetro/vazamento): se o vazamento ultrapassar zero, o filtro é considerado reprovado; abaixo de determinado limite, é permitido reparo com silicone, desde que dentro da área máxima de reparo prevista na norma (o técnico mede o retângulo do rasgo e calcula a área). Esse é um campo raramente usado, pois clientes grandes preferem trocar o filtro a repará-lo.

## 13. Direção do fluxo de ar entre salas (36:39–38:00)

O **sentido do fluxo de ar** (setas de pressão diferencial entre salas) segue a planta do cliente, mas normalmente é definido de forma consistente (ex.: de uma sala "suja" para uma "limpa"). Quando o fluxo é invertido em relação ao padrão, o resultado deve ser lançado como valor negativo.

## 14. Contagem de partículas — fitas do equipamento e leitura por ponto (38:00–46:00)

O contador de partículas imprime uma **fita** física com o resultado de cada ponto (0,5 µm e 5 µm). Na norma antiga, bastava um único resultado consolidado a 95% de confiança; na **norma atual**, cada ponto deve ser registrado individualmente — não existe mais o critério consolidado de 95%.

Regras definidas para o app:
- Cada ponto de leitura gera **dois campos de resultado** (0,5 µm e 5 µm).
- É necessário ter um campo para o técnico **fotografar/escanear a fita** do contador como evidência, já que esse é um dado que precisa ser guardado (as fitas desbotam/apagam com o tempo).
- Sem anexar a foto da fita (ou da contagem), o técnico não deve conseguir avançar para o próximo teste.

## 15. Diferença entre Graus A/B/C e Grau D (46:00–48:00)

Salas de **Grau A, B e C** possuem etapas adicionais de teste de queda de energia e recuperação; salas de **Grau D** não possuem essas etapas. Por isso, o grau da sala precisa ser um campo cadastrado desde o início (junto com nome/volume/área), pois determina quais testes serão exigidos mais adiante.

## 16. Teste de recuperação e queda de energia (48:00–51:00)

O teste de recuperação de partículas registra três momentos: **inicial**, **gerada** (pico após sujar a sala propositalmente) e **final** (após a sala retornar ao critério). O tempo de recuperação **não pode ultrapassar 15 minutos**. O mesmo padrão (inicial/gerada/final) se aplica ao teste de queda/religamento de energia, cujo horário de início ainda precisa ganhar um campo próprio no aplicativo (hoje não há campo específico para isso).

## 17. Organização das tabelas — "dever de casa" (49:00–52:00)

Ficou definido que a lista completa de tabelas (uma por tipo de teste/ensaio) seria levantada e enviada com: resumo de cada cálculo, fórmula utilizada e nome/justificativa do cálculo, para servir de base às regras de negócio do sistema.

## 18. Formato de geração do relatório: Word vs. PDF (52:00–56:00)

Decisão registrada: para evitar retrabalho e atraso, o relatório será gerado inicialmente em **Word** (permitindo edição manual quando necessário e posterior exportação para PDF). Gerar diretamente em PDF fica como evolução futura, sem prioridade agora.

Também foi discutido o processo de **assinatura**: hoje o processo ainda é manual/impresso (a equipe interna imprime, monta a pasta e assina fisicamente); no futuro, poderá ser substituído por assinatura eletrônica associada ao usuário que revisou/aprovou o relatório.

## 19. Indicação visual de campos editáveis (56:00–58:15)

Proposta de convenção visual no modelo de relatório: campos em **verde** = editáveis pela equipe de elaboração de relatório; campos em **vermelho** = preenchidos pelo técnico em campo. Também foi sugerida uma tela de "pré-visualização ao vivo": conforme o usuário for selecionando testes/preenchendo campos (empresa, testes, resumo etc.), o aplicativo vai montando uma prévia do relatório final em tempo real.

## 20. Perfis de acesso e permissões (58:15–1:05:00)

Perfis definidos para o sistema:
- **Técnico** — só acessa e edita a página de **resultados** de campo; não pode alterar dados de configuração do relatório.
- **Supervisor** (ex.: Vinicius) — autoriza liberações excepcionais (ex.: técnico não completou todos os pontos, ferramenta fora de validade, necessidade de alterar um resultado já lançado).
- **Elaboração de relatório** (equipe interna que monta a estrutura do relatório antes de ir a campo) — não deve poder alterar a página de resultados, para preservar rastreabilidade de quem alterou o quê.
- **Diretor** — acesso amplo, podendo atuar em todas as funções acima (inclusive aprovando o que o técnico solicitar).

Regra-chave: quem edita a "frente" (estrutura/configuração) do relatório não edita a parte de "resultado", e vice-versa — evitando que alterações de resultado sejam feitas sem rastreabilidade e gerando a necessidade de autorização do supervisor para qualquer exceção.

## 21. Encaminhamentos e próxima reunião (1:05:00–1:10:00)

Ficou combinado que as alterações de regra de negócio serão implementadas e testadas antes do próximo encontro, preferencialmente **presencial** (mencionados os dias 26 e 28, com horário após as 10h/13h a definir). Foi levantada a necessidade de compartilhar acesso/e-mail com outro interessado no projeto (Gerson) para acompanhamento do andamento.

## 22. Evidência fotográfica da contagem (1:10:00–1:13:04)

Reforço da regra de evidência: o técnico deve anexar a **foto da fita/contagem** do equipamento antes de finalizar o teste; sem isso, o teste não pode ser dado como concluído. Foi discutido o risco de técnicos não engajados tirarem fotos genéricas em vez da fita real — como isso não é totalmente controlável pelo aplicativo, a mitigação combinada foi reforçar o processo de conferência do relatório antes da entrega ao cliente. Reunião encerrada com o encaminhamento desses pontos junto ao setor comercial.

---

*Transcrição literal (bruta, com marcação de tempo por trecho) disponível em [meeting_literal.txt](meeting_literal.txt).*
