# Execução E2E — Fluxo Laminar: Elaboração → Campo → Aprovação → Emissão

Data/Hora: 2026-10-09 08:41:54.448219  
Usuário: admin@celacanto.com  
Área do teste: AREA E2E 1791546019694  
Projeto: PRJ-1791546037312  
Registro de e-mail: relatorios_email/HzZv5r755LsthNXSmAgi

| # | Verificação | Resultado | Evidência |
|---|---|---|---|
| 01 | Login com admin@celacanto.com | OK | 01_home.png |
| 02 | Empresa 11.222.333/0001-81 encontrada no Firestore (EMPRESA TESTE AUTOMATIZADO) | OK | - |
| 03 | Sala não pode ser criada sem máquina | OK | - |
| 04 | Máquina FLUXO-01 com 2× H14 | OK | 04_modal_maquina.png |
| 05 | Sala SALA 01 com os 2 filtros H14 da máquina alocados | OK | 05_modal_sala.png |
| 06 | Prévia com Integridade de Filtros em 2 pontos H14 | OK | 06_elaboracao_completa.png |
| 07 | Projeto PRJ-1791546037312 pronto para campo com máquina, sala e 2 H14 alocados | OK | - |
| 08 | Lista do técnico filtrada por área | OK | 08_campo_lista.png |
| 09 | TAG inexistente rejeitada | OK | - |
| 10 | TAG de outro tipo (Manômetro) rejeitada para Fotômetro | OK | - |
| 11 | Fotômetro FOT-9001 validado | OK | 11_campo_ferramentas.png |
| 12 | Finalizar com pendências exige liberação (TOTP/offline); cancelado | OK | 12_campo_liberacao_pendentes.png |
| 13 | Encerramento incompleto exige liberação do supervisor; cancelado | OK | - |
| 14 | Integridade: 2 pontos H14 preenchidos | OK | 14_campo_execucao.png |
| 15 | Todos os testes feitos: relatório enviado para revisão | OK | 15_campo_concluido.png |
| 16 | Status em revisão; 2 pontos gravados e vinculados aos filtros | OK | - |
| 17 | Supervisor corrige ponto 1 de 0.005 para 0.006 | OK | 17_revisao_correcao.png |
| 18 | Conclusão "Cumpre" antes da emissão | OK | 18_emissao_conclusao.png |
| 19 | Relatório Fluxo Laminar aprovado, gerado e enviado por e-mail | OK | 19_relatorio_emitido.png |
| 20 | Status aprovado; conclusão, observações e correção 0.005 → 0.006 no histórico | OK | - |
| 21 | E-mail registrado como enviado para admin@celacanto.com (relatorios_email/HzZv5r755LsthNXSmAgi) | OK | - |
| 22 | DOCX C:\Users\Michael/Downloads/Celacanto/Relatorio_PRJ-1791546037312.docx: cliente, área, equipamento e técnico preenchidos | OK | - |
| 23 | DOCX traz só o teste executado (Integridade = Anexo 1) e anexos renumerados em sequência | OK | - |
| 24 | DOCX contém ferramenta (TAG do Fotômetro) | OK | - |
| 25 | DOCX contém sala | OK | - |
| 26 | DOCX contém leituras do campo | OK | - |
| 27 | Regeneração gravou um novo DOCX e manteve o status aprovado | OK | - |
