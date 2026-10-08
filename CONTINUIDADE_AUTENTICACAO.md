# Continuidade — autenticação e Carteira Digital

Este documento é o ponto de retomada do trabalho no app Soterópolis Chain.
Foi escrito para que outra pessoa ou outra IA continue do estado atual sem
recomeçar a investigação. Leia também o README principal e o README do app.

## Checkout exato

O trabalho está no branch
`agents/projeto-analise-e-corrigindo-erros`, publicado no GitHub. Um clone
normal sem indicar branch começa no `main`, que não contém necessariamente
estas alterações. Clone diretamente o branch de continuidade:

```bash
git clone --branch agents/projeto-analise-e-corrigindo-erros --single-branch https://github.com/Leila-Souza430/projeto-soteropolis-chain.git
```

Commit base deste guia: `932ea81` (`fix: enable password auth for testing`).

## Evidências confirmadas

- O projeto Supabase está hospedado e o app Flutter usa sua URL e chave pública
  através de defines locais. Não incluir valores locais de configuração neste
  guia nem solicitar senhas/tokens à responsável.
- O login por magic link foi testado. O Supabase registrou `/verify` com
  `403: Email link is invalid or has expired` e `One-time token not found`.
  Isso demonstra falha na verificação daquele link, mas não identifica sozinho
  se estava expirado, já usado ou consumido por outro processamento.
- O template padrão “Magic link or OTP” foi inspecionado em modo preview e
  apresenta um link. O SMTP personalizado está desligado. O plano gratuito
  pode ter limites de envio, porém não foi provado que esse limite causou o
  erro de token inválido.
- O callback `soteropolisapp://supabase-auth-callback` consta na lista de
  Redirect URLs do Supabase e no intent filter Android. Um teste Android com
  URI de callback sintética confirmou o encaminhamento ao app; não confirmou
  a troca de código PKCE de um link real.
- A conta de teste criada pela interface de convite aparece como confirmada,
  mas o convite redirecionou para `localhost`. “Confirmed at” e “Last signed
  in” não provam que foi criada uma senha.
- Houve um relato anterior de “Não foi possível configurar sua Carteira
  Digital”, mas a tentativa mais recente (21:26, horário local) foi registrada
  pelo app como `AuthApiException`, HTTP 400, `invalid_credentials`,
  `Invalid login credentials`. O Supabase recusou a autenticação por senha,
  então essa tentativa não chegou ao MetaMask/Web3Auth. A senha não foi lida
  nem registrada neste diagnóstico.
- A ligação da carteira depende do MetaMask Embedded Wallets/Web3Auth e
  posteriormente do backend. A verificação local confirmou que a porta 8000
  não tem servidor escutando e que `soteropolis-backend/.env` não existe.
  `adb reverse` encaminha a porta USB, mas não inicia o backend.
- A conexão Supabase Custom Authentication no painel MetaMask foi configurada
  com JWKS, issuer e audience. A autenticação Web3Auth ainda não foi validada
  com sucesso.
- A documentação oficial Flutter de custom JWT usa o Embedded Wallets project
  client ID em `AuthConnectionConfig.clientId`. O branch foi atualizado para
  seguir esse exemplo em vez do valor local experimental anterior. O ajuste
  foi compilado e instalado; uma tentativa real com esse ajuste está pendente.
- A prévia do Supabase, após o callback sintético, registrou “No code detected
  in query parameters”. Isso era esperado para o teste sem código; não se deve
  interpretar como uma tentativa real de login.

## Código neste branch

- O app tem temporariamente um formulário de e-mail e senha para permitir
  testes sem envio de e-mail. A senha é mascarada na UI e não deve ser
  solicitada nem incluída em logs/documentação. A tentativa mais recente foi
  recusada pelo Supabase (`invalid_credentials`); autenticação por senha
  ainda não está comprovada.
- `AuthService.signInWithPasswordAndLinkWallet` autentica no Supabase e chama
  o vínculo/derivação da carteira em seguida.
- O listener de `onAuthStateChange` também tenta completar esse vínculo e
  apresenta erro de configuração da Carteira Digital quando falha.
- O callback magic-link Supabase continua no Manifest e na configuração de
  URL como opção para retomar o diagnóstico depois.
- O log do callback registra apenas esquema/host/caminho, sem query ou
  fragmento, para não expor código PKCE ou tokens.
- O README do app documenta defines necessários e os limites conhecidos.

## Validação feita

- `flutter build apk --debug --dart-define-from-file=dart_define.local.json`
  concluiu com sucesso e o APK foi instalado/aberto no Android.
- `flutter analyze` não apontou erros ligados às mudanças; emitiu um aviso
  informativo preexistente em `lib/services/api_client.dart:96`.
- `git diff --check` passou.
- O APK mais recente da tela de senha também compilou, foi instalado e aberto.
  O fato de compilar não valida o login da carteira.

## Próxima sequência recomendada

1. Não pedir novos links de e-mail por enquanto e não ativar SMTP sem um
   provedor controlado pela dona do projeto.
2. Definir/redefinir uma senha conhecida para a conta de teste. A conta criada
   por convite foi confirmada, mas isso não prova que a senha usada no app seja
   válida. Não apagar usuários existentes nem reutilizar o link de convite como
   prova de criação de senha.
3. Fazer uma única tentativa com credenciais sabidamente corretas e confirmar
   primeiro que o Supabase aceitou o login.
4. Com consentimento da responsável, coletar logs locais sanitizados. Nunca
   compartilhar senha, JWT, refresh token, código de callback ou URI completa.
5. Antes de testar o vínculo final, conferir se o backend FastAPI está rodando,
   se a URL de
   `API_BASE_URL` alcança o backend a partir do Android físico e se o `.env`
   do backend está configurado. Na última verificação, o arquivo `.env` não
   existia e a porta 8000 estava sem listener; o valor local de API aponta
   para loopback, portanto `adb reverse` não substitui o servidor.
6. Distinguir nos logs: retorno do `Web3AuthFlutter.connectTo`, falha de
   derivação de chave, erro HTTP do backend e ausência de serviço. Melhorar a
   mensagem de erro para orientar a pessoa sem revelar detalhes sensíveis.
7. Retestar Web3Auth com o ajuste do project client ID. Se falhar, obter
   `connectTo` e código de erro sanitizados e pedir à MetaMask confirmação
   sobre o comportamento do SDK v7. Nunca usar Client Secret no app.
8. Só então retestar Supabase → Web3Auth → carteira → backend como etapas
   separadas e documentar o resultado.
9. Retomar magic link/OTP depois. Tratar limite do plano gratuito e scanner/
   rastreador de links como hipóteses a testar, não como causa já provada.

## Dados deliberadamente fora do Git

- `soteropolis-app/dart_define.local.json` é ignorado pelo Git; um clone não
  terá esse arquivo. Criá-lo localmente com valores obtidos em canais
  apropriados.
- Não versionar `.env`, senha de conta de teste, chaves Supabase privilegiadas,
  access/refresh tokens, Client Secret MetaMask ou URLs de callback com
  parâmetros/códigos.
- O projeto Supabase, usuários, painel MetaMask e configuração hospedada não
  são clonados junto com o código; continuam associados às contas da dona.
