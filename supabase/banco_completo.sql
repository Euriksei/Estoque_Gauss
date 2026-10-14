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
create type condicao_item    as enum ('novo', 'usado');
create type tipo_movimento   as enum ('ENTRADA_COMPRA', 'DEVOLUCAO_CLIENTE', 'SAIDA_CLIENTE',
                                      'TRANSFERENCIA', 'CONSUMO_INTERNO', 'DESCARTE', 'AJUSTE');
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
                                      'reservar_para_unidade_id', reservar_para_unidade_id))
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
  ('DVR DashCAM', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('DVR Intelbras 3404', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
  ('DVR Intelbras 5404', 'MDVR e monitores', '', 'Intelbrás', '30', '0'),
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
