# Estoque Gauss: aplicativo web

A documentação completa (uso, perfis, instalação e problemas comuns) está no [README da raiz](../README.md).

Next.js 14 + Supabase. O app lê pelas tabelas e views (protegidas por perfil no banco) e grava só pelas funções do banco (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, ...).

## Telas
- **Estoque**: saldo por local, condição (novo/usado) e situação (livre ou dedicado); alerta de estoque mínimo. O técnico vê só o próprio carro.
- **Registrar**: entrada por compra, devolução e saída para cliente (chamado do Jira opcional), consumo, descarte e ajuste. O técnico só dá baixa de saída para cliente.
- **Transferências**: envio com data, meio, rastreio e prazo; o destino acompanha e confirma o recebimento. Item pode ser enviado já dedicado a um cliente.
- **Solicitações**: o técnico pede material; o operador atende e o material segue para o carro do técnico.
- **Dedicados**: onde está cada item reservado para um cliente (guardado, em trânsito, entregue) e o histórico completo.
- **Histórico**, **Cadastros** (clientes, unidades, itens, estoque mínimo) e **Usuários** (perfil, acesso e estoques), os dois últimos só para administradores.

## Como rodar
1. Crie um projeto no Supabase e aplique, nesta ordem, `supabase/migrations/0001_schema.sql`, `0002_seguranca_e_funcoes.sql`, `0003_primeiro_administrador.sql`, `0004_tecnicos_e_modo_de_envio.sql` e `supabase/seed.sql`.
2. Copie `web/.env.example` para `web/.env.local` e preencha a URL e a chave pública (publishable) do projeto.
3. `cd web && npm install && npm run dev`.
4. Crie sua conta pela tela de login ("Primeiro acesso"). O primeiro cadastro do sistema vira administrador ativo automaticamente.
5. Daí em diante, libere os outros usuários na tela **Usuários**: escolha o perfil, marque o acesso e os estoques (para técnico, crie o estoque/carro dele).
