# Relatório de QA — MVP Celacantoapp

**Data:** 2026-10-09  
**Ambiente:** Windows, Flutter desktop, Android release, Firebase real de teste  
**Escopo:** login, elaboração, execução em campo, aprovação, emissão/envio de relatório, suíte Flutter, Cloud Functions e geração do APK.

## 1. Resumo executivo

**Veredito: Apto com ressalvas para instalação direta do APK em ambiente de teste. Não apto para publicação em loja ou operação definitiva sem as correções de Storage e assinatura.**

O suporte à tecla Enter foi implementado no login. O Enter no e-mail avança para a senha; o Enter na senha executa o mesmo fluxo do botão **Entrar**. O analyzer do Flutter e os diagnósticos do VS Code ficaram limpos.

O upload de evidências foi corrigido para Windows/Linux com HTTPS autenticado e metadata explícito; Android/iOS continuam usando o plugin oficial. A sincronização de projetos aprovados também deixou de bloquear o login.

| Resultado | Quantidade |
|---|---:|
| BLOCKER aberto | 0 |
| MAJOR aberto | 2 |
| MINOR aberto | 2 |
| TRIVIAL aberto | 1 |
| GAP de QA/tooling | 3 |
| Testes pós-correção aprovados | 68/68 (100%) |

Os 68 resultados pós-correção correspondem a 42 testes Flutter, 24 testes Node e 2 fluxos E2E no Windows. Houve uma execução E2E inicial falha por extração incorreta da senha no script de execução e uma segunda falha porque o teste não selecionava a conformidade obrigatória; ambos foram corrigidos antes da execução final aprovada.

## 2. Escopo e limitações

### Executado

- Login por botão e por Enter.
- Elaboração de projeto Fluxo Laminar.
- Execução de ensaios, validação de pontos e aprovação.
- Emissão do DOCX e envio de e-mail nos E2E.
- Suíte unitária/widget Flutter.
- Suíte Node das Cloud Functions.
- `flutter analyze`, `flutter pub get`, `npm ci` e `npm audit --omit=dev`.
- Geração e verificação criptográfica do APK release.

### Não executado

- Instalação do APK em aparelho físico ou emulador Android.
- Captura OCR e câmera em hardware Android real.
- Publicação na Play Store.
- Lint das Functions: o script existe, mas o projeto não possui o executável/configuração do ESLint.
- Atualização das dependências, do Gradle, do AGP ou do Kotlin; foram apenas avaliados.

Os E2E usam Firebase real de teste e criam dados de teste. Credenciais não são reproduzidas neste relatório.

## 3. Portões de qualidade

| Portão | Resultado | Evidência/observação |
|---|---|---|
| `flutter pub get` | PASS | Dependências resolvidas; 34 pacotes têm versões mais novas incompatíveis com as restrições atuais. |
| Diagnósticos do VS Code | PASS | `get_errors`: nenhum erro. |
| `flutter analyze` | PASS | Nenhum issue após as correções de `@override`, `if` e teardown. |
| Formatação Dart | RESSALVA | A checagem `dart format --set-exit-if-changed` ainda aponta arquivos antigos não formatados: `lib/database_helper.dart`, `lib/projeto_service.dart`, o E2E e `test/widget_test.dart`. |
| `flutter test` | PASS | 42 testes aprovados. |
| `npm ci` em `functions/` | PASS COM RESSALVA | Instalação concluída; runtime local Node `24.18.0`, enquanto o projeto declara Node `22`. |
| `npm test` | PASS | 24 testes aprovados. |
| `npm run lint` | NÃO EXECUTADO | Falha de tooling: `'eslint' não é reconhecido`; não há ESLint nas dependências nem configuração encontrada. |
| `npm audit --omit=dev` | RESSALVA | 2 vulnerabilidades moderadas transitivas em `uuid`, via `gaxios`. |
| E2E principal Windows | PASS | Elaboração → campo → aprovação → DOCX → e-mail. |
| E2E com oito ensaios Windows | PASS | Fluxo completo aprovado; três evidências receberam URL HTTPS e o DOCX incorporou as imagens. |
| `flutter build apk --release` | PASS COM AVISOS | APK gerado em 107,7 MB; avisos de atualização futura do Gradle, AGP e Kotlin. |

## 4. Matriz de fluxos críticos

| Fluxo | Resultado | Observação |
|---|---|---|
| Login com botão | OK | Exercitado nos dois E2E. |
| Login com Enter | OK | Teste de widget aprovado e mesmo callback do botão utilizado. |
| Elaboração | OK | Empresa, sistema, máquina, sala e filtros criados no E2E. |
| Execução em campo | OK | Pontos salvos e vinculados aos filtros. |
| Bloqueio de pendência/liberação | OK | Cenários de pendência e liberação cancelada exercitados. |
| Aprovação | OK | Status e histórico de auditoria validados. |
| Emissão de relatório | OK | DOCX produzido e salvo em Downloads. |
| Envio de e-mail | OK | Validado pelo E2E principal. |
| Evidência fotográfica no Storage | OK no Windows | Upload autenticado e URL HTTPS validados no E2E; falta repetir após publicar a regra restritiva final. |
| OCR/câmera em Android | NÃO TESTADO | Precisa de aparelho ou emulador com câmera/plugin disponível. |
| Recuperação de senha | NÃO TESTADO | Não fez parte dos E2E executados. |

## 5. Achados detalhados

### QA-001 — Evidências fotográficas no Firebase Storage

- **Severidade:** MAJOR
- **Status:** Corrigido no código; publicação da regra final pendente
- **Área:** evidências de campo / Storage
- **Ambiente:** E2E Windows com Firebase real
- **Reprodução:** executar `fluxo_laminar_todos_ensaios_test.dart` com as credenciais de teste e observar as três chamadas de upload de evidência.
- **Esperado:** a foto ser enviada ao Storage e uma URL remota persistente ser registrada no resultado.
- **Obtido antes:** `firebase_storage/unauthorized`; o código usava o plugin diretamente no Windows e mantinha a evidência como `local://...`.
- **Obtido depois:** E2E final passou com três URLs HTTPS e imagens incorporadas no DOCX.
- **Causa:** o upload do plugin Windows não carregava a autenticação nesse cenário; multipart REST também foi recusado, enquanto `uploadType=media` autenticado foi aceito.
- **Referência:** `lib/storage_upload_client.dart`, `lib/execucao_ensaio_page.dart` e `storage.rules`.
- **Correção:** Windows/Linux usam upload media HTTPS com token Firebase e obtêm a URL pelo SDK; Android/iOS usam `SettableMetadata(contentType: ...)`. O E2E agora rejeita `local://` e DOCX sem `word/media/`.
- **Pendência:** publicar no console a regra versionada de `storage.rules`; a regra atualmente publicada aceita `application/octet-stream`, conforme o diagnóstico.
- **Esforço:** M
- **Risco de regressão:** Alto; afeta evidências e relatórios.

### QA-002 — APK release está assinado com certificado debug

- **Severidade:** MAJOR para distribuição em loja; aceitável para sideload de teste
- **Status:** Aberto por decisão de release
- **Área:** Android/release
- **Reprodução:** executar `flutter build apk --release` e `apksigner verify --verbose --print-certs`.
- **Esperado:** certificado de release/upload mantido pelo cliente.
- **Obtido:** certificado `Android Debug`, assinatura v2 válida.
- **Referência:** `android/app/build.gradle.kts`, `buildTypes.release.signingConfig`.
- **Correção sugerida:** criar keystore de upload, configurar `android/key.properties` fora do Git e trocar a assinatura antes da Play Store ou de atualizações futuras. O `applicationId` continua `com.example.celacantoapp` e também deve ser revisado antes da publicação.
- **Esforço:** M
- **Risco de regressão:** Alto; uma troca tardia de chave/ID afeta atualizações e Firebase.

### QA-003 — Vulnerabilidades transitivas em dependências das Functions

- **Severidade:** MINOR
- **Status:** Aberto
- **Área:** dependências/backend
- **Reprodução:** executar `npm audit --omit=dev` em `functions/`.
- **Esperado:** nenhuma vulnerabilidade de produção ou uma exceção documentada.
- **Obtido:** 2 vulnerabilidades moderadas em `uuid <11.1.1`, trazidas por `gaxios`.
- **Correção sugerida:** executar atualização controlada (`npm audit fix` ou upgrade compatível), repetir `npm test` e revisar o lockfile antes do deploy.
- **Esforço:** P/M
- **Risco de regressão:** Médio; atualizar dependências pode afetar geração de DOCX e chamadas Firebase.

### QA-004 — Toolchain Android próxima do fim do suporte Flutter

- **Severidade:** MINOR
- **Status:** Aberto
- **Área:** build Android
- **Evidência:** o build passou, mas avisou que Gradle `8.14.0`, AGP `8.11.1` e Kotlin `2.2.20` terão suporte removido em versões futuras do Flutter.
- **Correção sugerida:** planejar atualização coordenada do Gradle wrapper, AGP e Kotlin, validando plugins Flutter/Firebase e o APK em CI.
- **Esforço:** M
- **Risco de regressão:** Médio/alto; mudanças de toolchain podem quebrar plugins nativos.

### QA-005 — Formatação Dart não está estável em quatro arquivos

- **Severidade:** TRIVIAL
- **Status:** Aberto
- **Área:** manutenção
- **Evidência:** `dart format --output=none --set-exit-if-changed` retorna alterações em `lib/database_helper.dart`, `lib/projeto_service.dart`, `integration_test/fluxo_elaboracao_campo_aprovacao_test.dart` e `test/widget_test.dart`.
- **Correção sugerida:** aplicar `dart format` nesses arquivos em uma mudança separada para não misturar uma reformatacão ampla com o MVP.
- **Esforço:** P
- **Risco de regressão:** Baixo, mas o diff pode ficar grande.

## 6. Gaps de QA e tooling

### QA-GAP-001 — Lint JavaScript indisponível

`functions/package.json` declara `"lint": "eslint ."`, porém não declara `eslint` em `devDependencies` e não há configuração ESLint no diretório. O teste de lint termina antes de analisar qualquer arquivo. Adicionar a ferramenta e uma configuração compatível com Node 22 antes de colocá-la no CI.

### QA-GAP-002 — Falta de smoke test Android real

O APK foi compilado e assinado, mas não foi instalado em dispositivo/emulador. O fluxo de câmera, OCR, permissões, Storage e teclado físico/virtual precisa de uma execução Android antes da entrega ao cliente.

### QA-GAP-003 — Cobertura limitada fora do fluxo E2E principal

Recuperação de senha, atualização de senha, QR Code e comportamento de rede lenta/offline não foram validados em um dispositivo Android. O E2E observou timeout de sincronização offline de autorizações, mas o fluxo continuou e foi aprovado.

### QA-006 — Sincronização pendente não deve bloquear o login

- **Severidade:** MINOR
- **Status:** Corrigido
- **Área:** login/sincronização offline
- **Reprodução:** manter no banco local um projeto aprovado pendente, executar o E2E e observar `cloud_firestore/permission-denied` durante a sincronização inicial.
- **Esperado:** a Home abrir mesmo quando um projeto antigo não puder ser atualizado.
- **Obtido antes da correção:** o login aguardava a sincronização e o E2E expirava esperando a Home.
- **Correção:** a sincronização após login passou a ser executada em segundo plano, com timeout de 10 segundos e tratamento de erro em `lib/main.dart`.
- **Validação:** o E2E dos oito ensaios passou com `exit code 0` e `All tests passed!`.
- **Esforço:** P
- **Risco de regressão:** Baixo; a sincronização continua sendo tentada e também é acionada pelo listener de conectividade.

## 7. Plano de solução priorizado

1. Corrigir e validar o Storage (QA-001), incluindo regras, bucket e teste de URL remota.
2. Definir a estratégia de distribuição: manter o APK debug somente para teste direto ou criar imediatamente uma chave de release/upload (QA-002).
3. Instalar o APK em aparelho/emulador Android e executar smoke test de login, Enter, câmera/OCR, evidência e emissão (QA-GAP-002).
4. Adicionar ESLint/configuração e alinhar CI ao Node 22; depois tratar as vulnerabilidades transitivas (QA-GAP-001 e QA-003).
5. Atualizar Gradle/AGP/Kotlin em uma tarefa isolada e repetir o build (QA-004).
6. Aplicar a formatação Dart em mudança separada (QA-005).

## 8. Plano de testes recomendado

- CI Flutter: `flutter pub get` → `flutter analyze` → `flutter test` → build APK.
- CI Functions: `npm ci` com Node 22 → `npm test` → `npm run lint` → `npm audit --omit=dev`.
- Smoke Android em cada release: login por toque e Enter, permissões, câmera/OCR, Storage, relatório e botão voltar.
- E2E de Storage que falhe quando a evidência ficar apenas em `local://`.
- E2E de recuperação de senha e expiração/retorno de rede.
- Ambiente Firebase de staging para os fluxos que criam projetos, geram DOCX e enviam e-mail.

## 9. Artefato gerado

- **APK:** `build/app/outputs/flutter-apk/app-release.apk`
- **Tamanho:** 112.917.823 bytes (107,7 MB)
- **SHA-256:** `46ADA9E3BD350995C7FC56A861CC64F39085F43B744A9AA44658B6CF898F1D3C`
- **Assinatura:** APK Signature Scheme v2, certificado `Android Debug`
- **Versão:** `1.0.0+1`, exibida na home como `v1.0.0`
- **Application ID:** `com.example.celacantoapp`
