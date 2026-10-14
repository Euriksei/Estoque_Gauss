# Estoque Gauss

Sistema web para controlar a **entrada e a saída de equipamentos e insumos** da empresa, por quantidade, com níveis de acesso por perfil. Cada estoque (São Bernardo, Nova Lima e o carro de cada técnico) tem o próprio saldo, e todo movimento fica registrado e auditável.

## O que o sistema faz

- **Saldo por local e item** (sem separar novo e usado). O saldo nunca é digitado: ele é calculado a partir das movimentações e nunca pode ficar negativo.
- **Movimentações**: entrada por compra, devolução de cliente, saída para cliente, consumo interno ou teste, descarte e ajuste de inventário.
- **Saída para estoque técnico**: em Registrar, escolha "Saída para estoque técnico" e o técnico. O saldo sai do seu estoque na hora, mas só entra no estoque do técnico quando ele confirma o recebimento (em Transferências). Até lá, o item aparece como "em trânsito". Técnico sem login não confirma sozinho: o operador do estoque de origem (ou da base do técnico) ou um administrador confirma por ele.
- **Transferências em duas etapas**: quem envia informa data, meio de envio, código de rastreio e prazo de chegada, e o saldo sai do estoque dele na hora. O destino acompanha o envio e só recebe o saldo quando confirma o recebimento.
- **Técnicos (CLT e PJ)**: cada técnico é um cadastro com vínculo CLT ou PJ e tem o próprio estoque. Se ele usa o sistema, vê só o próprio estoque, pede material, dá baixa do que usou no cliente e confirma o que recebe. Técnicos sem login também podem ser cadastrados, para aparecerem como quem leva o material ao cliente.
- **Modo de envio na saída para cliente**: correios, sedex, retirada, transportadora ou técnico. Quando o envio é por técnico, escolhe-se qual técnico leva; quando o próprio técnico dá a baixa, ele já fica registrado como quem levou.
- **Itens dedicados a um cliente**: o item fica reservado para uma unidade de cliente, fora do estoque livre, com acompanhamento completo (guardado em qual estoque ou carro, em trânsito, entregue) e histórico. Ele **nasce** em Registrar (entrada por compra ou ajuste de inventário, campo "Dedicado para") ou numa transferência. Depois de dedicado, só se movimenta pela tela **Dedicados**: transferir para outro estoque ou enviar ao cliente (com modo de envio e técnico, como nas demais saídas).
- **Chicote junto com o módulo** (todos os rastreadores Ruptela, GalileoSky e Teltonika): cada linha de módulo tem a sua caixa "Com chicote", marcada por padrão, na entrada e na saída. Desmarque quando for só o módulo. Dá para misturar no mesmo registro (por exemplo, 6 FMC 650 com chicote e 2 FMC 150 sem). A quantidade de chicotes acompanha a do módulo e pode ser editada.
- **Quantidades** nunca aceitam negativo: no ajuste de inventário escolha **Aumentar** ou **Reduzir**.
- **Busca nos seletores**: item e cliente/unidade ficam em ordem alfabética e filtram enquanto você digita.
- **Alerta de estoque mínimo** na tela de Estoque.
- **Auditoria**: nada é apagado. Correções são estornos, feitos só por administrador, e ficam registradas.

## Perfis de acesso

| Ação | Administrador | Operador de estoque | Técnico | Consulta | Agendamento |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver saldo e histórico | todos os locais | só os estoques liberados para ele | só o próprio estoque | todos os locais | todos os locais |
| Registrar entrada, saída, devolução, consumo, descarte, ajuste | ✓ | ✓ (nos seus estoques) | só saída para cliente, do próprio estoque | | |
| Criar transferência (enviar) | ✓ | ✓ (do seu estoque) | | | |
| Confirmar recebimento | ✓ | ✓ (no seu estoque; no estoque de técnico que ele enviou ou da sua base) | ✓ (no próprio estoque) | | |
| Fazer solicitação | ✓ (escolhe de onde e para onde) | ✓ (escolhe de onde e para onde) | ✓ (só para o próprio estoque, saindo do estoque base dele) | | ✓ (escolhe de onde e para onde) |
| Atender solicitação | ✓ | ✓ (da origem que ele opera) | | | |
| Cadastros (itens, clientes, técnicos, mínimos) e usuários | ✓ | | | | |
| Estornar movimentação | ✓ | | | | |

Essas regras são garantidas no banco de dados, não só nas telas.

## Como usar no dia a dia

1. **Entre** com e-mail e senha. Quem ainda não tem conta usa "Primeiro acesso" e espera um administrador liberar.
2. **Estoque**: veja o saldo por local, filtre por local ou busque um item. Itens abaixo do mínimo aparecem em destaque.
3. **Registrar**: escolha o tipo, o local, a data e os itens. Em saída e devolução, escolha o cliente/unidade e, se quiser, informe o link do chamado do Jira (opcional). Na **saída para cliente**, informe também o modo de envio (e o técnico que leva, se for por técnico). Para criar um item dedicado, escolha o cliente em "Dedicado para (opcional)" na entrada por compra ou no ajuste.
4. **Transferências**: a tela abre com as transferências em andamento e as concluídas; o botão **Nova transferência** abre o formulário. No formulário, escolha de onde para onde, o meio de envio, o rastreio e o prazo. Para transformar estoque livre em dedicado, escolha o cliente em "Dedicado para". O destino confirma o recebimento na mesma tela.
5. **Solicitações**: a tela mostra as pendentes e as concluídas; o botão **Nova solicitação** abre o formulário. O técnico pede só para o próprio estoque, saindo do estoque base dele. Cada item do pedido pode ser pedido já dedicado a um cliente ("Dedicado para"). Administrador, operador e agendamento escolhem de onde e para onde. Administrador e operador (da origem) atendem, e o envio segue como transferência; o destino confirma o recebimento em Transferências.
6. **Dedicados**: acompanhe cada item reservado, do estoque até a entrega, e movimente-o: **Transferir** para outro estoque ou **Enviar ao cliente**.
7. **Histórico**: veja as movimentações. O administrador pode estornar uma movimentação informando o motivo.

### Para o administrador

- **Usuários**: quem se cadastra entra inativo. Escolha o perfil, marque "Ativo" e, para operador, marque os estoques que ele pode movimentar. Para os técnicos, veja Cadastros.
- **Cadastros**: adicione clientes e unidades, **técnicos** (CLT ou PJ, com ou sem login, cada um com o seu estoque), itens e ajuste o estoque mínimo de cada item. Cada técnico precisa de um **estoque base** (SBC ou Nova Lima): é de lá que saem os pedidos dele. Defina em Cadastros, Técnicos (os técnicos já cadastrados precisam ter o base escolhido uma vez). Para um técnico acessar o sistema, ele cria a conta, você marca o perfil "Técnico" em Usuários e liga o login dele ao cadastro dele em Cadastros, Técnicos.
- O **primeiro cadastro** do sistema vira administrador automaticamente.

## Estrutura do repositório

```
docs/        modelo de dados e catálogo de itens (94 itens em 15 categorias)
supabase/    banco de dados: migrações, carga inicial e testes
web/         aplicativo web (Next.js 14 + Tailwind + Supabase)
```

O app lê pelas tabelas e views (protegidas por perfil) e **grava só pelas funções do banco** (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, `cancelar_transferencia`, `estornar_movimentacao`, `criar_solicitacao`, `atender_solicitacao`, `cancelar_solicitacao`). Elas checam perfil e local, travam o local contra uso simultâneo e desfazem tudo se algum saldo ficar negativo.

Mais detalhes do modelo estão em [`docs/modelo-de-dados.md`](docs/modelo-de-dados.md).

## Instalação (para quem vai rodar ou mexer no sistema)

Você precisa de Node.js 18 ou mais novo, Git e um projeto no [Supabase](https://supabase.com).

### 1. Banco de dados

No Supabase, abra o **SQL Editor** e rode, **nesta ordem**, o *conteúdo* de cada arquivo (abra o arquivo, copie todo o texto e cole no editor, não o nome do arquivo):

1. `supabase/migrations/0001_schema.sql`
2. `supabase/migrations/0002_seguranca_e_funcoes.sql`
3. `supabase/migrations/0003_primeiro_administrador.sql`
4. `supabase/seed.sql`
5. `supabase/atualizar_0004_a_0010.sql` (técnicos, dedicados, chicotes, sem condição novo/usado, solicitações e agendamento; junta as migrações 0004 a 0010)

Quem já tinha o sistema até a 0003 roda só o item 5. Quem já aplicou a 0004 roda só `supabase/atualizar_0005_a_0010.sql`. Quem já aplicou até a 0009 roda só `supabase/migrations/0010_solicitacao_dedicada.sql`. Todos podem ser repetidos sem problema. Os arquivos `0004` a `0010` em `migrations/` são o mesmo conteúdo separado, para consulta: **não rode os dois**.

Cada um deve terminar com "Success". Para testes, em Authentication, Providers, Email você pode desligar "Confirm email".

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

`supabase/tests/` tem um cenário que exercita permissões, transferência em duas etapas, estoque do técnico e itens dedicados. Ele roda num PostgreSQL 15 ou mais novo comum: rode `00_stub_auth.sql` (simula o login do Supabase), as migrações, o `seed.sql` e por fim `01_cenarios.sql`. Os erros que aparecem no resultado são esperados, cada um marcado "deve falhar".

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `npm install` diz que não acha o `package.json` | Você não está na pasta `web`. Rode `cd web` antes. |
| `'next' não é reconhecido` | As dependências não foram instaladas. Rode `npm install` em `web/`. |
| "Your project's URL and Key are required" | Falta o `web/.env.local` ou o nome da variável está errado. Reinicie o `npm run dev` depois de criá-lo. |
| O SQL Editor dá erro de sintaxe em `migrations/0001...` | Foi colado o nome do arquivo. Cole o conteúdo dele. |
| Entro e volto para o login, ou aparece "Aguardando liberação" | A conta ainda não foi liberada, ou não tem linha na tabela de usuários. Rode a migração `0003` e peça a um administrador para liberar. |
| "Saldo insuficiente" | O local não tem a quantidade (livre ou dedicado, conforme a reserva escolhida). Confira o saldo na tela Estoque. |
| "Sem permissão para movimentar este local" | O seu perfil ou os estoques liberados para você não incluem esse local. Peça a um administrador. |

## Segurança

- As regras de acesso são aplicadas no banco (segurança por linha do Supabase) e valem mesmo que alguém chame a API diretamente.
- Quem se cadastra entra sem acesso e inativo, até um administrador liberar.
- Nada de chaves secretas no repositório: só a chave pública vai no app.

## Próximos passos

- Tela de "esqueci minha senha".
- Relatórios e exportação.
- Publicação (por exemplo, na Vercel) com as mesmas variáveis do `.env.local`.
