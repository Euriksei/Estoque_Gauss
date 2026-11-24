# Estoque Gauss: resumo do funcionamento

Controle de **entrada e saída de equipamentos e insumos por quantidade**, em vários estoques: os fixos (São Bernardo/SBC e Nova Lima) e o carro de cada técnico. Cada pessoa vê e faz só o que o perfil dela permite, e as regras valem no banco de dados, não só na tela.

## 1. Ideia central

- **O saldo nunca é digitado.** Ele é a soma das movimentações de cada local + item (+ chip, nos módulos). Nenhuma movimentação pode deixar saldo negativo; se deixar, tudo é desfeito.
- **Nada é apagado.** Erro se corrige com **estorno** (só administrador), que fica registrado no histórico.
- **Três "bolsos" de saldo** em cada local:
  - **Livre**: pode sair para qualquer cliente.
  - **Dedicado**: reservado para uma unidade de cliente; só se movimenta pela tela Dedicados.
  - **Em trânsito**: já saiu da origem e ainda não foi confirmado no destino. Não conta em nenhum dos dois.

## 2. Perfis

| Perfil | O que faz |
|---|---|
| **Administrador** | Tudo: movimenta qualquer estoque, atende qualquer solicitação, estorna, cadastra itens/clientes/técnicos, libera usuários. |
| **Operador** | Movimenta só os estoques liberados para ele. Atende solicitações cuja **origem** é estoque dele. Confirma recebimento no estoque dele e no de técnicos da base dele ou que ele enviou. |
| **Técnico** | Vê só **Transferências** (o que foi enviado para ele, e confirma o recebimento) e **Solicitações** (pede material para o próprio carro, saindo do estoque base dele). |
| **Agendamento** | Só leitura + pede saída **do estoque dele para um técnico, informando o cliente**. |
| **Consulta** | Só leitura de tudo. |

Quem cria conta entra **inativo**. O administrador escolhe o perfil e marca "Ativo" em **Usuários**. O primeiro cadastro do banco vira administrador sozinho.

## 3. Telas

| Tela | Uso | Quem vê |
|---|---|---|
| Estoque | saldo por local/item, filtros, alerta de mínimo | todos menos técnico |
| Registrar | entrada por compra, devolução, saída para cliente, saída para estoque técnico, consumo/teste, descarte, ajuste | admin, operador |
| Transferências | envios em andamento/concluídos, nova transferência, confirmar recebimento | todos (técnico: só os dele) |
| Solicitações | pedidos pendentes, em produção, concluídos | todos (criar: menos consulta) |
| Dedicados | onde está cada item reservado; transferir ou enviar ao cliente | todos menos técnico |
| Chips | instalar, trocar e descartar chip de módulos | admin, operador |
| Histórico | todas as movimentações; estorno | todos (estornar: admin) |
| Cadastros | itens, clientes/unidades, técnicos (CLT/PJ, estoque base), mínimos | admin |
| Usuários | perfil, ativo, estoques do operador, estoque do agendamento | admin |
| Senha | trocar a própria senha (e "Esqueci minha senha" no login) | todos |

## 4. Fluxos principais

**Entrada por compra**
Registrar → "Entrada por compra" → local, fornecedor, NF, itens. O saldo livre sobe na hora. Com "Dedicado para", entra já reservado para o cliente.

**Saída para cliente**
Registrar → "Saída para cliente" → cliente/unidade, modo de envio (correios, sedex, retirada, transportadora, técnico), itens. Link do Jira opcional.

**Transferência (duas etapas)**
```
Origem cria a transferência ──► saldo sai da origem, fica "em trânsito"
                                       │
Destino confirma o recebimento ──► saldo entra no destino
(ou cancela ──► volta para a origem)
```
"Saída para estoque técnico" em Registrar é o mesmo fluxo, com o carro do técnico como destino. Técnico sem login: o operador da base ou o admin confirma por ele.

**Solicitação**
```
Aberta ──Aceitar──► Em produção (prazo 1 dia) ──Atender (enviar)──► gera Transferência ──► destino confirma
   └──────────── Cancelar (depois de aceita, só admin/operador) ────────────┘
```
- Técnico: para o próprio carro, saindo do estoque base.
- Agendamento: do estoque dele para um técnico, com cliente obrigatório.
- Admin/operador: estoque → técnico ou estoque → estoque, de qualquer origem.
- Item dedicado a **outro** cliente gera alerta e pede confirmação.

**Chips dos módulos (Ruptela, Galileosky, Teltonika)**
O saldo do módulo é separado por chip: sem chip, Claro, Vivo, Arqia. Na tela Chips: instalar chip num módulo sem chip (baixa 1 chip avulso), trocar de operadora (o chip antigo volta ao avulso) ou descartar o chip de um módulo que não comunicou.

**Chicote**
Cada linha de módulo tem "Com chicote" marcado por padrão; a quantidade de chicotes acompanha a do módulo.

## 5. Como é feito

- **App**: Next.js 14 + Tailwind (`web/`). Lê pelas views protegidas por perfil e **grava só por funções do banco** (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, `cancelar_transferencia`, `estornar_movimentacao`, `criar_solicitacao`, `atender_solicitacao`, `cancelar_solicitacao`, `trocar_chip`).
- **Banco**: Supabase (PostgreSQL) com segurança por linha. Arquivo completo: `supabase/banco_completo.sql`; atualizações em `supabase/atualizar_*.sql`.
- **Principais tabelas**: `usuario`, `local` (estoque fixo ou carro de técnico), `usuario_local`, `tecnico`, `produto`/`categoria`/`fornecedor`, `cliente`/`unidade_cliente`, `movimentacao` + `movimentacao_item`, `solicitacao` + `solicitacao_item`, `auditoria`.
- **Testes**: `supabase/tests/` (regras do banco em PostgreSQL puro) e `testes-tela/` (navegador percorrendo as telas de cada perfil, com banco e API locais, sem tocar no Supabase real).

## 6. Fluxo de teste sugerido (manual, no sistema real)

1. **Admin**: em Cadastros, crie 1 cliente com 1 unidade e 1 técnico (base SBC, sem login).
2. **Registrar** entrada por compra em SBC: 10 de um módulo (com chicote, sem chip), 5 chips Claro avulsos.
3. **Estoque**: confira o saldo; confira o alerta de mínimo se o item tiver mínimo.
4. **Chips**: instale chip Claro em 2 módulos → módulo "Claro" = 2, "sem chip" = 8, chip avulso = 3.
5. **Transferências**: envie 3 módulos de SBC para Nova Lima → aparecem "em trânsito"; confirme o recebimento.
6. **Registrar** saída para estoque técnico (2 módulos) → confirme pelo técnico (admin confirma por ele).
7. **Solicitações**: crie um pedido de Nova Lima para o técnico → Aceitar → Atender → confirmar em Transferências.
8. **Registrar** entrada com "Dedicado para" o cliente → em **Dedicados**, envie ao cliente.
9. **Registrar** saída para cliente (modo "técnico") e uma **devolução**.
10. **Histórico**: estorne uma movimentação e veja o saldo voltar.
11. **Usuários**: crie uma conta de teste com "Primeiro acesso", libere como Operador só de Nova Lima e confira que ele não movimenta SBC.
12. Ao terminar, zere tudo com `supabase/resetar_dados.sql` (seção 7).

## 7. Zerar os dados (manter só o administrador)

`supabase/resetar_dados.sql`: troque `SEU_EMAIL_DE_ADMIN` pelo seu e-mail, cole no SQL Editor do Supabase e rode.

- **Apaga**: movimentações, transferências, solicitações, pedidos de compra, auditoria, técnicos e os carros deles, clientes/unidades e todas as contas de login menos a sua.
- **Mantém**: seu login de administrador, os estoques SBC e Nova Lima e o catálogo de itens (com os mínimos).
- Roda numa transação: se o e-mail não for de um administrador ativo, nada é apagado. **Não tem desfazer.**
