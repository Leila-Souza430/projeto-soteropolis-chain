# 🚀 PLANO DE AÇÃO MESTRE: SOTERÓPOLIS CHAIN (MVP)
**Projeto:** Plataforma GovTech Híbrida para Gestão Urbana e Recompensas via Green Tokens (Limpurb / Salvador)
**Diretrizes Técnicas:** 
- Simplicidade (KISS) e Modularidade.
- Segurança de Banco de Dados: Row Level Security (RLS) via Supabase Best Practices.
- Confiabilidade Financeira: Padrões de Idempotência e Auditoria (inspirados em Stripe Best Practices).
- Experiência do Usuário: Acessibilidade e atrito zero (Web Design Guidelines).
- Qualidade: Testes E2E integrados desde a concepção (Webapp Testing).

---

## 🗄️ FASE 1: FUNDAÇÃO DE DADOS & SEGURANÇA (SUPABASE / POSTGRES)
**Objetivo:** Estabelecer a camada de persistência com isolamento de dados e segurança rigorosa em nível de linha (RLS).

### 1.1 Configuração de Schema e Relacionamentos
Criar e executar o script SQL para as 4 tabelas principais:
* **`users` (Usuários):** 
  - `id` (UUID, PK, vinculado ao Auth do Supabase)
  - `email` (String)
  - `wallet_address` (String - Carteira Solana gerada via Web3Auth)
  - `instalacao_coelba` (String - Conta de luz para abatimento)
  - `created_at` (Timestamp)
* **`ecopontos` (Pontos Físicos):** 
  - `id` (UUID, PK), `nome` (String), `latitude` (Float), `longitude` (Float), `ativo` (Boolean)
* **`descartes` (Registro Antifraude):** 
  - `id` (UUID, PK), `user_id` (FK), `ecoponto_id` (FK), `tipo_residuo` (String), `peso_estimado` (Float), `foto_url` (String), `status` (Enum: "Pendente", "Validado", "Rejeitado"), `created_at` (Timestamp)
* **`transacoes_tokens` (Histórico On-Chain & Auditoria):** 
  - `id` (UUID, PK), `user_id` (FK), `tipo` (Enum: "MINT", "BURN"), `quantidade` (Float), `tx_hash` (String, único para garantir idempotência), `created_at` (Timestamp)

### 1.2 Políticas de Segurança (Row Level Security - RLS)
* Habilitar RLS em todas as tabelas.
* Criar políticas restritivas onde o cidadão autenticado só pode ler/escrever os seus próprios dados na tabela `users` e `descartes`.

---

## ⚙️ FASE 2: REGRA DE NEGÓCIO & ORQUESTRAÇÃO (BACKEND FASTAPI)
**Objetivo:** Construir a API central em Python aplicando validações robustas e tratamento de concorrência.

### 2.1 Estrutura Modular do Repositório
```text
soteropolis-backend/
├── main.py              # Inicialização e Middlewares
├── database.py          # Conexão segura com Supabase
├── models/              # Schemas de dados Pydantic
└── routers/
    ├── auth.py          # Gestão de perfis e carteiras
    ├── ecopontos.py     # Listagem geográfica
    └── descartes.py     # Endpoint crítico de envio de fotos e validação
```

### 2.2 Lógica de Validação Crítica e Idempotência

- **Geofencing (Fórmula de Haversine):** O backend calcula a distância entre a coordenada GPS enviada pelo app e a latitude/longitude do Ecoponto cadastrado. Tolerância máxima de 50 metros.
- **Timestamp de Servidor:** O horário do descarte é cravado pelo backend para impedir adulterações do relógio do cliente.
- **Idempotência de Transações:** Cada requisição de crédito de token (`Mint`) deve conter uma chave única ou hash de validação, impedindo duplicação de saldo em caso de falhas de rede ou reenvios pelo app.

---

## ⛓️ FASE 3: CAMADA ON-CHAIN & TOKENOMICS (SOLANA / ANCHOR)

**Objetivo:** Automatizar a emissão e a queima atômica de Green Tokens na rede Solana de forma transparente e segura.

**Status:** ✅ Concluída e testada — programa Anchor implantado em devnet e integrado ao backend (`services/blockchain.py`); fluxo de idempotência do `POST /descartes` (replay por `idempotency_key`, nova chave mintando corretamente, rejeição por geofencing) re-validado após a migração `idempotency_key`. Ver "Pendências de Segurança (Pré-Mainnet)" abaixo para itens a revisitar antes de produção real.

### 3.1 Arquitetura do Smart Contract (Rust / Anchor)

- **Token SPL:** Criação do ativo digital oficial do ecossistema (`Green Token - GT`).
- **Instrução `initialize`:** Configura a autoridade controladora do programa.
- **Instrução `mint_tokens`:** Executada de forma segura quando o backend valida o descarte, creditando tokens na carteira do cidadão.
- **Instrução `burn_tokens`:** Queima atômica dos tokens quando o usuário solicita o resgate do benefício na fatura de energia, mantendo o equilíbrio matemático (*Tokenomics*).

---

## ⚠️ PENDÊNCIAS DE SEGURANÇA (PRÉ-MAINNET)
**Contexto:** Achados da auditoria de segurança sobre `soteropolis-onchain/` (Fase 3). Nenhum dos dois itens abaixo bloqueia a Fase 3 — o ambiente atual é **devnet, sem dinheiro real em jogo**. Ambos devem ser revisitados antes de qualquer deploy em mainnet real.

### P.1 Autoridade de upgrade do programa == autoridade do backend (chave quente)
A mesma keypair (`9ER7DHqMG42wYjW2cyA9Q96VcSnn4mMSP7meRUwsyZmv`) é simultaneamente a autoridade de upgrade do programa Anchor, o `config.authority` on-chain, e a chave que o backend usa pra assinar mint/burn no dia a dia. Como o `PermanentDelegate` do mint já concede à Config PDA poder de queimar/transferir de qualquer conta do GT, quem tiver essa chave poderia, via upgrade do programa, adicionar uma instrução de transferência e drenar o saldo de todos os cidadãos — o "PermanentDelegate só é usado pra burn" é garantido apenas pelo código-fonte atual, não por nenhuma trava on-chain.

**Mitigação antes de qualquer deploy real:** separar a autoridade de upgrade da chave de assinatura do backend, idealmente atrás de um multisig (ex: Squads), e considerar zerar a autoridade de upgrade (torná-la imutável) quando o programa estiver estável.

### P.2 Rent de ATA de cidadão é permanentemente irrecuperável
Cada Associated Token Account criada para um cidadão custa ~0.00207 SOL de rent, pago pela autoridade (backend), e não pode ser reclamado — o cidadão nunca assina (carteira invisível), então não pode fechar a própria conta, e o `PermanentDelegate` concede poder de queima, não de fechamento de conta. Em escala: ~207 SOL travados pra 100 mil cidadãos, ~2074 SOL pra 1 milhão.

**Mitigação:** decisão orçamentária/arquitetural explícita antes de escalar pra produção real.

**Status (P.1 e P.2):** 🟡 Pendente — não bloqueiam a Fase 3, ambiente é devnet sem dinheiro real em jogo, revisitar antes de qualquer deploy em mainnet real.

---

## 📱 FASE 4: INTERFACE & EXPERIÊNCIA DO CIDADÃO (APP MOBILE - FLUTTER)

**Objetivo:** Desenvolver uma interface enxuta, acessível e de atrito zero para o público geral de Salvador, seguindo as Web Design Guidelines.

### 4.1 Autenticação Invisível
- Integração com Web3Auth (login social por e-mail ou CPF), gerando a carteira Solana em segundo plano sem exigir gestão de frases-senha pelo cidadão.

### 4.2 Fluxo Crítico de Telas
- **Home Dashboard:** Saldo em Green Tokens, status da coleta urbana e atalhos rápidos.
- **Câmera Antifraude:** Tela customizada que bloqueia o upload da galeria, exigindo captura em tempo real e embutindo metadados de GPS e timestamp.
- **Carteira Digital:** Extrato detalhado de ganhos e resgates.
- **Resgate de Benefício:** Tela para inserir o número da instalação da concessionária e abater o saldo.

---

## 🔌 FASE 5: INTEGRAÇÃO DE BENEFÍCIOS & TESTES E2E (MOCK COELBA)

**Objetivo:** Fechar o ciclo de valor do MVP e garantir estabilidade através de testes automatizados.

### 5.1 Simulador de API da Concessionária (Mock Webhook)
- Criação de um endpoint de teste simulando o sistema da Neoenergia Coelba. O endpoint valida o número de instalação, consome os tokens via queima na blockchain e retorna um recibo digital de desconto na fatura.

### 5.2 Testes Automatizados (Webapp Testing)
- Implementação de rotinas de teste ponta a ponta (E2E) simulando o ciclo completo: Captura de descarte -> Validação de GPS pelo FastAPI -> Emissão de Token -> Simulação de Abatimento na Coelba.
