# Plano diário e diário de trabalho — Soterópolis Chain

**Período:** 28/09/2026 a 10/10/2026
**Prazo informado para submissão:** 10/10/2026; confirmar horário e fuso oficiais.
**Decisão aprovada para planejamento:** Opção 1 — queimar Green Tokens (GT) e emitir comprovante digital demonstrativo.
**Estado:** planejamento; o código ainda não foi alterado em função desta decisão.

## Regras de trabalho

- Cada dia termina com: entregas concluídas, evidências, pendências e próximo passo.
- Marcar uma tarefa como concluída somente após executar e verificar; intenção ou edição sem teste não conta como entrega validada.
- Não usar o Supabase online compartilhado para testes destrutivos. Separar teste automatizado/mock de smoke test real.
- Não guardar nem incluir em relatório, README ou vídeo PATs, chaves privadas, service-role keys ou tokens.
- A IA de visão Gemini foi avaliada somente para responder se a proposta era viável. Não faz parte do escopo atual nem está planejada como trabalho opcional desta entrega.
- O comprovante atesta o burn e a referência registrada pelo sistema. Não deve ser chamado de certificado ambiental, desconto ou benefício comercial.

## Plano diário

### Segunda-feira — 28/09 — diagnóstico, decisão e planejamento

**Objetivo:** fechar direção de produto antes de codificar.

- [x] Analisar o projeto atual, seus pontos fortes, limitações e riscos.
- [x] Avaliar a proposta de adicionar verificação de foto por Gemini.
- [x] Explicar o significado de Green Token (GT) e os limites de alegar valor econômico.
- [x] Escolher a Opção 1: burn de GT e comprovante demonstrativo.
- [x] Preparar a ficha técnica e plano de ação detalhado para avaliação profissional.
- [x] Fechar o relatório do dia após a fundadora confirmar o encerramento do trabalho.

**Entrega do dia:** decisão de produto registrada e documentos de planejamento preparados. Nenhuma implementação da opção 1 foi feita hoje.

**Critério de conclusão:** relatório diário fechado com pendências e decisão preservadas.

### Terça-feira — 29/09 — descanso

**Estado:** descanso informado pela fundadora; nenhuma atividade ou entrega de projeto registrada. As tarefas planejadas para este dia foram transferidas para 30/09, sem marcar atraso como trabalho concluído.

### Quarta-feira — 30/09 — critérios, contrato do recibo e baseline

**Objetivo:** garantir que a solução planejada corresponde à submissão real e definir o que o recibo significa.

- [ ] Conferir no portal oficial o horário/fuso, critérios, categoria, links obrigatórios e eventual exigência de vídeo/demo/on-chain. O PAT do Colosseum estava inválido/expirado na última verificação; não afirmar que a pesquisa autenticada foi concluída.
- [x] Validar o estado atual da branch e separar alterações preexistentes de mudanças novas: há alterações de backend anteriores não relacionadas à opção de resgate e elas precisam ser preservadas/revisadas.
- [x] Revisar a rota de resgate, modelos Flutter/Pydantic, histórico da carteira, idempotência, migration recente, serviço Solana e handler Anchor de burn.
- [x] Desenhar fluxo de tela: saldo → informar quantidade de GT → confirmar burn → mostrar recibo.
- [x] Definir provisoriamente os campos mínimos do recibo: id/identificador da transação, quantidade de GT queimada, estado da operação, assinatura Solana, rede explicitamente configurada e horário gravado. Não incluir referência a descarte se ela não estiver persistida de forma confiável.
- [x] Definir mensagem visível: “Demonstração — não representa dinheiro, desconto, benefício comercial ou certificação ambiental”.
- [x] Definir comportamento esperado de replay: mesma chave e payload deve devolver o recibo original sem novo burn; quantia/payload divergente ou tipo de operação incompatível deve retornar conflito, nunca sucesso silencioso.
- [ ] Confirmar em qual ambiente Supabase as migrations foram aplicadas; não inferir pelo arquivo local.
- [ ] Confirmar rede Solana da demo (localnet ou Devnet), ID de programa/mint e serviço operacional sem expor segredos.
- [x] Especificar estados de operação, inclusive resultado pendente/ambíguo e reconciliação.
- [ ] Identificar testes isolados e um smoke test real controlado.
- [ ] Confirmar horário/fuso e requisitos no portal oficial, e fechar o relatório do dia ao terminar o trabalho.

**Entrega do dia (parcial):** contrato inicial do comprovante e mudanças afetadas foram descritos abaixo. Requisitos oficiais ainda não confirmados.

**Contrato inicial do comprovante (ainda sujeito à revisão dos estados de falha):**

- Request `POST /resgates`: `quantidade` positiva e header `Idempotency-Key`; remover `instalacao_coelba` do novo contrato.
- Resposta confirmada: `id`, `status` (`Confirmado` somente após confirmação on-chain), `tipo` (`BURN`), `tx_hash`, `quantidade`, `rede` e `created_at`.
- Exemplo conceitual: `{"id":"<uuid>","status":"Confirmado","tipo":"BURN","tx_hash":"<signature>","quantidade":10.0,"rede":"devnet","created_at":"<ISO-8601>"}`.
- `rede` não deve ser deduzida informalmente do nome do projeto nem afirmada com base apenas no `.env.example`; criar/usar configuração explícita e verificar a configuração efetiva do ambiente.
- O aviso de demonstração será exibido pelo app; o recibo não promete dinheiro, desconto, benefício comercial nem certificação ambiental.
- Não criar tabela de recibos automaticamente: primeiro confirmar se `transacoes_tokens` e as reservas existentes conseguem sustentar o replay e a reconciliação necessários.

**Baseline técnico de idempotência e recuperação (revisão estática de 30/09):**

- A reserva `idempotency_operations` usa a chave como PK e rejeita reutilização por outro usuário/operação ou payload diferente. Um conflito enquanto o registro está `pending` retorna HTTP 409, evitando que uma segunda requisição com a mesma chave chame novamente o serviço de blockchain.
- A proteção atual não recupera uma reserva `pending`: não há lease/expiração, estado de reconciliação, rotina de recuperação nem caminho de consulta do status Solana nessa reserva.
- No caminho atual do backend, o burn é construído/assinado, enviado e confirmado dentro de `SolanaBlockchainService`; só depois a rota recebe a assinatura e tenta gravar `transacoes_tokens` e concluir a reserva. Se o processo cair ou o banco falhar após a confirmação e antes dessa persistência, a reserva fica pendente sem assinatura, e retry recebe 409 indefinidamente. A operação pode ter sido executada, mas o backend perde a referência necessária para emitir o comprovante com segurança.
- O serviço trata `status.err` como falha quando há um status, mas não exige explicitamente que um status de confirmação exista; se a resposta não contiver status, ainda retorna a assinatura, e a rota responde `Confirmado`. O contrato novo deve exigir confirmação observada no commitment configurado antes de emitir sucesso.
- Embora `burn_tokens` receba `idempotency_key`, a implementação atual não a inclui na instrução nem na transação Solana. O programa Anchor também não registra uma chave de operação/PDA; portanto, a cadeia não oferece deduplicação por essa chave.
- A migration cria apenas os estados `pending`/`completed`, e campos para `tx_hash` e `resource_id`; a assinatura só é preenchida por `complete`, depois do insert de `transacoes_tokens`. Não há assinatura/transação preparada, block height, estado de falha ambígua ou metadados de reconciliação. O SQL local não comprova se a migration foi aplicada a algum ambiente.
- A rota tem um replay legado consultando `transacoes_tokens` antes da reserva, mas esse replay não valida que o registro encontrado seja `BURN` nem compara a quantidade do pedido com a quantidade gravada. O insert de unicidade recupera o registro existente pela chave sem verificar o tipo antes de usá-lo como resultado. `complete` também não confere se uma linha foi atualizada.
- Os testes existentes cobrem replay bem-sucedido sem duplicar linha, mas não simulam queda após envio/confirmação, falha no insert, reserva pendente antiga, operação com resultado desconhecido ou chave/payload divergente nesse intervalo.

**Desenho recomendado para a recuperação antes da implementação:**

1. Reservar a chave e validar usuário, operação e hash canônico do payload antes de qualquer efeito externo.
2. Separar “preparar/assinar” de “enviar”: construir a transação Solana e persistir na reserva, antes do broadcast, a assinatura esperada, o payload serializado já assinado e o `last_valid_block_height`. Esses dados não são a chave privada, mas o payload assinado deve ser protegido como dado operacional capaz de transmitir a operação enquanto válido.
3. Enviar somente a transação já persistida. Se o envio ou a confirmação tiver resultado ambíguo, consultar a assinatura na rede usando o histórico da transação. Enquanto o blockhash for válido, retransmitir apenas os mesmos bytes assinados, que conservam a mesma assinatura; não construir automaticamente outra transação para a mesma reserva.
4. Persistir o registro `BURN` e o estado `confirmed/completed` apenas após observar a confirmação no commitment configurado e verificar que não houve erro on-chain. Em caso de retry, validar usuário, operação, hash do payload e tipo/quantidade/hash da transação gravada antes de devolver o mesmo comprovante.
5. Se o blockhash expirar e a rede não permitir concluir com confiança se a transação foi executada, manter a operação bloqueada em `needs_reconciliation`, sem novo burn e sem comprovante de sucesso. Um operador deve consultar o histórico da assinatura em RPC confiável e reconciliar o resultado; se a ausência não puder ser provada, não reenviar uma transação nova automaticamente.
6. Usar estados explícitos, no mínimo `reserved`, `prepared`, `submitted`, `confirmed`, `failed` e `needs_reconciliation`, com timestamps e transições condicionais atômicas. Falha comprovadamente anterior ao broadcast pode ser repetida segundo política explícita; timeout/RPC indisponível não deve ser classificado como falha definitiva.
7. Considerar proteção on-chain por identificador de operação/PDA como endurecimento adicional para deduplicar mesmo se, no futuro, uma transação tiver de ser reconstruída. Isso exige mudar e redeployar o programa Anchor; não é coberto pela proposta mínima de persistir e retransmitir a mesma transação assinada.

**Limite de garantia:** essa abordagem evita criar automaticamente uma segunda transação quando o resultado da primeira é ambíguo, mas pode exigir intervenção manual após expiração/limites de histórico RPC. Não prometer “exactly once” absoluto sem deduplicação on-chain e reconciliação testada.

### Quinta-feira — 01/10 — registro pendente

**Registro:** não há confirmação de atividades ou entregas de projeto para esta data. As tarefas planejadas não serão marcadas como realizadas sem evidência.

**Estado:** sem relatório de trabalho confirmado.

### Sexta-feira — 02/10 — descanso

**Registro da fundadora:** dia de descanso; nenhuma atividade ou entrega de projeto.

### Sábado — 03/10 — retomada acelerada e correções seguras

**Objetivo:** avançar nas correções de idempotência com testes locais, sem consumir quota desconhecida nem arriscar transações ou dados remotos.

- [ ] Verificar o painel de uso/quota do Supabase e identificar o projeto/ambiente; não executar testes remotos antes de saber a situação.
- [ ] Comparar alternativas de banco de baixo custo/gratuitas considerando Auth, PostgreSQL/PostgREST, RLS, migrations, limites e esforço de migração; não decidir apenas pelo rótulo “grátis”.
- [x] Corrigir o replay para validar usuário, operação e payload também quando já existe reserva; validar usuário, tipo e quantidade para transações legadas.
- [x] Adicionar testes unitários isolados para as validações de replay/reserva e chamadas diretas às rotas com mocks, sem conectar ao Supabase ou Solana.
- [x] Implementar preparação/persistência local da transação assinada e fluxo mockado de recuperação; confirmação em rede real permanece para depois da validação de ambiente.
- [ ] Depois de confirmar ambiente de teste, validar em ambiente online isolado os estados e a reconciliação de operação on-chain ambígua.
- [ ] Preservar as alterações que já estavam no worktree e separar o que for feito nesta etapa.

**Entrega esperada:** correção verificável com testes locais e decisão informada sobre ambiente de dados; operações reais ficam bloqueadas até confirmar configuração, quota e autorização.

### Domingo — 04/10 — recuperação e contrato do burn

**Objetivo:** fechar estados seguros para resultados confirmados, falhos e ambíguos; continuar as correções de idempotência sem integração remota.

- [x] Implementar e testar replay com a mesma chave e payload, além de conflitos por usuário/operação/payload.
- [x] Definir transições de recuperação sem permitir que retry ambíguo crie uma nova transação.
- [x] Corrigir o caminho de mint que podia deixar descarte `Validado` sem transação após falha do mint: grava agora como `Pendente` e só promove para `Validado` após o mint e seu registro.
- [x] Separar preparação, persistência e envio da transação assinada; a lógica foi validada localmente com RPC simulado (validação real continua pendente).
- [x] Não aplicar migration remota sem ambiente de teste isolado confirmado.

**Entrega esperada:** contrato de estados e testes locais; não afirmar recuperação on-chain completa antes de validar.

### Segunda-feira — 05/10 — interface do recibo demonstrativo

**Objetivo:** remover a dependência visual e funcional da Coelba e apresentar um comprovante honesto.

- [ ] Atualizar o formulário para quantidade de GT e confirmação informada.
- [ ] Criar/ajustar o recibo com assinatura, quantidade, data e rede somente quando a API puder comprová-las.
- [ ] Exibir aviso de demonstração, sem valor comercial, desconto ou certificação ambiental.
- [ ] Atualizar modelos Dart, estados de erro e idempotência no cliente.
- [ ] Verificar loading, falha, pendência e sucesso sem simular confirmação on-chain.

**Entrega esperada:** fluxo visual sem Coelba, ligado a respostas mockadas/locais até existir integração segura.

### Terça-feira — 06/10 — ambiente e testes determinísticos

**Objetivo:** validar regras sem consumir quota remota nem tocar em contas reais.

- [ ] Conferir o painel de uso do Supabase com a fundadora ou usar apenas os dados que ela fornecer; não pedir nem registrar credenciais.
- [ ] Decidir entre continuar com Supabase para o hackathon ou migrar após comparar custo total e esforço. SQLite/local PostgreSQL podem servir para testes, mas não substituem automaticamente Auth, RLS e Storage.
- [ ] Cobrir saldo, replay, payload incompatível, reserva pendente e falhas simuladas com mocks.
- [ ] Aplicar migration somente em banco isolado e após revisar grants/RLS.

**Entrega esperada:** testes offline repetíveis e decisão explícita sobre o banco.

### Quarta-feira — 07/10 — integração e regressão

**Objetivo:** verificar o fluxo no ambiente confirmado como seguro e registrar o que é demonstrável.

- [ ] Rodar testes backend relevantes e `compileall`.
- [ ] Rodar `flutter analyze` e build para a plataforma de demo.
- [ ] Rodar testes Anchor/TypeScript e `cargo check` se o ambiente permitir.
- [ ] Executar fluxo mockado end-to-end; Devnet é opcional e depende de configuração, saldo e autorização confirmados.
- [ ] Conferir login, upload, geofence, mint, saldo, burn e recibo; registrar pass/fail/não executado com precisão.

**Entrega esperada:** relatório de regressão e lista objetiva do que está demonstrável.

### Quinta-feira — 08/10 — documentação, narrativa e gravação

**Objetivo:** fazer materiais públicos dizerem exatamente o que o sistema entrega.

- [ ] Atualizar README, SPEC e plano original: status, resgate demonstrativo, GT sem valor econômico declarado, limitações de GPS/peso.
- [ ] Corrigir contagem e descrição da suíte de testes conforme execução verificada.
- [ ] Escrever roteiro de demo com passos e plano de contingência.
- [ ] Gravar vídeo da jornada real, mostrando a rede usada e aviso de demo.
- [ ] Não mostrar segredos, dados pessoais, telas de configuração ou credenciais.

**Entrega esperada:** documentos alinhados e primeira gravação reproduzível.

### Sexta-feira — 09/10 — ensaio e submissão preparada

**Objetivo:** reduzir risco operacional e preparar envio com antecedência.

- [ ] Fazer dois ensaios de ponta a ponta nas condições da apresentação.
- [ ] Verificar câmera, conexão, login, ecoponto, RPC, assinatura e links públicos.
- [ ] Preparar cópia/local do vídeo e screenshots.
- [ ] Conferir formulário e critérios diretamente no portal oficial.
- [ ] Revisar todas as alegações do pitch e marcar limitações.
- [ ] Congelar features; somente corrigir bloqueadores.

**Entrega esperada:** submissão pronta para enviar, links testados e plano de contingência.

### Sábado — 10/10 — submissão

**Objetivo:** enviar antes do cutoff oficial e guardar evidência.

- [ ] Confirmar hora/fuso do prazo no portal.
- [ ] Enviar com margem, sem deixar upload para os minutos finais.
- [ ] Guardar confirmação/recibo da submissão e URL publicada.
- [ ] Não iniciar mudanças de código após congelamento, salvo erro impeditivo e com novo teste.

**Entrega esperada:** submissão confirmada e registro do horário/link.

## Diário de trabalho

O relatório de cada dia será fechado quando a fundadora disser que encerrou o trabalho do dia. Antes disso, o registro permanece parcial e pode receber atualizações.

### Segunda-feira — 28/09/2026 — relatório concluído

**Objetivo do dia:** avaliar a proposta de IA de visão, decidir o fluxo de resgate e iniciar planejamento diário da adaptação.

**Atividades realizadas nesta sessão**

- Revisada a proposta externa de adicionar Gemini 2.5 Flash-Lite ao fluxo de descarte.
- A proposta de Gemini foi analisada somente para avaliar a possibilidade; a fundadora decidiu não fazer essa alteração e seguir com o plano da Opção 1.
- Comparada a proposta com o fluxo implementado do app e backend: a foto é carregada no Supabase Storage pelo app e o backend recebe `foto_url`; não recebe bytes diretamente.
- Identificada necessidade de alteração no contrato app/API e no tratamento de `422` caso a análise visual seja incorporada.
- Avaliados riscos de URL arbitrária, política fail-open, confiança produzida pelo modelo, cotas variáveis e tratamento de imagens pessoais. A documentação oficial consultada indica que limites dependem do projeto/modelo e devem ser verificados na conta; a cota alegada de 1.000/dia não foi confirmada para a conta da fundadora.
- Esclarecido que GT significa Green Token, token experimental de recompensa do projeto, não moeda, dinheiro ou stablecoin.
- A fundadora escolheu a **Opção 1**: queimar GT e emitir comprovante digital demonstrativo, sem depender da Coelba.
- Iniciado o cronograma diário de 28/09 a 10/10.

**Entregas/documentos**

- Decisão da Opção 1 registrada em `FICHA_TECNICA_E_PLANO_DE_ACAO_HACKATHON.md` e `PLANO_DE_ADAPTACAO_HACKATHON_2026.md`.
- Este diário e plano diário preparado.

**Código alterado hoje:** não foi feita implementação da nova opção de resgate nem integração Gemini nesta sessão. Há alterações de backend anteriores ainda presentes no worktree; elas não devem ser confundidas com trabalho executado hoje.

**Validação:** conteúdo dos documentos revisado; não foi executado teste novo de código nesta sessão.

**Pendências**

- Confirmar no portal Colosseum horário/fuso e critérios finais da submissão.
- Especificar o contrato do comprovante e a persistência/reconciliação do burn.
- Confirmar ambiente de teste e estado das migrations.
- Nenhuma implementação de Gemini está planejada. A análise foi apenas uma avaliação de viabilidade solicitada pela fundadora.

**Estado do dia:** concluído. A fundadora encerrou o trabalho de 28/09.

**Próximo passo:** em 30/09, conferir os requisitos oficiais do hackathon e detalhar o contrato e a experiência do comprovante demonstrativo antes de implementar.

### Terça-feira — 29/09/2026 — descanso

**Registro da fundadora:** dia de descanso; não trabalhou no projeto.

**Atividades/entregas:** nenhuma.

**Estado:** descanso; sem tarefas consideradas concluídas.

### Quarta-feira — 30/09/2026 — relatório parcial

**Objetivo do dia:** retomar após o descanso, concluir o desenho do contrato do comprovante e preparar a implementação com entendimento do fluxo existente.

**Atividades realizadas**

- Registrado 29/09 como descanso, sem atribuir entregas ou progresso técnico àquele dia.
- Revistos a tela Flutter de resgate, modelos de request/response, mapeamento de erros do app, rota FastAPI, serviço de idempotência e armazenamento local da chave.
- Confirmado que o fluxo de resgate atual ainda exige `instalacao_coelba` no app/API, atualiza esse dado no perfil e apresenta texto de desconto; essa experiência precisa ser removida para a Opção 1.
- Confirmado que a transação BURN já guarda quantidade, assinatura, user ID e horário em `transacoes_tokens`; a resposta de API atual não inclui rede explicitamente configurada e ainda modela a instalação Coelba.
- Revisados o código da reserva e sua migration, as rotas de mint/burn, o envio e confirmação Solana, o handler Anchor `burn_tokens` e os testes de replay existentes.
- Confirmado que a reserva bloqueia duplicação concorrente com a mesma chave, mas não recupera `pending`: após falha ambígua, uma nova tentativa retorna 409 e não existe reconciliador.
- Identificado o intervalo crítico: o backend só recebe/persiste a assinatura depois do envio e da confirmação. Se o processo ou o banco falhar antes da gravação da assinatura, a Solana pode ter executado o burn e o backend não consegue associar com segurança essa execução à reserva.
- Identificado que a checagem da resposta Solana só rejeita `status.err` quando existe status; não há verificação explícita de status de confirmação presente antes de a rota declarar `Confirmado`.
- Confirmado que a chave é passada ao método `burn_tokens`, mas não é incorporada na transação nem usada pelo programa Anchor; o on-chain não oferece deduplicação por chave de idempotência.
- Identificado que o replay atual por `transacoes_tokens` precisa validar `tipo == BURN` e quantidade original; a gravação de uma transação concorrente deve conferir o tipo antes de tratá-la como resultado da operação.
- Confirmado que os testes atuais validam somente replays bem-sucedidos; não exercitam crash/falha entre confirmação Solana, insert da transação e conclusão da reserva.
- Definido como desenho recomendado preparar e assinar a transação, persistir assinatura e bytes assinados mais `last_valid_block_height` antes do broadcast; em resultado ambíguo, consultar a mesma assinatura e, enquanto válida, retransmitir apenas os mesmos bytes. Não assinar uma transação nova automaticamente.
- Definidos os estados desejados `reserved`, `prepared`, `submitted`, `confirmed`, `failed` e `needs_reconciliation`; quando expirar o blockhash sem prova conclusiva, bloquear retry e fazer reconciliação operacional, sem mostrar sucesso nem gerar novo burn.
- Registrado como endurecimento futuro a deduplicação on-chain por chave de operação/PDA, que exigiria alterar/redeployar o Anchor e não é parte automática do escopo mínimo.
- Definido contrato provisório do comprovante: ID da transação, quantidade GT queimada, estado confirmado, hash/assinatura, rede explicitamente configurada e timestamp. A referência a descarte será omitida, a menos que a associação esteja persistida e testada.
- Revisadas separadamente as alterações de backend e a migration já presentes no worktree, antes de iniciar novas mudanças.
- Identificado que os fast paths de replay em `/descartes` e `/resgates` consultam `transacoes_tokens` antes de `reserve` e devolvem a linha sem conferir operação, quantidade ou hash do payload. Assim, a validação mais forte implementada em `reserve` é ignorada nos replays com linha já gravada; em casos de legado/conflito, também pode ser devolvida uma linha do tipo oposto.
- Identificado que a migration concede acesso a `service_role`, mas não ativa RLS nem revoga explicitamente grants de `anon`/`authenticated`; permissões efetivas/default privileges do Supabase precisam ser verificadas e restringidas antes de aplicar.
- Identificado que `complete` não verifica se a atualização encontrou exatamente uma reserva; no mint, o descarte é marcado `Validado` antes do mint e pode permanecer sem transação/token se a chamada falhar. A reserva então fica pendente e bloqueia retry.
- Avaliadas positivamente as validações adicionadas para limites/valores finitos de coordenadas e peso, e a validação de chave Solana on-curve no perfil; os schemas ainda aceitam strings compostas apenas por espaços, aspecto secundário para endurecer.
- Mantida fora do escopo a IA Gemini, que foi analisada apenas quanto à viabilidade.
- A tentativa anterior de verificar o portal/API autenticada do Colosseum recebeu 401; por isso as regras oficiais de submissão seguem pendentes de confirmação.

**Entregas/documentos:** atualização deste cronograma/diário, registro do baseline técnico da idempotência e definição inicial da resposta/UX do comprovante.

**Código alterado nesta sessão:** nenhum. As alterações de backend que já estavam no worktree são anteriores e continuam pendentes de revisão/testes; não foram tratadas como parte do trabalho de hoje.

**Validação:** revisão estática do diff preexistente de schemas, auth, rotas de mint/burn, serviço de idempotência, migration SQL, testes existentes e handler Anchor. Nenhum teste foi executado nem migration aplicada nesta sessão; a suíte E2E existente usa Supabase e Solana reais, portanto não foi executada durante esta revisão.

**Pendências**

- Confirmar prazo, fuso e requisitos oficiais do hackathon no portal.
- Confirmar ambiente Supabase e rede Solana efetivamente usados; o `.env.example` informa Devnet, mas isso não prova a configuração ativa.
- Confirmar a rede configurada para demo antes de expor explorer link no recibo.
- Corrigir/verificar replay por payload/operação, permissões da tabela da migration e tratamento de descarte sem mint antes de ampliar a idempotência.
- Aprovar/ajustar o desenho de recuperação antes de implementar a migration e o serviço de preparação/reconciliação.
- Verificar consumo e limites do plano Supabase; a fundadora não sabe se a cota gratuita já foi excedida e prefere considerar alternativas antes de testes remotos.
- Fechar o relatório de 30/09 somente quando a fundadora disser que encerrou o trabalho de hoje.

**Próximo passo registrado em 30/09:** verificar quota/ambiente do Supabase e comparar alternativas de banco antes de executar testes remotos ou aplicar migrations.

## Modelo para fechar próximos dias

Ao encerrar cada dia, registrar:

- **Objetivo planejado**
- **Atividades efetivamente realizadas**
- **Entregas e arquivos alterados**
- **Testes executados e resultados**
- **Bloqueios / decisões pendentes**
- **O que não foi concluído e por quê**
- **Próximo passo**
- **Estado:** concluído, parcial ou bloqueado

### Sábado — 03/10/2026 — relatório parcial

**Objetivo do dia:** retomar o projeto, acelerar as correções de idempotência e manter os testes independentes de Supabase e Solana remotos.

**Registro de datas**

- 01/10: não há relato confirmado de trabalho; nenhuma entrega foi atribuída.
- 02/10: a fundadora informou que descansou; nenhuma atividade ou entrega de projeto.
- 03/10: retomada do trabalho.

**Atividades realizadas**

- Reorganizado o cronograma restante até 10/10, removendo datas duplicadas e ajustando escopo para priorizar correções, testes offline, comprovante e regressão.
- Adicionado `get_existing` ao serviço de idempotência para validar proprietário, operação e hash do payload antes de retornar reservas completas; reserva `pending` permanece em conflito e dados incompletos não são tratados como sucesso.
- Adicionada validação das transações legadas por usuário, tipo e quantidade, aplicada aos caminhos de replay das rotas `/descartes` e `/resgates`.
- Quando uma transação legada válida não tinha reserva correspondente, o fluxo cria/conclui uma reserva para vincular aquela chave ao hash do payload recebido; não foi possível comprovar o payload histórico original que não estava armazenado.
- No fluxo de burn, retry de uma reserva `pending` agora tenta recuperar somente se já existir em `transacoes_tokens` um registro correspondente com mesmo usuário, tipo `BURN` e quantidade; nesse caso conclui a reserva e devolve a assinatura existente. Sem esse registro, retorna conflito explícito e não chama a Solana.
- Adicionados testes para os dois resultados de uma reserva pendente: recuperar burn já persistido no banco ou bloquear com conflito quando a transação ainda não foi registrada.
- Refatorado o serviço Solana para preparar e assinar uma transação de burn separadamente do broadcast. A preparação devolve assinatura, bytes assinados em Base64 e `last_valid_block_height`; a rota persiste esses dados antes de enviar a transação.
- Implementado envio de transação preparada: primeiro consulta o status da mesma assinatura; se ainda não houver status e o blockhash continuar válido, retransmite exatamente os mesmos bytes assinados; exige status sem erro no commitment configurado antes de devolver sucesso.
- Resultado temporariamente desconhecido produz HTTP 503 com orientação de repetir usando a mesma chave. Se o blockhash expirou e o histórico RPC não comprova o resultado, a reserva muda para `needs_reconciliation`, a API responde conflito e não gera nova transação.
- Falha on-chain comprovada é registrada como `failed`, limpa os bytes assinados da reserva e retorna erro sem afirmar burn concluído; operação com o mesmo idempotency key não segue para novo envio.
- Após o insert do burn em `transacoes_tokens`, o fluxo conclui a reserva e remove os bytes assinados da reserva. Em caso de falha do insert ou da conclusão, os bytes permanecem disponíveis para retry com a mesma assinatura.
- Criada a migration versionada `migrations/fase6_signed_transaction_recovery.sql` para os dados da transação assinada, block height, erro/estado e controle de acesso. Ela depende da migration Fase 5 e permanece local, sem aplicação em banco.
- Criados testes unitários para assinatura/serialização local, verificação de assinatura, confirmação e erro on-chain simulados, retransmissão idêntica, expiração ambígua, persistência antes do broadcast, retry após transação preparada e bloqueio de reconciliação.
- `complete` agora solicita a representação da linha atualizada e falha explicitamente se a reserva não existir.
- Migration `fase5_idempotency_reservations.sql` agora habilita RLS e revoga acesso direto de `anon` e `authenticated`, mantendo grant para `service_role`. Migration não foi aplicada a nenhum banco.
- Criados testes isolados em `soteropolis-backend/unit_tests/test_idempotency_unit.py` e `test_routes_replay_unit.py`; essa pasta não carrega o `conftest.py` que faz login e leitura no Supabase real. As rotas são chamadas diretamente com dados falsos; não há chamadas HTTP ao Supabase ou à Solana.

**Arquivos alterados nesta sessão**

- `soteropolis-backend/services/idempotency.py`
- `soteropolis-backend/services/blockchain.py`
- `soteropolis-backend/models/schemas.py` (rejeição de quantidade não finita em resgate)
- `soteropolis-backend/routers/resgates.py`
- `migrations/fase5_idempotency_reservations.sql`
- `migrations/fase6_signed_transaction_recovery.sql` (novo)
- `soteropolis-backend/unit_tests/test_idempotency_unit.py` (novo)
- `soteropolis-backend/unit_tests/test_routes_replay_unit.py` (novo)
- `soteropolis-backend/unit_tests/test_blockchain_recovery_unit.py` (novo)
- `DIARIO_E_PLANO_DIARIO_HACKATHON.md`

**Validação**

- `python -m pytest unit_tests -q` (executado em `soteropolis-backend`): **32 passaram**, incluindo testes do serviço com RPC simulado e chamadas diretas às rotas com mocks; 4 avisos de depreciação vieram das dependências FastAPI/Starlette.
- `python -m compileall -q` nos módulos Python alterados: passou.
- `git diff --check`: passou.
- Não executados testes E2E; não foram acessados Supabase, painel de quota ou Solana.

**Limitações e pendências**

- Os testes de rota chamam as funções diretamente com clientes falsos; ainda não exercitam o fluxo ASGI HTTP completo nem a corrida real no banco.
- O payload original de transações antigas não pode ser reconstruído se nunca foi persistido; no primeiro replay legado, a validação possível é usuário/operação/quantidade e o payload atual passa a ser associado à reserva.
- A persistência prévia de transação assinada e a recuperação via mesma assinatura foram implementadas no código, mas ainda não foram validadas contra RPC/Supabase reais.
- O caso de blockhash expirado sem evidência RPC continua exigindo reconciliação manual; não há endpoint/admin UI para reconciliar, e nenhum sucesso é emitido nesse estado.
- As migrations Fase 5/6 estão apenas em arquivos SQL locais; permissões efetivas e estado aplicado no Supabase continuam desconhecidos.
- A fundadora ainda precisa verificar a quota no painel; nenhuma migração de banco foi decidida.

**Próximo passo:** revisar integralmente o diff desta etapa e validar a aplicação das migrations/configuração de ambiente com a fundadora amanhã. Só após confirmar quota e ambiente isolado realizar consulta RPC controlada; nunca usar o Supabase remoto compartilhado para testes destrutivos sem autorização.

**Estado:** parcial; o dia permanece aberto até a fundadora informar que encerrou.

### Domingo — 04/10/2026 — relatório parcial

**Objetivo do dia:** retomar o trabalho, reforçar a consistência do ciclo de descarte/mint e validar localmente os estados de burn sem acessar serviços remotos.

**Atividades realizadas**

- Retomado o trabalho em 04/10; mantido o plano de não acessar Supabase/Solana reais sem confirmação do ambiente e quota.
- A fundadora informou que o painel Supabase Free diz não incluir backups agendados e compartilhou um dump SQL de contexto. No trecho enviado, `transacoes_tokens.idempotency_key` existe, mas `public.idempotency_operations` não aparece. Como o próprio dump avisa que é apenas contexto, isso é evidência indicativa, não confirmação direta do schema completo/atual.
- Por haver dados de usuários no schema e não haver backup agendado incluído no plano Free, nenhuma migration será aplicada ao projeto atual até confirmarmos um ambiente isolado ou uma estratégia de exportação/restauração testada.
- As rotas alteradas dependem de `public.idempotency_operations`; se essa tabela realmente estiver ausente no projeto configurado, as chamadas ao banco falharão. Não executar o novo fluxo contra esse Supabase antes de verificar a tabela em ambiente controlado.
- A fundadora informou que não consegue criar outro projeto Supabase neste momento. Diagnóstico local: Docker está instalado; Supabase CLI e configuração local `supabase/config.toml` não estão presentes. Supabase local via Docker é a alternativa isolada em avaliação; nenhum container, instalação ou conexão remota foi iniciada.
- A CLI Supabase foi executada via `npx` (versão 2.119.0, sem alterar manifestos do repositório), mas `docker info` falhou porque o Docker Desktop Linux Engine não está acessível (`dockerDesktopLinuxEngine` pipe ausente). O ambiente local ainda não foi iniciado; é necessário iniciar o Docker Desktop/engine antes de `supabase start`.
- Corrigido o ciclo de descarte para persistir inicialmente como `Pendente`; o status só muda para `Validado` depois de a chamada de mint retornar e a transação MINT ficar registrada.
- A atualização do status verifica que uma linha de descarte foi efetivamente alterada; se não houver atualização, o backend gera erro explícito em vez de afirmar persistência concluída.
- Ampliados os testes offline das rotas para cobrir tanto mint bem-sucedido, com transação registrada antes da promoção para `Validado`, quanto falha simulada de mint, que deixa o descarte `Pendente`.
- Revisados também os testes já adicionados para persistência da transação assinada antes do broadcast, retry dos mesmos bytes, outcomes desconhecidos, erro on-chain e reconciliação pendente.

**Arquivos alterados hoje**

- `soteropolis-backend/routers/descartes.py`
- `soteropolis-backend/unit_tests/test_routes_replay_unit.py`
- Este diário de trabalho.

**Validação**

- `python -m pytest unit_tests -q` (em `soteropolis-backend`): **34 passaram**, com 4 avisos de depreciação em dependências FastAPI/Starlette.
- `python -m compileall -q` nos módulos Python alterados: passou.
- `git diff --check`: passou.
- Não executados testes de integração; nenhum acesso ao Supabase, painel de quota ou Solana.

**Limitações e pendências**

- A promoção para `Pendente` evita declarar um descarte como validado antes do mint; se o mint for confirmado mas houver falha posterior ao persistir `transacoes_tokens`, a reserva continua sem recuperação do MINT. O caminho robusto de transação assinada foi implementado apenas para BURN nesta etapa.
- A rota e o banco reais ainda não foram testados; migrations Fase 5/6 continuam sem aplicação confirmada.
- Nenhum endpoint de reconciliação administrativa foi criado. Se a assinatura expirar sem evidência suficiente na RPC, a reserva fica bloqueada em `needs_reconciliation`.
- O relatório de 04/10 permanece parcial até a fundadora encerrar o trabalho do dia.

**Próximo passo:** revisar o diff completo; em seguida, confirmar quota e ambiente isolado do Supabase com a fundadora e só então validar migrations e uma consulta/transação controlada na rede explicitamente configurada.

**Estado:** parcial; o dia permanece aberto.

#### Continuação em 04/10 — Supabase local

- A fundadora iniciou o Docker Desktop. A engine respondeu e o Supabase CLI 2.119.0 foi usado sem vincular um projeto remoto (`linked_project: null`).
- A stack local foi iniciada com os serviços necessários ao banco, Auth e REST. Studio, Storage, Realtime e outros serviços opcionais foram excluídos para reduzir o escopo; portanto, esta não é uma stack local completa.
- Inicialmente, o schema e as migrations Fase 5/6 foram aplicados diretamente ao Postgres local. Na continuação, esses mesmos scripts foram organizados como migrations versionadas e reaplicados por reset local.
- O `supabase/config.toml` foi ajustado para manter a API ativa, executar migrations e não tentar carregar `supabase/seed.sql`, arquivo que não existe no projeto.
- Validação repetida: `python -m pytest unit_tests -q` — **34 passaram**, com os mesmos 4 avisos de depreciação; `git diff --check` passou.
- Nenhum segredo remoto foi configurado ou exibido. Não houve consulta ao painel de quota, acesso ao Supabase hospedado ou transação Solana.

#### Continuação em 04/10 — migrations reproduzíveis e integração local

- Criadas migrations Supabase versionadas para o baseline de `database_schema.sql`, Fase 5 e Fase 6, nesta ordem: `20261004190000`, `20261004190100` e `20261004190200`.
- Foi encontrado e corrigido um estado de configuração em que `db.migrations.enabled` estava `false`; o primeiro reset havia completado sem criar as tabelas. O reset foi repetido com migrations explicitamente habilitadas e `--local --no-seed`.
- O reset limpo aplicou as três migrations; `supabase migration list --local` e `supabase_migrations.schema_migrations` confirmaram as três versões.
- Verificado que as tabelas base e `idempotency_operations` existem, com RLS habilitada; a tabela de idempotência contém as 15 colunas previstas e privilégios para `service_role`.
- Feito smoke test pelo cliente Python do backend, recebendo as credenciais da stack local apenas em variáveis de ambiente temporárias do processo. A consulta ao REST local para `idempotency_operations` retornou zero linhas. Nenhum arquivo `.env` foi criado e nenhum segredo foi impresso.
- A API Auth local respondeu HTTP 200. O projeto continua sem vínculo remoto (`linked_project: null`).
- Reexecutados `python -m pytest unit_tests -q`: **34 passaram**, com 4 avisos de depreciação de FastAPI/Starlette. `git diff --check` também passou.
- Executado teste de integração real da rota `POST /descartes` via FastAPI TestClient, apontando o cliente Supabase do backend para a stack local e `BLOCKCHAIN_MODE=mock`.
- O teste criou usuário de Auth local (confirmando o trigger de perfil), vinculou carteira de teste e criou ecoponto temporário. A rota aceitou descarte dentro do geofence, persistiu a transação MINT simulada e marcou o descarte como `Validado`.
- Repetir a requisição com a mesma `Idempotency-Key` retornou o mesmo descarte e `tx_hash`; confirmou-se apenas uma transação, uma reserva `completed` e um descarte persistidos durante o teste.
- Os dados temporários foram removidos; consulta posterior confirmou zero usuários, ecopontos e transações do teste. Nenhuma rede Solana foi acessada.

**Estado atualizado:** sequência reproduzível das migrations locais e conexão do cliente backend validadas. Permanecem pendentes a conferência da quota do projeto hospedado e da rede Solana; não houve operação remota nem transação on-chain. A stack local continua mínima, sem Studio/Storage/Realtime e serviços opcionais.

#### Continuação em 04/10 — ecoponto fictício para demonstração local

- Decisão da fundadora: como não haverá teste presencial nem levantamento de todos os pontos, separar claramente fixture de teste dos dados reais e não alegar cobertura de Salvador.
- Adicionado `supabase/seed.sql`, carregado somente pela configuração local Supabase. Ele cria um registro ativo nomeado `PONTO FICTICIO - DEMO LOCAL (GPS SIMULADO)` em coordenadas sintéticas `(0, 0)`, com UUID reservado para a fixture; o seed é repetível via upsert.
- Ativado o carregamento do seed na configuração local. Nenhum registro foi inserido no Supabase hospedado.
- Teste pela API FastAPI local: `GET /ecopontos` listou exatamente o ponto fictício. Com autenticação Supabase local, `BLOCKCHAIN_MODE=mock` e coordenadas de requisição simuladas, `POST /descartes` aceitou posições calculadas a 49 m e 50 m, e rejeitou 51 m; somente os dois casos aceitos geraram mint simulado.
- O teste criou temporariamente um usuário de Auth local e seus dados associados; o usuário foi apagado e confirmou-se zero usuários temporários restantes. O ponto fictício permanece no banco local como fixture de demonstração.
- Reexecutados os testes unitários offline: **34 passaram**, com 4 avisos de depreciação em dependências FastAPI/Starlette. `git diff --check` passou.
- Limitação explicitada: foi testado o contrato da API com coordenadas simuladas, não a precisão de um aparelho/GPS nem a presença de um ecoponto real. A suíte validou o limite atual: 50 m exatos ainda são aceitos (a rejeição usa `distancia > tolerancia`).

**Plano de ação atualizado, por prioridade**

1. **Concluído hoje — fixture segura e teste do geofence:** manter o ponto fictício apenas no Supabase local, rodar requests simulados em ambos os lados do limite e preservar os testes unitários.
2. **Próxima prioridade — demo reproduzível no app:** verificar Auth, localização simulada, câmera e upload no emulador. A configuração local do bucket e da policy já foi testada via API/SDK, mas a jornada física da câmera no Flutter ainda depende de dispositivo ou emulador.
3. **Depois — revisar precisão/UX sem mudar regra às cegas:** tratar com clareza erro de GPS versus falha de conexão e registrar que 50 m é o limite funcional da demo, não um raio validado em campo; não aumentar a tolerância sem medições justificáveis.
4. **Após a fundadora enviar — conferir critérios oficiais do hackathon:** ajustar escopo e roteiro somente ao que as regras pedirem, sem afirmar que critérios foram confirmados antes de recebê-los.
5. **Por último — preparar narrativa e evidências:** dizer que o geofence foi testado com coordenadas simuladas e ponto explicitamente fictício; não alegar ecopontos reais, cobertura municipal, GPS inviolável ou antifraude comprovado. Nenhum dado fictício deve ser publicado no Supabase hospedado como ponto real.

**Estado:** implementação da fixture local e teste de limite concluídos; demo completa do app ainda depende de validação Flutter em emulador/dispositivo. Projeto remoto e rede Solana continuam fora do escopo desta etapa.

#### Continuação em 04/10 — Storage local e teste de upload

- Configurado o bucket local `descarte-fotos` como público para leitura por URL, limitado a 10 MiB e aos tipos JPEG/PNG/WebP/HEIC, conforme o contrato atual do app. Adicionada migration Supabase local `20261004190300_descarte_fotos_storage_policy.sql`, permitindo apenas INSERT autenticado sob o prefixo do próprio `auth.uid()`.
- A inicialização normal do Storage ficou sem healthcheck verde no tempo limite da CLI. Iniciado com `--ignore-health-check` e verificado separadamente: container ficou saudável e `/storage/v1/status` respondeu HTTP 200. O bucket foi confirmado no banco local.
- `supabase db reset --local --yes` aplicou as quatro migrations e o seed fictício, criou o bucket configurado e finalizou com sucesso.
- Teste de integração de Storage no Supabase local: upload JPEG autenticado no prefixo do próprio usuário funcionou; tentativa de upload em prefixo de outro usuário foi negada; URL pública retornou os mesmos bytes do arquivo. A URL foi aceita em `POST /descartes` e persistida junto do mint simulado.
- Dados temporários de Auth, descarte e arquivo foram removidos. Confirmado zero usuários e arquivos temporários restantes; o ponto fictício é o único registro de ecoponto na base local.
- `python -m pytest unit_tests -q`: **34 passaram**, 4 avisos de depreciação. `git diff --check` passou.
- `flutter analyze` completou e relatou um item `info` preexistente em `lib/services/api_client.dart:96` (`prefer_initializing_formals`). Não houve alteração Dart feita nesta etapa; o comando resolveu dependências e não deixou mudanças de app no worktree.
- `flutter devices` listou Windows e navegadores, mas `flutter emulators` não encontrou emuladores Android configurados. Portanto, câmera, localização do dispositivo e chamada Flutter do SDK Storage continuam sem teste visual/no aparelho.
- A fundadora escolheu continuar usando aparelho Android por USB; no momento da verificação, `adb devices -l` não detectou nenhum aparelho conectado, então essa parte aguarda conexão e depuração USB ativada.
- A inicialização do app também depende de valores compile-time de Supabase e Web3Auth; `SUPABASE_URL` e `SUPABASE_ANON_KEY` podem apontar para os endpoints locais, mas as credenciais do Web3Auth não foram configuradas nesta etapa.
- O app Android usa os endpoints locais por HTTP; antes de testar em aparelho real, validar acesso de rede local (por exemplo, `adb reverse`) e permitir cleartext apenas na configuração debug, nunca ampliar essa permissão para o build de release sem decisão de segurança.

#### Continuação — teste no Redmi A2 após conexão ADB

- O ADB reconheceu o aparelho Android 13 `23028RN4DG`; `flutter devices` listou o mesmo telefone como dispositivo Android.
- Criada configuração temporária ignorada pelo Git com a URL/chave pública **locais** do Supabase; URLs foram configuradas como `127.0.0.1` e encaminhadas ao aparelho com `adb reverse` para as portas 54321 (Supabase) e 8000 (FastAPI). Não foram usados endpoints ou credenciais remotas.
- Adicionado `android:usesCleartextTraffic="true"` somente em `android/app/src/debug/AndroidManifest.xml`, necessário para o app debug falar HTTP com serviços em loopback; o manifest principal/release não foi alterado.
- `flutter build apk --debug --dart-define-from-file=dart_define.local.json` foi concluído com sucesso. O primeiro build limpo levou cerca de 34 minutos e exibiu avisos de dependência Kotlin legado em `web3auth_flutter`, SDK XML mais novo e opções Java 8 depreciadas; nenhum erro de compilação.
- O APK foi instalado e iniciado no Redmi A2. A tela de login do Soterópolis Chain apareceu em primeiro plano; logs filtrados após reinício não mostraram erro do app.
- Não foi concluído login nem fluxo da câmera: os IDs de cliente/configuração do Web3Auth não existem/estão ausentes no projeto e não foram inventados. O bucket local, API e a policy já foram testados diretamente via SDK no host, mas a conectividade HTTP pelo próprio processo Android e uma captura/upload iniciado pelo Flutter ainda precisam de prova após configurar autenticação válida.
- `flutter doctor` ainda marca licenças Android como desconhecidas, embora o build debug e instalação tenham funcionado. `flutter analyze` mantém um aviso `info` preexistente em `lib/services/api_client.dart:96`.
- A configuração temporária local `soteropolis-app/dart_define.local.json` será removida ao final; nenhum arquivo `.env` ou chave de `service_role` foi gravado no app.

**Estado da validação no aparelho:** APK debug compila, instala e abre a tela de login. Não considerar autenticação, GPS real, câmera ou fluxo completo validados neste aparelho enquanto Web3Auth não estiver configurado. O fluxo de produto continua sem usar Supabase hospedado ou Solana real.
- Privacidade: como o bucket é público para compatibilidade com `getPublicUrl`, qualquer pessoa com a URL pode ler uma imagem. A regra de prefixo limita quem pode fazer upload, não quem consegue ler a URL; tratar fotos reais como conteúdo público até se projetar e testar outra estratégia.

**Próxima ação de maior prioridade:** providenciar/configurar um emulador Android ou dispositivo de teste e os valores de ambiente necessários, usando apenas as chaves locais; executar o fluxo Flutter de login, ponto fictício, câmera/localização simulada, upload e descarte com blockchain mock. Não compartilhar segredos no chat nem usar o Supabase hospedado. Em seguida, revisar a UX de erro de GPS e receber os critérios oficiais do hackathon antes de congelar a demo.

#### Relatório de encerramento — 04/10/2026

**Objetivo do trabalho:** avançar a validação local do Soterópolis Chain sem usar o Supabase hospedado ou executar transações Solana reais.

**Entregas e verificações concluídas hoje**

- Preparadas e verificadas migrations locais para o schema base e as Fases 5/6; aplicadas no Supabase local, sem vínculo com projeto remoto.
- Mantida uma fixture de ecoponto explicitamente fictícia em coordenadas sintéticas `(0, 0)`. A rota local foi testada com coordenadas simuladas: 49 m e 50 m aceitos, 51 m rejeitado. Isso não comprova coordenadas reais nem precisão de GPS em campo.
- Testada a jornada de API de descarte com `BLOCKCHAIN_MODE=mock`, incluindo idempotência: repetição da mesma chave devolveu o mesmo resultado sem duplicar transação. Dados temporários dos testes foram removidos.
- Testado o Storage local: upload autenticado na pasta do usuário aceito, upload na pasta de outro usuário recusado e URL pública conferida. A configuração de leitura pública significa que qualquer pessoa com a URL pode acessar a foto.
- Os **34 testes unitários do backend passaram**. O resultado incluiu quatro avisos de depreciação de dependências FastAPI/Starlette.
- No Redmi A2 (Android 13), o APK debug foi compilado, instalado e aberto na tela de login. `adb reverse` permanece configurado para as portas locais 54321 (Supabase) e 8000 (backend). A permissão HTTP foi limitada ao manifest debug.
- Verificações desta sessão confirmaram HTTP 200 para Auth local, Storage local e `/docs` do backend. O telefone continuou conectado por ADB e o app estava em execução na última verificação.
- `flutter analyze` terminou sem erros de análise e apontou somente um item informativo preexistente: `prefer_initializing_formals` em `soteropolis-app/lib/services/api_client.dart:96`.
- A configuração temporária `soteropolis-app/dart_define.local.json`, que continha valores locais e chave pública local, foi removida após o build.

**Não concluído / não alegar como validado**

- Não foi possível iniciar a caixa local de captura de e-mails (porta 54324 indisponível). Portanto, o link de autenticação por e-mail ainda não foi testado no celular. A tentativa de iniciar o serviço não resetou o banco nem alterou dados; a configuração local foi mantida conforme estava.
- Login completo, integração Web3Auth, carteira, GPS pelo Flutter, câmera e upload iniciado pelo app continuam pendentes. A configuração real do Web3Auth não existe ainda.
- Não houve acesso ao Supabase hospedado, aplicação remota de migrations, envio de e-mail real, uso de chave `service_role` no app ou transação Solana real.
- A troca futura para outro projeto Supabase ou outro provedor continua sendo uma possibilidade a avaliar; nenhuma decisão ou migração foi feita hoje.
- Os critérios oficiais da hackathon ainda precisam ser confirmados com as informações da fundadora.

**Pendências para amanhã**

1. Retomar a caixa local de e-mail e validar o link/callback no Redmi A2, sem modificar o Supabase hospedado.
2. Se a autenticação local puder ser validada, continuar com o que for possível da jornada no aparelho e registrar separadamente os bloqueios de Web3Auth.
3. Após os testes locais, decidir se é necessário avaliar outro projeto/provedor Supabase; não iniciar migração sem plano, autorização e validações necessárias.

**Estado do dia:** encerrado por decisão da fundadora. A validação de backend, banco, geofence simulado e Storage local tem evidências; a validação ponta a ponta no app permanece parcial.

#### Continuação em 05/10/2026 — autenticação local no Redmi A2

**Objetivo:** testar o e-mail de acesso e o callback do Supabase local no aparelho, sem tocar no Supabase hospedado.

**Concluído e verificado**

- Docker Desktop foi iniciado e a stack Supabase local foi recuperada usando o volume existente do Postgres. Não foram executados `db reset`, migrations ou seed durante a retomada; a fixture permaneceu no banco.
- A caixa de captura local Mailpit ficou disponível em `http://127.0.0.1:54324`. Auth, Storage e Mailpit responderam HTTP 200.
- Incluído `soteropolisapp://supabase-auth-callback` em `auth.additional_redirect_urls` na configuração Supabase local, que antes permitia apenas o redirect web padrão. O container Auth foi recriado para carregar a allowlist; os dados continuam no volume do Postgres.
- No Redmi A2, o app debug iniciou, enviou um magic link para endereço sintético `.test` através do SDK Flutter e recebeu o link no Mailpit local.
- Abrir o link mais recente no telefone entregou o callback `soteropolisapp://supabase-auth-callback` ao app. Os logs confirmaram o início de `Web3AuthFlutter.connectTo`; a interface exibiu a mensagem prevista de carteira não configurada. Isso valida o caminho local até a fronteira do Web3Auth, **não** uma sessão Web3Auth completa nem a criação/recuperação da carteira.
- Foram removidos os dois usuários sintéticos, seus perfis e as mensagens de teste. Verificação posterior confirmou zero contas/perfis de teste e zero mensagens `.test` na caixa local.
- O ponto fictício continuou sendo o único ecoponto local; o backend FastAPI serviu esse ponto e `/docs` após ser iniciado em `BLOCKCHAIN_MODE=mock`.
- `python -m pytest unit_tests -q`: **34 passaram**, com quatro avisos de depreciação em FastAPI/Starlette.
- A configuração temporária de defines não foi recriada nem embutida no repositório. O estado de sessão local do app foi limpo após o teste; o Redmi A2 ficou na tela de login e com `adb reverse` ativo para 54321/8000.

**Limites e observações**

- Uma tentativa intermediária usou um link antigo depois de iniciar outra tentativa de login e falhou na validação PKCE. Foi repetido o teste com um link novo, sem iniciar outra solicitação antes de abri-lo; essa execução chegou ao Web3Auth.
- Web3Auth continua sem Client ID/conexão custom configurados. Não se tentou contornar esse requisito; login completo, carteira, câmera, GPS do app e upload iniciado pelo app continuam pendentes.
- Nenhum e-mail foi enviado à internet, nenhuma chave `service_role` foi usada no app e nenhuma operação Solana real foi feita.
- O backend está ativo localmente em modo mock. A stack local preserva o banco. O container opcional Vector foi parado após entrar em reinício contínuo; os serviços essenciais (Postgres, Auth, REST/Kong, Storage e Mailpit) ficaram disponíveis.
- A troca para outro projeto Supabase ou outro provedor segue em aberto, sem decisão nem migração.

**Próximo passo:** escolher/configurar uma alternativa válida para a etapa Web3Auth ou decidir se a demonstração continuará explicitamente limitada até esse ponto. Depois, se houver autenticação completa, avançar câmera, localização e upload pelo Flutter; manter todos os testes na stack local.
