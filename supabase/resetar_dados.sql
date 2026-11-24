-- RESET DOS DADOS: zera o sistema para começar a usar de verdade, mantendo só UM administrador.
--
-- APAGA: movimentações (entradas, saídas, transferências, estornos, trocas de chip), solicitações,
--        pedidos de compra, auditoria, técnicos e os estoques deles, clientes e unidades,
--        e todas as contas de login, MENOS a do administrador informado abaixo.
-- MANTÉM: o administrador (login, senha e perfil), os estoques fixos (SBC, Nova Lima), os estoques
--        liberados para o admin, o catálogo (itens, categorias, fornecedores, estoque mínimo, itens associados).
-- Com isso todo saldo volta a zero (o saldo é calculado a partir das movimentações).
--
-- COMO USAR: troque SEU_EMAIL_DE_ADMIN pelo e-mail do seu login (linha marcada abaixo), cole tudo no
-- SQL Editor do Supabase e rode. Tudo roda numa transação só: se o e-mail não for de um administrador
-- ativo, nada é apagado. NÃO tem como desfazer depois de rodar.

begin;

create temp table _manter on commit drop as
select id from public.usuario
where lower(email) = lower('matheus.silva@globaldotcom.com.br')      -- <<< troque aqui
  and perfil = 'admin' and ativo;

do $$ begin
  if (select count(*) from _manter) <> 1 then
    raise exception 'E-mail não corresponde a um administrador ativo. Nada foi apagado.';
  end if;
end $$;

-- 1. Movimentações, solicitações, pedidos de compra, clientes (tudo que depende deles junto).
truncate table public.solicitacao_item, public.solicitacao,
               public.movimentacao_item, public.movimentacao,
               public.pedido_compra,
               public.unidade_cliente, public.cliente
  restart identity;

-- 2. Técnicos e os estoques (carros) deles.
delete from public.usuario_local ul using public.local l where l.id = ul.local_id and l.tipo = 'tecnico';
delete from public.local where tipo = 'tecnico';
delete from public.tecnico;
alter sequence public.tecnico_id_seq restart with 1;

-- 3. Usuários: fica só o administrador. Apagar em auth.users remove também a linha em usuario (cascade).
--    A auditoria aponta para usuários, então é limpa antes (e de novo no fim).
truncate table public.auditoria restart identity;
delete from public.usuario_local where usuario_id not in (select id from _manter);
delete from auth.users where id not in (select id from _manter);
delete from public.usuario where id not in (select id from _manter);

-- 4. Auditoria por último (os deletes acima também geram linhas nela).
truncate table public.auditoria restart identity;

commit;

-- Conferência: deve mostrar 1 usuário, 0 técnicos, 0 clientes, 0 movimentações, 0 solicitações.
select (select count(*) from public.usuario)      as usuarios,
       (select count(*) from public.tecnico)      as tecnicos,
       (select count(*) from public.cliente)      as clientes,
       (select count(*) from public.movimentacao) as movimentacoes,
       (select count(*) from public.solicitacao)  as solicitacoes,
       (select count(*) from public.produto)      as itens_no_catalogo,
       (select string_agg(nome, ', ') from public.local) as estoques;
