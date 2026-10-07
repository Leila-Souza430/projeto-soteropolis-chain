# Ficha técnica e plano de ação — Soterópolis Chain

**Documento para avaliação técnica e de produto**
**Data de referência:** 28 de setembro de 2026
**Prazo de submissão informado pela fundadora:** 10 de outubro de 2026
**Status deste documento:** diagnóstico e proposta. A fundadora escolheu a Opção A (burn de GT com comprovante digital demonstrativo); os detalhes técnicos e a implementação ainda precisam de aprovação/teste.

> **Nota sobre o prazo:** entre 28/09 e 10/10 há 12 dias corridos, mas o horário/fuso de encerramento pode reduzir o tempo efetivo. Confirmar o cutoff no portal oficial do hackathon.

---

## 1. Objetivo do documento

Dar a um profissional de produto/engenharia uma visão honesta do Soterópolis Chain antes de alterar o código. O documento:

1. descreve o sistema como está implementado no repositório;
2. separa funcionalidades implementadas, declaradas e ainda não verificadas;
3. lista pontos fortes, limitações, defeitos e riscos operacionais;
4. compara três alternativas para remover a dependência de resgate da Neoenergia Coelba;
5. propõe um plano priorizado, com critérios de aceite, riscos e itens fora do escopo.

Este documento não assume que há parceria com Coelba, ecopontos, cooperativas, comerciantes ou compradores de créditos ambientais.

---

## 2. Resumo executivo

O Soterópolis Chain é um MVP de reciclagem com aplicativo Flutter, API FastAPI, Supabase/PostgreSQL e um programa Solana/Anchor para emissão e queima de Green Tokens (GT). O fluxo pretendido é: autenticação → seleção de ecoponto → captura de foto e GPS → validação da distância no backend → emissão de GT → consulta de saldo → resgate/queima.

O projeto tem uma base técnica relevante: separação entre app/API/programa, autenticação, registro de descarte, geofencing, armazenamento de fotos, trilha de transações, modo blockchain simulado e integração Solana configurável. O problema de produto é que o resgate está acoplado a um número de instalação Coelba, apesar de não haver integração real com a concessionária. Isso deixa o valor prometido dependente de uma entidade externa.

Há, contudo, riscos que precisam ser tratados antes de apresentar o MVP como “totalmente funcional”:

- O estado de execução da suíte E2E não foi comprovado nesta análise. Os testes dependem de Supabase, usuário e dados remotos; o README diz 11 testes E2E, enquanto foram localizadas 9 funções de teste pytest no backend.
- A migration de reserva de idempotência criada recentemente não foi aplicada nem validada contra banco. O novo código precisa de uma estratégia explícita para operações que ficam `pending`; uma reserva de banco não torna atômicos banco e blockchain.
- As coordenadas são fornecidas pelo cliente e usadas no cálculo de distância; isso é uma checagem útil, mas não autentica o GPS.
- O peso é estimado/informado no app; o servidor limita a emissão por chamada, mas não verifica a massa real.
- O projeto não deve afirmar “antifraude completo”, “crédito ambiental certificado”, “desconto real” ou “parceria” sem mecanismos e evidência correspondentes.

### Recomendação executiva

Manter o núcleo de registro de descarte e emissão de GT, remover a Coelba do caminho crítico da demo e escolher conscientemente uma das três opções:

1. queimar GT para emitir um comprovante digital demonstrativo;
2. oferecer um catálogo de recompensas explicitamente simuladas; ou
3. não implementar resgate nesta submissão.

Para menor risco de entrega, a opção 3 é a mais simples. A opção 1 preserva um fluxo on-chain de mint e burn, mas o comprovante precisa ser descrito como recibo de uma transação — não certificado ambiental. A opção 2 é mais fácil de entender visualmente, mas oferece a maior chance de parecer uma promessa comercial inexistente e requer mais interface.

**Nenhuma destas decisões deve ser implementada até a fundadora e o profissional responsável confirmarem o resultado esperado e as regras oficiais do hackathon.**

---

## 3. Escopo, fontes e grau de certeza

### 3.1 Material avaliado

- Código e documentação no repositório principal:
  - `README.md`, `SPEC.md`, `PLANO_DE_ACAO.md`, `database_schema.sql`, `migrations/`;
  - `soteropolis-app/`;
  - `soteropolis-backend/`;
  - `soteropolis-onchain/`.
- Projeto de referência ICP “Proof of Recycling” localizado pela usuária em `Downloads/Projeto Hackathon/icp-recycling-main`.
- Saídas de validação tentadas durante esta sessão anterior.

### 3.2 Limites da análise

- Revisão estática de código e documentação; não é certificação de segurança nem teste de penetração.
- Não foi executada uma jornada E2E completa no Supabase e Solana Devnet.
- Não foram verificadas ao vivo as implantações alegadas nos documentos.
- O serviço de pesquisa Colosseum respondeu que o PAT configurado era inválido/expirado. Portanto, este documento **não afirma ter consultado** o corpus autenticado de projetos, portfólios, vencedores ou concorrentes do Colosseum.
- A regra final, data/hora de cutoff, categoria, critérios de avaliação e requisitos de submissão devem ser confirmados no portal oficial. Não inferir exigências não lidas.
- A revisão do projeto ICP foi baseada em arquivos específicos; o projeto ICP não foi compilado nem auditado integralmente neste trabalho.

### 3.3 Convenção de leitura

- **Verificado no código:** comportamento diretamente observado nos arquivos.
- **Declarado na documentação:** afirmação escrita pelo projeto, ainda que não reproduzida durante a revisão.
- **Não verificado:** depende de execução, serviço externo, deploy ou evidência que não foi conferida.

---

## 4. Produto atual

### 4.1 Problema e proposta descritos

O projeto quer incentivar a reciclagem por meio de uma experiência mobile que associa um registro de descarte a um ecoponto, registra dados e atribui recompensas em GT. A proposta original sugere transformar GT em desconto de conta de energia Coelba.

### 4.2 Usuários e atores

- **Cidadão:** entra no app, vincula uma carteira invisível, registra um descarte, consulta saldo e solicita resgate.
- **Backend/API:** autentica solicitações, valida distância, conversa com Supabase e chama o serviço de blockchain.
- **Operador do ecoponto/administrador:** ecopontos cadastrados são consultados, mas o fluxo operacional de confirmação humana de peso/recebimento não está demonstrado como parte do MVP.
- **Concessionária/parceiro:** não há evidência de integração operacional real na implementação observada; o resgate Coelba é descrito como simulado.

### 4.3 Jornada presente no app/código

1. O app Flutter inicializa Supabase Auth.
2. Login usa OTP por e-mail ou telefone; após autenticação, o app tenta derivar/vincular uma carteira via Web3Auth.
3. A tela de descarte pede permissão de localização e câmera.
4. O cidadão escolhe um ecoponto e tira uma foto pela câmera do app; a tela não oferece seletor de galeria.
5. O app obtém a posição atual, envia a foto ao bucket Supabase Storage e chama `POST /descartes` com ecoponto, latitude, longitude, categoria, peso estimado e URL da foto.
6. O backend consulta o ecoponto ativo e calcula a distância Haversine. Fora da tolerância, registra como rejeitado e não emite GT.
7. Dentro da tolerância, calcula a recompensa e pede ao serviço de blockchain que emita tokens.
8. O app consulta o saldo/extrato conforme as telas e serviços existentes.
9. O resgate atual exige `quantidade` e um número de instalação de exatamente 10 dígitos, grava o valor no perfil se alterado e solicita burn. A resposta é um recibo da API, não uma confirmação de desconto da concessionária.

### 4.4 O que a jornada não prova

- Capturar pela câmera do app não prova que a imagem retrata descarte legítimo.
- A localização reportada pelo dispositivo não é atestada contra falsificação.
- A distância ao ecoponto confirma apenas que as coordenadas recebidas ficam dentro do raio calculado.
- Peso informado no app não equivale a pesagem certificada.
- Foto armazenada e transação on-chain não provam, por si só, que uma quantidade específica de resíduo foi coletada, processada ou reciclada.
- Um recibo de burn não equivale a benefício entregue nem a certificado EPR reconhecido.

---

## 5. Arquitetura técnica atual

### 5.1 Aplicativo

- **Tecnologia:** Flutter/Dart.
- **Serviços visíveis no código:** Supabase Flutter, Dio para API, câmera, geolocalização, SharedPreferences para estado local de idempotência, UUID e Web3Auth.
- **Fluxos:** login, dashboard, captura de descarte, carteira, resgate.
- **Plataforma comprovada no repositório:** há estrutura Android. O README afirma teste em Android físico; isso não foi reproduzido nesta análise. iOS não foi identificado na árvore inspecionada.
- **Integrações de configuração:** URLs e valores de Supabase/Web3Auth/API via configuração de build. Verificar variáveis e redirecionamentos no ambiente de demo.

### 5.2 API/backend

- **Tecnologia:** Python, FastAPI, Pydantic, Supabase Python client, httpx, solders/solana-py.
- **Routers:** autenticação/perfil, ecopontos, descartes, resgates.
- **Autenticação:** backend valida o bearer token chamando Supabase Auth `/auth/v1/user`; o user ID vem dessa validação, não do corpo da requisição.
- **Banco:** cliente backend usa service-role, que ignora RLS. A chave deve permanecer exclusivamente no ambiente do servidor.
- **Blockchain:** interface comum com `MockBlockchainService` e `SolanaBlockchainService`; configuração seleciona o modo.
- **Geofencing:** comparação em metros com uma tolerância configurável, documentada como 50 m.
- **Tokenomics:** peso estimado × taxa por kg, ou valor fixo se peso ausente; há teto de emissão por descarte.
- **Testes:** pytest em backend, E2E preparados com Supabase real e Solana Devnet conforme fixtures/documentos.

### 5.3 Banco e armazenamento

- **Serviço declarado:** Supabase PostgreSQL com RLS.
- **Tabelas principais:** `users`, `ecopontos`, `descartes`, `transacoes_tokens`.
- **Armazenamento de fotos:** bucket Supabase Storage `descarte-fotos`, URL pública devolvida para a API.
- **Migrações:** arquivos SQL manuais incluem, entre outros, chave de idempotência, política de storage, RPC de saldo, trigger de criação de perfil e nova tabela de reservas.
- **Estado dos ambientes:** não foi confirmado quais migrations foram efetivamente aplicadas ao projeto Supabase. O código atual que usa `idempotency_operations` requer a migration correspondente no banco.

### 5.4 Programa Solana

- **Tecnologia:** Rust, Anchor, Token-2022.
- **Instruções:** inicialização, mint e burn.
- **Autoridade:** o backend assina operações; o programa usa Config PDA/Permanent Delegate conforme código e documentação.
- **Endereço de programa:** um ID está declarado no código/configuração; isso não comprova que o deploy ainda exista ou corresponda ao código atual.
- **Estado da rede:** documentação afirma Devnet. `Anchor.toml` deve ser conferido antes da demo; a configuração lida anteriormente apontava o provider para `localnet`, então o modo de execução precisa ser reconciliado com as instruções de deploy e o backend.
- **Testes:** há testes Anchor em TypeScript, mas não foram executados nesta análise por falta de dependências/toolchain disponível.

---

## 6. Pontos fortes

1. **Entrega full-stack existente:** há app, backend, banco, storage e programa on-chain no mesmo repositório.
2. **Fluxo de cidadão compreensível:** câmera/localização, ponto de entrega, saldo e recompensa são fáceis de demonstrar.
3. **Geofencing calculado no servidor:** melhor do que aceitar só um texto de cidade fornecido pelo app.
4. **Câmera dentro do fluxo dedicado:** reduz o caminho de conveniência de selecionar diretamente uma foto já existente, embora não elimine falsificação.
5. **Identidade de usuário derivada do JWT validado:** as rotas protegidas não devem confiar em `user_id` fornecido pelo cliente.
6. **Separação do serviço blockchain:** modo mock permite desenvolvimento sem depender de cada operação real on-chain; modo Solana é implementado atrás de uma interface.
7. **Auditoria financeira básica:** tabela de transações guarda tipo, quantidade, hash da transação e usuário.
8. **RLS e separação de papéis:** cliente cidadão usa permissões de usuário; backend usa service-role para operações privilegiadas.
9. **Controles de quantia:** modelo/rota de resgate rejeita quantias não positivas; emissão possui teto configurável; o programa on-chain rejeita amount zero.
10. **Consciência de risco:** documentação existente registra riscos de autoridade de upgrade e rent de ATAs antes de mainnet.
11. **Escopo local como piloto:** começar por Salvador permite limitar geografia, ecopontos e experiência, sem prometer expansão imediata para qualquer país.

---

## 7. Fraquezas, falhas e riscos técnicos

### 7.1 Riscos críticos para confiar na demo

#### A. Estado do projeto de banco e migration de reservas

- A tabela `idempotency_operations` foi adicionada recentemente por migration, e os routers dependem dela em novos fluxos.
- Essa migration não foi aplicada/verificada contra o Supabase durante a análise.
- Testes do backend pararam na coleta quando as variáveis obrigatórias Supabase não estavam presentes; numa execução posterior, a fixture exigiu credenciais válidas.
- Sem migration aplicada, chamadas que chegam à reserva podem falhar em runtime.

**Ação:** identificar ambientes de desenvolvimento/teste/prod, aplicar migration apenas no ambiente correto, inspecionar schema e executar um smoke test antes de apresentar o fluxo.

#### B. Idempotência não resolve atomicamente blockchain + banco

A reserva em PostgreSQL protege contra duas requisições simultâneas com a mesma chave chegarem ambas ao mint/burn, se a migration estiver aplicada e o insert de reserva funcionar. Porém, PostgreSQL e Solana não participam da mesma transação distribuída.

Casos que continuam exigindo tratamento:

- Falha antes da chamada on-chain: reserva permanece `pending`; retry pode receber conflito sem caminho de recuperação.
- Descarte inserido e mint rejeitado/indisponível: descarte pode permanecer `Validado`, operação `pending`.
- Mint/burn confirmado e falha ao registrar transação no banco: cadeia e auditoria divergem.
- Falha ao marcar a reserva `completed`: transação pode estar gravada, mas o estado da reserva não.
- A consulta de transação prévia faz replay por chave e usuário antes de comparar hash do payload; uma chave reutilizada com payload diferente pode retornar uma operação anterior, em vez do conflito pretendido.
- A migration da reserva precisa persistir e validar os mesmos dados de operação/payload que a implementação espera.

**Ação:** definir contrato de estados e reconciliação; não chamar a operação “idempotência financeira garantida” até cobrir falhas pós-side-effect e testar replays com payload divergente.

#### C. Validação geográfica e peso não são prova física

- A API valida faixa de coordenadas e distância, mas as coordenadas continuam vindo do dispositivo.
- Não há atestação de GPS vista no fluxo; é possível falsificar o cliente/coordenadas.
- O usuário pode informar peso; o servidor multiplica esse valor pela taxa e limita o total, mas não verifica a massa.
- A foto é enviada a storage, porém não há análise de conteúdo no backend.

**Ação:** usar linguagem de “registro geolocalizado” e “peso estimado” no produto; não “antifraude completo”, “peso comprovado” ou “reciclagem certificada”.

#### D. Side effects em ordem inadequada / registros incompletos

- A rota de descarte valida wallet antes de inserir um descarte validado na versão atual revisada, corrigindo um risco observado anteriormente.
- Ainda assim, a criação do descarte, o mint e a escrita da transação não são uma unidade atômica.
- A tela da câmera captura foto e faz upload antes de recuperar a solicitação pendente guardada localmente. Após falha de rede, uma tentativa pode fazer novo upload e depois reenviar o payload antigo; a foto nova pode ficar sem referência.
- Falhas em upload/captura podem não deixar o estado local/servidor perfeitamente sincronizado.

**Ação:** testar falhas deliberadas em cada fronteira; preservar status `Pendente`/`Validado` apenas quando seu significado operacional for coerente e reconciliável.

### 7.2 Riscos de saldo e concorrência

- O saldo para resgate é calculado somando `MINT - BURN` em registros do banco.
- Chamadas de resgate com chaves diferentes podem verificar saldo quase ao mesmo tempo. O on-chain deve rejeitar um burn acima do saldo de tokens, mas a API pode retornar erro de cadeia e requerer experiência clara para o usuário.
- A representação Python/DB usa números float para quantidades, enquanto tokens on-chain usam unidades inteiras em precisão configurada; arredondamentos podem gerar discrepâncias. Há conversão decimal no serviço Solana, que precisa ser testada nos limites de decimais.
- Uma transação pode confirmar na cadeia e ter resposta RPC ambígua; o sistema precisa consultar/reconciliar assinatura antes de tentar novamente uma operação irreversível.

**Ação:** testar precisão de token, quantidades mínimas, saldo exato, saldo insuficiente, repetição e confirmação ambígua. Planejar unidades inteiras no contrato API/DB numa fase estrutural posterior.

### 7.3 Riscos de resgate e promessa de produto

- `ResgateCreate` exige exatamente 10 dígitos para `instalacao_coelba`. O comentário do schema chama o formato de mock.
- O endpoint atual atualiza `instalacao_coelba` no perfil e queima GT.
- Não foi observada chamada para API real da Neoenergia nem resposta da concessionária.
- A interface apresenta linguagem de desconto na conta de energia e a tela de sucesso dá a entender que o desconto virá na próxima fatura.

**Ação:** remover a afirmação de benefício real antes de demonstração pública, salvo se houver evidência externa verificável de integração/compromisso.

### 7.4 Riscos de segurança/centralização

- A service-role key do Supabase e a keypair operacional Solana são segredos de alto impacto; devem existir apenas em ambiente servidor protegido.
- A autoridade do backend pode emitir e queimar tokens; o modelo depende de confiança no backend.
- A documentação anterior identificou autoridade operacional/upgradability e rent de ATA como questões pré-mainnet.
- A wallet “invisível” não deve ser descrita como sem custódia sem uma explicação técnica adequada do arranjo de chave e recuperação. O fluxo observado cria/deriva carteira com Web3Auth e não torna a autoridade do programa descentralizada.
- As APIs de autenticação, Web3Auth, Supabase, RPC e Storage são dependências externas; sua disponibilidade afeta a demo.

**Ação:** usar Devnet, manter segredos fora do app e repositório, não aceitar mainnet sem revisão operacional, proteção/rotação de chaves e modelo claro de autoridade.

### 7.5 Qualidade, documentação e ambiente de teste

- O README declara 11 testes E2E automatizados. Foram localizadas 9 funções pytest no backend visível; a suíte não foi executada integralmente.
- `pytest` sem mudar para a pasta backend falhou com caminho de import; executado no diretório backend, a coleta falhou por ausência de credenciais Supabase.
- Os testes atuais usam usuário, ecoponto, Supabase e Devnet reais conforme `conftest.py`; não são independentes nem seguros para rodar repetidamente contra dados compartilhados sem planejamento.
- Flutter `pub get` concluiu, mas `flutter analyze` terminou com um aviso de estilo (prefer initializing formals), não com zero findings.
- Lint on-chain não rodou por ausência de dependências npm; `cargo check` tentou baixar toolchain e falhou durante download.
- O arquivo `.env.example` é template; não copiar segredos para documentação ou demo.
- `README.md`, `SPEC.md` e plano atual ainda descrevem a Coelba, “desconto” e status/quantidade de testes de forma mais forte do que foi verificado.

**Ação:** atualizar o status com resultados reproduzíveis e separar testes unitários/mock de smoke tests externos.

---

## 8. Avaliação da análise externa sobre o projeto ICP

O material de referência consultado descreve um projeto de reciclagem em ICP (“Proof of Recycling”), com upload de imagem, uso de IA no frontend, token e NFTs ligados a benefícios. É um comparável de problema/fluxo, não uma base técnica ou implementação a copiar.

### Afirmações da outra análise que são sustentadas pelo material consultado

- O formulário ICP oferece seleção de arquivo de imagem; não exige captura exclusiva pela câmera.
- A localização é convertida para um texto de cidade/país com serviço de geocoding, e não há validação de distância a um ecoponto cadastrado nesse formulário.
- A chamada ao Gemini acontece no frontend e usa um prompt permissivo, incluindo “responder No só se tiver 100% certeza”.
- A interface do formulário chama o mint após salvar a evidência no canister.
- Foram vistos literais de credenciais de serviço no projeto ICP; não reproduzir valores aqui. Se o projeto ou os serviços ainda estiverem sob controle da usuária/ativos, o mantenedor deve revogá-los. Não reutilizar credenciais de terceiros.
- O canister do token ICP exibido em `icrc2/lib.rs` não aparenta verificar autorização do caller antes de `mint`; as funções do canister NFT aceitam owner passado como argumento e há endpoint de reinicialização.

### O que a análise externa superestima/incompleta

- No Soterópolis, app ter câmera dedicada e backend calcular distância são melhorias de desenho em relação ao comparável, mas não eliminam GPS spoofing, foto de tela, submissão encenada ou peso falso.
- Não se verificou “RLS, auditoria e testes adversariais” como se fossem equivalentes a certificação. RLS protege linhas no banco conforme políticas; não valida a verdade física dos dados. Os E2E usam serviços reais e não foram reproduzidos.
- O maior problema de produto da Soterópolis não é necessariamente falta de IA: é a diferença entre evidência técnica observada e o nível de confiança que a recompensa promete.
- Adicionar IA de visão agora traz chave/serviço, latência, custo/quota, privacidade de imagem, falsos positivos/negativos, observabilidade e dependência externa. A IA não certifica reciclagem e não resolve peso nem presença física.

### Posição profissional

**Não priorizar IA no prazo curto.** Se avaliada futuramente, mantê-la como sinal auxiliar de revisão, nunca como juiz único que libera dinheiro/tokens. Primeiro tornar explícitos o tipo de evidência, a regra de recompensa, os estados de operação e o escopo real do benefício.

---

## 9. Três opções de modificação do produto

As três opções abaixo respondem à mesma necessidade: **tirar uma empresa externa do caminho crítico para a demo**. São alternativas de produto, não implementações concluídas.

### Opção A — Queimar GT e emitir comprovante digital demonstrativo

#### Fluxo

1. Usuário obtém GT após o fluxo de descarte.
2. Escolhe gerar comprovante e informa uma quantidade de GT.
3. Backend valida quantidade e saldo.
4. Serviço de blockchain queima GT na Devnet.
5. Sistema apresenta recibo com quantidade, hash/link da transação e referência interna ao descarte.
6. Recibo avisa: “Demonstração — registro de transação; não representa desconto, pagamento, certificado ambiental ou benefício comercial”.

#### O que é demonstrado

- Mint e burn reais na rede de demonstração, caso RPC, carteira e contrato estejam funcionais.
- Uma jornada com começo/meio/fim e rastreabilidade de transação.
- Capacidade de ligar referências do app a operações financeiras on-chain.

#### Vantagens

- Não depende de concessionária ou parceiro.
- Mantém a utilidade técnica do GT mais visível.
- Pode aproveitar parte substancial do endpoint atual de burn.

#### Custos e riscos

- Há custo de produto: queimar GT por um comprovante sem valor pode parecer artificial.
- Exige alterar request/response, UI, recibo, testes e documentação; o endpoint atual carrega `instalacao_coelba`.
- Associar a transação a um descarte não torna o descarte ambientalmente certificado.
- A narrativa deve chamar o documento de recibo de transação/registro demonstrativo, não “certificado de reciclagem”.
- Persistência/reconciliação entre Solana e banco continua crítica.

#### Critério de aceite

Uma demo reproduz mint → burn → comprovante com assinatura visível, sem dado Coelba e com aviso explícito de que não há valor comercial.

### Opção B — Catálogo pequeno de recompensas simuladas

#### Fluxo

1. Usuário obtém GT.
2. Visualiza poucas recompensas ilustrativas no app.
3. Seleciona uma recompensa e confirma a quantidade de GT.
4. Backend valida catálogo/saldo e queima os GT.
5. App gera um voucher demo, sem valor de uso externo, com estado “simulado”.

#### O que é demonstrado

- Uma possível experiência de fidelidade/recompensa.
- Como um ecossistema futuro poderia conectar moradores a ofertas locais.
- Mint, burn e apresentação visual de recompensa, se a operação for real na Devnet.

#### Vantagens

- Mais intuitiva visualmente em pitch do que um recibo puro.
- Pode sustentar a visão de rede de benefícios locais, sem limitar a uma conta de energia.
- Permite demonstrar como parceiros poderiam ser adicionados futuramente.

#### Custos e riscos

- Maior escopo de front-end, catálogo, estado de voucher e modelo de oferta.
- Sem parceiro, voucher não é resgatável; chamar isso de benefício pode frustrar ou induzir o usuário a erro.
- Precisa rotular todos os itens como demonstração e evitar marcas reais sem autorização.
- Não criar linguagem de “parceiros”, “desconto disponível” ou “oferta garantida”.
- Pode desviar tempo da confiabilidade do fluxo de descarte, câmera, backend e contrato.

#### Critério de aceite

Uma demo permite selecionar e “resgatar” somente itens claramente marcados como fictícios/demonstração; não há promessa de aceitação por estabelecimento.

### Opção C — Remover resgate da entrega atual

#### Fluxo

1. Usuário registra descarte.
2. Backend valida a solicitação conforme as regras atuais e registra a operação.
3. GT é emitido conforme política de recompensa escolhida.
4. Carteira mostra saldo e histórico; interface explica que GT é recompensa experimental sem conversão/benefício comercial nesta versão.
5. Resgate vira fase posterior sujeita a validação de uso e parceiros.

#### O que é demonstrado

- Núcleo de participação, registro e recompensa.
- App → API → Supabase → blockchain, caso o percurso seja reproduzido.
- Uma tese de infraestrutura local sem inventar o último elo de utilidade.

#### Vantagens

- Menor risco de escopo e de erro de integração.
- Não cria voucher ou promessa fictícia.
- Permite dedicar o tempo a construir teste reproduzível e melhorar a qualidade da evidência.
- É a alternativa mais apropriada se o fluxo de burn/banco não puder ser validado a tempo.

#### Custos e riscos

- GT ainda não tem uso concreto no MVP.
- Narrativa de utilidade é mais fraca; precisa explicar que o token é mecanismo de recompensa experimental, não dinheiro.
- Não demonstra a operação de burn na jornada final.

#### Critério de aceite

A submissão mostra saldo/histórico e declara explicitamente que o MVP não oferece resgate nem valor monetário.

### Matriz comparativa

| Critério | A. Comprovante demonstrativo | B. Catálogo simulado | C. Sem resgate |
|---|---:|---:|---:|
| Dependência de parceiro externo | Nenhuma | Nenhuma, mas voucher não é utilizável | Nenhuma |
| Demonstra burn Solana | Sim | Sim | Não na jornada de usuário |
| Esforço relativo | Médio | Médio/alto | Baixo |
| Risco de parecer promessa falsa | Baixo se rotulado com rigor | Mais alto | Baixo |
| Utilidade entregue hoje | Recibo digital sem valor comercial | Voucher fictício | Saldo e histórico |
| Risco técnico no prazo | Médio | Médio/alto | Menor |
| Melhor para | Demo on-chain completa | Protótipo de experiência de benefícios | Estabilidade e escopo mínimo |

### Critério de decisão proposto

- Se prioridade é **reproduzir o menor fluxo com menor risco**: C.
- Se prioridade é **mostrar mint + burn sem depender de terceiro** e há tempo para testar: A.
- Se prioridade é **demonstrar visualmente uma futura rede de benefícios**, aceitando que nada será resgatável: B.

**Não escolher B somente porque outro projeto tem NFT/loja.** Não copiar formato de benefício; escolher pela tese e pelo fluxo que é possível demonstrar honestamente.

---

## 10. Plano de ação técnico e de produto

### Fase 0 — Decisão e congelamento de escopo (imediato)

**Objetivo:** estabelecer a regra de produto e reduzir risco de trabalho desperdiçado.

**Tarefas**

1. Confirmar com a fundadora qual opção de resgate será perseguida (A/B/C).
2. Conferir regras atuais do hackathon no portal:
   - hora e fuso do cutoff;
   - categoria/trilha e elegibilidade;
   - exigência de produto on-chain, contrato implantado ou rede específica;
   - campos obrigatórios, vídeo, demo, URL pública e limite de equipe.
3. Fixar um branch/commit de baseline da aplicação atual; guardar lista das alterações locais existentes.
4. Classificar cada afirmação dos materiais como “implementado”, “simulado”, “planejado” ou “não verificado”.
5. Confirmar ambiente de demonstração: Supabase usado, RPC, programa/mint, wallet de teste, saldo, armazenamento e credenciais.

**Critérios de saída**

- Opção de produto aprovada.
- Checklist oficial anexado à tarefa de submissão.
- Nenhuma mudança irreversível no banco online feita para experimentar.

### Fase 1 — Auditoria de baseline e ambiente seguro

**Objetivo:** descobrir o que funciona hoje antes de modificar.

**Tarefas**

1. Registrar versão de Flutter/Dart, Python, Rust/Anchor, Node e dependências.
2. Verificar migrations aplicadas no Supabase sem imprimir chaves em logs.
3. Conferir se `idempotency_operations` existe no ambiente de teste e se corresponde à migration.
4. Executar `flutter analyze` no diretório do app e guardar findings.
5. Executar lint/typecheck/testes do projeto on-chain no diretório e toolchain corretos.
6. Executar backend unitário/mocked; separar isso dos E2E externos.
7. Realizar um smoke test controlado de login, listagem de ecopontos, upload, descarte e consulta de saldo.
8. Validar de forma controlada uma transação Devnet e obter assinatura verificável; não usar mainnet.
9. Corrigir documentação sobre número e natureza de testes somente após contar/executar testes.

**Critérios de saída**

- Matriz “passa/falha/não executado” por componente.
- Nenhum teste de automação altera usuário/dados compartilhados sem autorização e limpeza definida.
- Hashes/IDs de deploys e rede usados na demo registrados sem incluir segredos.

### Fase 2 — Corrigir a alegação de produto e a tela de resgate

**Objetivo:** a interface não prometer benefício não entregue.

**Tarefas comuns a A/B/C**

1. Remover texto afirmando desconto que virá na fatura.
2. Substituir labels Coelba no caminho crítico conforme a opção escolhida.
3. Revisar mensagens, recibos, modelos Dart/Pydantic, chamadas API, histórico e testes.
4. Preservar campos históricos no banco se remover coluna/migration não for essencial para a demo; evitar DDL destrutivo durante o prazo.
5. Não usar marca de empresa como parceira sem aprovação/documentação.

**Critérios de saída**

- Um usuário iniciante entende, sem explicação verbal, se o resultado é demo ou benefício real.
- Nenhuma tela de sucesso sugere que entidade externa realizou ação que não ocorreu.

### Fase 3 — Regras de recompensa e evidência

**Objetivo:** não converter entrada não verificada em impacto ambiental apresentado como fato.

**Tarefas**

1. Decidir uma regra de recompensa no servidor:
   - valor fixo por descarte registrado, ou
   - tabela conservadora de valor por categoria;
   - não usar peso como se fosse medido por balança quando vem do usuário.
2. Se peso permanecer no formulário, apresentar “peso estimado informado pelo usuário”.
3. Avaliar se há necessidade real de armazenar foto para a demo; definir retenção e acesso.
4. Escrever descrição explícita do que valida a API: ponto ativo, coordenadas recebidas, distância calculada e faixa aceita.
5. Registrar o status como validação técnica do fluxo, não certificação de reciclagem.

**Critérios de saída**

- Regra de GT clara, previsível e aplicada no servidor.
- Usuário e avaliador conseguem distinguir dado medido, estimado e verificado.

### Fase 4 — Idempotência e reconciliação mínima

**Objetivo:** evitar emissão/queima duplicada e não esconder divergência quando serviço falha.

**Tarefas**

1. Revisar migration e chamadas para a tabela de reservas.
2. Definir estados mínimos: `pending`, `completed`, `failed`/`needs_reconciliation`; não reexecutar side effect automaticamente em estado ambíguo.
3. Validar a mesma chave com:
   - mesmo usuário, mesma operação, mesmo payload;
   - mesmo usuário, payload diferente;
   - usuário diferente;
   - operação diferente;
   - duas requisições concorrentes;
   - falha simulada antes do RPC, após confirmação on-chain e antes/depois do insert no banco.
4. Corrigir replay legado por `transacoes_tokens` para conferir operação e identidade do pedido; payload divergente não deve receber resposta de sucesso anterior.
5. Associar `descarte_id`/`transacao_id` à operação no banco de modo coerente com as chaves estrangeiras e respostas.
6. Documentar procedimento manual de reconciliação da Devnet.
7. Não declarar “atômico” ou “garantia de exactly once”: a chamada blockchain e a gravação DB não formam uma transação distribuída.

**Critérios de saída**

- Testes provam que replays concluídos não repetem mint/burn.
- Nenhuma falha ambígua cria novo side effect automaticamente.
- Registros inconsistentes podem ser detectados e reconciliados.

### Fase 5 — Testes, ensaio e submissão

**Objetivo:** apresentar somente o que foi repetido com sucesso.

**Tarefas**

1. Criar/usar casos de teste que não chamem Supabase remoto por padrão.
2. Manter testes de integração real opt-in e delimitados a dados de teste.
3. Ensaiar duas vezes o fluxo escolhido em aparelho/dispositivo de demo.
4. Capturar provas do programa/rede/transação real, quando usado.
5. Preparar plano B para falha de internet, RPC, login, câmera ou faucet.
6. Atualizar README, SPEC e plano de ação com status honesto.
7. Preparar vídeo e submissão segundo regras oficiais, não segundo suposições.
8. Revisar links e permissões públicas sem publicar credenciais ou dados pessoais.

**Critérios de saída**

- Demo ensaiada de ponta a ponta.
- Vídeo e documentação refletem a mesma versão demonstrada.
- Nenhuma funcionalidade simulada aparece como parceria ou benefício real.

---

## 11. Backlog priorizado

### P0 — Bloqueadores antes da demo

- [ ] Confirmar cutoff e critérios oficiais do Colosseum.
- [ ] Escolher A, B ou C.
- [ ] Confirmar rede e programa usados (localnet ou Devnet).
- [ ] Confirmar migration de reserva no ambiente de teste.
- [ ] Remover linguagem de desconto real da tela de resgate.
- [ ] Preparar jornada reprodutível sem operação de terceiro.
- [ ] Nunca usar service-role, keypair operacional ou token secreto no app/README/vídeo.

### P1 — Recomendados se couberem

- [ ] Testes unitários sem Supabase remoto para Pydantic/geofence/regras de recompensa/idempotência.
- [ ] Testes de conflito de idempotency key e payload diferente.
- [ ] Resultado visível para operações `pending`/falhas de cadeia.
- [ ] Tratar a repetição da captura para não fazer uploads órfãos quando existe pedido pendente local.
- [ ] Corrigir contagem/descrição de testes no README.
- [ ] Atualizar textos do resgate e recibo.

### P2 — Adiar para depois do hackathon

- [ ] IA de visão como sinal auxiliar.
- [ ] Aplicativo genérico multi-cidade/multi-idioma.
- [ ] Marketplace empresarial e liquidez de créditos EPR.
- [ ] Integração real de desconto/coleta com empresa ou governo.
- [ ] Verificação de peso certificado e cadeia de custódia de material.
- [ ] Migração ou substituição do Supabase completo.
- [ ] Deploy de mainnet.

---

## 12. Plano de teste de aceitação para o profissional

### Casos comuns a qualquer opção

1. Login válido e expirado.
2. Listagem de ecopontos ativos e ausência de ecopontos.
3. Permissão de câmera/localização negada e serviço de localização desligado.
4. Coordenadas dentro/fora da tolerância; limites de latitude/longitude; NaN/Infinity.
5. Peso zero, negativo, ausente, muito alto e decimal; prova de que o cálculo não aceita valor inválido.
6. Usuário sem wallet e carteira malformada.
7. Foto válida, upload falho, URL ausente, retry de rede e descarte repetido.
8. Requisição com chave idempotente repetida com mesmo payload e com payload divergente.
9. Serviço Solana indisponível/timeout; confirmação ambígua; transação confirmada com banco indisponível.
10. Saldo exato, insuficiente, quantidade mínima e burn concorrente.
11. Verificação do histórico e reconciliação de IDs/hash.
12. RLS do cliente e segregação de dados de dois usuários.

### Casos específicos da opção A

- Um comprovante é emitido apenas quando o burn está confirmado.
- Hash/assinatura aponta para a rede correta.
- Nenhum texto chama o comprovante de certificado reconhecido.
- Replay não queima novamente.

### Casos específicos da opção B

- Catálogo contém apenas recompensas explicitamente demo.
- Vouchers demo não podem ser confundidos com código comercial válido.
- Não existem logotipos/ofertas de terceiro sem autorização.
- Saldo, burn e estado do voucher permanecem coerentes.

### Casos específicos da opção C

- Nenhuma rota/tela sugere que GT pode ser trocado hoje.
- Saldo e histórico continuam claros.
- Documentação explica que resgate não está disponível nesta versão.

---

## 13. Materiais e narrativa pública: afirmações aceitáveis

### Formulação defensável, se confirmada por teste

> “O Soterópolis registra solicitações de descarte associadas a ecopontos e coordenadas, verifica no backend a distância informada e registra recompensas GT na Solana Devnet. O fluxo atual é um protótipo: o peso é estimado pelo usuário e não há integração comercial para resgate.”

### Afirmações a evitar até prova adicional

- “Antifraude completo/impossível de fraudar.”
- “A blockchain prova que o resíduo foi reciclado.”
- “Crédito EPR elegível/certificado.”
- “Desconto real aplicado na conta de luz.”
- “Integração/parceria com Coelba, Limpurb, cooperativa ou comerciante.”
- “11 testes E2E passaram”, a menos que a quantidade e a execução sejam reproduzidas.
- “Totalmente funcional” sem descrever rede, modo mock/Devnet, serviços e limites do fluxo.

### Sobre Solana

Explicar por que a blockchain está no protótipo: registrar emissão/queima verificável e demonstrar uma rede pública. Só afirmar custo baixo, rapidez, escala ou benefício específico com medições/fontes adequadas e distinguindo Devnet de produção.

---

## 14. Decisões necessárias da fundadora e do profissional

1. Qual das opções A/B/C atende melhor ao objetivo do hackathon e ao que é possível validar?
2. O que o usuário deve receber hoje: GT sem resgate, comprovante demonstrativo ou voucher fictício?
3. O token deve ser mostrado como recompensa de participação ou como unidade com promessa de valor?
4. Qual será a política de emissão: valor fixo, categoria ou peso estimado?
5. Qual rede e contrato serão usados na demo, e qual é a evidência de deploy vigente?
6. Qual ambiente Supabase é seguro para integração; quais migrations estão aplicadas?
7. A demo será feita em dispositivo físico, emulador ou vídeo gravado?
8. Quais critérios oficiais do Colosseum são obrigatórios e qual é o horário de cutoff?
9. Que limitações serão declaradas ao avaliador?
10. Quem será responsável por suporte operacional, reconciliação e credenciais no dia da demo?

---

## 15. Parecer final

O projeto tem uma base técnica demonstrável e uma tese local plausível, mas hoje combina uma verificação de presença aproximada, dados fornecidos pelo usuário e um resgate sem integração comercial comprovada. Seu diferencial mais honesto é **registrar e rastrear um fluxo de descarte associado a um ecoponto e a transações na blockchain**, não afirmar que já certifica reciclagem nem que aplica descontos reais.

Para competir profissionalmente, o maior ganho no prazo não é adicionar mais uma integração externa ou um modelo de IA. É:

1. retirar a Coelba do caminho crítico;
2. escolher uma única experiência de ponta a ponta;
3. testar o que existe com segurança e evidência reproduzível;
4. fechar as lacunas de idempotência/reconciliação que possam duplicar ou perder operações;
5. distinguir rigorosamente fato, simulação e visão futura em app, pitch e README.

**Decisão de produto registrada:** a fundadora escolheu A — queimar GT e emitir um comprovante digital demonstrativo. O recibo registra a operação de burn e sua referência no sistema; não é certificado ambiental, benefício comercial, desconto ou prova independente de reciclagem. Antes de implementar, detalhar o contrato da API, os dados do recibo, o tratamento de falhas e os testes de reconciliação. Transformar somente os itens P0/P1 aprovados em tarefas de implementação; preservar as demais ideias para o roadmap posterior.
