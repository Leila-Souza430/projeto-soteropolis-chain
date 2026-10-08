# 🌱 Soterópolis Chain

**Reciclou, ganhou.** GovTech de reciclagem urbana com recompensas em blockchain para Salvador (BA).

O Soterópolis Chain transforma o descarte correto de material reciclável em desconto real na fatura de energia elétrica. O cidadão valida o descarte por câmera + GPS em um Ecoponto cadastrado, recebe Green Tokens (GT) emitidos em blockchain, e resgata esses tokens como desconto direto na conta de luz — sem precisar entender nada de blockchain no processo.

---

## Índice

- [Sobre o projeto](#sobre-o-projeto)
- [Como funciona](#como-funciona)
- [Arquitetura e stack tecnológica](#arquitetura-e-stack-tecnológica)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Status do projeto](#status-do-projeto)
- [Guia de continuidade](#guia-de-continuidade)
- [Como rodar localmente](#como-rodar-localmente)
- [Segurança](#segurança)
- [Testes](#testes)
- [Roadmap](#roadmap)
- [Autoria](#autoria)

---

## Sobre o projeto

Moradores de Salvador que se dispõem a reciclar não recebem nenhum retorno tangível pelo esforço, e não existe comprovação confiável de que o descarte realmente aconteceu — o que abre espaço para fraude e desestimula o hábito. O Soterópolis Chain resolve isso com:

- **Validação antifraude** por câmera em tempo real (sem upload de galeria) + geolocalização (GPS), com tolerância de 50 metros do Ecoponto cadastrado.
- **Recompensa com valor prático imediato**: desconto real na conta de luz, não pontos genéricos.
- **Carteira digital blockchain invisível**: criada automaticamente no primeiro login, sem o cidadão precisar entender ou manipular chaves criptográficas.

## Como funciona

1. O cidadão autentica no Supabase. O app está temporariamente em modo de teste por e-mail e senha; a criação/vinculação da carteira Solana acontece em seguida e ainda está em validação.
2. No Ecoponto, tira uma foto do material reciclável em tempo real, com GPS anexado automaticamente.
3. O backend valida a distância até o Ecoponto (fórmula de Haversine) e rejeita tentativas fora do raio permitido — mantendo o registro para auditoria antifraude.
4. Descartes validados emitem Green Tokens (GT) via smart contract na Solana, de forma idempotente (sem risco de duplicação em falha de rede).
5. O cidadão acompanha saldo e extrato na carteira digital do app, e resgata GT como desconto na fatura de energia (integração simulada com a Coelba nesta fase de MVP).

## Arquitetura e stack tecnológica

| Camada | Tecnologia |
|---|---|
| App mobile | Flutter (Dart) |
| Backend | Python + FastAPI |
| Banco de dados | Supabase (PostgreSQL) com Row Level Security (RLS) |
| Autenticação | Web3Auth / MetaMask Embedded Wallets (carteira Solana "invisível") |
| Blockchain | Solana — contrato inteligente em Rust/Anchor (testado na devnet) |
| Testes | pytest (11 testes E2E automatizados contra ambiente real) |

## Estrutura do repositório

```
.
├── soteropolis-backend/     # API FastAPI: geofencing, idempotência, auditoria
├── soteropolis-app/         # Aplicativo Flutter
├── soteropolis-onchain/     # Programa Anchor (Rust) — mint/burn do Green Token
├── migrations/               # Migrações SQL incrementais do Supabase
├── database_schema.sql       # Schema completo do banco (Fase 1)
├── SPEC.md                   # Especificação funcional completa do projeto
└── PLANO_DE_ACAO.md          # Plano de ação do MVP, fase a fase
```

## Status do projeto

O repositório reúne o app Flutter, o backend e o programa Solana. O projeto ainda precisa validar o caminho de autenticação e carteira no app de ponta a ponta; o estado abaixo separa o que foi observado do que ainda falta confirmar.

### Progresso recente de autenticação (7 de outubro de 2026)

- O app Flutter foi compilado em modo debug, instalado e aberto em um Android físico.
- O login por link de e-mail foi testado, mas o Supabase registrou `/verify` com `403: Email link is invalid or has expired`. A conta de teste criada por convite confirmou o e-mail e o link de convite redirecionou para `localhost`, que não está rodando no celular.
- O callback `soteropolisapp://supabase-auth-callback` está na lista de Redirect URLs do Supabase e no intent filter do Android. Um teste local confirmou o encaminhamento desse esquema ao app; isso não comprovou a aceitação de um link real.
- A prévia do template padrão “Magic link or OTP” mostra um link. O SMTP personalizado permanece desligado. O plano gratuito pode impor limites de envio, mas os dados vistos não provam que esse seja o motivo do erro `/verify`.
- Para testar sem depender de e-mail, o app foi alterado temporariamente para aceitar e-mail e senha. Uma tentativa anterior chegou à mensagem “Não foi possível configurar sua Carteira Digital”, mas a tentativa mais recente foi recusada pelo Supabase com `invalid_credentials` (HTTP 400); essa última tentativa não chegou ao MetaMask.
- A conexão Custom Authentication do MetaMask foi configurada para validar o JWT Supabase por JWKS, issuer e audience. O código agora usa o client ID público do projeto Embedded Wallets no `AuthConnectionConfig.clientId`, como no exemplo oficial Flutter de custom JWT. Ainda falta confirmar esse caminho em uma autenticação Web3Auth real.
- O build de debug passou. `flutter analyze` não encontrou erros nas alterações de login; apontou somente um aviso informativo preexistente em `lib/services/api_client.dart`.
- SMTP, dados do projeto hospedado e contas de usuário não foram alterados por essas mudanças de código. Credenciais, senhas, tokens e o arquivo local `soteropolis-app/dart_define.local.json` não devem ser commitados.

### Próximos passos

1. Definir uma senha conhecida para uma conta de teste no Supabase. A conta criada por convite teve o e-mail confirmado, mas isso não comprova que a senha usada no app esteja correta; não apagar usuários existentes.
2. Fazer uma tentativa com credenciais sabidamente corretas e confirmar primeiro que o Supabase aceitou o login.
3. Se o Supabase aceitar, investigar a etapa MetaMask/Web3Auth e obter erro técnico sanitizado, separando-a da chamada ao backend.
4. Configurar e iniciar o backend local antes de testar o vínculo final da carteira.
5. Depois, retomar o login por link. Considerar limites do plano gratuito e varredura/rastreamento de links como hipóteses, não como causa confirmada.
6. Configurar SMTP próprio somente se houver um provedor controlado pela responsável pelo projeto; não é necessário ativar os avisos de segurança para autenticação.
7. Revisar configuração e migrações Supabase/backend e executar os testes integrados novamente antes de apresentar o fluxo como pronto.

### Guia de continuidade

Para continuar exatamente deste ponto em outro computador ou com outra IA,
clone o branch de trabalho (não o branch padrão `main`):

```bash
git clone --branch agents/projeto-analise-e-corrigindo-erros --single-branch https://github.com/Leila-Souza430/projeto-soteropolis-chain.git
```

Leia primeiro [`CONTINUIDADE_AUTENTICACAO.md`](./CONTINUIDADE_AUTENTICACAO.md).
Esse guia registra as evidências, as alterações feitas, o problema pendente e
uma ordem segura para retomar. O histórico do branch contém o código atual;
as configurações locais e credenciais não são incluídas e precisam ser
recriadas localmente pela responsável.

## Como rodar localmente

### Backend
```bash
cd soteropolis-backend
pip install -r requirements.txt --break-system-packages
cp .env.example .env   # preencha com suas credenciais do Supabase
uvicorn main:app --reload --port 8000
```

### App mobile
```bash
cd soteropolis-app
flutter pub get
flutter run --dart-define-from-file=dart_define.local.json
```

### Contrato Solana (devnet)
```bash
cd soteropolis-onchain
anchor build
anchor test
```

> Cada subprojeto tem seu próprio `.env.example` — nenhuma credencial real está commitada neste repositório.

## Segurança

- Row Level Security (RLS) no Supabase garante que cada cidadão só acessa os próprios dados.
- Idempotência de transações via coluna dedicada, prevenindo emissão duplicada de tokens em caso de retry de rede.
- Auditoria do contrato inteligente encontrou e corrigiu, antes do lançamento: validação de endereços de carteira matematicamente inválidos ("off-curve") e ausência de teto máximo de emissão por chamada.

**Pendências conhecidas antes de qualquer operação em mainnet** (documentadas conscientemente, não escondidas):
- Separar a chave de upgrade do contrato da chave operacional do backend.
- Revisar o custo de rent das contas de token.

## Testes

O repositório contém testes automatizados para o backend e para o programa on-chain. O fluxo atual de autenticação Supabase → MetaMask/Web3Auth → backend ainda não foi confirmado de ponta a ponta; execute novamente as suítes relevantes antes de considerar o MVP validado.

## Roadmap

- Firmar parceria piloto real com a Coelba e/ou a Limpurb.
- Validar o fluxo completo com moradores reais em um Ecoponto piloto em Salvador.
- Resolver as pendências de segurança documentadas.
- Migrar da devnet para a mainnet da Solana após validação do piloto.

## Autoria

Desenvolvido por **Leila Souza**.
