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
- **Chip dos módulos de telemetria**: todo módulo Ruptela, Galileosky ou Teltonika vem com chip (Claro, Vivo, Arquia Claro ou Arquia Vivo) ou sem chip, e o estoque é separado por isso. É possível pegar chips avulsos para instalar em módulos sem chip, trocar de operadora e descartar o chip de um módulo que não comunicou.
- **Quantidades** nunca aceitam negativo: no ajuste de inventário escolha **Aumentar** ou **Reduzir**.
- **Estoque e Cadastros**: a tela Estoque mostra a categoria e filtra por local, tipo de estoque, categoria e busca; em Cadastros, a lista de itens também tem busca e filtro por categoria.
- **Busca nos seletores**: item e cliente/unidade ficam em ordem alfabética e filtram enquanto você digita.
- **Alerta de estoque mínimo** na tela de Estoque.
- **Auditoria**: nada é apagado. Correções são estornos, feitos só por administrador, e ficam registradas.

## Perfis de acesso

| Ação | Administrador | Operador de estoque | Técnico | Consulta | Agendamento |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver saldo e histórico | todos os locais | só os estoques liberados para ele | não vê estoque nem histórico (só as transferências e solicitações dele) | todos os locais | todos os locais |
| Registrar entrada, saída, devolução, consumo, descarte, ajuste | ✓ | ✓ (nos seus estoques) | | | |
| Criar transferência (enviar) | ✓ | ✓ (do seu estoque) | | | |
| Confirmar recebimento | ✓ | ✓ (no seu estoque; no estoque de técnico que ele enviou ou da sua base) | ✓ (só o que foi enviado para ele) | | |
| Fazer solicitação | ✓ (escolhe de onde e para onde) | ✓ (escolhe de onde e para onde) | ✓ (só para o próprio estoque, saindo do estoque base dele) | | ✓ (escolhe de onde e para onde) |
| Aceitar e atender solicitação | ✓ | ✓ (da origem que ele opera) | | | |
| Cadastros (itens, clientes, técnicos, mínimos) e usuários | ✓ | | | | |
| Estornar movimentação | ✓ | | | | |

Essas regras são garantidas no banco de dados, não só nas telas.

### O que cada acesso faz, em palavras

- **Administrador**: tudo. Vê todos os estoques, registra qualquer movimentação, cria e confirma transferências, atende solicitações, estorna, cadastra itens, clientes, técnicos e usuários, e libera ou bloqueia o acesso das pessoas.
- **Operador de estoque**: trabalha nos estoques que o administrador liberou para ele (por exemplo, só Nova Lima). Neles registra entrada, saída, devolução, consumo, descarte e ajuste, envia transferências e atende solicitações que saem do estoque dele. Confirma recebimentos no estoque dele e também no estoque de um técnico quando foi ele quem enviou ou quando o técnico pertence à base dele (útil para técnico sem login). Não estorna nem mexe em cadastros.
- **Técnico**: só vê duas telas, **Transferências** e **Solicitações**. Em Transferências aparece apenas o que foi enviado para o estoque dele; ao chegar, ele confere os itens e quantidades e confirma o recebimento. Em Solicitações ele pede material de acordo com a demanda e vê só os pedidos dele. O pedido sempre é para o próprio estoque e sempre sai do **estoque base** dele. Ele não vê o Estoque geral, Registrar, Dedicados nem o Histórico.
- **Consulta**: só olha. Vê todos os estoques, transferências, solicitações, dedicados e histórico, sem nenhum botão de ação.
- **Agendamento**: igual à Consulta, mais a possibilidade de **fazer solicitações de transferência** (escolhendo de onde sai e para onde vai). Não registra movimentação, não envia nem confirma transferência e não atende pedidos.

Quem se cadastra entra **sem acesso** até um administrador escolher o perfil e marcar "Ativo" em Usuários.

### Termos usados no sistema

- **Livre**: saldo que pode sair para qualquer cliente. **Dedicado**: saldo reservado para um cliente/unidade específico, fora do estoque livre.
- **Em trânsito**: enviado, mas ainda não confirmado pelo destino. Não conta em nenhum dos dois estoques.
- **Estoque base**: o estoque fixo (São Bernardo ou Nova Lima) de onde saem os pedidos de um técnico.
- **Estoque do técnico**: o carro do técnico. Tem saldo próprio, como qualquer estoque.

## Telas

| Tela | Para que serve | Quem vê |
|---|---|---|
| Estoque | saldo por local e item, com categoria, filtros e alerta de mínimo | todos, menos o técnico |
| Registrar | entradas e saídas | administrador e operador |
| Transferências | lista de envios em andamento e concluídos; botão **Nova transferência** | todos (técnico vê só o que é para ele; criar: administrador e operador) |
| Solicitações | pedidos pendentes, em produção e concluídos; botão **Nova solicitação** | todos (técnico vê só os dele; criar: todos, menos Consulta) |
| Dedicados | onde está cada item dedicado e como movimentá-lo | todos, menos o técnico |
| Chips | instalar, trocar e descartar chip dos módulos, e saldo por chip | administrador e operador |
| Histórico | todas as movimentações; estorno (administrador) | todos |
| Cadastros | itens, clientes, técnicos e estoque mínimo | administrador |
| Usuários | liberar pessoas, perfil e estoques do operador | administrador |

## Como usar no dia a dia

1. **Entre** com e-mail e senha. Quem ainda não tem conta usa "Primeiro acesso" e espera um administrador liberar.
2. **Estoque**: veja o saldo por local, filtre por local, tipo de estoque ou categoria, ou busque um item. Itens abaixo do mínimo aparecem em destaque.
3. **Registrar**: escolha o tipo, o local, a data e os itens. Os tipos são entrada por compra (fornecedor e NF), devolução de cliente, saída para cliente, saída para estoque técnico, consumo interno ou teste, descarte e ajuste de inventário (com justificativa). Item e cliente/unidade se escolhem digitando para buscar. Em saída e devolução, escolha o cliente/unidade e, se quiser, informe o link do chamado do Jira (opcional). Na **saída para cliente**, informe também o modo de envio (e o técnico que leva, se for por técnico). Para criar um item dedicado, escolha o cliente em "Dedicado para (opcional)" na entrada por compra ou no ajuste.
4. **Transferências**: a tela abre com as transferências em andamento e as concluídas; o botão **Nova transferência** abre o formulário. No formulário, escolha de onde para onde, o meio de envio, o rastreio e o prazo. Para transformar estoque livre em dedicado, escolha o cliente em "Dedicado para". O destino confirma o recebimento na mesma tela.
5. **Solicitações**: a tela mostra as pendentes, as em produção e as concluídas; o botão **Nova solicitação** abre o formulário. O técnico pede só para o próprio estoque, saindo do estoque base dele. Cada item do pedido pode ser pedido já dedicado a um cliente ("Dedicado para"). Administrador, operador e agendamento escolhem de onde e para onde. Só administrador e operador (da origem) tratam o pedido: **Aceitar** leva para **Em produção**, com **prazo de 1 dia** para finalizar (a tela avisa se atrasar); depois **Atender (enviar)** gera a transferência, e o destino confirma o recebimento em Transferências. Depois de aceito, só administrador e operador cancelam.
6. **Dedicados**: acompanhe cada item reservado, do estoque até a entrega, e movimente-o: **Transferir** para outro estoque ou **Enviar ao cliente**.
7. **Chips**: os módulos de telemetria (Ruptela, Galileosky, Teltonika) têm o saldo separado por chip: sem chip, Claro, Vivo, Arquia Claro, Arquia Vivo. Ao registrar entrada, saída ou transferência de um módulo, escolha o chip. Os chips avulsos são itens normais (entre por compra em Registrar). Na tela **Chips**, escolha o estoque, o módulo, a quantidade, o chip que ele tem hoje e o que vai ficar: instalar um chip em módulo sem chip baixa 1 chip avulso; trocar de operadora devolve o chip antigo ao avulso; e se o módulo **não comunicou no teste**, retire o chip e escolha **Descartar** (com o motivo) para ele não voltar ao estoque.
7. **Histórico**: veja as movimentações, quem fez e quando. O administrador pode estornar uma movimentação informando o motivo.

### Para o administrador

- **Usuários**: quem se cadastra entra inativo. Escolha o perfil, marque "Ativo" e, para operador, marque os estoques que ele pode movimentar. Para os técnicos, veja Cadastros.
- **Cadastros**: adicione clientes e unidades, **técnicos** (CLT ou PJ, com ou sem login, cada um com o seu estoque), itens e ajuste o estoque mínimo de cada item. Cada técnico precisa de um **estoque base** (SBC ou Nova Lima): é de lá que saem os pedidos dele. Defina em Cadastros, Técnicos (os técnicos já cadastrados precisam ter o base escolhido uma vez). Para um técnico acessar o sistema, ele cria a conta, você marca o perfil "Técnico" em Usuários e liga o login dele ao cadastro dele em Cadastros, Técnicos.
- O **primeiro cadastro** do sistema vira administrador automaticamente.

## Estrutura do repositório

```
docs/        modelo de dados e catálogo de itens (94 itens em 15 categorias)
supabase/    banco de dados completo (um arquivo só, com os dados iniciais) e testes
web/         aplicativo web (Next.js 14 + Tailwind + Supabase)
testes-tela/ testes automáticos de tela (navegador), com banco e API locais de teste
```

O app lê pelas tabelas e views (protegidas por perfil) e **grava só pelas funções do banco** (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, `cancelar_transferencia`, `estornar_movimentacao`, `criar_solicitacao`, `atender_solicitacao`, `cancelar_solicitacao`). Elas checam perfil e local, travam o local contra uso simultâneo e desfazem tudo se algum saldo ficar negativo.

Mais detalhes do modelo estão em [`docs/modelo-de-dados.md`](docs/modelo-de-dados.md).

## Instalação (para quem vai rodar ou mexer no sistema)

Você precisa de Node.js 18 ou mais novo, Git e um projeto no [Supabase](https://supabase.com).

### 1. Banco de dados

No Supabase, abra o **SQL Editor**, copie **todo o conteúdo** do arquivo `supabase/banco_completo.sql` (não o nome do arquivo) e rode uma vez. Ele cria tabelas, segurança, funções e o catálogo inicial de itens. **Se o seu banco já existe**, rode em vez disso os arquivos de atualização que ainda não rodou, **nesta ordem**: `supabase/atualizar_solicitacao_producao.sql` e depois `supabase/atualizar_chips.sql` (cada um uma vez; quem cria o banco do zero com o `banco_completo.sql` atual não precisa deles).

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

### 3. Comandos úteis

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

## Próximos passos

- Ajustes de aparência (front-end).
- Tela de "esqueci minha senha".
- Relatórios e exportação.
- Publicação (por exemplo, na Vercel) com as mesmas variáveis do `.env.local`.
