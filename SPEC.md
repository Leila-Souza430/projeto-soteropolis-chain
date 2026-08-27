# 📄 SPEC.md: SOTERÓPOLIS CHAIN (Especificação Técnica do Projeto)

## 1. Visão Geral do Projeto
O **Soterópolis Chain** é uma solução GovTech híbrida focada em sustentabilidade urbana para a cidade de Salvador (Bahia). O objetivo principal é gamificar o descarte correto de resíduos recicláveis, transformando lixo em utilidade pública real: **créditos de Green Tokens que podem ser convertidos diretamente em descontos na fatura de energia elétrica** (em parceria simulada com a Neoenergia Coelba) e recompensas urbanas.

O projeto foi desenhado sob o princípio de **atrito zero** para o cidadão comum, escondendo a complexidade criptográfica em segundo plano e garantindo segurança rígida contra fraudes físicas e digitais.

---

## 2. Arquitetura e Stack Tecnológica
A arquitetura do sistema adota um modelo em camadas desacoplado, garantindo escalabilidade, segurança e facilidade de manutenção:

* **Frontend (Mobile App):** Desenvolvido em **Flutter** (focado em acessibilidade, alto contraste e usabilidade para o público não-técnico).
* **Backend & Orquestração:** Desenvolvido em **Python (FastAPI)**, responsável pelas regras de negócio, validações geográficas, controle de transações e integração.
* **Banco de Dados & Autenticação:** **Supabase (PostgreSQL)**, utilizando Row Level Security (RLS) estrito para isolamento de dados por usuário.
* **Camada Blockchain (Web3):** Rede **Solana**, utilizando contratos inteligentes em **Rust / Anchor** para a emissão e queima atômica do token utilitário oficial (`Green Token - GT`).
* **Autenticação Invisible Wallet:** Integração via **Web3Auth**, gerando carteiras Solana automáticas através de login social (e-mail ou CPF), sem exigir frases-senha complexas do cidadão.

---

## 3. Requisitos Funcionais & Regras de Negócio Críticas

### 3.1. Câmera Antifraude e Metadados
* **Bloqueio de Galeria:** O aplicativo em Flutter bloqueia o upload de fotos da galeria do celular. A imagem do resíduo deve ser capturada estritamente em tempo real pela câmera nativa no momento da entrega no Ecoponto.
* **Metadados Automáticos:** No momento do disparo da foto, o app injeta invisivelmente as coordenadas de GPS (`latitude` e `longitude`) e o carimbo de data/hora (`timestamp`).

### 3.2. Validação Geográfica (Geofencing)
* **Fórmula de Haversine (Backend):** O servidor em FastAPI recebe as coordenadas enviadas pelo app e calcula a distância exata em metros até o Ecoponto selecionado.
* **Tolerância Máxima:** Se a distância calculada for superior a **50 metros**, o backend rejeita o descarte instantaneamente, prevenindo fraudes remotas.

### 3.3. Idempotência e Segurança Financeira
* **Prevenção de Duplicidade:** Cada requisição de emissão de tokens (`Mint`) enviada pelo backend para a blockchain deve possuir uma chave única de idempotência/hash, garantindo que falhas de rede ou reenvios não gerem créditos duplicados para o usuário.
* **Auditoria de Transações:** Todas as operações de entrada e saída de tokens geram registros imutáveis no banco de dados para fins de auditoria governamental.

### 3.4. Ciclo de Resgate (Mock Coelba)
* O cidadão insere o número da sua instalação de energia elétrica.
* O sistema valida a conta, realiza a queima atômica (`Burn`) dos tokens correspondentes na Solana e emite um recibo digital de abatimento na fatura de energia.

---

## 4. Personas e Jornadas do Usuário

* **O Cidadão (Público Geral):** 
  - Busca facilidade para reciclar e economizar na conta de luz.
  - Não possui conhecimento técnico sobre blockchain, criptomoedas ou chaves privadas.
  - Utiliza login simplificado por CPF/Ecoponto e navega por telas com botões grandes, claros e de feedback visual imediato (seguindo *Web Design Guidelines*).
* **O Operador / Ecoponto:**
  - Pontos físicos de recebimento de recicláveis cadastrados no sistema geolocalizado da plataforma.

---

## 5. Padrões de Qualidade, Testes e Segurança
* **Isolamento de Dados (Supabase RLS):** Políticas de acesso restritas onde o usuário autenticado só visualiza e manipula seus próprios registros de descartes e saldos.
* **Testes Automatizados (E2E):** Suíte de testes ponta a ponta validando o fluxo completo: Captura de descarte $\rightarrow$ Validação de GPS $\rightarrow$ Emissão de Tokens $\rightarrow$ Simulação de Abatimento na Concessionária.
