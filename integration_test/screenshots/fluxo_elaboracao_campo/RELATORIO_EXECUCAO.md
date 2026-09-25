# Execução ponto a ponto — Elaboração → Campo → Aprovação

Data/Hora: 2026-09-24 16:34:24.270040  
Usuário: admin@celacanto.com  
Área do teste: AREA E2E 1790278404209

| # | Verificação | Resultado | Evidência |
|---|---|---|---|
| 01 | Login com admin@celacanto.com | OK | 01_home.png |
| 02 | Item 5: painel lateral de pré-visualização exibido no Windows | OK | 02_elaboracao_vazia.png |
| 03 | Item 2: sala não pode ser criada sem máquina | OK | - |
| 04 | Máquina UTA-01 com filtro interno G4 (padrão do dropdown) | OK | 04_modal_maquina.png |
| 05 | Item 3: sala SALA 01 com filtro H14 x2 via dropdown | OK | 05_modal_SALA_01.png |
| 06 | Item 3: sala SALA 02 com filtro F9 x1 via dropdown | OK | 06_modal_SALA_02.png |
| 07 | Item 2: máquina UTA-01 atende SALA 01 e SALA 02 | OK | - |
| 08 | Itens 1/2/5: prévia com resumo e tabela salas × filtros (3 linhas) | OK | 08_elaboracao_completa.png |
| 09 | Item 2: salas gravadas com máquina e filtros (SQLite) | OK | - |
| 10 | Item 1: resumo gravado em testes_catalogo (domínio celacanto.com) | OK | - |
| 11 | Item 6: duplicidade detectada no mesmo minuto e liberada no minuto seguinte | OK | - |
| 12 | Item 9: lista do técnico filtrada por área | OK | 12_campo_lista_filtrada.png |
| 13 | Item 7: 3 testes exigidos (2 filtros SALA 01 + 1 filtro SALA 02) | OK | 13_campo_inicio.png |
| 14 | Item 7: outro ensaio bloqueado enquanto há ensaio pendente | OK | 14_campo_bloqueio_pendente.png |
| 15 | Item 7: ponto por filtro (Filtro 1 (F9)) preenchido | OK | 15_campo_execucao_sala02.png |
| 16 | Item 7: senha errada do supervisor recusada | OK | 16_campo_liberacao_negada.png |
| 17 | Item 7: relatório finalizado com liberação do supervisor | OK | 17_campo_finalizado.png |
| 18 | Item 7: status em revisão + histórico da liberação + ponto vinculado ao filtro | OK | - |
| 19 | Item 9: lista de aprovação filtrada por área | OK | 19_aprovacao_lista.png |
| 20 | Item 8: supervisor vê resultados (12.5) e pendências (—) antes de aprovar | OK | 20_aprovacao_revisao.png |
| 21 | Item 8: voltar da revisão não aprova o relatório | OK | - |
| 22 | Falha na emissão do relatório | OK | 22_FALHA_emissao.png |
