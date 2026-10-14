# Estoque Gauss

Sistema web de controle de estoque (entrada e saída de equipamentos e insumos), por quantidade, com níveis de acesso por perfil.

- `docs/`: modelo de dados e catálogo de itens
- `supabase/`: banco de dados (migrações, carga inicial e testes)
- `web/`: aplicativo web (Next.js + Supabase); veja `web/README.md` para rodar

## Banco de dados
- `supabase/migrations/0001_schema.sql`: tabelas e views (saldo, em trânsito, itens com cliente, itens dedicados).
- `supabase/migrations/0002_seguranca_e_funcoes.sql`: acesso por perfil (RLS), auditoria e as funções que fazem toda escrita de estoque.
- `supabase/migrations/0003_primeiro_administrador.sql`: o primeiro cadastro vira administrador; os seguintes entram inativos até serem liberados.
- `supabase/seed.sql`: locais (SBC, Nova Lima), 15 categorias e 90 itens.
- `supabase/tests/`: cenários de teste de permissões e fluxos (rodam num PostgreSQL comum com um stub do schema `auth`).

O app não grava direto nas tabelas de movimentação: só chama as funções (`registrar_movimentacao`, `criar_transferencia`, `confirmar_recebimento`, ...), que checam perfil e local, travam o local contra uso simultâneo e desfazem tudo se algum saldo ficar negativo.
