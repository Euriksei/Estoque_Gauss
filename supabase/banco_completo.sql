-- ESTOQUE GAUSS: banco de dados completo (tabelas, segurança, funções e dados iniciais) em um arquivo só.
--
-- Para um banco NOVO: cole o conteúdo todo no SQL Editor do Supabase e rode uma vez.
-- Quem já rodou as migrações antigas NÃO deve rodar este arquivo de novo (o banco já está completo).
--
-- Ele contém, em ordem: esquema e segurança, primeiro administrador, técnicos e modo de envio,
-- dedicados e confirmação de recebimento, chicotes dos rastreadores, saldo sem condição novo/usado,
-- solicitações e perfil agendamento, solicitação para dedicado, e por fim o catálogo inicial (seed).

-- ================================================================ 0001_schema
-- Sistema de Estoque: esquema PostgreSQL (migração 0001: tabelas e views, Supabase)
-- Ver modelo-de-dados.md para a explicação de cada tabela.

create type perfil_acesso    as enum ('admin', 'operador', 'tecnico', 'consulta');
create type tipo_local       as enum ('estoque', 'tecnico');          -- estoque fixo (SBC, Nova Lima) ou carro do técnico
-- A coluna "condicao" guarda o CHIP do módulo (rastreadores Ruptela, Teltonika e GalileoSky):
-- 'novo' = sem chip (e é o único valor dos demais itens); as outras são o chip instalado.
create type condicao_item    as enum ('novo', 'usado', 'claro', 'vivo', 'arqia');
create type tipo_movimento   as enum ('ENTRADA_COMPRA', 'DEVOLUCAO_CLIENTE', 'SAIDA_CLIENTE',
                                      'TRANSFERENCIA', 'CONSUMO_INTERNO', 'DESCARTE', 'AJUSTE', 'TROCA_CHIP');
create type status_movimento as enum ('registrado', 'em_transito', 'recebido', 'cancelado');
create type finalidade       as enum ('mobilizacao', 'manutencao');
create type modo_envio       as enum ('correios', 'sedex', 'retirada', 'tecnico', 'transportadora');
create type status_solicitacao as enum ('aberta', 'em_producao', 'atendida', 'cancelada');

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
  ativo             boolean not null default true,
  usa_chip          boolean not null default false,  -- módulo que vem com chip (ou sem, para instalar um avulso)
  chip_tipo         text                              -- chip avulso: claro, vivo ou arqia
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
  prazo_producao   timestamptz,                            -- preenchido ao aceitar: 1 dia para finalizar
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

-- ================================================================ 0002_seguranca_e_funcoes
-- Migração 0002: acesso por perfil (RLS), cadastro automático de usuário, auditoria e
-- as funções que fazem todas as escritas de estoque (o app nunca grava direto nas tabelas de movimentação).

-- ---------------------------------------------------------------- usuários novos
-- Quem se cadastra entra como "consulta" e inativo até um administrador liberar o perfil.
create function public.fn_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into usuario (id, nome, email, perfil, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)),
          new.email, 'consulta', false);
  return new;
end $$;

create trigger trg_novo_usuario after insert on auth.users
  for each row execute function public.fn_novo_usuario();

-- ---------------------------------------------------------------- permissões
create function public.fn_pode_operar_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()
      when 'admin'    then true
      when 'operador' then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'  then exists (select 1 from local l where l.id = p_local and l.tecnico_id = auth.uid())
    end, false)
$$;

-- ---------------------------------------------------------------- RLS
alter table usuario            enable row level security;
alter table local              enable row level security;
alter table usuario_local      enable row level security;
alter table categoria          enable row level security;
alter table fornecedor         enable row level security;
alter table produto            enable row level security;
alter table item_associado     enable row level security;
alter table cliente            enable row level security;
alter table unidade_cliente    enable row level security;
alter table movimentacao       enable row level security;
alter table movimentacao_item  enable row level security;
alter table solicitacao        enable row level security;
alter table solicitacao_item   enable row level security;
alter table pedido_compra      enable row level security;
alter table auditoria          enable row level security;

-- Usuários: cada um vê a si mesmo; administrador, operador e consulta veem todos; só o administrador altera.
create policy usuario_ler on usuario for select using (
  id = auth.uid() or fn_perfil() in ('admin','operador','consulta'));
create policy usuario_admin on usuario for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

create policy usuario_local_ler on usuario_local for select using (
  usuario_id = auth.uid() or fn_perfil() in ('admin','consulta'));
create policy usuario_local_admin on usuario_local for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

-- Locais, catálogo e clientes: qualquer usuário ativo lê; só o administrador altera.
-- (Os nomes dos locais são visíveis a todos; as QUANTIDADES só aparecem para quem pode ver o local.)
create policy local_ler on local for select using (fn_perfil() is not null);
create policy local_admin on local for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

create policy categoria_ler on categoria for select using (fn_perfil() is not null);
create policy categoria_admin on categoria for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy fornecedor_ler on fornecedor for select using (fn_perfil() is not null);
create policy fornecedor_admin on fornecedor for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy produto_ler on produto for select using (fn_perfil() is not null);
create policy produto_admin on produto for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy item_associado_ler on item_associado for select using (fn_perfil() is not null);
create policy item_associado_admin on item_associado for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy cliente_ler on cliente for select using (fn_perfil() is not null);
create policy cliente_admin on cliente for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy unidade_ler on unidade_cliente for select using (fn_perfil() is not null);
create policy unidade_admin on unidade_cliente for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

-- Movimentações: só leitura direta; vê quem pode ver o local de origem ou de destino.
create policy mov_ler on movimentacao for select using (
  (local_origem_id  is not null and fn_pode_ver_local(local_origem_id))
  or (local_destino_id is not null and fn_pode_ver_local(local_destino_id)));
create policy mov_item_ler on movimentacao_item for select using (
  exists (select 1 from movimentacao m where m.id = movimentacao_id));

-- Solicitações: o técnico vê as próprias; administrador, operador e consulta veem todas.
create policy sol_ler on solicitacao for select using (
  tecnico_id = auth.uid() or fn_perfil() in ('admin','operador','consulta'));
create policy sol_item_ler on solicitacao_item for select using (
  exists (select 1 from solicitacao s where s.id = solicitacao_id));

-- Pedidos de compra: técnico não vê; administrador e operador gerenciam.
create policy pedido_ler on pedido_compra for select using (fn_perfil() in ('admin','operador','consulta'));
create policy pedido_escrever on pedido_compra for all
  using (fn_perfil() in ('admin','operador')) with check (fn_perfil() in ('admin','operador'));

create policy auditoria_ler on auditoria for select using (fn_perfil() = 'admin');

-- ---------------------------------------------------------------- auditoria dos cadastros
create function public.fn_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into auditoria (usuario_id, tabela, registro_id, acao, antes, depois)
  values (auth.uid(), tg_table_name,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
          tg_op,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create trigger aud_usuario        after insert or update or delete on usuario        for each row execute function fn_auditar();
create trigger aud_local          after insert or update or delete on local          for each row execute function fn_auditar();
create trigger aud_produto        after insert or update or delete on produto        for each row execute function fn_auditar();
create trigger aud_cliente        after insert or update or delete on cliente        for each row execute function fn_auditar();
create trigger aud_unidade        after insert or update or delete on unidade_cliente for each row execute function fn_auditar();
create trigger aud_pedido_compra  after insert or update or delete on pedido_compra  for each row execute function fn_auditar();

-- ---------------------------------------------------------------- saldo nunca negativo
-- Chamada depois de cada escrita, dentro da mesma transação: se algum saldo ficou negativo, desfaz tudo.
create function public.fn_verificar_saldo(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select e.local_id, e.produto_id, e.condicao, e.reservado_unidade_id, sum(e.delta) as q
      from efeito_estoque e
     where e.local_id = any (p_locais)
     group by 1,2,3,4
    having sum(e.delta) < 0
     limit 1
  loop
    raise exception 'Saldo insuficiente: % (%), local %, quantidade faltando %',
      (select nome from produto where id = r.produto_id), r.condicao,
      (select nome from local where id = r.local_id), -r.q
      using errcode = 'P0001';
  end loop;
end $$;

-- Trava por local para duas pessoas não gastarem o mesmo saldo ao mesmo tempo.
create function public.fn_travar_locais(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare l integer;
begin
  for l in select distinct x from unnest(p_locais) x where x is not null order by x loop
    perform pg_advisory_xact_lock(l);
  end loop;
end $$;

create function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov,
            (it->>'produto_id')::int,
            coalesce(it->>'condicao', 'novo')::condicao_item,
            (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- ---------------------------------------------------------------- registrar movimentação simples
-- p: {tipo, data, local_id, unidade_id, fornecedor_id, numero_nf, finalidade, chamado_url, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id}]}
create function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_ajuste_pos boolean;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  -- O técnico só dá baixa de saída para cliente no próprio estoque/carro.
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, criado_por)
  values (v_tipo, 'registrado', coalesce((p->>'data')::date, current_date),
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  -- Ajuste: quantidade positiva soma no local, negativa subtrai.
  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'reservar_para_unidade_id só vale em transferência';
  end if;

  -- Entradas e saídas aceitam só quantidade positiva; ajuste aceita sinal.
  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  -- Reserva só faz sentido para o cliente dedicado: a saída deve ser para a mesma unidade.
  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;

-- ---------------------------------------------------------------- transferência em duas etapas
-- p: {origem_id, destino_id, data, modo_envio, codigo_rastreio, prazo_chegada, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
create function public.criar_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_origem  integer := (p->>'origem_id')::int;
  v_destino integer := (p->>'destino_id')::int;
  v_id bigint;
begin
  if fn_perfil() is null or fn_perfil() = 'consulta' then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if v_origem is null or v_destino is null or v_origem = v_destino then
    raise exception 'Informe origem e destino diferentes';
  end if;
  -- Só o dono do local de origem inicia o envio.
  if not fn_pode_operar_local(v_origem) then
    raise exception 'Sem permissão para enviar deste local' using errcode = '42501';
  end if;
  if fn_perfil() = 'tecnico' then
    raise exception 'Técnico não cria transferência; use solicitação' using errcode = '42501';
  end if;

  perform fn_travar_locais(array[v_origem, v_destino]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, modo_envio, codigo_rastreio,
                            prazo_chegada, observacao, criado_por)
  values ('TRANSFERENCIA', 'em_transito', coalesce((p->>'data')::date, current_date), v_origem, v_destino,
          nullif(p->>'modo_envio','')::modo_envio, nullif(p->>'codigo_rastreio',''),
          nullif(p->>'prazo_chegada','')::date, nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  perform fn_gravar_itens(v_id, p->'itens');
  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  perform fn_verificar_saldo(array[v_origem]);
  return v_id;
end $$;

-- Quem recebe confirma; só então o saldo entra no estoque dele (o técnico confirma o que chega ao carro).
create function public.confirmar_recebimento(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  select * into m from movimentacao where id = p_id for update;
  if not found or m.tipo <> 'TRANSFERENCIA' then raise exception 'Transferência não encontrada'; end if;
  if m.status <> 'em_transito' then raise exception 'Esta transferência não está em trânsito'; end if;
  if not fn_pode_operar_local(m.local_destino_id) then
    raise exception 'Só quem recebe pode confirmar' using errcode = '42501';
  end if;
  update movimentacao set status = 'recebido', recebido_em = now(), recebido_por = auth.uid() where id = p_id;
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'RECEBIMENTO', jsonb_build_object('status', 'recebido'));
end $$;

-- Cancela um envio ainda em trânsito (o saldo volta para a origem). Quem enviou ou o administrador.
create function public.cancelar_transferencia(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  select * into m from movimentacao where id = p_id for update;
  if not found or m.tipo <> 'TRANSFERENCIA' then raise exception 'Transferência não encontrada'; end if;
  if m.status <> 'em_transito' then raise exception 'Só dá para cancelar o que está em trânsito'; end if;
  if not fn_pode_operar_local(m.local_origem_id) then
    raise exception 'Só quem enviou pode cancelar' using errcode = '42501';
  end if;
  update movimentacao set status = 'cancelado',
         observacao = concat_ws(E'\n', observacao, 'Cancelada: ' || coalesce(p_motivo, '')) where id = p_id;
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'CANCELAMENTO', jsonb_build_object('motivo', p_motivo));
end $$;

-- Estorno de movimentação registrada: só administrador. Marca como cancelada (nada é apagado) e
-- confere que nenhum saldo fica negativo por causa disso.
create function public.estornar_movimentacao(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  if fn_perfil() <> 'admin' then raise exception 'Só administrador estorna' using errcode = '42501'; end if;
  if nullif(p_motivo,'') is null then raise exception 'Informe o motivo'; end if;
  select * into m from movimentacao where id = p_id for update;
  if not found then raise exception 'Movimentação não encontrada'; end if;
  if m.tipo = 'TRANSFERENCIA' and m.status = 'em_transito' then
    raise exception 'Use cancelar_transferencia para o que está em trânsito';
  end if;
  if m.status not in ('registrado','recebido') then raise exception 'Movimentação já cancelada'; end if;
  perform fn_travar_locais(array[m.local_origem_id, m.local_destino_id]);
  update movimentacao set status = 'cancelado',
         observacao = concat_ws(E'\n', observacao, 'Estornada: ' || p_motivo) where id = p_id;
  perform fn_verificar_saldo(array[m.local_origem_id, m.local_destino_id]);
  insert into auditoria (usuario_id, tabela, registro_id, acao, antes, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'ESTORNO', jsonb_build_object('status', m.status),
          jsonb_build_object('motivo', p_motivo));
end $$;

-- ---------------------------------------------------------------- solicitações do técnico
-- p: {chamado_url, observacao, itens:[{produto_id, quantidade}]}
create function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb;
begin
  if fn_perfil() not in ('admin','operador','tecnico') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;
  insert into solicitacao (tecnico_id, chamado_url, observacao)
  values (auth.uid(), nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int);
  end loop;
  return v_id;
end $$;

-- O operador atende gerando a transferência do estoque base para o carro do técnico.
-- p tem os mesmos campos de criar_transferencia (origem_id, modo_envio, itens...); o destino é o carro do técnico.
create function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_destino integer; v_mov bigint;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status <> 'aberta' then raise exception 'Solicitação já encerrada'; end if;
  select id into v_destino from local where tecnico_id = s.tecnico_id;
  if v_destino is null then raise exception 'Técnico sem estoque/carro cadastrado'; end if;
  v_mov := criar_transferencia(p || jsonb_build_object('destino_id', v_destino));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

create function public.cancelar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found or s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação não está em andamento'; end if;
  if s.status::text = 'em_producao' and fn_perfil()::text not in ('admin','operador') then
    raise exception 'Depois de aceita, só administrador e operador cancelam' using errcode = '42501';
  end if;
  if s.tecnico_id <> auth.uid() and fn_perfil() not in ('admin','operador') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  update solicitacao set status = 'cancelada' where id = p_id;
end $$;

-- ---------------------------------------------------------------- grants
-- O app só escreve em movimentações/solicitações pelas funções acima.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update, delete on usuario, usuario_local, local, categoria, fornecedor, produto, item_associado,
      cliente, unidade_cliente, pedido_compra to authenticated;   -- limitado pelas políticas acima
grant usage on all sequences in schema public to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  fn_perfil(), fn_pode_ver_local(integer), fn_pode_operar_local(integer),
  registrar_movimentacao(jsonb), criar_transferencia(jsonb), confirmar_recebimento(bigint),
  cancelar_transferencia(bigint, text), estornar_movimentacao(bigint, text),
  criar_solicitacao(jsonb), atender_solicitacao(bigint, jsonb), cancelar_solicitacao(bigint)
  to authenticated;

-- ================================================================ 0003_primeiro_administrador
-- Migração 0003: o primeiro cadastro do sistema vira administrador ativo; os seguintes entram inativos
-- como "consulta" até um administrador liberar. Também cria a linha de usuário para contas que já existiam
-- no login do Supabase sem registro na tabela (backfill).

create or replace function public.fn_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean;
begin
  -- Trava para dois cadastros simultâneos não virarem ambos administradores.
  perform pg_advisory_xact_lock(hashtext('primeiro_administrador'));
  select not exists (select 1 from usuario) into primeiro;
  insert into usuario (id, nome, email, perfil, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)), new.email,
          case when primeiro then 'admin'::perfil_acesso else 'consulta'::perfil_acesso end,
          primeiro)
  on conflict (id) do nothing;
  return new;
end $$;

-- Contas que existem no login mas não na tabela: a mais antiga vira administrador se ainda não houver nenhum.
insert into usuario (id, nome, email, perfil, ativo)
select u.id, coalesce(u.raw_user_meta_data->>'nome', split_part(u.email, '@', 1)), u.email,
       case when not exists (select 1 from usuario where perfil = 'admin') and
                 u.id = (select id from auth.users order by created_at limit 1)
            then 'admin'::perfil_acesso else 'consulta'::perfil_acesso end,
       not exists (select 1 from usuario where perfil = 'admin') and
                 u.id = (select id from auth.users order by created_at limit 1)
from auth.users u
where not exists (select 1 from usuario x where x.id = u.id);

-- ================================================================ 0004_tecnicos_e_modo_de_envio
-- Migração 0004: técnicos cadastrados (PJ ou CLT) e modo de envio na saída para cliente.
--
-- Antes, o estoque de um técnico era ligado direto a um usuário do login. Agora o técnico é um cadastro
-- próprio (com vínculo PJ ou CLT). Ele pode ter login (usuario_id) ou não, e cada técnico tem seu estoque.
-- Na saída para cliente passam a valer o modo de envio e, quando o envio é feito por técnico, qual técnico.

create type vinculo_tecnico as enum ('pj', 'clt');

create table tecnico (
  id          serial primary key,
  nome        text not null,
  vinculo     vinculo_tecnico not null,
  usuario_id  uuid unique references usuario(id),   -- preenchido quando o técnico acessa o sistema
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);

-- Técnicos que já tinham estoque ligado a um usuário viram cadastro (vínculo CLT por padrão: ajuste em Cadastros).
insert into tecnico (nome, vinculo, usuario_id)
select u.nome, 'clt', u.id from local l join usuario u on u.id = l.tecnico_id;

alter table local add column tecnico_ref integer unique references tecnico(id);
update local l set tecnico_ref = t.id from tecnico t where t.usuario_id = l.tecnico_id;

-- Troca local.tecnico_id (usuário) por local.tecnico_id (cadastro de técnico). O check antigo cai junto com a coluna.
alter table local drop column tecnico_id;
alter table local rename column tecnico_ref to tecnico_id;
alter table local add constraint local_tecnico_ck check ((tipo = 'tecnico') = (tecnico_id is not null));

-- Quem entregou a saída para o cliente, modo de envio e rastreio já existem em movimentacao (modo_envio, codigo_rastreio).
alter table movimentacao add column tecnico_id integer references tecnico(id);

-- ---------------------------------------------------------------- segurança
alter table tecnico enable row level security;
create policy tecnico_ler on tecnico for select using (fn_perfil() is not null);
create policy tecnico_admin on tecnico for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create trigger aud_tecnico after insert or update or delete on tecnico for each row execute function fn_auditar();
grant select, insert, update, delete on tecnico to authenticated;
grant usage on sequence tecnico_id_seq to authenticated;

-- O técnico enxerga e opera só o estoque ligado ao cadastro dele (que aponta para o login dele).
create or replace function public.fn_pode_ver_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()
      when 'admin'    then true
      when 'consulta' then true
      when 'operador' then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'  then exists (select 1 from local l join tecnico t on t.id = l.tecnico_id
                                    where l.id = p_local and t.usuario_id = auth.uid())
    end, false)
$$;

create or replace function public.fn_pode_operar_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()
      when 'admin'    then true
      when 'operador' then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'  then exists (select 1 from local l join tecnico t on t.id = l.tecnico_id
                                    where l.id = p_local and t.usuario_id = auth.uid())
    end, false)
$$;

-- ---------------------------------------------------------------- registrar movimentação
-- p: {tipo, data, local_id, unidade_id, fornecedor_id, numero_nf, finalidade, chamado_url, observacao,
--     modo_envio, codigo_rastreio, tecnico_id, itens:[{produto_id, condicao, quantidade, reservado_unidade_id}]}
-- Na saída para cliente o modo de envio é obrigatório; se for "tecnico", informe qual técnico leva.
-- Quando o próprio técnico dá a baixa, o modo é "tecnico" e o técnico é ele mesmo.
create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      select t.id into v_tec from tecnico t where t.usuario_id = auth.uid();
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', coalesce((p->>'data')::date, current_date),
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'reservar_para_unidade_id só vale em transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;

-- O operador atende o pedido do técnico enviando para o estoque do técnico que fez o pedido.
create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_destino integer; v_mov bigint;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status <> 'aberta' then raise exception 'Solicitação já encerrada'; end if;
  select l.id into v_destino from local l join tecnico t on t.id = l.tecnico_id where t.usuario_id = s.tecnico_id;
  if v_destino is null then raise exception 'Técnico sem estoque cadastrado'; end if;
  v_mov := criar_transferencia(p || jsonb_build_object('destino_id', v_destino));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- ================================================================ 0005_dedicados_e_confirmacao
-- Migração 0005: itens dedicados entram por compra, ajuste e transferência; operadores confirmam recebimento.
--
-- 1) registrar_movimentacao passa a aceitar "reservar_para_unidade_id" em ENTRADA_COMPRA e AJUSTE: o item entra
--    já reservado para a unidade do cliente (fora do estoque livre). Depois de dedicado, a movimentação dele
--    (transferir ou enviar ao cliente) é feita pela tela Dedicados, usando "reservado_unidade_id".
-- 2) confirmar_recebimento: quando o destino é o estoque de um técnico, o operador do estoque de origem e o
--    operador da base desse técnico também confirmam (útil para técnico sem login). Entre SBC e Nova Lima
--    continua valendo: só quem opera o destino confirma. Administrador sempre confirma.

create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      select t.id into v_tec from tecnico t where t.usuario_id = auth.uid();
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', coalesce((p->>'data')::date, current_date),
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Item dedicado nasce por compra, ajuste ou transferência. Nos demais tipos não se cria dedicado.
  if v_tipo not in ('ENTRADA_COMPRA','AJUSTE')
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só pode ser criado por compra, ajuste ou transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;


create or replace function public.confirmar_recebimento(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao; v_ok boolean;
begin
  select * into m from movimentacao where id = p_id for update;
  if not found or m.tipo <> 'TRANSFERENCIA' then raise exception 'Transferência não encontrada'; end if;
  if m.status <> 'em_transito' then raise exception 'Esta transferência não está em trânsito'; end if;
  v_ok := fn_pode_operar_local(m.local_destino_id)
       or (fn_perfil() = 'operador' and exists (
             select 1 from local d where d.id = m.local_destino_id and d.tipo = 'tecnico'
                and (fn_pode_operar_local(m.local_origem_id) or (d.base_id is not null and fn_pode_operar_local(d.base_id)))));
  if not coalesce(v_ok, false) then
    raise exception 'Sem permissão para confirmar este recebimento' using errcode = '42501';
  end if;
  update movimentacao set status = 'recebido', recebido_em = now(), recebido_por = auth.uid() where id = p_id;
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'RECEBIMENTO', jsonb_build_object('status', 'recebido'));
end $$;

-- ================================================================ 0006_chicote_fmc130_fmc150
-- Migração 0006: módulos FMC 130 e FMC 150 levam o chicote correspondente (sugestão editável).
-- Se já rodou o seed.sql, este arquivo basta; ele não duplica nada.
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote ' || replace(p.nome, ' ', '')
 where p.nome in ('FMC 130', 'FMC 150')
on conflict do nothing;

-- ================================================================ 0007_chicote_para_todos_os_rastreadores
-- Migração 0007: regra do chicote para todos os rastreadores Ruptela, GalileoSky e Teltonika.
-- Todo rastreador Ruptela, GalileoSky e Teltonika leva o chicote correspondente (sugestão editável).
-- Cria os chicotes que ainda não existiam (ECO 5, ECO-LIGHT +S, HCV5, FMB920) e liga cada módulo ao seu.
insert into produto (nome, categoria_id)
select v.nome, (select id from categoria where nome = 'Cabos, chicotes e conexões')
  from (values ('Chicote ECO 5'), ('Chicote ECO-LIGHT +S'), ('Chicote HCV5'), ('Chicote FMB920')) as v(nome)
on conflict (nome) do nothing;

insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1
  from (values
    ('ECO 5', 'Chicote ECO 5'), ('ECO-LIGHT +S', 'Chicote ECO-LIGHT +S'), ('HCV5', 'Chicote HCV5'),
    ('GF Pro4', 'Chicote Pro4'), ('PRO5 Lite', 'Chicote Pro5'), ('TRACE 5', 'Chicote Trace5'),
    ('FMB920', 'Chicote FMB920'), ('FMC 130', 'Chicote FMC130'), ('FMC 150', 'Chicote FMC150'), ('FMC 650', 'Chicote FMC650'),
    ('Galileo 7x / 10HUB', 'Chicote Galileo'), ('GalileoSky WIFI', 'Chicote Galileo')
  ) as v(modulo, chicote)
  join produto p on p.nome = v.modulo
  join produto a on a.nome = v.chicote
on conflict do nothing;

-- ================================================================ 0008_sem_condicao_novo_usado
-- Migração 0008: o sistema deixa de separar itens novos e usados. O saldo é uma contagem única por item.
-- O que já estava registrado como "usado" passa a contar como "novo" (some na soma). A coluna continua
-- existindo, sempre "novo", para não mexer nas views e funções.
update movimentacao_item set condicao = 'novo' where condicao <> 'novo';

create or replace function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov,
            (it->>'produto_id')::int,
            'novo',
            (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- ================================================================ 0009_solicitacoes_e_agendamento
-- Migração 0009: perfil "agendamento" e solicitações com origem e destino definidos.
--
-- * Perfil novo "agendamento": vê tudo como a consulta e pode fazer solicitações de transferência.
-- * Solicitação passa a guardar de onde sai (origem) e para onde vai (destino).
--   - Técnico: pede só para o próprio estoque e só do estoque base dele (a origem não é escolhida).
--   - Administrador, operador e agendamento: escolhem origem e destino.
--   - Quem atende (administrador ou operador da origem) só confirma o envio; origem e destino já vêm do pedido.

alter type perfil_acesso add value if not exists 'agendamento';

alter table solicitacao add column if not exists origem_id  integer references local(id);
alter table solicitacao add column if not exists destino_id integer references local(id);

-- Pedidos antigos: o destino é o estoque do técnico e a origem é a base dele.
update solicitacao s set destino_id = l.id, origem_id = l.base_id
  from tecnico t join local l on l.tecnico_id = t.id
 where t.usuario_id = s.tecnico_id and s.destino_id is null;

-- Quem vê o quê (comparação por texto: o valor novo do tipo só pode ser usado depois de confirmado).
create or replace function public.fn_pode_ver_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()::text
      when 'admin'       then true
      when 'consulta'    then true
      when 'agendamento' then true
      when 'operador'    then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'     then exists (select 1 from local l join tecnico t on t.id = l.tecnico_id
                                       where l.id = p_local and t.usuario_id = auth.uid())
    end, false)
$$;

drop policy if exists usuario_ler on usuario;
create policy usuario_ler on usuario for select using (
  id = auth.uid() or fn_perfil()::text in ('admin','operador','consulta','agendamento'));
drop policy if exists sol_ler on solicitacao;
create policy sol_ler on solicitacao for select using (
  tecnico_id = auth.uid() or fn_perfil()::text in ('admin','operador','consulta','agendamento'));

-- p: {itens:[{produto_id, quantidade}], chamado_url, observacao, origem_id, destino_id}
-- (técnico: origem e destino são definidos pelo sistema, a partir do estoque dele)
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb; v_perfil text := fn_perfil()::text; v_dest integer; v_orig integer;
begin
  if v_perfil is null or v_perfil not in ('admin','operador','tecnico','agendamento') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;

  if v_perfil = 'tecnico' then
    select l.id, l.base_id into v_dest, v_orig
      from local l join tecnico t on t.id = l.tecnico_id where t.usuario_id = auth.uid();
    if v_dest is null then raise exception 'Seu login não está ligado a um estoque de técnico. Fale com um administrador'; end if;
    if v_orig is null then raise exception 'Seu estoque não tem um estoque base definido. Fale com um administrador'; end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    v_orig := nullif(p->>'origem_id','')::int;
    if v_dest is null or v_orig is null then raise exception 'Informe de onde sai e para onde vai'; end if;
    if v_dest = v_orig then raise exception 'Origem e destino devem ser diferentes'; end if;
  end if;

  insert into solicitacao (tecnico_id, origem_id, destino_id, chamado_url, observacao)
  values (auth.uid(), v_orig, v_dest, nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int);
  end loop;
  return v_id;
end $$;

-- Atender = enviar do estoque de origem do pedido para o destino do pedido. Só administrador e operador.
-- p: {modo_envio, codigo_rastreio, prazo_chegada, observacao, itens}
create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_mov bigint;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status <> 'aberta' then raise exception 'Solicitação já encerrada'; end if;
  if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- ================================================================ 0010_solicitacao_dedicada
-- Migração 0010: solicitação para estoque dedicado.
-- Cada item do pedido pode ser pedido já dedicado a uma unidade de cliente ("Dedicado para"). Ao atender, a
-- transferência leva esses itens com a mesma reserva. O atendimento usa os itens do próprio pedido.

alter table solicitacao_item add column if not exists reservar_para_unidade_id integer references unidade_cliente(id);
alter table solicitacao_item drop constraint if exists solicitacao_item_pkey;
create unique index if not exists solicitacao_item_unico
  on solicitacao_item (solicitacao_id, produto_id, coalesce(reservar_para_unidade_id, 0));

-- p: {itens:[{produto_id, quantidade, reservar_para_unidade_id}], chamado_url, observacao, origem_id, destino_id}
-- (técnico: origem e destino são definidos pelo sistema, a partir do estoque dele)
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb; v_perfil text := fn_perfil()::text; v_dest integer; v_orig integer;
begin
  if v_perfil is null or v_perfil not in ('admin','operador','tecnico','agendamento') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;

  if v_perfil = 'tecnico' then
    select l.id, l.base_id into v_dest, v_orig
      from local l join tecnico t on t.id = l.tecnico_id where t.usuario_id = auth.uid();
    if v_dest is null then raise exception 'Seu login não está ligado a um estoque de técnico. Fale com um administrador'; end if;
    if v_orig is null then raise exception 'Seu estoque não tem um estoque base definido. Fale com um administrador'; end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    v_orig := nullif(p->>'origem_id','')::int;
    if v_dest is null or v_orig is null then raise exception 'Informe de onde sai e para onde vai'; end if;
    if v_dest = v_orig then raise exception 'Origem e destino devem ser diferentes'; end if;
  end if;

  insert into solicitacao (tecnico_id, origem_id, destino_id, chamado_url, observacao)
  values (auth.uid(), v_orig, v_dest, nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade, reservar_para_unidade_id)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int, nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
  return v_id;
end $$;

-- Atender = enviar do estoque de origem do pedido para o destino do pedido. Só administrador e operador.
-- p: {modo_envio, codigo_rastreio, prazo_chegada, observacao}; os itens vêm do próprio pedido
create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_mov bigint; v_itens jsonb;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação já encerrada'; end if;
  if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
  select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                      'reservar_para_unidade_id', reservar_para_unidade_id,
                                      -- p.chips: {"<produto_id>|<unidade dedicada ou vazio>": "claro"}; sem escolha = módulo sem chip
                                      'condicao', coalesce(p->'chips'->>(produto_id::text || '|' || coalesce(reservar_para_unidade_id::text, '')), 'novo')))
    into v_itens from solicitacao_item where solicitacao_id = p_id;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- Aceitar = o operador/administrador assume o pedido: vai para "em produção" com 1 dia de prazo para finalizar.
create or replace function public.aceitar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador aceitam solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text <> 'aberta' then raise exception 'Só dá para aceitar solicitação aberta'; end if;
  update solicitacao set status = 'em_producao', prazo_producao = now() + interval '1 day' where id = p_id;
end $$;
revoke execute on function public.aceitar_solicitacao(bigint) from public, anon;
grant execute on function public.aceitar_solicitacao(bigint) to authenticated;

-- ================================================================ 0011_chips
-- Chips dos módulos de telemetria. O saldo do módulo é separado pelo chip instalado (coluna "condicao":
-- 'novo' = sem chip). Chips avulsos são itens normais (produto.chip_tipo). "Trocar chip" converte módulos e
-- mexe nos chips avulsos; um chip que não funcionou pode ser descartado.

create or replace function public.fn_rotulo_chip(c text) returns text language sql immutable as $$
  select case c when 'novo' then 'sem chip' when 'claro' then 'Claro' when 'vivo' then 'Vivo'
                when 'arqia' then 'Arqia' else c end
$$;

create or replace view efeito_estoque with (security_invoker = true) as
select m.local_destino_id as local_id, i.produto_id, i.condicao,
       coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) as reservado_unidade_id, i.quantidade as delta
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_destino_id is not null
   and ((m.tipo::text in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE','AJUSTE','TROCA_CHIP') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status = 'recebido'))
union all
select m.local_origem_id, i.produto_id, i.condicao, i.reservado_unidade_id, -i.quantidade
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_origem_id is not null
   and ((m.tipo in ('SAIDA_CLIENTE','CONSUMO_INTERNO','DESCARTE') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status in ('em_transito','recebido')));

create or replace function public.fn_verificar_saldo(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select e.local_id, e.produto_id, e.condicao, e.reservado_unidade_id, sum(e.delta) as q
      from efeito_estoque e
     where e.local_id = any (p_locais)
     group by 1,2,3,4
    having sum(e.delta) < 0
     limit 1
  loop
    raise exception 'Saldo insuficiente: %, local %, quantidade faltando %',
      (select nome from produto where id = r.produto_id) ||
      case when exists (select 1 from produto where id = r.produto_id and usa_chip)
           then ' (' || fn_rotulo_chip(r.condicao::text) || ')' else '' end,
      (select nome from local where id = r.local_id), -r.q
      using errcode = 'P0001';
  end loop;
end $$;

create or replace function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb; v_pid integer; v_chip text;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    v_pid := (it->>'produto_id')::int;
    -- só módulos com chip guardam o chip; os demais itens ficam sempre em 'novo'
    v_chip := case when exists (select 1 from produto where id = v_pid and usa_chip)
                   then coalesce(nullif(it->>'condicao',''), 'novo') else 'novo' end;
    if v_chip not in ('novo','claro','vivo','arqia') then raise exception 'Chip inválido: %', v_chip; end if;
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov, v_pid, v_chip::condicao_item, (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arqia).
-- Instalar chip avulso baixa o chip avulso; o chip retirado volta ao estoque avulso ou é descartado.
-- p: {local_id, produto_id, quantidade, de, para, chip_retirado ('estoque'|'descartar'), observacao, data}
create or replace function public.trocar_chip(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := (p->>'local_id')::int; v_prod integer := (p->>'produto_id')::int;
  v_qtd integer := (p->>'quantidade')::int;
  v_de text := coalesce(nullif(p->>'de',''), 'novo'); v_para text := coalesce(nullif(p->>'para',''), 'novo');
  v_dest text := coalesce(nullif(p->>'chip_retirado',''), 'estoque');
  v_id bigint; v_chip_de integer; v_chip_para integer; v_obs text := nullif(p->>'observacao','');
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arqia') or v_para not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  -- Mesmo chip de antes só faz sentido para substituir um chip ruim: o antigo é descartado e sai outro avulso.
  if v_de = v_para and (v_de = 'novo' or coalesce(nullif(p->>'chip_retirado',''), 'estoque') <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  if v_de <> 'novo' then select id into v_chip_de from produto where chip_tipo = v_de and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_de); end if; end if;
  if v_para <> 'novo' then select id into v_chip_para from produto where chip_tipo = v_para and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_para); end if; end if;

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', coalesce((p->>'data')::date, current_date), v_local,
          concat_ws(E'\n', case when v_de = v_para then 'Chip ' || fn_rotulo_chip(v_de) || ' substituído por outro' else fn_rotulo_chip(v_de) || ' → ' || fn_rotulo_chip(v_para) end ||
                    case when v_de <> 'novo' and v_dest = 'descartar' then ' (chip retirado descartado)' else '' end, v_obs), auth.uid())
  returning id into v_id;
  if v_de <> v_para then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values
      (v_id, v_prod, v_de::condicao_item, -v_qtd), (v_id, v_prod, v_para::condicao_item, v_qtd);
  end if;
  if v_chip_de is not null and v_dest = 'estoque' then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_de, 'novo', v_qtd);
  end if;
  if v_chip_para is not null then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_para, 'novo', -v_qtd);
  end if;
  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;
revoke execute on function public.trocar_chip(jsonb) from public, anon;
grant execute on function public.trocar_chip(jsonb) to authenticated;

-- ================================================================ 0012_regras_de_solicitacao
-- Agendamento: só faz solicitação "do estoque dele para um técnico" (saída para cliente), informando o cliente.
--   O estoque dele é o liberado em Usuários (um só). Pode tirar do estoque livre ou do dedicado de um cliente
--   (o alerta de cliente diferente é mostrado na tela, na hora de enviar).
-- Administrador e operador: "estoque → técnico" (cliente opcional) e "estoque → estoque", de qualquer origem.
-- Dar andamento (aceitar/atender): o operador só nas solicitações cuja origem é um estoque que ele opera; o administrador em todas.
alter table solicitacao add column if not exists unidade_id integer references unidade_cliente(id);   -- cliente da saída
alter table solicitacao_item add column if not exists reservado_unidade_id integer references unidade_cliente(id);  -- sai do dedicado deste cliente
drop index if exists solicitacao_item_unico;
create unique index solicitacao_item_unico
  on solicitacao_item (solicitacao_id, produto_id, coalesce(reservar_para_unidade_id, 0), coalesce(reservado_unidade_id, 0));

-- p: {itens:[{produto_id, quantidade, reservar_para_unidade_id, reservado_unidade_id}], chamado_url, observacao, origem_id, destino_id, unidade_id}
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb; v_perfil text := fn_perfil()::text; v_dest integer; v_orig integer;
        v_un integer := nullif(p->>'unidade_id','')::int; v_n integer;
begin
  if v_perfil is null or v_perfil not in ('admin','operador','tecnico','agendamento') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;

  if v_perfil = 'tecnico' then
    select l.id, l.base_id into v_dest, v_orig
      from local l join tecnico t on t.id = l.tecnico_id where t.usuario_id = auth.uid();
    if v_dest is null then raise exception 'Seu login não está ligado a um estoque de técnico. Fale com um administrador'; end if;
    if v_orig is null then raise exception 'Seu estoque não tem um estoque base definido. Fale com um administrador'; end if;
    v_un := null;
  elsif v_perfil = 'agendamento' then
    select count(*), min(ul.local_id) into v_n, v_orig
      from usuario_local ul join local l on l.id = ul.local_id where ul.usuario_id = auth.uid() and l.tipo = 'estoque';
    if v_n <> 1 then raise exception 'Seu acesso ainda não tem um estoque definido. Fale com um administrador'; end if;
    v_dest := nullif(p->>'destino_id','')::int;
    if v_dest is null or not exists (select 1 from local where id = v_dest and tipo = 'tecnico') then
      raise exception 'O agendamento solicita do seu estoque para um técnico';
    end if;
    if v_un is null then raise exception 'Informe o cliente'; end if;
    if exists (select 1 from jsonb_array_elements(p->'itens') x where nullif(x->>'reservar_para_unidade_id','') is not null) then
      raise exception 'O agendamento só pode tirar de estoque livre ou dedicado, não criar dedicado';
    end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    v_orig := nullif(p->>'origem_id','')::int;
    if v_dest is null or v_orig is null then raise exception 'Informe de onde sai e para onde vai'; end if;
    if v_dest = v_orig then raise exception 'Origem e destino devem ser diferentes'; end if;
    if not exists (select 1 from local where id = v_dest and tipo = 'tecnico') then v_un := null; end if;  -- cliente só em "estoque → técnico"
  end if;
  if exists (select 1 from jsonb_array_elements(p->'itens') x
              where nullif(x->>'reservar_para_unidade_id','') is not null and nullif(x->>'reservado_unidade_id','') is not null) then
    raise exception 'Um item não pode sair de um dedicado e ser dedicado ao mesmo tempo';
  end if;

  insert into solicitacao (tecnico_id, origem_id, destino_id, unidade_id, chamado_url, observacao)
  values (auth.uid(), v_orig, v_dest, v_un, nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade, reservar_para_unidade_id, reservado_unidade_id)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int,
            nullif(it->>'reservar_para_unidade_id','')::int, nullif(it->>'reservado_unidade_id','')::int);
  end loop;
  return v_id;
end $$;

create or replace function public.aceitar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador aceitam solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text <> 'aberta' then raise exception 'Só dá para aceitar solicitação aberta'; end if;
  if fn_perfil()::text = 'operador' and not fn_pode_operar_local(s.origem_id) then
    raise exception 'Só quem opera o estoque de origem (%) dá andamento a esta solicitação', (select nome from local where id = s.origem_id) using errcode = '42501';
  end if;
  update solicitacao set status = 'em_producao', prazo_producao = now() + interval '1 day' where id = p_id;
end $$;

create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_mov bigint; v_itens jsonb;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação já encerrada'; end if;
  if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
  select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                      'reservar_para_unidade_id', reservar_para_unidade_id,
                                      'reservado_unidade_id', reservado_unidade_id,
                                      -- p.chips: {"<produto_id>|<unidade dedicada ou vazio>": "claro"}; sem escolha = módulo sem chip
                                      'condicao', coalesce(p->'chips'->>(produto_id::text || '|' || coalesce(reservar_para_unidade_id::text, '')), 'novo')))
    into v_itens from solicitacao_item where solicitacao_id = p_id;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- ================================================================ dados iniciais (seed)
-- Carga inicial: locais, categorias, fornecedores e os 90 itens do catálogo (modelagem/catalogo-itens.csv).
insert into local (nome, tipo) values ('São Bernardo (SBC)', 'estoque'), ('Nova Lima', 'estoque');
insert into categoria (nome) values
  ('Rastreamento e telemetria'),
  ('Câmeras'),
  ('MDVR e monitores'),
  ('Cabos, chicotes e conexões'),
  ('Tablets e acessórios'),
  ('RFID e identificação'),
  ('Alimentação e conversores'),
  ('Sensores e sinalização'),
  ('Automação e controle'),
  ('Comunicação e conectividade'),
  ('Armazenamento de dados'),
  ('Caixas e gabinetes'),
  ('Controle de abastecimento e comboio'),
  ('Navegação e orientação veicular'),
  ('Integração veicular');
insert into fornecedor (nome) values
  ('Ruptela'),
  ('Teltonika'),
  ('SGBras'),
  ('Omnicomm'),
  ('Suntech'),
  ('Intelbrás'),
  ('Mercado Livre'),
  ('Securitek'),
  ('Roboflex'),
  ('Drexia'),
  ('M11N Baterias'),
  ('Anderson Conversores'),
  ('MCE Técnica'),
  ('AutoSender'),
  ('PrimeField'),
  ('Finder Tech'),
  ('CTA');
insert into produto (nome, categoria_id, fabricante, fornecedor_id, prazo_medio_dias, estoque_minimo)
select v.nome, c.id, nullif(v.fabricante,''), f.id, nullif(v.prazo,'')::int, coalesce(nullif(v.minimo,'')::int, 0)
from (values
  ('ECO 5', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '', '0'),
  ('ECO-LIGHT +S', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '', '0'),
  ('FMB920', 'Rastreamento e telemetria', 'Teltonika', 'Teltonika', '', '0'),
  ('FMC 130', 'Rastreamento e telemetria', 'Teltonika', 'Teltonika', '25', '150'),
  ('FMC 150', 'Rastreamento e telemetria', 'Teltonika', 'Teltonika', '25', '200'),
  ('FMC 650', 'Rastreamento e telemetria', 'Teltonika', 'Teltonika', '25', '250'),
  ('Galileo 7x / 10HUB', 'Rastreamento e telemetria', 'GalileoSky', 'SGBras', '15', '100'),
  ('GalileoSky WIFI', 'Rastreamento e telemetria', 'GalileoSky', '', '', '0'),
  ('GF Pro4', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '', '0'),
  ('HCV5', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '', '0'),
  ('Omnicomm Optim', 'Rastreamento e telemetria', 'Omnicomm', 'Omnicomm', '', '20'),
  ('Omnicomm Profi', 'Rastreamento e telemetria', 'Omnicomm', 'Omnicomm', '', '0'),
  ('PRO5 Lite', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '30', '0'),
  ('TRACE 5', 'Rastreamento e telemetria', 'Ruptela', 'Ruptela', '30', '0'),
  ('SUNTECH Plug Play', 'Rastreamento e telemetria', 'Suntech', 'Suntech', '15', '0'),
  ('Camera Contexto (3Fios)', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera Contexto (3Fios) DashCAM', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera Fadiga (T)', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera Fadiga (T) DashCAM', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera frontal (vermelha)', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera IP', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('Camera de ré', 'Câmeras', '', 'Mercado Livre', '10', '0'),
  ('Camera Contadora passageiros', 'Câmeras', '', 'Intelbrás', '30', '0'),
  ('DashCAM', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('MDVR Intelbras 3404', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('MDVR Intelbras 5404', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('Monitor Intelbras CP4', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('Monitor de alarme', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('Cabo rede 3 metros', 'Cabos, chicotes e conexões', '', 'Intelbrás', '30', '0'),
  ('Chicote Pro5', 'Cabos, chicotes e conexões', '', 'Securitek', '30', '0'),
  ('Chicote Pro4', 'Cabos, chicotes e conexões', '', 'Securitek', '30', '0'),
  ('Chicote Trace5', 'Cabos, chicotes e conexões', '', 'Securitek', '30', '0'),
  ('Chicote FMC650', 'Cabos, chicotes e conexões', '', 'Securitek', '30', '0'),
  ('Chicote FMC150', 'Cabos, chicotes e conexões', '', '', '', ''),
  ('Chicote FMC130', 'Cabos, chicotes e conexões', '', '', '', ''),
  ('Chicote Galileo', 'Cabos, chicotes e conexões', '', '', '', ''),
  ('Extensão cameras Intelbras', 'Cabos, chicotes e conexões', '', 'Intelbrás', '30', '0'),
  ('Extensão cameras Intelbras DashCAM', 'Cabos, chicotes e conexões', '', 'Intelbrás', '30', '0'),
  ('Switch cabo rede Intelbras', 'Cabos, chicotes e conexões', '', 'Intelbrás', '30', '0'),
  ('Tablet Multilaser 7''''', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Tablet Samsung', 'Tablets e acessórios', '', 'Roboflex', '20', '20'),
  ('Suporte Case Tablet Multilaser 7"', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Suporte Case Tablet Multilaser 7" TURTURCASE', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Suporte Case Tablet Samsung 8"', 'Tablets e acessórios', '', 'Roboflex', '20', '30'),
  ('Suporte Case Tablet Samsung Ventilada', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Suporte Tablet Multilaser 7"', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Suporte Tablet Multilaser 7" TURTURCASE', 'Tablets e acessórios', '', 'Roboflex', '20', '0'),
  ('Suporte Tablet Samsung 8"', 'Tablets e acessórios', '', 'Roboflex', '20', '20'),
  ('Suporte Ventosa', 'Tablets e acessórios', '', 'Roboflex', '20', '20'),
  ('Carregador DC/DC 12V Tablet Roboflex', 'Tablets e acessórios', '', 'Roboflex', '20', '30'),
  ('Cartão RFID 125', 'RFID e identificação', '', 'Mercado Livre', '5', '200'),
  ('Cartão RFID 13,56', 'RFID e identificação', '', 'Mercado Livre', '5', '500'),
  ('Leitor RFID 125 DREXIA', 'RFID e identificação', '', 'SGBras', '15', '0'),
  ('Leitor RFID 125 SGBRAS', 'RFID e identificação', '', 'SGBras', '15', '0'),
  ('Leitor RFID 13,56 / 125', 'RFID e identificação', '', 'SGBras', '15', '500'),
  ('Leitor RFID 13,56 DREXIA', 'RFID e identificação', '', 'Drexia', '', '0'),
  ('Leitor RFID 13,56 SGBRAS', 'RFID e identificação', '', 'SGBras', '15', '0'),
  ('Baterias Plug&Play M11', 'Alimentação e conversores', '', 'M11N Baterias', '15', '5'),
  ('Carregador Plug Play', 'Alimentação e conversores', '', 'M11N Baterias', '15', '5'),
  ('Conversor locomotiva 1 Amper', 'Alimentação e conversores', '', 'Anderson Conversores', '10', '0'),
  ('Conversor locomotiva 3 Amper', 'Alimentação e conversores', '', 'Anderson Conversores', '10', '20'),
  ('Conversor locomotiva 15 Amper', 'Alimentação e conversores', '', 'MCE Técnica', '15', '0'),
  ('Sensor de temperatura', 'Sensores e sinalização', '', 'AutoSender', '10', '20'),
  ('Sensor Betoneira', 'Sensores e sinalização', '', 'AutoSender', '10', '0'),
  ('Buzzer', 'Sensores e sinalização', '', 'Mercado Livre', '10', '200'),
  ('Repetir de Sinal WIFI', 'Sensores e sinalização', '', 'PrimeField', '30', '0'),
  ('Leitor EasyCAN', 'Sensores e sinalização', '', 'Teltonika', '30', '50'),
  ('Relé Bloqueio 12 Volts', 'Automação e controle', '', 'Mercado Livre', '10', '30'),
  ('Relé Bloqueio 24 Volts', 'Automação e controle', '', 'Mercado Livre', '10', '30'),
  ('Relé Finder', 'Automação e controle', '', 'Finder Tech', '30', '30'),
  ('Velocimetro Universal', 'Automação e controle', '', 'Mercado Livre', '10', '0'),
  ('Valvula Solenoide CTA', 'Automação e controle', '', 'Securitek', '30', '0'),
  ('Antena Move2GO', 'Comunicação e conectividade', '', 'PrimeField', '', '0'),
  ('Chip Claro M2M', 'Comunicação e conectividade', '', 'Securitek', '30', '0'),
  ('Chip Vivo M2M', 'Comunicação e conectividade', '', 'Securitek', '30', '100'),
  ('Chip Arqia M2M', 'Comunicação e conectividade', '', 'Securitek', '30', '0'),
  ('Chip Claro Voz e Dados', 'Comunicação e conectividade', '', 'Securitek', '30', '0'),
  ('Chip Vivo Voz e Dados', 'Comunicação e conectividade', '', 'Securitek', '30', '0'),
  ('Chip Arqia Voz e Dados', 'Comunicação e conectividade', '', 'Securitek', '30', '0'),
  ('Cartão Memória 128GB', 'Armazenamento de dados', '', 'Intelbrás', '30', '0'),
  ('Cartão Memória 256GB', 'Armazenamento de dados', '', 'Intelbrás', '30', '0'),
  ('Cartão Memória Galileo', 'Armazenamento de dados', '', 'SGBras', '15', '0'),
  ('Cartão Memória 128GB MICRO SD', 'Armazenamento de dados', '', 'Intelbrás', '30', '0'),
  ('Cartão Memória 256GB MICRO SD', 'Armazenamento de dados', '', 'Intelbrás', '30', '0'),
  ('Caixa patola Locomotiva', 'Caixas e gabinetes', '', 'Mercado Livre', '10', '5'),
  ('Caixa patola para Fadiga', 'Caixas e gabinetes', '', 'Mercado Livre', '10', '50'),
  ('KIT CTA Comboio', 'Controle de abastecimento e comboio', '', 'CTA', '30', '0'),
  ('KIT CTA Posto fixo', 'Controle de abastecimento e comboio', '', 'CTA', '30', '0'),
  ('Galielo Rotograma falado', 'Navegação e orientação veicular', '', 'SGBras', '15', '20'),
  ('Smartlink Carretinha', 'Integração veicular', '', 'PrimeField', '30', '0')
) as v(nome, categoria, fabricante, fornecedor, prazo, minimo)
join categoria c on c.nome = v.categoria
left join fornecedor f on f.nome = v.fornecedor;

-- Itens que andam juntos (sugestão editável): módulo Galileo leva chicote Galileo.
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p, produto a
 where p.nome in ('Galileo 7x / 10HUB', 'GalileoSky WIFI') and a.nome = 'Chicote Galileo';

-- Módulos Teltonika FMC130 e FMC150 também levam o chicote correspondente (sugestão editável).
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote ' || replace(p.nome, ' ', '')
 where p.nome in ('FMC 130', 'FMC 150')
on conflict do nothing;

-- Todo rastreador Ruptela, GalileoSky e Teltonika leva o chicote correspondente (sugestão editável).
-- Cria os chicotes que ainda não existiam (ECO 5, ECO-LIGHT +S, HCV5, FMB920) e liga cada módulo ao seu.
insert into produto (nome, categoria_id)
select v.nome, (select id from categoria where nome = 'Cabos, chicotes e conexões')
  from (values ('Chicote ECO 5'), ('Chicote ECO-LIGHT +S'), ('Chicote HCV5'), ('Chicote FMB920')) as v(nome)
on conflict (nome) do nothing;

insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1
  from (values
    ('ECO 5', 'Chicote ECO 5'), ('ECO-LIGHT +S', 'Chicote ECO-LIGHT +S'), ('HCV5', 'Chicote HCV5'),
    ('GF Pro4', 'Chicote Pro4'), ('PRO5 Lite', 'Chicote Pro5'), ('TRACE 5', 'Chicote Trace5'),
    ('FMB920', 'Chicote FMB920'), ('FMC 130', 'Chicote FMC130'), ('FMC 150', 'Chicote FMC150'), ('FMC 650', 'Chicote FMC650'),
    ('Galileo 7x / 10HUB', 'Chicote Galileo'), ('GalileoSky WIFI', 'Chicote Galileo')
  ) as v(modulo, chicote)
  join produto p on p.nome = v.modulo
  join produto a on a.nome = v.chicote
on conflict do nothing;

-- ================================================================ 0011_chips (dados)
-- Dados dos chips: quais itens são módulos com chip e quais são chips avulsos.
update produto set usa_chip = true
 where fabricante in ('Ruptela','Teltonika','GalileoSky')
   and categoria_id = (select id from categoria where nome = 'Rastreamento e telemetria');
update produto set chip_tipo = 'claro' where nome = 'Chip Claro M2M';
update produto set chip_tipo = 'vivo'  where nome = 'Chip Vivo M2M';
update produto set chip_tipo = 'arqia'  where nome = 'Chip Arqia M2M';


-- ================================================================ 0013_catalogo
-- Catálogo novo (77 itens) e chip Arqia como uma operadora só (mesmo conteúdo de atualizar_catalogo.sql).


-- ---------------------------------------------------------------- 1. Arqia: uma operadora só
-- Renomear o valor do enum mantém as linhas existentes; o que era arquia_vivo passa para arqia.
-- Aceita qualquer estado anterior: arquia_claro/arquia_vivo (chips antigos), arquia (nome provisório) ou arqia.
do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'condicao_item' and e.enumlabel = 'arqia') then
    if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                where t.typname = 'condicao_item' and e.enumlabel = 'arquia') then
      alter type condicao_item rename value 'arquia' to 'arqia';
    elsif exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                   where t.typname = 'condicao_item' and e.enumlabel = 'arquia_claro') then
      alter type condicao_item rename value 'arquia_claro' to 'arqia';
    end if;
  end if;
end $$;
update movimentacao_item set condicao = 'arqia' where condicao::text in ('arquia', 'arquia_claro', 'arquia_vivo');
update produto set chip_tipo = 'arqia' where chip_tipo in ('arquia', 'arquia_claro', 'arquia_vivo');

create or replace function public.fn_rotulo_chip(c text) returns text language sql immutable as $$
  select case c when 'novo' then 'sem chip' when 'claro' then 'Claro' when 'vivo' then 'Vivo'
                when 'arqia' then 'Arqia' else c end
$$;

create or replace function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb; v_pid integer; v_chip text;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    v_pid := (it->>'produto_id')::int;
    -- só módulos com chip guardam o chip; os demais itens ficam sempre em 'novo'
    v_chip := case when exists (select 1 from produto where id = v_pid and usa_chip)
                   then coalesce(nullif(it->>'condicao',''), 'novo') else 'novo' end;
    if v_chip not in ('novo','claro','vivo','arqia') then raise exception 'Chip inválido: %', v_chip; end if;
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov, v_pid, v_chip::condicao_item, (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arqia).
-- Instalar chip avulso baixa o chip avulso; o chip retirado volta ao estoque avulso ou é descartado.
-- p: {local_id, produto_id, quantidade, de, para, chip_retirado ('estoque'|'descartar'), observacao, data}
create or replace function public.trocar_chip(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := (p->>'local_id')::int; v_prod integer := (p->>'produto_id')::int;
  v_qtd integer := (p->>'quantidade')::int;
  v_de text := coalesce(nullif(p->>'de',''), 'novo'); v_para text := coalesce(nullif(p->>'para',''), 'novo');
  v_dest text := coalesce(nullif(p->>'chip_retirado',''), 'estoque');
  v_id bigint; v_chip_de integer; v_chip_para integer; v_obs text := nullif(p->>'observacao','');
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arqia') or v_para not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  -- Mesmo chip de antes só faz sentido para substituir um chip ruim: o antigo é descartado e sai outro avulso.
  if v_de = v_para and (v_de = 'novo' or v_dest <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  if v_de <> 'novo' then select id into v_chip_de from produto where chip_tipo = v_de and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_de); end if; end if;
  if v_para <> 'novo' then select id into v_chip_para from produto where chip_tipo = v_para and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_para); end if; end if;

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', coalesce((p->>'data')::date, current_date), v_local,
          concat_ws(E'\n', case when v_de = v_para then 'Chip ' || fn_rotulo_chip(v_de) || ' substituído por outro' else fn_rotulo_chip(v_de) || ' → ' || fn_rotulo_chip(v_para) end ||
                    case when v_de <> 'novo' and v_dest = 'descartar' then ' (chip retirado descartado)' else '' end, v_obs), auth.uid())
  returning id into v_id;
  if v_de <> v_para then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values
      (v_id, v_prod, v_de::condicao_item, -v_qtd), (v_id, v_prod, v_para::condicao_item, v_qtd);
  end if;
  if v_chip_de is not null and v_dest = 'estoque' then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_de, 'novo', v_qtd);
  end if;
  if v_chip_para is not null then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_para, 'novo', -v_qtd);
  end if;
  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;

-- Chip avulso da Arqia: "Chip Arqia M2M". O que estava em Arqia Claro/Vivo M2M passa para ele.
update produto set chip_tipo = 'arqia' where nome = 'Chip Arqia M2M';
update movimentacao_item set produto_id = (select id from produto where nome = 'Chip Arqia M2M')
 where produto_id in (select id from produto where nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M'));
update pedido_compra set produto_id = (select id from produto where nome = 'Chip Arqia M2M')
 where produto_id in (select id from produto where nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M'));
-- Solicitações: a linha (solicitação, item, reservas) é única. Soma na linha do Chip Arqia M2M
-- quando ela já existe; senão cria. As linhas antigas saem no passo 4, junto com os dois produtos.
create temporary table arqia_sol as
select si.solicitacao_id, si.reservar_para_unidade_id, si.reservado_unidade_id, sum(si.quantidade) as qtd
  from solicitacao_item si join produto p on p.id = si.produto_id
 where p.nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M')
 group by 1, 2, 3;
update solicitacao_item si set quantidade = si.quantidade + a.qtd
  from arqia_sol a
 where si.produto_id = (select id from produto where nome = 'Chip Arqia M2M')
   and si.solicitacao_id = a.solicitacao_id
   and coalesce(si.reservar_para_unidade_id, 0) = coalesce(a.reservar_para_unidade_id, 0)
   and coalesce(si.reservado_unidade_id, 0) = coalesce(a.reservado_unidade_id, 0);
insert into solicitacao_item (solicitacao_id, produto_id, quantidade, reservar_para_unidade_id, reservado_unidade_id)
select a.solicitacao_id, (select id from produto where nome = 'Chip Arqia M2M'), a.qtd,
       a.reservar_para_unidade_id, a.reservado_unidade_id
  from arqia_sol a
 where not exists (select 1 from solicitacao_item si
                    where si.produto_id = (select id from produto where nome = 'Chip Arqia M2M')
                      and si.solicitacao_id = a.solicitacao_id
                      and coalesce(si.reservar_para_unidade_id, 0) = coalesce(a.reservar_para_unidade_id, 0)
                      and coalesce(si.reservado_unidade_id, 0) = coalesce(a.reservado_unidade_id, 0));
drop table arqia_sol;

-- ---------------------------------------------------------------- 2. Renomear
update produto p set nome = v.novo
  from (values
    ('ECO 5', 'Módulo ECO 5'),
    ('ECO-LIGHT +S', 'Módulo ECO-LIGHT +S'),
    ('FMB920', 'Módulo FMB920'),
    ('FMC 130', 'Módulo FMC 130'),
    ('FMC 150', 'Módulo FMC 150'),
    ('FMC 650', 'Módulo FMC 650'),
    ('Galileo 7x / 10HUB', 'Módulo Galileo 7x / 10HUB'),
    ('GF Pro4', 'Módulo GF Pro4'),
    ('HCV5', 'Módulo HCV5'),
    ('PRO5 Lite', 'Módulo PRO5 Lite'),
    ('TRACE 5', 'Módulo TRACE 5'),
    ('SUNTECH Plug Play', 'Módulo SUNTECH PLUG PLAY'),
    ('Camera Contexto (3Fios)', 'Camera contexto DVR'),
    ('Camera Contexto (3Fios) DashCAM', 'Camera Contexto DashCAM'),
    ('Camera Fadiga (T)', 'Camera Fadiga DVR'),
    ('Camera Fadiga (T) DashCAM', 'Camera Fadiga DashCAM'),
    ('Camera frontal (vermelha)', 'Camera frontal (Adas) DVR'),
    ('Monitor de alarme', 'Monitor de alarme (SmartWach)'),
    ('Cabo rede 3 metros', 'Cabo rede'),
    ('Chicote Galileo', 'Chicote Galileo 7x / 10HUB'),
    ('Extensão cameras Intelbras', 'Extensão cameras'),
    ('Extensão cameras Intelbras DashCAM', 'Extensão cameras DashCAM'),
    ('Tablet Multilaser 7''''', 'Tablet Multilaser'),
    ('Suporte Case Tablet Multilaser 7"', 'Case Tablet Multilaser'),
    ('Suporte Case Tablet Samsung 8"', 'Case Tablet Samsung'),
    ('Suporte Tablet Multilaser 7"', 'Suporte Tablet Multilaser'),
    ('Suporte Tablet Samsung 8"', 'Suporte Tablet Samsung'),
    ('Leitor RFID 125 SGBRAS', 'Leitor RFID 125'),
    ('Leitor RFID 13,56 SGBRAS', 'Leitor RFID 13,56')
  ) as v(antigo, novo)
 where p.nome = v.antigo
   and not exists (select 1 from produto x where x.nome = v.novo);

-- ---------------------------------------------------------------- 2b. MDVR e monitores (lista de 2026-11-23)
-- Renomeia (mesmo id, o histórico continua ligado). Os dois MDVRs Intelbras continuam separados.
update produto p set nome = v.novo
  from (values
    ('DVR DashCAM', 'DashCAM'),
    ('DVR Intelbras 3404', 'MDVR Intelbras 3404'),
    ('DVR Intelbras 5404', 'MDVR Intelbras 5404')
  ) as v(antigo, novo)
 where p.nome = v.antigo
   and not exists (select 1 from produto x where x.nome = v.novo);

-- ---------------------------------------------------------------- 3. Itens novos
insert into produto (nome, categoria_id, fornecedor_id, prazo_medio_dias)
values
  ('Camera frontal (Adas) DashCAM', (select id from categoria where nome = 'Câmeras'),
   (select id from fornecedor where nome = 'Intelbrás'), 30),
  ('Chicote SUNTECH Plug Play', (select id from categoria where nome = 'Cabos, chicotes e conexões'),
   (select id from fornecedor where nome = 'Suntech'), 15)
on conflict (nome) do nothing;

-- O módulo Suntech sai com o chicote dele (sugestão editável, "Com chicote").
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote SUNTECH Plug Play'
 where p.nome = 'Módulo SUNTECH PLUG PLAY'
on conflict do nothing;

-- ---------------------------------------------------------------- 4. Apagar o que não está na lista
drop table if exists catalogo_novo, produto_apagar;
create temporary table catalogo_novo (nome text primary key);
insert into catalogo_novo (nome) values
  ('Baterias Plug&Play M11'), ('Buzzer'), ('Cabo rede'), ('Camera Contexto DashCAM'), ('Camera contexto DVR'),
  ('Camera Fadiga DVR'), ('Camera Fadiga DashCAM'), ('Camera frontal (Adas) DVR'), ('Camera frontal (Adas) DashCAM'),
  ('Camera IP'), ('Carregador DC/DC 12V Tablet Roboflex'), ('Carregador Plug Play'), ('Cartão Memória 128GB'),
  ('Cartão Memória 128GB MICRO SD'), ('Cartão Memória 256GB'), ('Cartão Memória 256GB MICRO SD'), ('Cartão RFID 125'),
  ('Cartão RFID 13,56'), ('Chicote ECO 5'), ('Chicote ECO-LIGHT +S'), ('Chicote FMB920'), ('Chicote FMC130'),
  ('Chicote FMC150'), ('Chicote FMC650'), ('Chicote Galileo 7x / 10HUB'), ('Chicote Pro4'), ('Chicote Pro5'),
  ('Chicote SUNTECH Plug Play'), ('Chicote Trace5'), ('Chip Arqia M2M'), ('Chip Arqia Voz e Dados'), ('Chip Claro M2M'),
  ('Chip Claro Voz e Dados'), ('Chip Vivo M2M'), ('Chip Vivo Voz e Dados'), ('Conversor locomotiva 1 Amper'),
  ('Conversor locomotiva 15 Amper'), ('Conversor locomotiva 3 Amper'), ('DashCAM'), ('MDVR Intelbras 3404'),
  ('MDVR Intelbras 5404'), ('Extensão cameras'), ('Extensão cameras DashCAM'), ('Galielo Rotograma falado'),
  ('KIT CTA Comboio'), ('KIT CTA Posto fixo'), ('Leitor EasyCAN'), ('Leitor RFID 125'), ('Leitor RFID 13,56'),
  ('Leitor RFID 13,56 / 125'), ('Módulo ECO 5'), ('Módulo ECO-LIGHT +S'), ('Módulo FMB920'), ('Módulo FMC 130'),
  ('Módulo FMC 150'), ('Módulo FMC 650'), ('Módulo Galileo 7x / 10HUB'), ('Módulo GF Pro4'), ('Módulo HCV5'),
  ('Módulo PRO5 Lite'), ('Módulo SUNTECH PLUG PLAY'), ('Módulo TRACE 5'), ('Monitor de alarme (SmartWach)'),
  ('Relé Bloqueio 12 Volts'), ('Relé Bloqueio 24 Volts'), ('Relé Finder'), ('Sensor Betoneira'),
  ('Sensor de temperatura'), ('Smartlink Carretinha'), ('Case Tablet Multilaser'), ('Case Tablet Samsung'),
  ('Suporte Tablet Multilaser'), ('Suporte Tablet Samsung'), ('Suporte Ventosa'), ('Switch cabo rede Intelbras'),
  ('Tablet Multilaser'), ('Tablet Samsung');

create temporary table produto_apagar as
select id, nome from produto where nome not in (select nome from catalogo_novo);

do $$ declare r record; begin
  for r in select nome from produto_apagar order by nome loop raise notice 'Apagando: %', r.nome; end loop;
end $$;

delete from item_associado where produto_id in (select id from produto_apagar) or associado_id in (select id from produto_apagar);
delete from solicitacao_item where produto_id in (select id from produto_apagar);
delete from pedido_compra where produto_id in (select id from produto_apagar);
delete from movimentacao_item where produto_id in (select id from produto_apagar);
delete from produto where id in (select id from produto_apagar);

-- Conferência: tem que haver exatamente os 77 itens da lista.
do $$ declare v_faltando text; v_total int; begin
  select string_agg(c.nome, ', ') into v_faltando from catalogo_novo c where not exists (select 1 from produto p where p.nome = c.nome);
  if v_faltando is not null then raise exception 'Itens da lista que não existem no banco: %', v_faltando; end if;
  select count(*) into v_total from produto;
  if v_total <> 77 then raise exception 'Esperava 77 itens, o banco tem %', v_total; end if;
end $$;

drop table catalogo_novo, produto_apagar;


-- ================================================================ 0014_permissoes_funcoes
-- No Supabase toda função nova do schema public já nasce executável por anon e authenticated.
-- Fecha as funções internas (ex.: fn_gravar_itens) e libera só as que o app e a RLS usam
-- (mesmo conteúdo de atualizar_permissoes_funcoes.sql).

revoke execute on all functions in schema public from public, anon, authenticated;

-- Lista final das funções liberadas para usuário logado. Funções que ainda não existem (atualizações
-- seguintes não rodadas) são puladas. criar_transferencia só fica liberada enquanto o fluxo de pedidos
-- (atualizar_fluxo_pedidos.sql) não foi instalado; depois dele ela é interna.
do $$
declare
  f text;
  lista text[] := array[
    -- usadas pelas regras de segurança (RLS), pelas views e pelas telas
    'public.fn_perfil()', 'public.fn_pode_ver_local(integer)', 'public.fn_pode_operar_local(integer)',
    'public.fn_rotulo_chip(text)', 'public.fn_hoje()', 'public.fn_local_responsavel(public.solicitacao)',
    'public.fn_pode_cancelar(public.solicitacao)', 'public.definir_visualizacao(jsonb)',
    -- chamadas pelo app
    'public.registrar_movimentacao(jsonb)', 'public.confirmar_recebimento(bigint)',
    'public.cancelar_transferencia(bigint,text)', 'public.estornar_movimentacao(bigint,text)',
    'public.criar_pedido_transferencia(jsonb)', 'public.criar_solicitacao(jsonb)', 'public.aceitar_solicitacao(bigint)',
    'public.atender_solicitacao(bigint,jsonb)', 'public.cancelar_solicitacao(bigint)', 'public.trocar_chip(jsonb)'];
begin
  if to_regprocedure('public.criar_pedido_transferencia(jsonb)') is null then
    lista := lista || 'public.criar_transferencia(jsonb)'::text;
  end if;
  foreach f in array lista loop
    if to_regprocedure(f) is not null then
      execute 'grant execute on function ' || to_regprocedure(f)::regprocedure::text || ' to authenticated';
    end if;
  end loop;
end $$;

-- Conferência: as funções internas não podem ficar liberadas para usuário logado nem anônimo.
do $$ declare v text; begin
  select string_agg(p.proname, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname in ('fn_gravar_itens', 'fn_verificar_saldo', 'fn_travar_locais', 'fn_auditar', 'fn_novo_usuario',
                        'fn_data_movimento', 'fn_verificar_dedicado_inteiro', 'fn_itens_dedicado', 'fn_nome_unidade',
                        'fn_gravar_itens_pedido', 'fn_perfil_real', 'fn_simulacao', 'fn_tecnico_atual', 'fn_local_do_usuario')
          or (p.proname = 'criar_transferencia' and to_regprocedure('public.criar_pedido_transferencia(jsonb)') is not null))
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  if v is not null then raise exception 'Funções internas ainda liberadas: %', v; end if;
end $$;


-- ================================================================ 0015_regras_dedicado_datas
-- Datas não podem ser futuras (hoje em São Paulo), sedex vira correios, dedicado só nasce por devolução,
-- ajuste ou transferência, e dedicado sai inteiro (mesmo conteúdo de atualizar_regras_dedicado_datas.sql).

-- ---------------------------------------------------------------- 1. Hoje em São Paulo e data da movimentação
create or replace function public.fn_hoje() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

-- Data informada (ou hoje em São Paulo, se vier vazia); data no futuro é recusada.
create or replace function public.fn_data_movimento(p_data text) returns date
language plpgsql stable set search_path = public as $$
declare v date := coalesce(nullif(p_data, '')::date, fn_hoje());
begin
  if v > fn_hoje() then
    raise exception 'A data não pode ser no futuro (hoje é %)', to_char(fn_hoje(), 'DD/MM/YYYY');
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------- 2. Meio de envio: sedex vira correios
update movimentacao set modo_envio = 'correios' where modo_envio = 'sedex';
alter table movimentacao drop constraint if exists movimentacao_sem_sedex;
alter table movimentacao add constraint movimentacao_sem_sedex check (modo_envio is distinct from 'sedex');

-- ---------------------------------------------------------------- 3. Dedicado vai inteiro
-- Para cada unidade cujo dedicado esta movimentação tirou de um local, confere que não sobrou nada
-- dela naquele local (somando todos os itens e chips). Chamada depois de fn_verificar_saldo.
create or replace function public.fn_verificar_dedicado_inteiro(p_mov bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_resta integer;
begin
  for r in
    select distinct x.local_id, x.unidade_id from (
      select m.local_origem_id as local_id, i.reservado_unidade_id as unidade_id
        from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
       where i.movimentacao_id = p_mov and m.local_origem_id is not null and i.reservado_unidade_id is not null
         and m.tipo in ('SAIDA_CLIENTE','CONSUMO_INTERNO','DESCARTE','TRANSFERENCIA')
      union
      select m.local_destino_id, coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id)
        from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
       where i.movimentacao_id = p_mov and m.local_destino_id is not null and i.quantidade < 0
         and coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) is not null
         and m.tipo in ('AJUSTE','TROCA_CHIP')
    ) x
  loop
    select coalesce(sum(e.delta), 0) into v_resta
      from efeito_estoque e where e.local_id = r.local_id and e.reservado_unidade_id = r.unidade_id;
    if v_resta <> 0 then
      raise exception 'O estoque dedicado de % em % precisa ir inteiro: faltam % itens',
        (select c.nome || ' - ' || u.nome from unidade_cliente u join cliente c on c.id = u.cliente_id where u.id = r.unidade_id),
        (select nome from local where id = r.local_id), v_resta
        using errcode = 'P0001';
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- 4. registrar_movimentacao
-- p: {tipo, data, local_id, unidade_id, fornecedor_id, numero_nf, finalidade, chamado_url, observacao,
--     modo_envio, codigo_rastreio, tecnico_id,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
-- Na saída para cliente o modo de envio é obrigatório; se for "tecnico", informe qual técnico leva.
-- Quando o próprio técnico dá a baixa, o modo é "tecnico" e o técnico é ele mesmo.
create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
  v_data date;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      select t.id into v_tec from tecnico t where t.usuario_id = auth.uid();
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', v_data,
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Dedicado nasce por devolução de cliente, ajuste ou recebimento de transferência ("Dedicado para").
  if v_tipo not in ('DEVOLUCAO_CLIENTE','AJUSTE')
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;
  -- Na compra, item que já sai de um dedicado também não faz sentido (criaria dedicado na entrada).
  if v_tipo = 'ENTRADA_COMPRA'
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservado_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. criar_transferencia (só data, meio de envio e dedicado inteiro)
-- p: {origem_id, destino_id, data, modo_envio, codigo_rastreio, prazo_chegada, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
create or replace function public.criar_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_origem  integer := (p->>'origem_id')::int;
  v_destino integer := (p->>'destino_id')::int;
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_data date;
  v_id bigint;
begin
  if fn_perfil() is null or fn_perfil() = 'consulta' then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if v_origem is null or v_destino is null or v_origem = v_destino then
    raise exception 'Informe origem e destino diferentes';
  end if;
  -- Só o dono do local de origem inicia o envio.
  if not fn_pode_operar_local(v_origem) then
    raise exception 'Sem permissão para enviar deste local' using errcode = '42501';
  end if;
  if fn_perfil() = 'tecnico' then
    raise exception 'Técnico não cria transferência; use solicitação' using errcode = '42501';
  end if;
  if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
  v_data := fn_data_movimento(p->>'data');

  perform fn_travar_locais(array[v_origem, v_destino]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, modo_envio, codigo_rastreio,
                            prazo_chegada, observacao, criado_por)
  values ('TRANSFERENCIA', 'em_transito', v_data, v_origem, v_destino,
          v_modo, nullif(p->>'codigo_rastreio',''),
          nullif(p->>'prazo_chegada','')::date, nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  perform fn_gravar_itens(v_id, p->'itens');
  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  perform fn_verificar_saldo(array[v_origem]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 6. trocar_chip (só a data)
-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arqia), sempre no estoque livre.
-- Instalar chip avulso baixa o chip avulso; o chip retirado volta ao estoque avulso ou é descartado.
-- p: {local_id, produto_id, quantidade, de, para, chip_retirado ('estoque'|'descartar'), observacao, data}
create or replace function public.trocar_chip(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := (p->>'local_id')::int; v_prod integer := (p->>'produto_id')::int;
  v_qtd integer := (p->>'quantidade')::int;
  v_de text := coalesce(nullif(p->>'de',''), 'novo'); v_para text := coalesce(nullif(p->>'para',''), 'novo');
  v_dest text := coalesce(nullif(p->>'chip_retirado',''), 'estoque');
  v_id bigint; v_chip_de integer; v_chip_para integer; v_obs text := nullif(p->>'observacao','');
  v_data date;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arqia') or v_para not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  -- Mesmo chip de antes só faz sentido para substituir um chip ruim: o antigo é descartado e sai outro avulso.
  if v_de = v_para and (v_de = 'novo' or v_dest <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  v_data := fn_data_movimento(p->>'data');
  if v_de <> 'novo' then select id into v_chip_de from produto where chip_tipo = v_de and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_de); end if; end if;
  if v_para <> 'novo' then select id into v_chip_para from produto where chip_tipo = v_para and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_para); end if; end if;

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', v_data, v_local,
          concat_ws(E'\n', case when v_de = v_para then 'Chip ' || fn_rotulo_chip(v_de) || ' substituído por outro' else fn_rotulo_chip(v_de) || ' → ' || fn_rotulo_chip(v_para) end ||
                    case when v_de <> 'novo' and v_dest = 'descartar' then ' (chip retirado descartado)' else '' end, v_obs), auth.uid())
  returning id into v_id;
  if v_de <> v_para then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values
      (v_id, v_prod, v_de::condicao_item, -v_qtd), (v_id, v_prod, v_para::condicao_item, v_qtd);
  end if;
  if v_chip_de is not null and v_dest = 'estoque' then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_de, 'novo', v_qtd);
  end if;
  if v_chip_para is not null then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_para, 'novo', -v_qtd);
  end if;
  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 7. Permissões das funções novas
-- (no Supabase função nova já nasce liberada para anon e authenticated)
revoke execute on function public.fn_data_movimento(text), public.fn_verificar_dedicado_inteiro(bigint)
  from public, anon, authenticated;
revoke execute on function public.fn_hoje() from public, anon;
grant execute on function public.fn_hoje() to authenticated;
revoke execute on function public.registrar_movimentacao(jsonb), public.criar_transferencia(jsonb), public.trocar_chip(jsonb)
  from public, anon;
grant execute on function public.registrar_movimentacao(jsonb), public.criar_transferencia(jsonb), public.trocar_chip(jsonb)
  to authenticated;



-- ================================================================ 0016_fluxo_pedidos
-- Transferência vira pedido (origem aceita e envia), solicitação só do agendamento para cliente
-- (mesmo conteúdo de atualizar_fluxo_pedidos.sql).

-- ---------------------------------------------------------------- 1. Tabelas
alter table solicitacao add column if not exists tipo text not null default 'legado';
alter table solicitacao drop constraint if exists solicitacao_tipo_valido;
alter table solicitacao add constraint solicitacao_tipo_valido
  check (tipo in ('transferencia', 'enviar_cliente', 'enviar_dedicado', 'retirar_dedicado', 'legado'));

-- Cada linha do pedido ganha um id (para escolher o chip no envio) e o chip pedido (nulo = escolher no envio).
alter table solicitacao_item add column if not exists id bigint generated by default as identity;
create unique index if not exists solicitacao_item_id_unico on solicitacao_item (id);
alter table solicitacao_item add column if not exists condicao condicao_item;
drop index if exists solicitacao_item_unico;
create unique index solicitacao_item_unico
  on solicitacao_item (solicitacao_id, produto_id, condicao,
                       coalesce(reservar_para_unidade_id, 0), coalesce(reservado_unidade_id, 0)) nulls not distinct;

-- Dedicados que um pedido de transferência leva inteiros (todo o saldo da unidade no estoque de origem).
create table if not exists solicitacao_dedicado (
  solicitacao_id bigint  not null references solicitacao(id),
  unidade_id     integer not null references unidade_cliente(id),
  primary key (solicitacao_id, unidade_id)
);
alter table solicitacao_dedicado enable row level security;
drop policy if exists sol_ded_ler on solicitacao_dedicado;
create policy sol_ded_ler on solicitacao_dedicado for select using (
  exists (select 1 from solicitacao s where s.id = solicitacao_id));
revoke all on solicitacao_dedicado from public, anon, authenticated;
grant select on solicitacao_dedicado to authenticated;

-- O técnico vê também os pedidos de transferência para o carro dele (ele confirma o recebimento).
drop policy if exists sol_ler on solicitacao;
create policy sol_ler on solicitacao for select using (
  tecnico_id = auth.uid()
  or fn_perfil()::text in ('admin','operador','consulta','agendamento')
  or (fn_perfil()::text = 'tecnico' and destino_id is not null and fn_pode_ver_local(destino_id)));

-- ---------------------------------------------------------------- 2. Funções internas
-- Todo o saldo dedicado de uma unidade num local, como itens de movimentação (todos os itens e chips).
create or replace function public.fn_itens_dedicado(p_local integer, p_unidade integer) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('produto_id', produto_id, 'condicao', condicao, 'quantidade', q,
                                               'reservado_unidade_id', p_unidade) order by produto_id, condicao), '[]'::jsonb)
    from (select e.produto_id, e.condicao, sum(e.delta) as q
            from efeito_estoque e
           where e.local_id = p_local and e.reservado_unidade_id = p_unidade
           group by 1, 2 having sum(e.delta) > 0) x
$$;

create or replace function public.fn_nome_unidade(p_unidade integer) returns text
language sql stable security definer set search_path = public as $$
  select c.nome || ' - ' || u.nome from unidade_cliente u join cliente c on c.id = u.cliente_id where u.id = p_unidade
$$;

-- Grava as linhas de um pedido. p_itens: [{produto_id, quantidade, condicao?, reservar_para_unidade_id?}]
create or replace function public.fn_gravar_itens_pedido(p_sol bigint, p_itens jsonb, p_dedicado_para boolean) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb; v_pid integer; v_chip text; v_qtd integer;
begin
  for it in select * from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) loop
    v_pid := nullif(it->>'produto_id','')::int;
    v_qtd := nullif(it->>'quantidade','')::int;
    if v_pid is null or not exists (select 1 from produto where id = v_pid) then raise exception 'Item inválido'; end if;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
    if nullif(it->>'reservado_unidade_id','') is not null then
      raise exception 'Para levar estoque dedicado, escolha a unidade em dedicados (vai o dedicado inteiro)';
    end if;
    if nullif(it->>'reservar_para_unidade_id','') is not null and not p_dedicado_para then
      raise exception 'Este pedido não aceita "Dedicado para"';
    end if;
    v_chip := case when exists (select 1 from produto where id = v_pid and usa_chip) then nullif(it->>'condicao','')
                   else 'novo' end;
    if v_chip is not null and v_chip not in ('novo','claro','vivo','arqia') then raise exception 'Chip inválido: %', v_chip; end if;
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade, condicao, reservar_para_unidade_id)
    values (p_sol, v_pid, v_qtd, v_chip::condicao_item, nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- Local que dá andamento ao pedido: a origem; no retirar_dedicado, o destino.
create or replace function public.fn_local_responsavel(s solicitacao) returns integer
language sql stable set search_path = public as $$
  select case when s.tipo = 'retirar_dedicado' then s.destino_id else s.origem_id end
$$;

-- ---------------------------------------------------------------- 3. Criar pedido de transferência
-- p: {origem_id, destino_id, chamado_url, observacao,
--     itens:[{produto_id, quantidade, condicao?, reservar_para_unidade_id?}], dedicados:[unidade_id,...]}
create or replace function public.criar_pedido_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_orig integer := nullif(p->>'origem_id','')::int; v_dest integer := nullif(p->>'destino_id','')::int;
  v_id bigint; v_un integer;
begin
  if fn_perfil()::text not in ('admin','operador') or fn_perfil() is null then
    raise exception 'Só administrador e operador criam pedido de transferência' using errcode = '42501';
  end if;
  if v_orig is null or v_dest is null then raise exception 'Informe de onde sai e para onde vai'; end if;
  if v_orig = v_dest then raise exception 'Origem e destino devem ser diferentes'; end if;
  if not exists (select 1 from local where id = v_orig and tipo = 'estoque') then raise exception 'A origem deve ser um estoque'; end if;
  if not exists (select 1 from local where id = v_dest) then raise exception 'Destino inválido'; end if;
  if coalesce(jsonb_array_length(nullif(p->'itens','null'::jsonb)), 0) = 0
     and coalesce(jsonb_array_length(nullif(p->'dedicados','null'::jsonb)), 0) = 0 then
    raise exception 'Informe ao menos um item ou um dedicado';
  end if;

  insert into solicitacao (tipo, tecnico_id, origem_id, destino_id, chamado_url, observacao)
  values ('transferencia', auth.uid(), v_orig, v_dest, nullif(p->>'chamado_url',''), nullif(p->>'observacao',''))
  returning id into v_id;
  perform fn_gravar_itens_pedido(v_id, p->'itens', true);
  for v_un in select distinct (x #>> '{}')::int from jsonb_array_elements(coalesce(nullif(p->'dedicados','null'::jsonb), '[]'::jsonb)) x loop
    if fn_itens_dedicado(v_orig, v_un) = '[]'::jsonb then
      raise exception 'Não há estoque dedicado de % em %', coalesce(fn_nome_unidade(v_un), 'unidade ' || v_un),
        (select nome from local where id = v_orig);
    end if;
    insert into solicitacao_dedicado (solicitacao_id, unidade_id) values (v_id, v_un);
  end loop;
  return v_id;
end $$;

-- ---------------------------------------------------------------- 4. Criar solicitação (só agendamento)
-- enviar_cliente:   {tipo, origem_id, unidade_id, chamado_url, observacao, itens:[{produto_id, quantidade, condicao?}]}
-- enviar_dedicado:  {tipo, origem_id, unidade_id, chamado_url, observacao}
-- retirar_dedicado: {tipo, destino_id, unidade_id, chamado_url, observacao, itens:[{produto_id, quantidade, condicao?}]}
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo text := nullif(p->>'tipo',''); v_un integer := nullif(p->>'unidade_id','')::int;
  v_orig integer; v_dest integer; v_id bigint;
  v_n integer := coalesce(jsonb_array_length(nullif(p->'itens','null'::jsonb)), 0);
  v_chamado text := nullif(btrim(p->>'chamado_url'), '');
begin
  if fn_perfil() is null or fn_perfil()::text <> 'agendamento' then
    raise exception 'Só o agendamento cria solicitação (transferência entre estoques é pedido de transferência)' using errcode = '42501';
  end if;
  if v_tipo is null or v_tipo not in ('enviar_cliente','enviar_dedicado','retirar_dedicado') then
    raise exception 'Tipo de solicitação inválido: use enviar_cliente, enviar_dedicado ou retirar_dedicado';
  end if;
  if v_un is null or not exists (select 1 from unidade_cliente where id = v_un) then raise exception 'Informe o cliente'; end if;

  if v_tipo in ('enviar_cliente','enviar_dedicado') then
    v_orig := nullif(p->>'origem_id','')::int;
    if v_orig is null or not exists (select 1 from local where id = v_orig and tipo = 'estoque') then
      raise exception 'Informe o estoque de onde sai';
    end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    if v_dest is null or not exists (select 1 from local where id = v_dest and tipo = 'estoque') then
      raise exception 'Informe o estoque para onde vai';
    end if;
  end if;
  if v_tipo = 'enviar_dedicado' then
    if v_n > 0 then raise exception 'Enviar dedicado leva o dedicado inteiro: não informe itens'; end if;
    if fn_itens_dedicado(v_orig, v_un) = '[]'::jsonb then
      raise exception 'Não há estoque dedicado de % em %', fn_nome_unidade(v_un), (select nome from local where id = v_orig);
    end if;
  elsif v_n = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  -- Enviar e retirar dedicado exigem o link do chamado (Jira); nos outros tipos ele é opcional.
  if v_tipo in ('enviar_dedicado','retirar_dedicado') then
    if v_chamado is null then
      raise exception 'Informe o link do chamado: é obrigatório para enviar e retirar dedicado';
    end if;
    if v_chamado !~* '^https?://' then
      raise exception 'O link do chamado deve começar com http:// ou https://';
    end if;
  end if;

  insert into solicitacao (tipo, tecnico_id, origem_id, destino_id, unidade_id, chamado_url, observacao)
  values (v_tipo, auth.uid(), v_orig, v_dest, v_un, v_chamado, nullif(p->>'observacao',''))
  returning id into v_id;
  perform fn_gravar_itens_pedido(v_id, p->'itens', false);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. Aceitar
create or replace function public.aceitar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_resp integer;
begin
  if fn_perfil()::text not in ('admin','operador') or fn_perfil() is null then
    raise exception 'Só administrador e operador aceitam solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text <> 'aberta' then raise exception 'Só dá para aceitar solicitação aberta'; end if;
  v_resp := fn_local_responsavel(s);
  if not fn_pode_operar_local(v_resp) then
    raise exception 'Só quem opera o estoque de % (%) dá andamento a esta solicitação',
      case when s.tipo = 'retirar_dedicado' then 'destino' else 'origem' end,
      coalesce((select nome from local where id = v_resp), '?') using errcode = '42501';
  end if;
  update solicitacao set status = 'em_producao', prazo_producao = now() + interval '1 day' where id = p_id;
end $$;

-- ---------------------------------------------------------------- 6. Atender (enviar, entregar ou registrar a chegada)
-- transferencia:    {data, modo_envio, codigo_rastreio, prazo_chegada, observacao, chips}  -> TRANSFERENCIA em trânsito
-- enviar_cliente /
-- enviar_dedicado:  {data, modo_envio, tecnico_id, codigo_rastreio, observacao, chips}     -> SAIDA_CLIENTE
-- retirar_dedicado: {data, observacao, chips}                                              -> DEVOLUCAO_CLIENTE dedicada
-- legado:           como antes (transferência origem -> destino com os itens do pedido)
-- chips: {"<solicitacao_item.id>": "novo"|"claro"|"vivo"|"arqia"}; sem escolha vale o chip do item (nulo = sem chip).
create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  s solicitacao; v_mov bigint; v_itens jsonb; v_resp integer; v_un integer; v_ded jsonb;
  v_obs text := coalesce(nullif(p->>'observacao',''), null);
begin
  if fn_perfil()::text not in ('admin','operador') or fn_perfil() is null then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação já encerrada'; end if;
  if s.tipo <> 'legado' and s.status::text <> 'em_producao' then
    raise exception 'Aceite a solicitação antes de atender';
  end if;
  v_resp := fn_local_responsavel(s);
  if not fn_pode_operar_local(v_resp) then
    raise exception 'Só quem opera o estoque de % (%) dá andamento a esta solicitação',
      case when s.tipo = 'retirar_dedicado' then 'destino' else 'origem' end,
      coalesce((select nome from local where id = v_resp), '?') using errcode = '42501';
  end if;

  if s.tipo = 'legado' then
    -- Pedido antigo: transferência com os itens do pedido. Chip: pelo id da linha ou pela chave antiga
    -- "<produto_id>|<unidade dedicada ou vazio>".
    if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
    select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                        'reservar_para_unidade_id', reservar_para_unidade_id,
                                        'reservado_unidade_id', reservado_unidade_id,
                                        'condicao', coalesce(p->'chips'->>(id::text),
                                                             p->'chips'->>(produto_id::text || '|' || coalesce(reservar_para_unidade_id::text, '')),
                                                             condicao::text, 'novo')))
      into v_itens from solicitacao_item where solicitacao_id = p_id;
    v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));

  else
    select coalesce(jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                        'reservar_para_unidade_id', case when s.tipo = 'retirar_dedicado' then s.unidade_id
                                                                         else reservar_para_unidade_id end,
                                        'condicao', coalesce(p->'chips'->>(id::text), condicao::text, 'novo'))), '[]'::jsonb)
      into v_itens from solicitacao_item where solicitacao_id = p_id;

    if s.tipo = 'transferencia' then
      for v_un in select unidade_id from solicitacao_dedicado where solicitacao_id = p_id order by unidade_id loop
        v_ded := fn_itens_dedicado(s.origem_id, v_un);
        if v_ded = '[]'::jsonb then
          raise exception 'Não há mais estoque dedicado de % em %', fn_nome_unidade(v_un), (select nome from local where id = s.origem_id);
        end if;
        v_itens := v_itens || v_ded;
      end loop;
      if nullif(p->>'modo_envio','') is null then raise exception 'Informe o meio de envio'; end if;
      v_mov := criar_transferencia(jsonb_build_object(
        'origem_id', s.origem_id, 'destino_id', s.destino_id, 'data', p->>'data', 'modo_envio', p->>'modo_envio',
        'codigo_rastreio', p->>'codigo_rastreio', 'prazo_chegada', p->>'prazo_chegada',
        'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));
      update movimentacao set chamado_url = s.chamado_url where id = v_mov;

    elsif s.tipo in ('enviar_cliente','enviar_dedicado') then
      if s.tipo = 'enviar_dedicado' then
        v_itens := fn_itens_dedicado(s.origem_id, s.unidade_id);
        if v_itens = '[]'::jsonb then
          raise exception 'Não há mais estoque dedicado de % em %', fn_nome_unidade(s.unidade_id), (select nome from local where id = s.origem_id);
        end if;
      end if;
      v_mov := registrar_movimentacao(jsonb_build_object(
        'tipo', 'SAIDA_CLIENTE', 'local_id', s.origem_id, 'unidade_id', s.unidade_id, 'data', p->>'data',
        'modo_envio', p->>'modo_envio', 'tecnico_id', p->>'tecnico_id', 'codigo_rastreio', p->>'codigo_rastreio',
        'chamado_url', s.chamado_url, 'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));

    else  -- retirar_dedicado: o material chegou ao destino; entra como devolução já dedicada à unidade
      v_mov := registrar_movimentacao(jsonb_build_object(
        'tipo', 'DEVOLUCAO_CLIENTE', 'local_id', s.destino_id, 'unidade_id', s.unidade_id, 'data', p->>'data',
        'chamado_url', s.chamado_url, 'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));
    end if;
  end if;

  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- ---------------------------------------------------------------- 6b. Cancelar
-- Aberta ou em produção: o administrador ou o operador do local responsável (a origem; no retirar_dedicado,
-- o destino), a mesma regra de aceitar e atender. O agendamento cancela a própria solicitação enquanto aberta.
-- Depois de enviado/atendido não cancela (a transferência em trânsito usa cancelar_transferencia).
create or replace function public.fn_pode_cancelar(s solicitacao) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(s.status::text in ('aberta','em_producao')
    and ((fn_perfil()::text in ('admin','operador') and fn_pode_operar_local(fn_local_responsavel(s)))
         or (s.status::text = 'aberta' and fn_perfil()::text = 'agendamento' and s.tecnico_id = auth.uid())), false)
$$;

create or replace function public.cancelar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_resp integer;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found or s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação não está em andamento'; end if;
  if not fn_pode_cancelar(s) then
    if s.status::text = 'em_producao' and fn_perfil()::text not in ('admin','operador') then
      raise exception 'Depois de aceita, só administrador e operador cancelam' using errcode = '42501';
    end if;
    v_resp := fn_local_responsavel(s);
    raise exception 'Só o administrador ou quem opera o estoque de % (%) cancela esta solicitação',
      case when s.tipo = 'retirar_dedicado' then 'destino' else 'origem' end,
      coalesce((select nome from local where id = v_resp), '?') using errcode = '42501';
  end if;
  update solicitacao set status = 'cancelada' where id = p_id;
end $$;

-- ---------------------------------------------------------------- 7. View para a tela: situação e o que o usuário pode fazer
create or replace view solicitacao_acoes with (security_invoker = true) as
select s.id, s.tipo, s.status::text as status,
       case
         when s.status::text in ('aberta','em_producao','cancelada') then s.status::text
         when s.tipo in ('transferencia','legado') then
           coalesce((select case m.status::text when 'em_transito' then 'em_transito' when 'recebido' then 'recebido'
                                                when 'cancelado' then 'cancelada' else 'atendida' end
                       from movimentacao m where m.id = s.movimentacao_id), 'atendida')
         else 'atendida'
       end as situacao,
       (s.status::text = 'aberta' and fn_perfil()::text in ('admin','operador')
          and fn_pode_operar_local(fn_local_responsavel(s))) as pode_aceitar,
       ((s.status::text = 'em_producao' or (s.tipo = 'legado' and s.status::text = 'aberta'))
          and fn_perfil()::text in ('admin','operador') and fn_pode_operar_local(fn_local_responsavel(s))) as pode_atender,
       fn_pode_cancelar(s) as pode_cancelar
  from solicitacao s;
revoke all on solicitacao_acoes from public, anon, authenticated;
grant select on solicitacao_acoes to authenticated;

-- ---------------------------------------------------------------- 8. Permissões
-- Não existe mais envio direto: criar_transferencia só roda por dentro de atender_solicitacao.
revoke execute on function public.criar_transferencia(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_itens_dedicado(integer, integer), public.fn_nome_unidade(integer),
  public.fn_gravar_itens_pedido(bigint, jsonb, boolean)
  from public, anon, authenticated;
revoke execute on function public.fn_local_responsavel(solicitacao) from public, anon;
grant execute on function public.fn_local_responsavel(solicitacao) to authenticated;   -- usada pela view
revoke execute on function public.fn_pode_cancelar(solicitacao), public.cancelar_solicitacao(bigint) from public, anon;
grant execute on function public.fn_pode_cancelar(solicitacao), public.cancelar_solicitacao(bigint) to authenticated;
revoke execute on function public.criar_pedido_transferencia(jsonb), public.criar_solicitacao(jsonb),
  public.aceitar_solicitacao(bigint), public.atender_solicitacao(bigint, jsonb) from public, anon;
grant execute on function public.criar_pedido_transferencia(jsonb), public.criar_solicitacao(jsonb),
  public.aceitar_solicitacao(bigint), public.atender_solicitacao(bigint, jsonb) to authenticated;


-- ================================================================ 0017_ver_como
-- "Ver como" do administrador: perfil e local simulados valem de verdade (mesmo conteúdo de atualizar_ver_como.sql).

-- ---------------------------------------------------------------- 1. Onde fica a simulação
create table if not exists visualizacao (
  usuario_id    uuid primary key references usuario(id),
  perfil        perfil_acesso not null check (perfil::text <> 'admin'),
  local_id      integer references local(id),
  tecnico_id    integer references tecnico(id),
  atualizado_em timestamptz not null default now()
);
alter table visualizacao enable row level security;
drop policy if exists visualizacao_ler on visualizacao;
create policy visualizacao_ler on visualizacao for select using (usuario_id = auth.uid());
revoke all on visualizacao from public, anon, authenticated;
grant select on visualizacao to authenticated;

-- ---------------------------------------------------------------- 2. Perfil real e perfil efetivo
-- Perfil gravado na tabela usuario (sem simulação).
create or replace function public.fn_perfil_real() returns perfil_acesso
language sql stable security definer set search_path = public as $$
  select perfil from usuario where id = auth.uid() and ativo
$$;

-- Perfil efetivo: o simulado, se o usuário for administrador de verdade e estiver simulando; senão, o real.
create or replace function public.fn_perfil() returns perfil_acesso
language sql stable security definer set search_path = public as $$
  select case when r.perfil = 'admin'
              then coalesce((select v.perfil from visualizacao v where v.usuario_id = auth.uid()), r.perfil)
              else r.perfil end
    from (select fn_perfil_real() as perfil) r
$$;

-- A simulação vale (administrador real com uma linha em visualizacao)?
create or replace function public.fn_simulacao() returns visualizacao
language sql stable security definer set search_path = public as $$
  select v.* from visualizacao v where v.usuario_id = auth.uid() and fn_perfil_real() = 'admin'
$$;

-- Técnico do login (tecnico.usuario_id) ou o técnico simulado.
create or replace function public.fn_tecnico_atual() returns integer
language sql stable security definer set search_path = public as $$
  select case when (fn_simulacao()).usuario_id is not null then (fn_simulacao()).tecnico_id
              else (select t.id from tecnico t where t.usuario_id = auth.uid() order by t.id limit 1) end
$$;

-- O local está entre os estoques do usuário (usuario_local) ou é o estoque simulado?
create or replace function public.fn_local_do_usuario(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select case when (fn_simulacao()).usuario_id is not null then (fn_simulacao()).local_id is not distinct from p_local
              else exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local) end
$$;

-- ---------------------------------------------------------------- 3. Regras de local com o perfil efetivo
create or replace function public.fn_pode_ver_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()::text
      when 'admin'       then true
      when 'consulta'    then true
      when 'agendamento' then true
      when 'operador'    then fn_local_do_usuario(p_local)
      when 'tecnico'     then exists (select 1 from local l where l.id = p_local and l.tecnico_id = fn_tecnico_atual())
    end, false)
$$;

create or replace function public.fn_pode_operar_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()::text
      when 'admin'    then true
      when 'operador' then fn_local_do_usuario(p_local)
      when 'tecnico'  then exists (select 1 from local l where l.id = p_local and l.tecnico_id = fn_tecnico_atual())
    end, false)
$$;

-- ---------------------------------------------------------------- 4. registrar_movimentacao: técnico do login ou o simulado
create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
  v_data date;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      v_tec := fn_tecnico_atual();   -- o técnico do login (ou o simulado pelo administrador)
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', v_data,
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Dedicado nasce por devolução de cliente, ajuste ou recebimento de transferência ("Dedicado para").
  if v_tipo not in ('DEVOLUCAO_CLIENTE','AJUSTE')
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;
  -- Na compra, item que já sai de um dedicado também não faz sentido (criaria dedicado na entrada).
  if v_tipo = 'ENTRADA_COMPRA'
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservado_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. Ativar e voltar
-- p: {perfil: null|'admin'|'operador'|'tecnico'|'consulta'|'agendamento', local_id, tecnico_id}
--   operador e agendamento: local_id (estoque fixo) obrigatório; consulta: local_id opcional (só informativo);
--   tecnico: tecnico_id (tecnico.id) obrigatório e com estoque (carro); o local passa a ser a base dele.
--   perfil nulo ou 'admin': volta a administrador.
create or replace function public.definir_visualizacao(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_perfil text := nullif(btrim(coalesce(p->>'perfil','')), '');
  v_local integer := nullif(p->>'local_id','')::int;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
begin
  if fn_perfil_real() is distinct from 'admin' then
    raise exception 'Só o administrador pode ver como outro perfil' using errcode = '42501';
  end if;

  if v_perfil is null or v_perfil = 'admin' then
    delete from visualizacao where usuario_id = auth.uid();
    insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
    values (auth.uid(), 'visualizacao', auth.uid()::text, 'VER_COMO', jsonb_build_object('perfil', 'admin'));
    return;
  end if;

  if v_perfil not in ('operador','tecnico','consulta','agendamento') then
    raise exception 'Perfil inválido: use operador, tecnico, consulta ou agendamento';
  end if;
  if v_perfil in ('operador','agendamento') then
    if v_local is null or not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'Escolha o estoque fixo (por exemplo, Nova Lima ou SBC)';
    end if;
    v_tec := null;
  elsif v_perfil = 'tecnico' then
    if v_tec is null or not exists (select 1 from tecnico where id = v_tec) then raise exception 'Escolha o técnico'; end if;
    if not exists (select 1 from local where tecnico_id = v_tec) then
      raise exception 'Este técnico não tem estoque (carro) cadastrado';
    end if;
    select l.base_id into v_local from local l where l.tecnico_id = v_tec order by l.id limit 1;
  else  -- consulta
    if v_local is not null and not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'Escolha um estoque fixo';
    end if;
    v_tec := null;
  end if;

  insert into visualizacao (usuario_id, perfil, local_id, tecnico_id, atualizado_em)
  values (auth.uid(), v_perfil::perfil_acesso, v_local, v_tec, now())
  on conflict (usuario_id) do update
    set perfil = excluded.perfil, local_id = excluded.local_id, tecnico_id = excluded.tecnico_id, atualizado_em = now();
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'visualizacao', auth.uid()::text, 'VER_COMO',
          jsonb_build_object('perfil', v_perfil, 'local_id', v_local, 'tecnico_id', v_tec));
end $$;

-- ---------------------------------------------------------------- 6. Para a tela: quem sou e como estou vendo
create or replace view minha_visualizacao with (security_invoker = true) as
select u.id as usuario_id,
       u.perfil::text as perfil_real,
       fn_perfil()::text as perfil,
       (u.perfil = 'admin' and u.ativo and v.usuario_id is not null) as simulando,
       case when u.perfil = 'admin' and u.ativo then v.local_id end as local_id,
       case when u.perfil = 'admin' and u.ativo then l.nome end as local_nome,
       case when u.perfil = 'admin' and u.ativo then v.tecnico_id end as tecnico_id,
       case when u.perfil = 'admin' and u.ativo then t.nome end as tecnico_nome,
       array(select x.id from local x where fn_pode_operar_local(x.id) order by x.id) as locais_operaveis
  from usuario u
  left join visualizacao v on v.usuario_id = u.id
  left join local l on l.id = v.local_id
  left join tecnico t on t.id = v.tecnico_id
 where u.id = auth.uid();
revoke all on minha_visualizacao from public, anon, authenticated;
grant select on minha_visualizacao to authenticated;

-- ---------------------------------------------------------------- 7. Permissões
revoke execute on function public.fn_perfil_real(), public.fn_simulacao(), public.fn_tecnico_atual(),
  public.fn_local_do_usuario(integer) from public, anon, authenticated;
revoke execute on function public.definir_visualizacao(jsonb), public.fn_perfil(), public.fn_pode_ver_local(integer),
  public.fn_pode_operar_local(integer), public.registrar_movimentacao(jsonb) from public, anon;
grant execute on function public.definir_visualizacao(jsonb), public.fn_perfil(), public.fn_pode_ver_local(integer),
  public.fn_pode_operar_local(integer), public.registrar_movimentacao(jsonb) to authenticated;


-- ================================================================ 0018_finalidade
-- Finalidade da solicitação (mesmo conteúdo de atualizar_finalidade.sql).

alter table solicitacao add column if not exists finalidade text;
alter table solicitacao drop constraint if exists solicitacao_finalidade_valida;
alter table solicitacao add constraint solicitacao_finalidade_valida
  check (finalidade is null or finalidade in ('mobilizacao', 'manutencao'));

-- criar_solicitacao: igual à de atualizar_fluxo_pedidos.sql, mais a finalidade obrigatória.
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo text := nullif(p->>'tipo',''); v_un integer := nullif(p->>'unidade_id','')::int;
  v_orig integer; v_dest integer; v_id bigint;
  v_n integer := coalesce(jsonb_array_length(nullif(p->'itens','null'::jsonb)), 0);
  v_chamado text := nullif(btrim(p->>'chamado_url'), '');
  v_fin text := lower(nullif(btrim(p->>'finalidade'), ''));
begin
  if fn_perfil() is null or fn_perfil()::text <> 'agendamento' then
    raise exception 'Só o agendamento cria solicitação (transferência entre estoques é pedido de transferência)' using errcode = '42501';
  end if;
  if v_tipo is null or v_tipo not in ('enviar_cliente','enviar_dedicado','retirar_dedicado') then
    raise exception 'Tipo de solicitação inválido: use enviar_cliente, enviar_dedicado ou retirar_dedicado';
  end if;
  if v_un is null or not exists (select 1 from unidade_cliente where id = v_un) then raise exception 'Informe o cliente'; end if;

  if v_tipo in ('enviar_cliente','enviar_dedicado') then
    v_orig := nullif(p->>'origem_id','')::int;
    if v_orig is null or not exists (select 1 from local where id = v_orig and tipo = 'estoque') then
      raise exception 'Informe o estoque de onde sai';
    end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    if v_dest is null or not exists (select 1 from local where id = v_dest and tipo = 'estoque') then
      raise exception 'Informe o estoque para onde vai';
    end if;
  end if;
  if v_tipo = 'enviar_dedicado' then
    if v_n > 0 then raise exception 'Enviar dedicado leva o dedicado inteiro: não informe itens'; end if;
    if fn_itens_dedicado(v_orig, v_un) = '[]'::jsonb then
      raise exception 'Não há estoque dedicado de % em %', fn_nome_unidade(v_un), (select nome from local where id = v_orig);
    end if;
  elsif v_n = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  -- Enviar e retirar dedicado exigem o link do chamado (Jira); nos outros tipos ele é opcional.
  if v_tipo in ('enviar_dedicado','retirar_dedicado') then
    if v_chamado is null then
      raise exception 'Informe o link do chamado: é obrigatório para enviar e retirar dedicado';
    end if;
    if v_chamado !~* '^https?://' then
      raise exception 'O link do chamado deve começar com http:// ou https://';
    end if;
  end if;

  if v_fin is null or v_fin not in ('mobilizacao','manutencao') then
    raise exception 'Informe a finalidade: mobilizacao ou manutencao';
  end if;

  insert into solicitacao (tipo, tecnico_id, origem_id, destino_id, unidade_id, chamado_url, observacao, finalidade)
  values (v_tipo, auth.uid(), v_orig, v_dest, v_un, v_chamado, nullif(p->>'observacao',''), v_fin)
  returning id into v_id;
  perform fn_gravar_itens_pedido(v_id, p->'itens', false);
  return v_id;
end $$;

revoke execute on function public.criar_solicitacao(jsonb) from public, anon;
grant execute on function public.criar_solicitacao(jsonb) to authenticated;


-- ============================================================ Envio para estoque técnico (atualizar_envio_tecnico.sql)
-- Envio para estoque técnico (tela Registrar): registrar_movimentacao aceita tipo 'ENVIO_TECNICO'.
-- Sai do estoque escolhido e entra NA HORA no carro do técnico: grava uma TRANSFERENCIA já
-- 'recebido' (sem trânsito, sem confirmação), então efeito_estoque e o Histórico já a tratam.
-- p: {tipo:'ENVIO_TECNICO', local_id (estoque de origem), tecnico_id (tecnico.id, obrigatório),
--     modo_envio (correios|retirada|transportadora|tecnico, obrigatório), chamado_url (opcional),
--     data, observacao, itens}
-- Idempotente (create or replace). Rode uma vez depois de atualizar_finalidade.sql.

create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_envio boolean := (p->>'tipo') = 'ENVIO_TECNICO';
  v_tipo tipo_movimento := case when (p->>'tipo') = 'ENVIO_TECNICO' then 'TRANSFERENCIA' else (p->>'tipo') end::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
  v_dest integer;
  v_data date;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' and not v_envio then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;

  -- ------------------------------------------------ Envio para estoque técnico
  if v_envio then
    if not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'O envio para estoque técnico sai de um estoque fixo';
    end if;
    if v_tec is null then raise exception 'Informe o técnico que recebe'; end if;
    select l.id into v_dest from local l where l.tecnico_id = v_tec and l.tipo = 'tecnico' order by l.id limit 1;
    if v_dest is null then raise exception 'Este técnico não tem estoque (carro) cadastrado'; end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    v_data := fn_data_movimento(p->>'data');

    perform fn_travar_locais(array[v_local, v_dest]);

    insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, chamado_url, observacao,
                              modo_envio, tecnico_id, recebido_em, recebido_por, criado_por)
    values ('TRANSFERENCIA', 'recebido', v_data, v_local, v_dest, nullif(p->>'chamado_url',''),
            nullif(p->>'observacao',''), v_modo, v_tec, now(), auth.uid(), auth.uid())
    returning id into v_id;

    perform fn_gravar_itens(v_id, p->'itens');

    if exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
      raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
    end if;
    if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
      raise exception 'Quantidade deve ser maior que zero';
    end if;

    perform fn_verificar_saldo(array[v_local]);
    perform fn_verificar_dedicado_inteiro(v_id);
    return v_id;
  end if;

  -- ------------------------------------------------ Demais tipos (sem mudança)
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      v_tec := fn_tecnico_atual();   -- o técnico do login (ou o simulado pelo administrador)
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', v_data,
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Dedicado nasce por devolução de cliente, ajuste ou recebimento de transferência ("Dedicado para").
  if v_tipo not in ('DEVOLUCAO_CLIENTE','AJUSTE')
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;
  -- Na compra, item que já sai de um dedicado também não faz sentido (criaria dedicado na entrada).
  if v_tipo = 'ENTRADA_COMPRA'
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservado_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;


-- ============================================================ Atualização 2026-11-25 (atualizar_2026_11_25.sql)
-- Atualização 2026-11-25 (spec2). Rode uma vez depois de atualizar_envio_tecnico.sql. Idempotente.
--  1. Fornecedor sai do sistema (tabela e colunas).
--  2. registrar_transferencia: envio direto (sem pedido), fica em trânsito e o destino confirma.
--  3. Devolução de cliente: modo de envio obrigatório (técnico que entregou, se for técnico), sem dedicado;
--     (kits ficam em item_associado: atualizar_kits.sql).
--  4. Descarte exige justificativa.
--  5. Chip M2M x Voz e Dados (produto.chip_rede); MDVR e DashCAM passam a usar chip;
--     trocar_chip usa o avulso do tipo certo; trocar_chips_entre troca chips entre dois equipamentos.
--  6. O administrador também cria solicitações.

-- ---------------------------------------------------------------- 1. Fornecedor
alter table movimentacao  drop column if exists fornecedor_id;
alter table produto       drop column if exists fornecedor_id;
alter table pedido_compra drop column if exists fornecedor_id;
drop table if exists fornecedor cascade;

-- ---------------------------------------------------------------- 5. Chip M2M x Voz e Dados
alter table produto add column if not exists chip_rede text;
alter table produto drop constraint if exists produto_chip_rede_valida;
alter table produto add constraint produto_chip_rede_valida check (chip_rede is null or chip_rede in ('m2m', 'voz_dados'));

update produto set usa_chip = true where nome in ('MDVR Intelbras 3404', 'MDVR Intelbras 5404', 'DashCAM');
update produto set chip_rede = 'voz_dados'
 where chip_rede is null and nome in ('MDVR Intelbras 3404', 'MDVR Intelbras 5404', 'DashCAM');
update produto set chip_rede = 'm2m'
 where chip_rede is null and usa_chip and fabricante in ('Ruptela', 'Teltonika', 'GalileoSky');
-- chips avulsos
update produto set chip_tipo = 'claro' where chip_tipo is null and nome = 'Chip Claro Voz e Dados';
update produto set chip_tipo = 'vivo'  where chip_tipo is null and nome = 'Chip Vivo Voz e Dados';
update produto set chip_tipo = 'arqia' where chip_tipo is null and nome = 'Chip Arqia Voz e Dados';
update produto set chip_rede = 'voz_dados' where chip_rede is null and chip_tipo is not null and nome ilike '%voz e dados%';
update produto set chip_rede = 'm2m'       where chip_rede is null and chip_tipo is not null and nome ilike '%m2m%';

-- ---------------------------------------------------------------- 3/4. registrar_movimentacao
-- Igual à de atualizar_envio_tecnico.sql, mais:
--  - sem fornecedor_id;
--  - DESCARTE exige justificativa (observacao);
--  - DEVOLUCAO_CLIENTE exige modo_envio (correios|retirada|transportadora|tecnico) e, se for técnico, tecnico_id;
--    não aceita "Dedicado para". A exceção é o atendimento de Retirar dedicado (atender_solicitacao), que marca
--    a transação com estoque.retirar_dedicado = 'on'.
create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_envio boolean := (p->>'tipo') = 'ENVIO_TECNICO';
  v_tipo tipo_movimento := case when (p->>'tipo') = 'ENVIO_TECNICO' then 'TRANSFERENCIA' else (p->>'tipo') end::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
  v_interno boolean := coalesce(current_setting('estoque.retirar_dedicado', true), '') = 'on';
  v_dest integer;
  v_data date;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' and not v_envio then raise exception 'Use registrar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;

  -- ------------------------------------------------ Envio para estoque técnico
  if v_envio then
    if not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'O envio para estoque técnico sai de um estoque fixo';
    end if;
    if v_tec is null then raise exception 'Informe o técnico que recebe'; end if;
    select l.id into v_dest from local l where l.tecnico_id = v_tec and l.tipo = 'tecnico' order by l.id limit 1;
    if v_dest is null then raise exception 'Este técnico não tem estoque (carro) cadastrado'; end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    v_data := fn_data_movimento(p->>'data');

    perform fn_travar_locais(array[v_local, v_dest]);

    insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, chamado_url, observacao,
                              modo_envio, tecnico_id, recebido_em, recebido_por, criado_por)
    values ('TRANSFERENCIA', 'recebido', v_data, v_local, v_dest, nullif(p->>'chamado_url',''),
            nullif(p->>'observacao',''), v_modo, v_tec, now(), auth.uid(), auth.uid())
    returning id into v_id;

    perform fn_gravar_itens(v_id, p->'itens');

    if exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
      raise exception 'Item dedicado só nasce por transferência recebida (Dedicado para), ajuste de inventário ou atendimento de Retirar dedicado';
    end if;
    if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
      raise exception 'Quantidade deve ser maior que zero';
    end if;

    perform fn_verificar_saldo(array[v_local]);
    perform fn_verificar_dedicado_inteiro(v_id);
    return v_id;
  end if;

  -- ------------------------------------------------ Demais tipos
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;
  if v_tipo = 'DESCARTE' and nullif(btrim(p->>'observacao'),'') is null then
    raise exception 'Descarte exige justificativa';
  end if;
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      v_tec := fn_tecnico_atual();   -- o técnico do login (ou o simulado pelo administrador)
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  elsif v_tipo = 'DEVOLUCAO_CLIENTE' and not v_interno then
    if v_modo is null then raise exception 'Informe o modo de envio do recebimento'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que entregou o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', v_data,
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Dedicado nasce por ajuste, transferência recebida ("Dedicado para") ou atendimento de Retirar dedicado.
  if v_tipo <> 'AJUSTE' and not (v_tipo = 'DEVOLUCAO_CLIENTE' and v_interno)
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por transferência recebida (Dedicado para), ajuste de inventário ou atendimento de Retirar dedicado';
  end if;
  -- Na compra, item que já sai de um dedicado também não faz sentido (criaria dedicado na entrada).
  if v_tipo = 'ENTRADA_COMPRA'
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservado_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por transferência recebida (Dedicado para), ajuste de inventário ou atendimento de Retirar dedicado';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 2. registrar_transferencia (envio direto)
-- p: {origem_id, destino_id, data, modo_envio, codigo_rastreio, prazo_chegada, chamado_url, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
-- Admin ou operador da origem. Fica em trânsito; o destino confirma com confirmar_recebimento.
create or replace function public.registrar_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if fn_perfil()::text is distinct from 'admin' and fn_perfil()::text is distinct from 'operador' then
    raise exception 'Só administrador e operador registram transferência' using errcode = '42501';
  end if;
  if nullif(p->>'origem_id','') is null or not fn_pode_operar_local((p->>'origem_id')::int) then
    raise exception 'Sem permissão para enviar deste local' using errcode = '42501';
  end if;
  if nullif(p->>'modo_envio','') is null then raise exception 'Informe o modo de envio'; end if;
  v_id := criar_transferencia(p);
  update movimentacao set chamado_url = nullif(btrim(p->>'chamado_url'),'') where id = v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. trocar_chip: avulso do tipo certo (M2M ou Voz e Dados)
-- p: {local_id, produto_id, quantidade, de, para, chip_retirado ('estoque'|'descartar'), observacao, data}
create or replace function public.trocar_chip(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := (p->>'local_id')::int; v_prod integer := (p->>'produto_id')::int;
  v_qtd integer := (p->>'quantidade')::int;
  v_de text := coalesce(nullif(p->>'de',''), 'novo'); v_para text := coalesce(nullif(p->>'para',''), 'novo');
  v_dest text := coalesce(nullif(p->>'chip_retirado',''), 'estoque');
  v_id bigint; v_chip_de integer; v_chip_para integer; v_obs text := nullif(p->>'observacao','');
  v_data date; v_rede text;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  select coalesce(chip_rede, 'm2m') into v_rede from produto where id = v_prod;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arqia') or v_para not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  if v_de = v_para and (v_de = 'novo' or v_dest <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  v_data := fn_data_movimento(p->>'data');
  if v_de <> 'novo' then
    select id into v_chip_de from produto where chip_tipo = v_de and coalesce(chip_rede,'m2m') = v_rede and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há chip avulso % % cadastrado', fn_rotulo_chip(v_de),
      case v_rede when 'voz_dados' then 'Voz e Dados' else 'M2M' end; end if;
  end if;
  if v_para <> 'novo' then
    select id into v_chip_para from produto where chip_tipo = v_para and coalesce(chip_rede,'m2m') = v_rede and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há chip avulso % % cadastrado', fn_rotulo_chip(v_para),
      case v_rede when 'voz_dados' then 'Voz e Dados' else 'M2M' end; end if;
  end if;

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', v_data, v_local,
          concat_ws(E'\n', case when v_de = v_para then 'Chip ' || fn_rotulo_chip(v_de) || ' substituído por outro' else fn_rotulo_chip(v_de) || ' → ' || fn_rotulo_chip(v_para) end ||
                    case when v_de <> 'novo' and v_dest = 'descartar' then ' (chip retirado descartado)' else '' end, v_obs), auth.uid())
  returning id into v_id;
  if v_de <> v_para then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values
      (v_id, v_prod, v_de::condicao_item, -v_qtd), (v_id, v_prod, v_para::condicao_item, v_qtd);
  end if;
  if v_chip_de is not null and v_dest = 'estoque' then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_de, 'novo', v_qtd);
  end if;
  if v_chip_para is not null then
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values (v_id, v_chip_para, 'novo', -v_qtd);
  end if;
  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. trocar_chips_entre (entre dois equipamentos)
-- p: {local_id, produto_a_id, chip_a, produto_b_id, chip_b, quantidade, data, observacao}
-- N de A (chip_a) e N de B (chip_b) trocam os chips: A fica chip_b e B fica chip_a. Um dos dois pode ser
-- 'novo' (sem chip): o chip só muda de equipamento. Mesmo tipo de chip (M2M ou Voz e Dados), só estoque livre.
create or replace function public.trocar_chips_entre(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := nullif(p->>'local_id','')::int;
  v_a integer := nullif(p->>'produto_a_id','')::int; v_b integer := nullif(p->>'produto_b_id','')::int;
  v_ca text := coalesce(nullif(p->>'chip_a',''), 'novo'); v_cb text := coalesce(nullif(p->>'chip_b',''), 'novo');
  v_qtd integer := nullif(p->>'quantidade','')::int;
  v_ra text; v_rb text; v_id bigint; v_data date;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_a is null or v_b is null or v_a = v_b then raise exception 'Escolha dois equipamentos diferentes'; end if;
  select case when usa_chip then coalesce(chip_rede,'m2m') end into v_ra from produto where id = v_a;
  select case when usa_chip then coalesce(chip_rede,'m2m') end into v_rb from produto where id = v_b;
  if v_ra is null or v_rb is null then raise exception 'Os dois equipamentos precisam usar chip'; end if;
  if v_ra <> v_rb then raise exception 'Só dá para trocar chips entre equipamentos do mesmo tipo de chip (M2M com M2M, Voz e Dados com Voz e Dados)'; end if;
  if v_ca not in ('novo','claro','vivo','arqia') or v_cb not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  if v_ca = v_cb then raise exception 'Os dois equipamentos estão com o mesmo chip: não há o que trocar'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  v_data := fn_data_movimento(p->>'data');

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', v_data, v_local,
          concat_ws(E'\n', 'Troca entre equipamentos: ' || v_qtd || ' ' || (select nome from produto where id = v_a) ||
                    ' (' || fn_rotulo_chip(v_ca) || ' → ' || fn_rotulo_chip(v_cb) || ') e ' ||
                    (select nome from produto where id = v_b) || ' (' || fn_rotulo_chip(v_cb) || ' → ' || fn_rotulo_chip(v_ca) || ')',
                    nullif(p->>'observacao','')), auth.uid())
  returning id into v_id;
  insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade) values
    (v_id, v_a, v_ca::condicao_item, -v_qtd), (v_id, v_a, v_cb::condicao_item, v_qtd),
    (v_id, v_b, v_cb::condicao_item, -v_qtd), (v_id, v_b, v_ca::condicao_item, v_qtd);
  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 6. criar_solicitacao: o administrador também cria
create or replace function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo text := nullif(p->>'tipo',''); v_un integer := nullif(p->>'unidade_id','')::int;
  v_orig integer; v_dest integer; v_id bigint;
  v_n integer := coalesce(jsonb_array_length(nullif(p->'itens','null'::jsonb)), 0);
  v_chamado text := nullif(btrim(p->>'chamado_url'), '');
  v_fin text := lower(nullif(btrim(p->>'finalidade'), ''));
begin
  if fn_perfil() is null or fn_perfil()::text not in ('agendamento','admin') then
    raise exception 'Só o agendamento e o administrador criam solicitação (transferência entre estoques é pedido de transferência)' using errcode = '42501';
  end if;
  if v_tipo is null or v_tipo not in ('enviar_cliente','enviar_dedicado','retirar_dedicado') then
    raise exception 'Tipo de solicitação inválido: use enviar_cliente, enviar_dedicado ou retirar_dedicado';
  end if;
  if v_un is null or not exists (select 1 from unidade_cliente where id = v_un) then raise exception 'Informe o cliente'; end if;

  if v_tipo in ('enviar_cliente','enviar_dedicado') then
    v_orig := nullif(p->>'origem_id','')::int;
    if v_orig is null or not exists (select 1 from local where id = v_orig and tipo = 'estoque') then
      raise exception 'Informe o estoque de onde sai';
    end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    if v_dest is null or not exists (select 1 from local where id = v_dest and tipo = 'estoque') then
      raise exception 'Informe o estoque para onde vai';
    end if;
  end if;
  if v_tipo = 'enviar_dedicado' then
    if v_n > 0 then raise exception 'Enviar dedicado leva o dedicado inteiro: não informe itens'; end if;
    if fn_itens_dedicado(v_orig, v_un) = '[]'::jsonb then
      raise exception 'Não há estoque dedicado de % em %', fn_nome_unidade(v_un), (select nome from local where id = v_orig);
    end if;
  elsif v_n = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  -- Enviar e retirar dedicado exigem o link do chamado (Jira); nos outros tipos ele é opcional.
  if v_tipo in ('enviar_dedicado','retirar_dedicado') then
    if v_chamado is null then
      raise exception 'Informe o link do chamado: é obrigatório para enviar e retirar dedicado';
    end if;
    if v_chamado !~* '^https?://' then
      raise exception 'O link do chamado deve começar com http:// ou https://';
    end if;
  end if;

  if v_fin is null or v_fin not in ('mobilizacao','manutencao') then
    raise exception 'Informe a finalidade: mobilizacao ou manutencao';
  end if;

  insert into solicitacao (tipo, tecnico_id, origem_id, destino_id, unidade_id, chamado_url, observacao, finalidade)
  values (v_tipo, auth.uid(), v_orig, v_dest, v_un, v_chamado, nullif(p->>'observacao',''), v_fin)
  returning id into v_id;
  perform fn_gravar_itens_pedido(v_id, p->'itens', false);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 3. atender_solicitacao: Retirar dedicado libera o "Dedicado para"
create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  s solicitacao; v_mov bigint; v_itens jsonb; v_resp integer; v_un integer; v_ded jsonb;
  v_obs text := coalesce(nullif(p->>'observacao',''), null);
begin
  if fn_perfil()::text not in ('admin','operador') or fn_perfil() is null then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação já encerrada'; end if;
  if s.tipo <> 'legado' and s.status::text <> 'em_producao' then
    raise exception 'Aceite a solicitação antes de atender';
  end if;
  v_resp := fn_local_responsavel(s);
  if not fn_pode_operar_local(v_resp) then
    raise exception 'Só quem opera o estoque de % (%) dá andamento a esta solicitação',
      case when s.tipo = 'retirar_dedicado' then 'destino' else 'origem' end,
      coalesce((select nome from local where id = v_resp), '?') using errcode = '42501';
  end if;

  if s.tipo = 'legado' then
    -- Pedido antigo: transferência com os itens do pedido. Chip: pelo id da linha ou pela chave antiga
    -- "<produto_id>|<unidade dedicada ou vazio>".
    if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
    select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                        'reservar_para_unidade_id', reservar_para_unidade_id,
                                        'reservado_unidade_id', reservado_unidade_id,
                                        'condicao', coalesce(p->'chips'->>(id::text),
                                                             p->'chips'->>(produto_id::text || '|' || coalesce(reservar_para_unidade_id::text, '')),
                                                             condicao::text, 'novo')))
      into v_itens from solicitacao_item where solicitacao_id = p_id;
    v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));

  else
    select coalesce(jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                        'reservar_para_unidade_id', case when s.tipo = 'retirar_dedicado' then s.unidade_id
                                                                         else reservar_para_unidade_id end,
                                        'condicao', coalesce(p->'chips'->>(id::text), condicao::text, 'novo'))), '[]'::jsonb)
      into v_itens from solicitacao_item where solicitacao_id = p_id;

    if s.tipo = 'transferencia' then
      for v_un in select unidade_id from solicitacao_dedicado where solicitacao_id = p_id order by unidade_id loop
        v_ded := fn_itens_dedicado(s.origem_id, v_un);
        if v_ded = '[]'::jsonb then
          raise exception 'Não há mais estoque dedicado de % em %', fn_nome_unidade(v_un), (select nome from local where id = s.origem_id);
        end if;
        v_itens := v_itens || v_ded;
      end loop;
      if nullif(p->>'modo_envio','') is null then raise exception 'Informe o meio de envio'; end if;
      v_mov := criar_transferencia(jsonb_build_object(
        'origem_id', s.origem_id, 'destino_id', s.destino_id, 'data', p->>'data', 'modo_envio', p->>'modo_envio',
        'codigo_rastreio', p->>'codigo_rastreio', 'prazo_chegada', p->>'prazo_chegada',
        'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));
      update movimentacao set chamado_url = s.chamado_url where id = v_mov;

    elsif s.tipo in ('enviar_cliente','enviar_dedicado') then
      if s.tipo = 'enviar_dedicado' then
        v_itens := fn_itens_dedicado(s.origem_id, s.unidade_id);
        if v_itens = '[]'::jsonb then
          raise exception 'Não há mais estoque dedicado de % em %', fn_nome_unidade(s.unidade_id), (select nome from local where id = s.origem_id);
        end if;
      end if;
      v_mov := registrar_movimentacao(jsonb_build_object(
        'tipo', 'SAIDA_CLIENTE', 'local_id', s.origem_id, 'unidade_id', s.unidade_id, 'data', p->>'data',
        'modo_envio', p->>'modo_envio', 'tecnico_id', p->>'tecnico_id', 'codigo_rastreio', p->>'codigo_rastreio',
        'chamado_url', s.chamado_url, 'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));

    else  -- retirar_dedicado: o material chegou ao destino; entra como devolução já dedicada à unidade
      perform set_config('estoque.retirar_dedicado', 'on', true);   -- libera o "Dedicado para" na devolução
      v_mov := registrar_movimentacao(jsonb_build_object(
        'tipo', 'DEVOLUCAO_CLIENTE', 'local_id', s.destino_id, 'unidade_id', s.unidade_id, 'data', p->>'data',
        'chamado_url', s.chamado_url, 'observacao', concat_ws(E'\n', s.observacao, v_obs), 'itens', v_itens));
      perform set_config('estoque.retirar_dedicado', '', true);
    end if;
  end if;

  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- ---------------------------------------------------------------- Permissões
revoke execute on function public.registrar_transferencia(jsonb), public.trocar_chips_entre(jsonb) from public, anon;
grant execute on function public.registrar_transferencia(jsonb), public.trocar_chips_entre(jsonb),
  public.registrar_movimentacao(jsonb), public.trocar_chip(jsonb), public.criar_solicitacao(jsonb),
  public.atender_solicitacao(bigint, jsonb) to authenticated;


-- ============================================================ Kits (atualizar_kits.sql)
-- Kits (spec3): catálogo novo de periféricos e kits em item_associado ("Com kit" na tela).
-- Rode uma vez depois de atualizar_2026_11_25.sql. Idempotente.
-- item_associado ganha: opcional (aparece desmarcado na tela) e grupo (mesmo grupo = escolhe um só).
-- A case de tablet tem o seu plug como associado: ao escolher a case, a tela traz o plug dela (1 nível).

-- ---------------------------------------------------------------- 1. Catálogo
update produto set nome = 'MDVR 3404' where nome = 'MDVR Intelbras 3404'
   and not exists (select 1 from produto where nome = 'MDVR 3404');
update produto set nome = 'MDVR 5404' where nome = 'MDVR Intelbras 5404'
   and not exists (select 1 from produto where nome = 'MDVR 5404');

insert into produto (nome, categoria_id)
select v.nome, (select id from categoria where nome = v.cat)
  from (values
    ('Antena GPS', 'Comunicação e conectividade'), ('Antena GSM Macho', 'Comunicação e conectividade'),
    ('Antena GSM Femea', 'Comunicação e conectividade'), ('Antena Wifi', 'Comunicação e conectividade'),
    ('Chicote MDVR', 'Cabos, chicotes e conexões'), ('Chicote DashCAM', 'Cabos, chicotes e conexões'),
    ('Case Tablet 4 pinos', 'Tablets e acessórios'), ('Case Tablet 10 pinos', 'Tablets e acessórios'),
    ('Case Tablet Tipo C', 'Tablets e acessórios'), ('Suporte Tablet', 'Tablets e acessórios'),
    ('Plug Carregador Tablet 4 pinos', 'Tablets e acessórios'), ('Plug Carregador Tablet 10 pinos', 'Tablets e acessórios')
  ) as v(nome, cat)
 where not exists (select 1 from produto p where lower(p.nome) = lower(v.nome));

-- Saem: apaga se nunca foi usado; com histórico (movimentação, saldo, pedido...) fica inativo.
do $$
declare r record;
begin
  for r in select id, nome from produto
            where nome in ('Case Tablet Samsung', 'Case Tablet Multilaser', 'Suporte Tablet Samsung', 'Suporte Tablet Multilaser')
  loop
    delete from item_associado where produto_id = r.id or associado_id = r.id;
    begin
      delete from produto where id = r.id;
    exception when foreign_key_violation then
      update produto set ativo = false where id = r.id;
      raise notice '% tem movimentação/saldo/pedido: ficou inativo, não foi apagado', r.nome;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------- 2. Kits em item_associado
alter table item_associado add column if not exists opcional boolean not null default false;
alter table item_associado add column if not exists grupo text;

insert into item_associado (produto_id, associado_id, quantidade, opcional, grupo)
select p.id, a.id, 1, v.opcional, v.grupo
  from (values
    ('Módulo FMC 650', 'Chicote FMC650', false, null), ('Módulo FMC 650', 'Antena GPS', false, null),
    ('Módulo FMC 650', 'Antena GSM Femea', false, null),
    ('Módulo Galileo 7x / 10HUB', 'Chicote Galileo 7x / 10HUB', false, null), ('Módulo Galileo 7x / 10HUB', 'Antena GPS', false, null),
    ('Módulo Galileo 7x / 10HUB', 'Antena GSM Macho', false, null), ('Módulo Galileo 7x / 10HUB', 'Antena Wifi', true, null),
    ('MDVR 3404', 'Chicote MDVR', false, null), ('MDVR 3404', 'Antena GPS', false, null),
    ('MDVR 3404', 'Antena GSM Macho', false, null), ('MDVR 3404', 'Antena Wifi', true, null),
    ('MDVR 5404', 'Antena GPS', false, null), ('MDVR 5404', 'Antena GSM Macho', false, null),
    ('MDVR 5404', 'Antena Wifi', true, null),
    ('DashCAM', 'Chicote DashCAM', false, null),
    ('Camera contexto DVR', 'Extensão cameras', false, null), ('Camera Fadiga DVR', 'Extensão cameras', false, null),
    ('Camera frontal (Adas) DVR', 'Extensão cameras', false, null),
    ('Camera Contexto DashCAM', 'Extensão cameras DashCAM', false, null), ('Camera Fadiga DashCAM', 'Extensão cameras DashCAM', false, null),
    ('Camera frontal (Adas) DashCAM', 'Extensão cameras DashCAM', false, null),
    ('Camera IP', 'Cabo rede', false, null),
    ('Tablet Samsung', 'Suporte Tablet', false, null), ('Tablet Samsung', 'Carregador DC/DC 12V Tablet Roboflex', false, null),
    ('Tablet Samsung', 'Case Tablet 4 pinos', false, 'Case'), ('Tablet Samsung', 'Case Tablet 10 pinos', false, 'Case'),
    ('Tablet Samsung', 'Case Tablet Tipo C', false, 'Case'),
    ('Tablet Multilaser', 'Suporte Tablet', false, null), ('Tablet Multilaser', 'Carregador DC/DC 12V Tablet Roboflex', false, null),
    ('Tablet Multilaser', 'Case Tablet 4 pinos', false, 'Case'), ('Tablet Multilaser', 'Case Tablet 10 pinos', false, 'Case'),
    ('Tablet Multilaser', 'Case Tablet Tipo C', false, 'Case'),
    ('Case Tablet 4 pinos', 'Plug Carregador Tablet 4 pinos', false, null),
    ('Case Tablet 10 pinos', 'Plug Carregador Tablet 10 pinos', false, null)
  ) as v(prod, assoc, opcional, grupo)
  join produto p on p.nome = v.prod
  join produto a on a.nome = v.assoc
on conflict (produto_id, associado_id) do update
  set quantidade = 1, opcional = excluded.opcional, grupo = excluded.grupo;

-- Demais módulos: ficam só com o chicote que já tinham (nenhuma antena).
-- Conferência: avisa se algum nome da lista não existe no catálogo.
do $$ declare v text; begin
  select string_agg(n, ', ') into v from unnest(array['Módulo FMC 650','Módulo Galileo 7x / 10HUB','MDVR 3404','MDVR 5404',
    'DashCAM','Camera contexto DVR','Camera Fadiga DVR','Camera frontal (Adas) DVR','Camera Contexto DashCAM',
    'Camera Fadiga DashCAM','Camera frontal (Adas) DashCAM','Camera IP','Tablet Samsung','Tablet Multilaser',
    'Extensão cameras','Extensão cameras DashCAM','Cabo rede','Chicote FMC650','Chicote Galileo 7x / 10HUB',
    'Carregador DC/DC 12V Tablet Roboflex']) n
   where not exists (select 1 from produto where nome = n);
  if v is not null then raise notice 'Itens não encontrados (kit não criado para eles): %', v; end if;
end $$;


-- ============================================================ Itens no Cadastros (atualizar_itens_admin.sql)
-- Itens (produto) no Cadastros: o administrador inclui, edita e exclui.
-- Incluir/editar: direto na tabela produto (RLS produto_admin). Nome único sem diferenciar maiúsculas.
-- Excluir: excluir_item(p_id) apaga só item sem uso; com movimentação, solicitação, pedido ou sendo componente
-- do kit de outro item, desativa (ativo = false). Retorna 'excluido' ou 'desativado'.
-- Rode uma vez depois de atualizar_kits.sql. Idempotente.

do $$ declare v text; begin
  select string_agg(n, ', ') into v from (select lower(nome) n from produto group by 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há itens com o mesmo nome (maiúsculas à parte): %. Renomeie antes.', v; end if;
end $$;
create unique index if not exists produto_nome_unico_ci on produto (lower(nome));

create or replace function public.excluir_item(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui itens' using errcode = '42501';
  end if;
  select nome into v_nome from produto where id = p_id;
  if v_nome is null then raise exception 'Item não encontrado'; end if;

  if not exists (select 1 from item_associado where associado_id = p_id) then
    begin
      delete from item_associado where produto_id = p_id;   -- o kit do próprio item
      delete from produto where id = p_id;
      return 'excluido';
    exception when foreign_key_violation then
      null;  -- tem histórico (movimentação, saldo, solicitação, pedido): desativa abaixo
    end;
  end if;

  update produto set ativo = false where id = p_id;
  raise notice '% tem histórico ou faz parte do kit de outro item: foi desativado, não excluído', v_nome;
  return 'desativado';
end $$;

revoke execute on function public.excluir_item(integer) from public, anon;
grant execute on function public.excluir_item(integer) to authenticated;


-- ============================================================ Clientes no Cadastros (atualizar_clientes_admin.sql)
-- Clientes e unidades no Cadastros: o administrador renomeia, move unidade de cliente e exclui.
-- Renomear/mover: update direto (RLS cliente_admin / unidade_admin). Nome único sem diferenciar maiúsculas
-- (cliente no geral; unidade dentro do mesmo cliente).
-- Excluir: excluir_cliente(p_id) / excluir_unidade(p_id) apagam só o que não tem uso; com movimentação,
-- solicitação, dedicado ou reserva, desativam (ativo = false). O cliente vai sempre junto com as unidades.
-- Retornam 'excluido' ou 'desativado'. Rode uma vez depois de atualizar_itens_admin.sql. Idempotente.

alter table cliente         add column if not exists ativo boolean not null default true;
alter table unidade_cliente add column if not exists ativo boolean not null default true;

do $$ declare v text; begin
  select string_agg(n, ', ') into v from (select lower(nome) n from cliente group by 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há clientes com o mesmo nome (maiúsculas à parte): %. Renomeie antes.', v; end if;
  select string_agg(n, ', ') into v from (select lower(nome) n from unidade_cliente group by cliente_id, 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há unidades repetidas no mesmo cliente (maiúsculas à parte): %. Renomeie antes.', v; end if;
end $$;
create unique index if not exists cliente_nome_unico_ci on cliente (lower(nome));
create unique index if not exists unidade_nome_unico_ci on unidade_cliente (cliente_id, lower(nome));

create or replace function public.excluir_unidade(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui unidades' using errcode = '42501';
  end if;
  if not exists (select 1 from unidade_cliente where id = p_id) then raise exception 'Unidade não encontrada'; end if;
  begin
    delete from unidade_cliente where id = p_id;
    return 'excluido';
  exception when foreign_key_violation then
    null;  -- tem movimentação, solicitação, dedicado ou reserva
  end;
  update unidade_cliente set ativo = false where id = p_id;
  return 'desativado';
end $$;

create or replace function public.excluir_cliente(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui clientes' using errcode = '42501';
  end if;
  if not exists (select 1 from cliente where id = p_id) then raise exception 'Cliente não encontrado'; end if;
  begin
    delete from unidade_cliente where cliente_id = p_id;
    delete from cliente where id = p_id;
    return 'excluido';
  exception when foreign_key_violation then
    null;  -- alguma unidade tem histórico: nada é apagado
  end;
  update unidade_cliente set ativo = false where cliente_id = p_id;
  update cliente set ativo = false where id = p_id;
  return 'desativado';
end $$;

revoke execute on function public.excluir_cliente(integer), public.excluir_unidade(integer) from public, anon;
grant execute on function public.excluir_cliente(integer), public.excluir_unidade(integer) to authenticated;

