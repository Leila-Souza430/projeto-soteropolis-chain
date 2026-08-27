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

1. Cidadão faz login por e-mail (link mágico, sem senha). Uma carteira Solana é criada automaticamente em segundo plano.
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

MVP completo, construído e testado em 5 fases sequenciais — cada uma validada contra ambiente real antes de avançar para a próxima:

- [x] **Fase 1 — Fundação de dados**: schema no Supabase com Row Level Security (RLS).
- [x] **Fase 2 — Backend**: API FastAPI com geofencing, idempotência e auditoria, testada contra Supabase real.
- [x] **Fase 3 — Blockchain**: contrato Anchor implantado na devnet da Solana, com mint/burn reais e auditoria de segurança.
- [x] **Fase 4 — App mobile**: aplicativo Flutter compilado e testado em dispositivo Android físico, com autenticação real.
- [x] **Fase 5 — Integração e testes**: 11 testes E2E automatizados passando contra Supabase e devnet reais, sem simulações.

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

Suíte de 11 testes automatizados de ponta a ponta (pytest), cobrindo o fluxo completo — captura de descarte → validação de GPS → emissão de token → simulação de resgate — rodando contra o Supabase e a devnet da Solana **reais**, sem mocks escondendo eventuais bugs.

## Roadmap

- Firmar parceria piloto real com a Coelba e/ou a Limpurb.
- Validar o fluxo completo com moradores reais em um Ecoponto piloto em Salvador.
- Resolver as pendências de segurança documentadas.
- Migrar da devnet para a mainnet da Solana após validação do piloto.

## Autoria

Desenvolvido por **Leila Souza**.
