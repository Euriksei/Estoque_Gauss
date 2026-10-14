-- Sistema de Estoque: esquema PostgreSQL (migração 0001: tabelas e views, Supabase)
-- Ver modelo-de-dados.md para a explicação de cada tabela.

create type perfil_acesso    as enum ('admin', 'operador', 'tecnico', 'consulta');
create type tipo_local       as enum ('estoque', 'tecnico');          -- estoque fixo (SBC, Nova Lima) ou carro do técnico
create type condicao_item    as enum ('novo', 'usado');
create type tipo_movimento   as enum ('ENTRADA_COMPRA', 'DEVOLUCAO_CLIENTE', 'SAIDA_CLIENTE',
                                      'TRANSFERENCIA', 'CONSUMO_INTERNO', 'DESCARTE', 'AJUSTE');
create type status_movimento as enum ('registrado', 'em_transito', 'recebido', 'cancelado');
create type finalidade       as enum ('mobilizacao', 'manutencao');
create type modo_envio       as enum ('correios', 'sedex', 'retirada', 'tecnico', 'transportadora');
create type status_solicitacao as enum ('aberta', 'atendida', 'cancelada');

create table usuario (
  id         uuid primary key references auth.users(id) on delete cascade,
  nome       text not null,
  email      text not null unique,
  perfil     perfil_acesso not null default 'consulta',
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- Estoques fixos (SBC, Nova Lima) e um "estoque/carro" por técnico
create table local (
  id          serial primary key,
  nome        text not null unique,
  tipo        tipo_local not null default 'estoque',
  tecnico_id  uuid unique references usuario(id),      -- preenchido só quando tipo = 'tecnico'
  base_id     integer references local(id),           -- estoque de origem do técnico (SBC ou Nova Lima)
  ativo       boolean not null default true,
  check ((tipo = 'tecnico') = (tecnico_id is not null))
);

-- Quais estoques cada usuário enxerga/movimenta (técnico enxerga só o próprio, via local.tecnico_id)
create table usuario_local (
  usuario_id uuid    not null references usuario(id),
  local_id   integer not null references local(id),
  primary key (usuario_id, local_id)
);

create table categoria (
  id   serial primary key,
  nome text not null unique
);

create table fornecedor (
  id   serial primary key,
  nome text not null unique
);

create table produto (
  id                serial primary key,
  nome              text not null unique,
  categoria_id      integer references categoria(id),
  fabricante        text,                       -- Ruptela, Teltonika, GalileoSky... (rastreadores)
  fornecedor_id     integer references fornecedor(id),
  prazo_medio_dias  integer,
  estoque_minimo    integer not null default 0,
  ativo             boolean not null default true
);

-- Itens que costumam sair juntos: ao enviar 1 Módulo Galileo, sugere 1 Chicote Galileo.
-- É uma sugestão pré-preenchida (o operador pode editar), não uma trava.
create table item_associado (
  produto_id   integer not null references produto(id),
  associado_id integer not null references produto(id),
  quantidade   integer not null default 1,        -- por unidade do produto principal
  primary key (produto_id, associado_id),
  check (produto_id <> associado_id)
);

create table cliente (
  id   serial primary key,
  nome text not null unique
);

create table unidade_cliente (
  id          serial primary key,
  cliente_id  integer not null references cliente(id),
  nome        text not null,
  responsavel text,
  unique (cliente_id, nome)
);

create table movimentacao (
  id               bigserial primary key,
  tipo             tipo_movimento not null,
  status           status_movimento not null default 'registrado',
  data             date not null,                  -- data da movimentação (na transferência, a data de envio)
  local_origem_id  integer references local(id),
  local_destino_id integer references local(id),
  unidade_id       integer references unidade_cliente(id),   -- saída / devolução
  fornecedor_id    integer references fornecedor(id),         -- entrada por compra
  numero_nf        text,                                       -- só na entrada por compra
  finalidade       finalidade,                                 -- saída para cliente
  chamado_url      text,                                       -- link do Jira (ex.: HW-5698), opcional
  observacao       text,
  -- só na transferência
  modo_envio       modo_envio,
  codigo_rastreio  text,
  prazo_chegada    date,
  recebido_em      timestamptz,
  recebido_por     uuid references usuario(id),
  criado_por       uuid not null references usuario(id),
  estorno_de       bigint references movimentacao(id),
  criado_em        timestamptz not null default now(),
  check (tipo <> 'AJUSTE' or observacao is not null),
  check (tipo <> 'TRANSFERENCIA' or (local_origem_id is not null and local_destino_id is not null
                                     and local_origem_id <> local_destino_id)),
  check (tipo not in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') or unidade_id is not null),
  check (tipo <> 'TRANSFERENCIA' or status in ('em_transito','recebido','cancelado'))
);
create index on movimentacao (data);
create index on movimentacao (status) where status = 'em_transito';

create table movimentacao_item (
  id                   bigserial primary key,
  movimentacao_id      bigint  not null references movimentacao(id),
  produto_id           integer not null references produto(id),
  condicao             condicao_item not null,
  quantidade           integer not null check (quantidade <> 0),
  -- Cliente dedicado: item reservado para uma unidade, fora do estoque livre, que só pode sair para ela.
  --  * reservado_unidade_id: a reserva de onde o item SAI (ou onde ENTRA, em compra/devolução/ajuste).
  --    Numa transferência, é o saldo reservado do local de origem que será enviado.
  --  * reservar_para_unidade_id: só em transferência. Tira do estoque LIVRE da origem e deixa o item
  --    reservado para essa unidade no destino (ex.: caixa dedicada enviada ao técnico).
  reservado_unidade_id     integer references unidade_cliente(id),
  reservar_para_unidade_id integer references unidade_cliente(id),
  check (reservar_para_unidade_id is null or reservado_unidade_id is null)
);
create index on movimentacao_item (produto_id, condicao);

-- Técnico pede material; o operador atende gerando uma transferência
create table solicitacao (
  id               bigserial primary key,
  tecnico_id       uuid not null references usuario(id),
  status           status_solicitacao not null default 'aberta',
  chamado_url      text,
  observacao       text,
  movimentacao_id  bigint references movimentacao(id),     -- transferência que atendeu o pedido
  criado_em        timestamptz not null default now()
);

create table solicitacao_item (
  solicitacao_id bigint  not null references solicitacao(id),
  produto_id     integer not null references produto(id),
  quantidade     integer not null check (quantidade > 0),
  primary key (solicitacao_id, produto_id)
);

create table pedido_compra (
  id               serial primary key,
  produto_id       integer not null references produto(id),
  fornecedor_id    integer references fornecedor(id),
  quantidade       integer not null,
  data_pedido      date,
  previsao_entrega date,
  status           text not null default 'solicitado'
);

create table auditoria (
  id          bigserial primary key,
  usuario_id  uuid references usuario(id),
  tabela      text not null,
  registro_id text not null,
  acao        text not null,
  antes       jsonb,
  depois      jsonb,
  em          timestamptz not null default now()
);


-- Funções de permissão usadas pelas views; as regras completas ficam na migração 0002.
create function public.fn_perfil() returns perfil_acesso
language sql stable security definer set search_path = public as $$
  select perfil from usuario where id = auth.uid() and ativo
$$;

create function public.fn_pode_ver_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()
      when 'admin'    then true
      when 'consulta' then true
      when 'operador' then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'  then exists (select 1 from local l where l.id = p_local and l.tecnico_id = auth.uid())
    end, false)
$$;

-- Efeito de cada movimentação no saldo de cada local.
--  * entrada por compra, devolução e ajuste: somam no destino ao registrar
--  * saída, consumo e descarte: subtraem da origem ao registrar
--  * transferência: subtrai da origem ao enviar (em_transito) e soma no destino só ao confirmar o recebimento (recebido)
create view efeito_estoque with (security_invoker = true) as
select m.local_destino_id as local_id, i.produto_id, i.condicao,
       coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) as reservado_unidade_id, i.quantidade as delta
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_destino_id is not null
   and ((m.tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE','AJUSTE') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status = 'recebido'))
union all
select m.local_origem_id, i.produto_id, i.condicao, i.reservado_unidade_id, -i.quantidade
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_origem_id is not null
   and ((m.tipo in ('SAIDA_CLIENTE','CONSUMO_INTERNO','DESCARTE') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status in ('em_transito','recebido')));

-- Saldo por local, item, condição e reserva (reservado_unidade_id nulo = estoque livre)
create view saldo with (security_invoker = true) as
select local_id, produto_id, condicao, reservado_unidade_id, sum(delta) as quantidade
  from efeito_estoque
 where public.fn_pode_ver_local(local_id)
 group by 1,2,3,4;

-- O que está a caminho, para o lado que vai receber acompanhar
create view transferencias_em_transito with (security_invoker = true) as
select m.id, m.local_origem_id, m.local_destino_id, m.data as data_envio, m.modo_envio,
       m.codigo_rastreio, m.prazo_chegada, i.produto_id, i.condicao, i.quantidade,
       coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) as reservado_unidade_id
  from movimentacao m join movimentacao_item i on i.movimentacao_id = m.id
 where m.tipo = 'TRANSFERENCIA' and m.status = 'em_transito';

-- Em cliente: saídas menos devoluções por unidade
create view itens_com_cliente with (security_invoker = true) as
select m.unidade_id, i.produto_id,
       sum(case when m.tipo = 'SAIDA_CLIENTE' then i.quantidade else -i.quantidade end) as quantidade
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and m.status = 'registrado'
 group by 1,2;

-- Acompanhamento dos itens dedicados (reservados para uma unidade de cliente):
-- onde está cada quantidade agora: guardada num estoque/carro, a caminho ou já entregue ao cliente.
create view dedicados_posicao with (security_invoker = true) as
select reservado_unidade_id as unidade_id, produto_id, condicao, 'em_local'::text as situacao,
       local_id, null::bigint as movimentacao_id, quantidade
  from saldo where reservado_unidade_id is not null and quantidade <> 0
union all
select coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id), i.produto_id, i.condicao, 'em_transito', m.local_destino_id, m.id, i.quantidade
  from movimentacao m join movimentacao_item i on i.movimentacao_id = m.id
 where m.tipo = 'TRANSFERENCIA' and m.status = 'em_transito'
   and coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) is not null
union all
select i.reservado_unidade_id, i.produto_id, i.condicao, 'entregue', null, null, sum(i.quantidade)
  from movimentacao m join movimentacao_item i on i.movimentacao_id = m.id
 where m.tipo = 'SAIDA_CLIENTE' and m.status = 'registrado' and i.reservado_unidade_id is not null
 group by 1,2,3;

-- Histórico completo de um item dedicado: toda movimentação que o tocou, em ordem.
create view dedicados_historico with (security_invoker = true) as
select coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) as unidade_id, i.produto_id, i.condicao, m.id as movimentacao_id,
       m.tipo, m.status, m.data, m.local_origem_id, m.local_destino_id, m.criado_por, i.quantidade
  from movimentacao m join movimentacao_item i on i.movimentacao_id = m.id
 where coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) is not null;

-- Regras que ficam na aplicação/banco (a detalhar na implementação):
--  * saldo nunca pode ficar negativo em nenhum local;
--  * saída que usa item reservado só pode ir para a unidade reservada;
--  * só o dono do local de origem cria a transferência; só o do destino confirma o recebimento;
--  * técnico enxerga só o próprio local (local.tecnico_id = auth.uid()); registra baixa de saída para cliente
--    e confirma recebimento de transferência apenas nesse local.
