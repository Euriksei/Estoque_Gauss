# Estoque Gauss

Sistema web para controlar a **entrada e a saída de equipamentos e insumos** da empresa, por quantidade, com níveis de acesso por perfil. Cada estoque (São Bernardo, Nova Lima e o carro de cada técnico) tem o próprio saldo, e todo movimento fica registrado e auditável.

## O que o sistema faz

- **Saldo por local e item** (sem separar novo e usado). O saldo nunca é digitado: ele é calculado a partir das movimentações e nunca pode ficar negativo.
- **Movimentações**: entrada por compra, devolução de cliente, saída para cliente, consumo interno ou teste, descarte e ajuste de inventário.
- **Saída para estoque técnico**: em Registrar, escolha "Saída para estoque técnico" e o técnico. O saldo sai do seu estoque na hora, mas só entra no estoque do técnico quando ele confirma o recebimento (em Transferências). Até lá, o item aparece como "em trânsito". Técnico sem login não confirma sozinho: o operador do estoque de origem (ou da base do técnico) ou um administrador confirma por ele.
- **Transferências em duas etapas**: quem envia informa data, meio de envio, código de rastreio e prazo de chegada, e o saldo sai do estoque dele na hora. O destino acompanha o envio e só recebe o saldo quando confirma o recebimento.
- **Técnicos (CLT e PJ)**: cada técnico é um cadastro com vínculo CLT ou PJ e tem o próprio estoque. Se ele usa o sistema, acessa só **Transferências** (o que foi enviado para ele, com confirmação do recebimento) e **Solicitações** (pede material e acompanha os pedidos dele). Técnicos sem login também podem ser cadastrados, para aparecerem como quem leva o material ao cliente.
- **Modo de envio na saída para cliente**: correios, sedex, retirada, transportadora ou técnico. Quando o envio é por técnico, escolhe-se qual técnico leva (a saída é registrada por administrador ou operador).
- **Itens dedicados a um cliente**: o item fica reservado para uma unidade de cliente, fora do estoque livre, com acompanhamento completo (guardado em qual estoque ou carro, em trânsito, entregue) e histórico. Ele **nasce** em Registrar (entrada por compra ou ajuste de inventário, campo "Dedicado para") ou numa transferência. Depois de dedicado, só se movimenta pela tela **Dedicados**: transferir para outro estoque ou enviar ao cliente (com modo de envio e técnico, como nas demais saídas).
- **Chicote junto com o módulo** (todos os rastreadores Ruptela, GalileoSky e Teltonika): cada linha de módulo tem a sua caixa "Com chicote", marcada por padrão, na entrada e na saída. Desmarque quando for só o módulo. Dá para misturar no mesmo registro (por exemplo, 6 FMC 650 com chicote e 2 FMC 150 sem). A quantidade de chicotes acompanha a do módulo e pode ser editada.
- **Chip dos módulos de telemetria**: todo módulo Ruptela, Galileosky ou Teltonika vem com chip (Claro, Vivo ou Arqia) ou sem chip, e o estoque é separado por isso. É possível pegar chips avulsos para instalar em módulos sem chip, trocar de operadora e descartar o chip de um módulo que não comunicou.
- **Quantidades** nunca aceitam negativo: no ajuste de inventário escolha **Aumentar** ou **Reduzir**.
- **Estoque e Cadastros**: a tela Estoque mostra a categoria e filtra por local, tipo de estoque, categoria e busca; em Cadastros, a lista de itens também tem busca e filtro por categoria.
- **Busca nos seletores**: item e cliente/unidade ficam em ordem alfabética e filtram enquanto você digita.
- **Alerta de estoque mínimo** na tela de Estoque.
- **Auditoria**: nada é apagado. Correções são estornos, feitos só por administrador, e ficam registradas.

## Perfis de acesso

| Ação | Administrador | Operador de estoque | Técnico | Consulta | Agendamento |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver saldo e histórico | todos os locais | só os estoques liberados para ele | não vê estoque nem histórico (só as transferências para o carro dele) | todos os locais | todos os locais |
| Registrar entrada, saída, devolução, consumo, descarte, ajuste | ✓ | ✓ (nos seus estoques) | | | |
| Criar pedido de transferência | ✓ | ✓ (de qualquer origem) | | | |
| Aceitar, preparar e enviar pedido de transferência | ✓ | ✓ (só quando a origem é um estoque dele) | | | |
| Confirmar recebimento | ✓ | ✓ (no seu estoque; no estoque de técnico cuja origem ou base é dele) | ✓ (só o que foi enviado para ele) | | |
| Criar solicitação (enviar ao cliente, enviar dedicado, retirar dedicado) | | | | | ✓ |
| Aceitar e atender solicitação | ✓ | ✓ (origem dele; no retirar dedicado, o destino dele) | | | |
| Cancelar pedido ou solicitação (aberta ou em produção) | ✓ | ✓ (só quando a origem é um estoque dele; no retirar dedicado, o destino) | | | ✓ (só a que ele criou, enquanto não foi aceita) |
| Cadastros (itens, clientes, técnicos, mínimos) e usuários | ✓ | | | | |
| Estornar movimentação | ✓ | | | | |

Essas regras são garantidas no banco de dados, não só nas telas.

### O que cada acesso faz, em palavras

- **Administrador**: tudo. Vê todos os estoques, registra qualquer movimentação, cria pedidos de transferência e dá andamento a qualquer pedido ou solicitação, confirma recebimentos, estorna, cadastra itens, clientes, técnicos e usuários, e libera ou bloqueia o acesso das pessoas.
- **Operador de estoque**: trabalha nos estoques que o administrador liberou para ele (por exemplo, só Nova Lima). Neles registra entrada, saída, devolução, consumo, descarte e ajuste (movimentação avulsa). Cria **pedidos de transferência** de qualquer origem (por exemplo, Nova Lima pedindo do SBC), mas quem aceita, prepara e envia é o operador da **origem**. Aceita e atende as solicitações do agendamento cuja origem é dele (no **retirar dedicado**, quando o destino é dele). Confirma recebimentos no estoque dele e também no estoque de um técnico quando a origem ou a base do técnico é dele (útil para técnico sem login). Não estorna nem mexe em cadastros.
- **Técnico**: só vê a tela **Transferências**, com os pedidos e envios para o carro dele. Quando o material chega, ele confere os itens e quantidades e confirma o recebimento. Não cria pedidos e não vê Estoque, Registrar, Solicitações, Dedicados nem Histórico.
- **Consulta**: só olha. Vê todos os estoques, transferências, solicitações, dedicados e histórico, sem nenhum botão de ação.
- **Agendamento**: igual à Consulta, mais as **solicitações**, que só ele cria: **Enviar ao cliente** (itens do estoque livre de qualquer estoque para um cliente/unidade), **Enviar dedicado** (o dedicado inteiro do cliente guardado num estoque) e **Retirar dedicado** (buscar itens no cliente e trazer para um estoque, onde chegam já dedicados a ele). Não registra movimentação, não cria pedido de transferência e não dá andamento a pedidos.

Quem se cadastra entra **sem acesso** até um administrador escolher o perfil e marcar "Ativo" em Usuários.

### Senha

- **Esqueci minha senha**: na tela de login, clique em "Esqueci minha senha" e informe o e-mail. Chega um link para criar uma nova senha (o link vale uma vez e expira).
- **Trocar senha**: logado, clique na **engrenagem** (Configurações) no topo da tela e escolha **Mudar senha**. Vale para todos os perfis.

### Termos usados no sistema

- **Livre**: saldo que pode sair para qualquer cliente. **Dedicado**: saldo reservado para um cliente/unidade específico, fora do estoque livre.
- **Em trânsito**: enviado, mas ainda não confirmado pelo destino. Não conta em nenhum dos dois estoques.
- **Estoque base**: o estoque fixo (São Bernardo ou Nova Lima) de onde saem os pedidos de um técnico.
- **Estoque do técnico**: o carro do técnico. Tem saldo próprio, como qualquer estoque.

## Telas

| Tela | Para que serve | Quem vê |
|---|---|---|
| Estoque | saldo livre por local e item (com as colunas de chip), filtros e alerta de mínimo; abaixo, o **Estoque dedicado** por cliente/unidade | todos, menos o técnico |
| Registrar | movimentação avulsa: entradas, saídas, devolução, consumo, descarte e ajuste | administrador e operador |
| Transferências | pedidos entre estoques: pendentes, em produção (prazo de 1 dia), em trânsito e concluídas; botão **Novo pedido de transferência** | todos (técnico vê só o que é para o carro dele; criar: administrador e operador) |
| Solicitações | pedidos do agendamento para o cliente: pendentes, em produção e concluídas; botão **Nova solicitação** | todos, menos o técnico (criar: só agendamento) |
| Dedicados | onde está cada item dedicado; movimenta o dedicado inteiro de um cliente num estoque | todos, menos o técnico |
| Chips | instalar, trocar e descartar chip dos módulos, e saldo por chip | administrador e operador |
| Histórico | todas as movimentações; estorno (administrador) | todos, menos o técnico |
| Cadastros | itens, clientes, técnicos e estoque mínimo | administrador |
| Usuários | liberar pessoas, perfil e estoques do operador | administrador |

## Como usar no dia a dia

1. **Entre** com e-mail e senha. Quem ainda não tem conta usa "Primeiro acesso" e espera um administrador liberar.
2. **Estoque**: veja o saldo livre por local, filtre por local, tipo de estoque ou categoria, ou busque um item. Itens abaixo do mínimo aparecem em destaque (o mínimo conta só o livre). O saldo dedicado não entra nessa conta: ele aparece separado em **Estoque dedicado**, por cliente/unidade, com os próprios totais.
3. **Registrar** (movimentação avulsa, por exemplo um pedido de boca): escolha o tipo, a data (nunca futura) e os itens; o local já vem escolhido quando você só tem um. Os tipos são entrada por compra (fornecedor e NF), devolução de cliente, saída para cliente, consumo interno ou teste, descarte e ajuste de inventário (com justificativa). Nas saídas, cada linha mostra o **Disponível** no local e o sistema não deixa tirar mais do que há. Em saída e devolução, escolha o cliente/unidade e, se quiser, o link do chamado do Jira. Na **saída para cliente**, informe também o modo de envio (e o técnico que leva, se for por técnico). Para criar um item dedicado, escolha o cliente em "Dedicado para (opcional)" na **devolução de cliente** ou no **ajuste**. Envio para o carro de um técnico ou para outro estoque é pedido de transferência.
4. **Transferências** (entre estoques): administrador ou operador clica em **Novo pedido de transferência** e escolhe a origem, o destino (estoque fixo ou carro de técnico), os itens do estoque livre (com "Dedicado para", se o item deve chegar dedicado a um cliente) e, se houver, os **dedicados** da origem, que vão inteiros (a tela mostra o que vai junto). Chamado do Jira e observação são opcionais. O saldo **não sai** ao criar o pedido. O administrador ou o operador da **origem** clica em **Aceitar** (vai para **Em produção**, com **prazo de 1 dia**; a tela avisa se atrasar) e depois em **Preparar e enviar**, informando a data de envio (nunca futura), o meio (Correios, retirada, transportadora ou técnico), o rastreio, o prazo de chegada e o chip de cada módulo. Aí o pedido vai para **Em trânsito** e o saldo sai da origem. O destino (técnico, operador do destino ou administrador; para técnico sem login, o operador da origem ou da base dele) clica em **Confirmar recebimento**. Pendente pode ser cancelado por quem criou, administrador ou operador; em produção, só por administrador ou operador. Um envio em trânsito pode ser cancelado pela origem, com motivo.
5. **Solicitações** (só o agendamento cria): clique em **Nova solicitação** e escolha o tipo. **Enviar ao cliente**: o estoque de origem, o cliente/unidade e os itens (só do estoque livre). **Enviar dedicado**: o cliente/unidade e o estoque onde está o dedicado; vai o dedicado inteiro, e a tela mostra o que vai junto. **Retirar dedicado**: o cliente/unidade, os itens e quantidades a buscar e o estoque que recebe. O link do chamado do Jira é **obrigatório** em **Enviar dedicado** e **Retirar dedicado** (começando com http:// ou https://) e opcional em Enviar ao cliente; a observação é opcional. O administrador ou o operador da origem (no retirar dedicado, do destino) clica em **Aceitar** (**Em produção**, prazo de 1 dia) e depois atende: em **Enviar ao cliente** informa a data, o meio de envio (e o técnico, se for por técnico), o rastreio e o chip de cada módulo, e a saída para o cliente é registrada na hora; em **Registrar chegada** (retirar dedicado) o material entra como devolução de cliente já dedicada àquela unidade. Depois de aceita, só administrador e operador cancelam.
6. **Dedicados**: acompanhe cada item reservado, do estoque até a entrega. A movimentação leva sempre o **dedicado inteiro** do cliente naquele estoque: **Transferir tudo** cria um pedido de transferência (que segue em Transferências) e **Enviar tudo ao cliente** registra a saída na hora.
7. **Chips**: os módulos de telemetria (Ruptela, Galileosky, Teltonika) têm o saldo separado por chip: sem chip, Claro, Vivo, Arqia. Ao registrar entrada ou saída de um módulo, escolha o chip; em pedidos e solicitações, o chip é escolhido por quem envia. Os chips avulsos são itens normais (entre por compra em Registrar). Na tela **Chips**, escolha o estoque, o módulo, a quantidade, o chip que ele tem hoje e o que vai ficar: instalar um chip em módulo sem chip baixa 1 chip avulso; trocar de operadora devolve o chip antigo ao avulso; e se o módulo **não comunicou no teste**, retire o chip e escolha **Descartar** (com o motivo) para ele não voltar ao estoque. Para trocar um chip ruim por **outro da mesma operadora**, deixe o mesmo chip nos dois campos: o antigo é descartado e sai outro do estoque avulso.
8. **Histórico**: veja as movimentações, quem fez e quando. O administrador pode estornar uma movimentação informando o motivo.

### Para o administrador

- **Usuários**: quem se cadastra entra inativo. Escolha o perfil, marque "Ativo" e, para operador, marque os estoques que ele pode movimentar; para agendamento, escolha o estoque dele. Para os técnicos, veja Cadastros.
- **Cadastros**: adicione clientes e unidades, **técnicos** (CLT ou PJ, com ou sem login, cada um com o seu estoque), itens e ajuste o estoque mínimo de cada item. Cada técnico precisa de um **estoque base** (SBC ou Nova Lima): é de lá que saem os pedidos dele. Defina em Cadastros, Técnicos (os técnicos já cadastrados precisam ter o base escolhido uma vez). Para um técnico acessar o sistema, ele cria a conta, você marca o perfil "Técnico" em Usuários e liga o login dele ao cadastro dele em Cadastros, Técnicos.
- **Ver como**: na engrenagem (Configurações) do topo, o administrador escolhe **Ver como** e um perfil (Administrador, Operador, Técnico, Consulta ou Agendamento), o estoque fixo (Nova Lima ou SBC) quando o perfil pede (operador e agendamento; na consulta é opcional) e o técnico quando o perfil é Técnico (só técnicos com carro; a base é a do carro). O app recarrega com os menus, as telas e as **permissões de verdade** desse perfil, também no banco. Enquanto isso, uma faixa amarela no topo de todas as telas mostra, por exemplo, "Vendo como Operador - Nova Lima", com o botão **Voltar a administrador**. O cadastro do administrador não muda, e o histórico continua registrando o usuário real.
- O **primeiro cadastro** do sistema vira administrador automaticamente.

## Estrutura do repositório

```
docs/        modelo de dados e catálogo de itens (77 itens em 14 categorias)
supabase/    banco de dados completo (um arquivo só, com os dados iniciais) e testes
web/         aplicativo web (Next.js 14 + Tailwind + Supabase)
testes-tela/ testes automáticos de tela (navegador), com banco e API locais de teste
```

O app lê pelas tabelas e views (protegidas por perfil) e **grava só pelas funções do banco** (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, `cancelar_transferencia`, `estornar_movimentacao`, `criar_solicitacao`, `atender_solicitacao`, `cancelar_solicitacao`). Elas checam perfil e local, travam o local contra uso simultâneo e desfazem tudo se algum saldo ficar negativo.

Mais detalhes do modelo estão em [`docs/modelo-de-dados.md`](docs/modelo-de-dados.md).

## Instalação (para quem vai rodar ou mexer no sistema)

Você precisa de Node.js 18 ou mais novo, Git e um projeto no [Supabase](https://supabase.com).

### 1. Banco de dados

No Supabase, abra o **SQL Editor**, copie **todo o conteúdo** do arquivo `supabase/banco_completo.sql` (não o nome do arquivo) e rode uma vez. Ele cria tabelas, segurança, funções e o catálogo inicial de itens. **Se o seu banco já existe**, rode em vez disso os arquivos de atualização que ainda não rodou, **nesta ordem**: `supabase/atualizar_solicitacao_producao.sql`, `supabase/atualizar_chips.sql`, `supabase/atualizar_regras_solicitacao.sql`, `supabase/atualizar_catalogo.sql`, `supabase/atualizar_permissoes_funcoes.sql`, `supabase/atualizar_regras_dedicado_datas.sql`, `supabase/atualizar_fluxo_pedidos.sql` e `supabase/atualizar_ver_como.sql` (cada um uma vez, sempre nesta ordem; quem cria o banco do zero com o `banco_completo.sql` atual não precisa deles).

Quem já tinha rodado as migrações antigas **não deve rodar este arquivo de novo**: o banco dele já está completo. Mudanças futuras virão como arquivos novos de atualização.

Deve terminar com "Success". Para testes, em Authentication, Providers, Email você pode desligar "Confirm email".

### 2. Aplicativo

```
cd web
npm install
```

Crie o arquivo `web/.env.local` com os dados do seu projeto (Settings, API no Supabase):

```
NEXT_PUBLIC_SUPABASE_URL=https://SEU-PROJETO.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sua-chave-publica
```

Use só a chave **pública** (publishable). Nunca coloque a chave secreta (service role) no app nem no repositório. O `.env.local` já está no `.gitignore`.

```
npm run dev
```

Abra http://localhost:3000, clique em "Primeiro acesso" e crie sua conta. Ela será o primeiro administrador.

### 3. E-mail de recuperação de senha

Para o link de "Esqueci minha senha" funcionar, configure no Supabase:

1. **Authentication, URL Configuration**: em *Site URL*, o endereço do sistema (ex.: `https://estoque.suaempresa.com.br`). Em *Redirect URLs*, adicione `https://estoque.suaempresa.com.br/**` e, para testes, `http://localhost:3000/**`.
2. **Authentication, Email Templates, Reset Password**: troque o link do modelo por:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery&next=/redefinir-senha">Criar nova senha</a>
```

O link usa o *Site URL*; para testar em `localhost`, coloque temporariamente `http://localhost:3000` no *Site URL*. O servidor de e-mail padrão do Supabase envia poucos e-mails por hora; em produção, configure um SMTP próprio em *Authentication, SMTP Settings*.

### 4. Comandos úteis

| Comando (dentro de `web/`) | Para quê |
|---|---|
| `npm run dev` | rodar em modo de desenvolvimento |
| `npm run build` | gerar a versão de produção |
| `npm run start` | rodar a versão de produção (depois do build) |
| `npm run typecheck` | checar os tipos do TypeScript |

## Testes do banco

`supabase/tests/` tem um cenário que exercita permissões, transferência em duas etapas, estoque do técnico e itens dedicados. Ele roda num PostgreSQL 15 ou mais novo comum: rode `00_stub_auth.sql` (simula o login do Supabase), `banco_completo.sql` e por fim `01_cenarios.sql`. Os erros que aparecem no resultado são esperados, cada um marcado "deve falhar".

## Testes de tela

`testes-tela/` tem testes automáticos que abrem o app num navegador e percorrem as telas de cada perfil (entrada com e sem chicote, saída mista, estoque do técnico, solicitações, dedicados, filtros, agendamento e consulta). Eles sobem um banco e uma API **locais de teste**, sem tocar no seu Supabase. Para rodar: `testes-tela/rodar.sh` (precisa de PostgreSQL 15+ e Node; veja o cabeçalho do script). Cada verificação aparece com ✔ ou ✘.

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `npm install` diz que não acha o `package.json` | Você não está na pasta `web`. Rode `cd web` antes. |
| `'next' não é reconhecido` | As dependências não foram instaladas. Rode `npm install` em `web/`. |
| "Your project's URL and Key are required" | Falta o `web/.env.local` ou o nome da variável está errado. Reinicie o `npm run dev` depois de criá-lo. |
| O SQL Editor dá erro de sintaxe em `supabase/banco_completo...` | Foi colado o nome do arquivo. Cole o conteúdo dele. |
| Entro e volto para o login, ou aparece "Aguardando liberação" | A conta ainda não foi liberada, ou não tem linha na tabela de usuários. Peça a um administrador para liberar (o primeiro cadastro vira administrador sozinho). |
| "Saldo insuficiente" | O local não tem a quantidade (livre ou dedicado, conforme a reserva escolhida). Confira o saldo na tela Estoque. |
| "Sem permissão para movimentar este local" | O seu perfil ou os estoques liberados para você não incluem esse local. Peça a um administrador. |

## Segurança

- As regras de acesso são aplicadas no banco (segurança por linha do Supabase) e valem mesmo que alguém chame a API diretamente.
- Quem se cadastra entra sem acesso e inativo, até um administrador liberar.
- Nada de chaves secretas no repositório: só a chave pública vai no app.

## Checklist

Atualizado a cada sessão de trabalho. Marque `[x]` quando concluir e anote a data.

### Feito

- [x] Saldo por local, movimentações, transferências em duas etapas e auditoria com estorno
- [x] Técnicos (CLT/PJ), estoque do técnico e confirmação de recebimento
- [x] Itens dedicados a cliente e tela Dedicados
- [x] Chicote junto com o módulo e chip dos módulos (tela Chips)
- [x] Solicitações com "Em produção" (prazo de 1 dia) e regras por perfil
- [x] Tela de "esqueci minha senha" e troca de senha logado
- [x] Catálogo de itens corrigido (lista enviada em 2026-11-23, 77 itens em 14 categorias): "DVR DashCAM" vira "DashCAM", "DVR Intelbras 3404" e "5404" viram "MDVR Intelbras 3404" e "MDVR Intelbras 5404" (continuam separados) — 2026-11-23
- [x] Tela Estoque mostra cada módulo numa linha, com as colunas Sem chip, Vivo, Claro, Arqia e o total, para todos os perfis que veem estoque — 2026-11-23
- [x] Registrar: tela de movimentação avulsa (ex.: pedido feito de boca). O operador só registra saída do estoque físico dele (ex.: base Nova Lima → só Nova Lima), e o formulário já mostra o saldo disponível por chip e bloqueia quantidade maior que o saldo (ex.: FMC 650 Vivo) — 2026-11-23
- [x] Segurança: funções internas do banco fechadas para usuário logado (`atualizar_permissoes_funcoes.sql`) — 2026-11-23
- [x] Nenhuma data futura em entrada, saída, transferência, solicitação ou chip (o prazo de chegada pode ser futuro) — 2026-11-23
- [x] Meio de envio: juntar "Correios" e "Sedex" numa opção só — 2026-11-23
- [x] Dedicado só nasce por devolução de cliente, recebimento de transferência ou ajuste de inventário (sai da entrada por compra) — 2026-11-23
- [x] Dedicado se movimenta inteiro: todo o saldo dedicado daquela unidade naquele estoque, ou nada — 2026-11-23
- [x] Estoque: saldo dedicado fora da contagem geral, com contagem própria — 2026-11-23
- [x] Cadastros: formulários de "novo" começam fechados e abrem ao clicar em criar/adicionar — 2026-11-23
- [x] Topo: trocar o botão "Senha" por um ícone de engrenagem (Configurações), com "Mudar senha" dentro — 2026-11-23
- [x] Transferências viram pedido: admin/operador pedem, só a origem aceita, prepara e envia, o destino confirma; campo para o chamado (Jira) — 2026-11-23
- [x] Solicitações só pelo agendamento: origem → cliente/unidade, sem campo de dedicado; a origem escolhe o meio ao enviar; botões "Enviar dedicado" e "Retirar dedicado" — 2026-11-23
- [x] Solicitações "Enviar dedicado" e "Retirar dedicado": link do chamado obrigatório (tela e banco) — 2026-11-23
- [x] Atualizações rodadas no Supabase (catálogo, permissões, dedicado/datas, fluxo de pedidos), com backup antes — 2026-11-23
- [x] Admin: em Configurações (engrenagem), "Ver como" outro perfil (operador, técnico, consulta, agendamento) com os mesmos acessos de verdade, escolhendo o estoque fixo (Nova Lima ou SBC), e botão para voltar a administrador — 2026-11-23 (rodado no Supabase)

### A fazer

- [ ] Testes de tela: reescrever o 3 e partes do 4 para o fluxo novo de pedidos e rodar do 3 ao 7 (as mudanças de 2026-11-23 ainda não foram testadas logado no navegador)
- [ ] Testes de tela rodarem no Windows (`testes-tela/rodar.sh` hoje só roda no Linux: acentos e caminho do PostgreSQL)
- [ ] (Depois) Chamado obrigatório também em "Enviar ao cliente" e nos pedidos de transferência
- [ ] Testar no Supabase a troca de chip pela mesma operadora (PR #4), já aplicada em 2026-11-23
- [ ] Ajustes de aparência (front-end)
- [ ] Relatórios e exportação
- [ ] Publicação (por exemplo, na Vercel) com as mesmas variáveis do `.env.local`
