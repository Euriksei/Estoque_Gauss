# Sistema de Estoque: modelo de dados (v4)

Base das decisões do Matheus: plataforma web com banco de dados; controle **só por quantidade**; a planilha é só ideia e os saldos dela não entram por enquanto. Arquivos: [catalogo-itens.csv](catalogo-itens.csv) (90 itens) e [schema.sql](schema.sql). O banco pronto, com segurança e funções, está em `estoque-app/` (ver README).

## 1. Itens e categorias

Cada item é um cadastro com nome, categoria, fabricante (nos rastreadores), fornecedor padrão, prazo médio de entrega e estoque mínimo. Usei a sua lista de 15 categorias e mantive os nomes como você passou.

| # | Categoria | Itens |
|---|---|:-:|
| 1 | Rastreamento e telemetria | 15 |
| 2 | Câmeras | 8 |
| 3 | MDVR e monitores | 5 |
| 4 | Cabos, chicotes e conexões | 11 |
| 5 | Tablets e acessórios | 11 |
| 6 | RFID e identificação | 7 |
| 7 | Alimentação e conversores | 5 |
| 8 | Sensores e sinalização | 5 |
| 9 | Automação e controle | 5 |
| 10 | Comunicação e conectividade | 7 |
| 11 | Armazenamento de dados | 5 |
| 12 | Caixas e gabinetes | 2 |
| 13 | Controle de abastecimento e comboio | 2 |
| 14 | Navegação e orientação veicular | 1 |
| 15 | Integração veicular | 1 |

São os 87 itens da aba Posição mais 3 chicotes novos (FMC150, FMC130 e Galileo). Fornecedor, prazo e estoque mínimo vieram da planilha; os 3 chicotes novos ficam em branco até você preencher. "Galielo Rotograma falado" ficou com a grafia que você mandou.

## 2. Locais e usuários

- **Estoques fixos:** São Bernardo (SBC) e Nova Lima. A CSN UPV saiu por enquanto.
- **Estoque do técnico:** cada técnico tem o próprio "estoque/carro", ligado ao estoque base dele (SBC ou Nova Lima). É um local como os outros, então a mesma lógica de saldo e transferência vale para ele.
- Saldo sempre por **local + item + condição (novo ou usado)**.

## 3. Níveis de acesso

| Ação | Administrador | Operador de estoque | Técnico | Consulta |
|---|:-:|:-:|:-:|:-:|
| Ver saldo e histórico | todos | do(s) seu(s) local(is) | **só o próprio estoque/carro** | todos |
| Registrar entrada, saída, devolução, descarte, consumo | ✓ | ✓ | só a baixa de saída para cliente, do próprio estoque | |
| Criar transferência (enviar) e confirmar recebimento | ✓ | ✓ (no seu local) | confirma o que recebe no próprio estoque | |
| Ajuste de inventário | ✓ | ✓ (com justificativa) | | |
| Pedir material (solicitação) | ✓ | ✓ | ✓ | |
| Cadastrar itens, clientes, mínimos, usuários | ✓ | | | |
| Estornar movimentação | ✓ | | | |

## 4. Tipos de movimentação

Toda movimentação tem data, local, itens (item + condição + quantidade), responsável e observação. Nada é apagado: correção é estorno, e tudo fica na auditoria.

| Tipo | Efeito | Campos |
|---|---|---|
| **Entrada por compra** | + no local | Fornecedor, NF de entrada, observação |
| **Devolução de cliente** | + no local (em geral usado) | Cliente/unidade, link do chamado Jira (opcional), observação |
| **Saída para cliente** | − no local | Cliente/unidade, finalidade (mobilização ou manutenção), link do chamado Jira (opcional, ex.: HW-5698), observação. Sem NF |
| **Transferência** | − origem ao enviar, + destino só ao confirmar o recebimento | Data de envio, meio de envio, código de rastreio, prazo de chegada, cliente dedicado (opcional) |
| **Consumo interno / teste** | − no local | Observação |
| **Descarte** | − no local | Observação |
| **Ajuste de inventário** | + ou − | Justificativa obrigatória |

### Transferência em duas etapas

1. Quem envia (dono do local de origem) cria a transferência. O saldo sai do estoque dele na hora, e o item passa a aparecer como **em trânsito**.
2. Quem recebe acompanha o envio (meio, rastreio, prazo de chegada). O saldo só entra no estoque dele quando ele **confirma o recebimento**.

Um item em trânsito não está em nenhum dos dois saldos; ele aparece numa lista própria de "a caminho".

### Estoque do técnico

- O técnico só vê o saldo do próprio estoque/carro, que muda toda hora.
- Ele **solicita material**: o pedido fica como "aberta" até um operador atendê-lo, e o atendimento é uma transferência do estoque base para o carro dele.
- O técnico **registra a própria baixa** (saída para cliente, só do próprio estoque) e **confirma o recebimento** das transferências que chegam ao carro dele.

### Cliente dedicado

Um item pode ser transferido já **reservado para uma unidade de cliente**. Ele não entra no estoque livre e só pode sair em saída para aquele cliente. Como as caixas costumam seguir lacradas com o técnico até o cliente, o acompanhamento cobre o caminho inteiro:

- **Posição atual** por cliente/unidade e item: guardado em qual estoque ou carro, **em trânsito** (com meio de envio e rastreio) ou **já entregue**.
- **Histórico completo**: toda movimentação que tocou o item (quem enviou, quando, quem recebeu, quem entregou), em ordem.
- O saldo mostra o reservado separado do livre, então o estoque livre de cada local nunca é inflado por itens dedicados.

### Itens que andam juntos (ex.: módulo Galileo + chicote Galileo)

Entendi que enviar um Módulo Galileo significa enviar também um Chicote Galileo. Proposta: uma tabela de **itens associados** (item principal → item associado → quantidade por unidade). Ao registrar uma saída ou transferência com o módulo, o sistema **sugere** o chicote com a quantidade correspondente, e o operador pode editar (confirmado). Não é uma trava. Fica para você me passar os pares com calma (outros candidatos óbvios: FMC650 → Chicote FMC650, Pro4 → Chicote Pro4, Trace 5 → Chicote Trace5, Pro5 → Chicote Pro5).

## 5. Decisões já tomadas

- Técnico registra a própria baixa e o recebimento no carro dele.
- Chicote associado é sugestão editável.
- Saída e entrada podem ocorrer sem chamado (o link do Jira é opcional).
- Itens dedicados ficam fora do estoque livre, com acompanhamento total.

## 6. Próximo passo

Montar a primeira versão do sistema (telas de cadastro, movimentações, transferência com recebimento, estoque do técnico e acompanhamento dos dedicados). Falta só você confirmar a plataforma de banco de dados que prefere, se tiver preferência (minha sugestão: Supabase/PostgreSQL, que já traz login e segurança por perfil).

## 6. Atualização: técnicos e modo de envio (migração 0004)

- **Técnicos** são cadastro próprio (`tecnico`): nome, vínculo **CLT ou PJ**, login opcional e situação (ativo ou não). Cada técnico tem o seu estoque (um local do tipo "técnico"). Técnicos sem login existem só para serem registrados como quem leva o material ao cliente.
- **Saída para cliente** passa a ter **modo de envio** obrigatório (correios, sedex, retirada, transportadora ou técnico). Quando o modo é "técnico", informa-se qual técnico leva; quando o próprio técnico dá a baixa, ele é registrado automaticamente.
- O código de rastreio vale para correios, sedex e transportadora.
