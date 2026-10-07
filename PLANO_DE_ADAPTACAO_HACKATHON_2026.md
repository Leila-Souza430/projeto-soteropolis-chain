# Plano de adaptação do Soterópolis Chain para o hackathon

**Data do plano:** 28/09/2026
**Prazo informado para submissão:** 10/10/2026
**Janela restante nesta data:** 12 dias corridos até a data informada; confirmar o horário e o fuso exatos no portal do hackathon.

## 1. Decisão executiva

Reposicionar o projeto como uma infraestrutura de **comprovantes digitais de descarte reciclável local**, começando por Salvador, com recompensas contabilizadas em Green Tokens na Solana.

O MVP não deve depender da Neoenergia Coelba, de outra concessionária ou de uma empresa parceira para completar a demonstração. O resgate pode virar uma experiência de demonstração autônoma — por exemplo, queimar GT e gerar um comprovante digital de impacto identificado explicitamente como **demo**, sem valor monetário e sem promessa de desconto real.

**Recomendação de escopo:** não adicionar IA de visão nesta reta final. Corrigir primeiro as alegações e os limites do fluxo existente, remover a dependência da Coelba, garantir um percurso de demonstração reproduzível e preparar uma submissão fiel ao que foi construído.

**Decisão da fundadora (28/09/2026): Opção 1 aprovada para planejamento.** O usuário queimará GT e receberá um comprovante demonstrativo. Isso ainda não autoriza implementação de benefício comercial ou certificado ambiental; o recibo provará a transação de burn e a referência interna registrada pelo sistema.

## 2. O que sabemos e o que ainda precisa ser confirmado

### Fatos observados no repositório

- O backend valida a distância entre as coordenadas recebidas e um Ecoponto cadastrado. Isso é uma validação de coordenadas informadas pelo cliente; não prova, por si só, que o GPS não foi falsificado.
- O app usa captura pela câmera, mas a foto é enviada ao Storage e a API recebe uma URL. Não há inspeção do conteúdo da foto no backend.
- O peso é informado pelo cliente e influencia a recompensa. Há um teto por descarte, mas isso não verifica o peso real.
- O fluxo de resgate e sua interface dependem de `instalacao_coelba`; a integração descrita no projeto é simulada, não um abatimento confirmado em conta.
- Os testes E2E atuais dependem de Supabase, usuário e dados remotos, além da integração Solana configurada. Não são uma suíte isolada que possa ser executada sem esses serviços.
- Existem alterações não commitadas, inclusive mudanças recentes de idempotência e uma migration nova. Elas precisam ser revisadas e testadas antes de serem consideradas parte estável do produto.

### Afirmações externas ainda não verificadas

- O PAT configurado para o agente de pesquisa do Colosseum foi recusado como inválido/expirado. Não foram obtidos resultados autenticados de projetos, vencedores ou portfólio do acelerador.
- A página pública do Colosseum acessível nesta sessão não exibiu as regras detalhadas da edição. Prazo, critérios, trilhas, exigências de vídeo e formato da submissão devem ser conferidos na conta/portal oficial antes de fechar o roteiro.
- Não afirmar que “a maioria dos projetos”, “os jurados” ou uma trilha específica exigem determinado formato sem uma regra oficial que sustente isso.

## 3. Avaliação da análise da outra IA

### O que está correto

- O projeto de referência analisado é de reciclagem, usa ICP e descreve tokens e NFTs associados a benefícios. Ele é um precedente conceitual útil, mas não deve ser copiado.
- No código dessa pasta, o formulário permite selecionar uma imagem, a localização é convertida em texto de cidade/país e a checagem com Gemini acontece no frontend.
- O prompt da checagem de imagem é permissivo e a implementação não demonstra que a IA verifica peso, autenticidade do descarte ou presença de material efetivamente reciclável.
- O backend do Soterópolis tem uma validação geográfica mais concreta: calcula distância até coordenadas de Ecoponto cadastradas, em vez de confiar apenas no rótulo de cidade enviado pelo usuário.
- Deixar uma chave de serviço no frontend é inseguro. Não usar nem reutilizar as credenciais que aparecem no projeto de referência; se forem credenciais ainda ativas, o responsável pelo projeto deve revogá-las.

### O que está exagerado ou incompleto

- “Câmera ao vivo + GPS + IA” não equivale automaticamente a antifraude forte. O cliente ainda pode tentar falsificar localização ou fotografar uma tela; a IA pode errar, ser contornada ou ficar indisponível.
- A vantagem do Soterópolis não deve ser descrita como “prova de que o descarte ocorreu”. A API compara coordenadas recebidas com um ponto cadastrado; não autentica o sensor GPS nem verifica a foto.
- O peso proporcional informado pelo usuário é uma fragilidade importante. O teto limita o valor máximo por chamada, mas não certifica o peso real.
- RLS, idempotência e testes são capacidades diferentes. O projeto tem RLS no Supabase e controles de idempotência, mas a suíte E2E depende de serviços e dados remotos; isso não comprova, por si só, uma avaliação adversarial abrangente.
- A IA de visão não é necessariamente a maior lacuna nem o melhor upgrade para o prazo. Ela acrescenta custo/quota, segredo de API, tratamento de imagens pessoais, latência, erros e uma dependência externa. Uma resposta “sim/não” de modelo não é atestado confiável de reciclagem.

### Conclusão sobre a recomendação de adicionar IA

**Não seguir como prioridade agora.** Se a IA for explorada depois, deve ser somente um sinal auxiliar, executado no servidor, com consentimento e tratamento adequado da imagem. Não deve, sozinha, liberar recompensa nem ser anunciada como camada antifraude comprovada.

## 4. Posicionamento e limites das promessas

### Frase de posicionamento proposta

> **Soterópolis transforma entregas em Ecopontos em comprovantes digitais auditáveis e recompensas em Green Tokens na Solana, começando por um piloto demonstrável em Salvador.**

Usar “auditável” para as transações e os registros associados; não usar “à prova de fraude”, “crédito EPR certificado”, “renda garantida” ou “desconto real” enquanto esses resultados não tiverem validação independente e parceiros operacionais.

### Separar explicitamente

- **Implementado:** app, backend, distância calculada até Ecoponto, emissão/queima de GT e registros conforme o estado efetivamente testado.
- **Demonstração:** recompensa/resgate sem parceiro, conta de luz ou valor monetário; indicar isso na interface, comprovante e vídeo.
- **Visão futura:** integração com cooperativas, comércio, concessionárias ou sistemas de responsabilidade estendida do produtor (EPR), após validação de regras, evidências e parceiros.

## 5. Escopo recomendado para a adaptação

### P0 — Confirmar submissão e congelar escopo

1. Conferir no portal oficial: prazo exato e fuso, critérios, trilha/categoria, elegibilidade, necessidade de Solana on-chain, campos do formulário, links e requisitos de vídeo.
2. Fixar o que estará funcional na demo; não iniciar migração de blockchain, internacionalização, integração empresarial ou marketplace real.
3. Registrar links verificáveis do repositório, contrato na Devnet, demo e transações que forem efetivamente testadas.

**Critério de saída:** checklist oficial da submissão preenchido e escopo sem dependência de terceiro.

### P1 — Fechar o fluxo demonstrável sem Coelba

1. Remover do fluxo de resgate a exigência de número de instalação Coelba.
2. Substituí-lo por uma ação autônoma: **resgatar GT por um comprovante/badge demonstrativo de impacto**. O recibo deve exibir a quantidade queimada, o identificador da transação e o aviso “Demonstração — não representa desconto ou benefício comercial”.
3. Evitar nomes, logotipos ou códigos que sugiram parceria real.
4. Manter as tabelas/campos históricos de instalação durante a entrega, se removê-los exigir uma migração arriscada; deixar de usá-los na nova jornada e documentar a limpeza como trabalho posterior.
5. Vincular descarte, transação e recibo na resposta/histórico da aplicação, sem alegar que a evidência fotográfica foi gravada on-chain se ela continuar no Storage/banco.

**Critério de saída:** uma pessoa consegue, na demo, obter GT por um descarte aceito e queimar GT para receber um comprovante claramente simulado, sem preencher dados da Coelba.

### P2 — Tornar o valor emitido mais defensável

1. Não recompensar peso autodeclarado como se fosse uma pesagem certificada.
2. Para a demo, preferir uma recompensa fixa por descarte validado ou valores definidos pelo servidor por categoria, com limites conservadores.
3. Se o peso informado continuar visível, rotulá-lo como estimativa do usuário e não usá-lo para alegar impacto ambiental medido.
4. Descrever a geolocalização como “distância calculada a partir das coordenadas enviadas pelo dispositivo”. Tratar QR estático ou GPS como sinal de presença, não como prova antifraude completa.
5. Opcional, somente se sobrar tempo e existir uma operação testável: autenticação adicional de presença no Ecoponto. Não depender de um QR estático como proteção contra replay.

**Critério de saída:** toda recompensa tem regra reproduzível no servidor e a interface explica o que foi medido, estimado ou simulado.

### P3 — Integridade transacional e testes seguros

1. Revisar as mudanças recentes de reserva de idempotência e sua migration antes de usá-las como garantia.
2. Definir recuperação para operações que ficam `pending` após falha. Uma reserva no banco bloqueia chamadas concorrentes, mas não torna atômicos o banco e uma transação Solana; uma falha depois do mint/burn ainda exige reconciliação.
3. Garantir que uma repetição da mesma chave e mesmo payload não emita/queime novamente; chave repetida com payload diferente deve ser rejeitada.
4. Ter testes automatizados sem escrever no Supabase de produção nem exigir saldo real de carteira compartilhada. Usar serviços simulados nos testes unitários e reservar a Devnet para uma verificação de integração controlada.
5. Aplicar migrations somente ao ambiente de desenvolvimento/teste até estarem verificadas.

**Critério de saída:** testes repetíveis documentados, sem alteração involuntária de dados remotos, e uma lista clara das falhas que ainda exigem reconciliação.

### P4 — Atualizar a narrativa e os materiais

1. Atualizar README, especificação e plano para separar MVP, simulação e visão futura.
2. Corrigir contagens de testes e status de integração para refletirem execuções reproduzíveis.
3. Explicar por que Solana é usada no fluxo atual com fatos observados e testados; não afirmar vantagens de desempenho/taxa sem medição ou fonte.
4. Produzir primeiro uma demo de ponta a ponta; depois, um pitch curto baseado nos critérios oficiais confirmados.
5. Incluir limitações em linguagem simples: peso estimado, coordenadas fornecidas pelo app, resgate simulado e Devnet sem valor financeiro.

## 6. Sequência de trabalho até 10/10

| Janela | Entrega | Regra de corte |
|---|---|---|
| 28–29 set. | Confirmar regras oficiais, baseline do que executa e decisões de escopo | Nenhuma afirmação de competição sem fonte |
| 29 set.–1 out. | Remover dependência Coelba da jornada e fechar contrato/UX do comprovante demo | Não criar marketplace nem parceiro fictício |
| 1–3 out. | Ajustar regra de recompensa, persistência e integridade de operações | Se recuperação de pending crescer, documentar limitação e priorizar não duplicar |
| 3–5 out. | Testes isolados, smoke test Devnet e execução completa do percurso | Não testar repetidamente contra dados compartilhados |
| 5–7 out. | Atualizar README, formulário, screenshots e gravar demo funcional | Mostrar somente comportamento reproduzido |
| 7–9 out. | Revisão final de links, transações, limitações e materiais | Congelar funcionalidades novas |
| 10 out. | Submeter antes do horário oficial de encerramento | Não deixar upload/formulário para o último minuto |

As janelas são uma proposta, não uma confirmação dos requisitos do hackathon. Reordenar assim que o portal oficial for conferido.

## 7. Fora de escopo antes da submissão

- IA como árbitro de validade da foto.
- Integração real com Coelba, comércio, cooperativa ou comprador de créditos EPR.
- Alegar créditos de reciclagem aceitos por reguladores/empresas.
- Migração do projeto de Solana para ICP ou cópia de implementação de terceiros.
- Internacionalização, múltiplas cidades com regras configuráveis completas ou marketplace de parceiros.
- Mainnet, salvo exigência oficial explícita.

## 8. Riscos que podem bloquear a entrega

| Risco | Tratamento |
|---|---|
| Regras oficiais ou cutoff diferem do informado | Confirmar no portal e submeter com margem |
| Acesso de pesquisa Colosseum não funciona | Regenerar/atualizar PAT localmente; até lá, não alegar pesquisa de corpus |
| Supabase remoto limita testes ou contém dados compartilhados | Testes unitários com doubles; integração remota somente controlada |
| Solana/Devnet ou faucet indisponível na gravação | Ensaiar previamente; mostrar transação já confirmada e identificada como Devnet se regras permitirem |
| Processo de mint/burn e banco divergem após falha | Não repetir automaticamente; registrar estado e reconciliar antes de retry |
| Prova física é mais fraca que a narrativa | Declarar limite; não vender o MVP como antifraude completo |
| Escopo cresce com IA, catálogo ou NFTs | Congelar funcionalidades fora dos P1–P3 |

## 9. Critérios de conclusão da adaptação

- [ ] Regras do hackathon verificadas no portal oficial.
- [ ] Fluxo completo demonstrado sem Coelba e sem parceiro externo.
- [ ] Ações de resgate identificadas como demonstração, sem valor comercial alegado.
- [ ] App, backend e Devnet usados na demo correspondem à versão apresentada.
- [ ] Regra de recompensa não trata peso autodeclarado como medição certificada.
- [ ] Testes não dependem de mutações em dados Supabase compartilhados.
- [ ] Migrations recentes revisadas, aplicadas apenas no ambiente correto e documentadas.
- [ ] README, vídeo e submissão distinguem claramente funcionalidades prontas e visão futura.
- [ ] Nenhuma credencial ou segredo incluído nos materiais públicos.

## 10. Decisão para iniciar implementação

Implementar somente depois de confirmar o checklist P0. A primeira entrega de código deve ser a jornada de comprovante demonstrativo após burn no lugar do resgate Coelba; em seguida vêm testes isolados e a revisão de idempotência. Não começar por IA nem por um mercado de créditos EPR.
