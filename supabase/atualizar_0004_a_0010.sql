-- ATUALIZAÇÃO ÚNICA: para quem parou na migração 0003 (junta 0004 a 0010).
-- Cole o conteúdo no SQL Editor e rode uma vez. Pode repetir sem duplicar nada.

-- ================================================================ 0004_tecnicos_e_modo_de_envio.sql
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

-- ================================================================ 0005_dedicados_e_confirmacao.sql
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

-- ================================================================ 0006_chicote_fmc130_fmc150.sql
-- Migração 0006: módulos FMC 130 e FMC 150 levam o chicote correspondente (sugestão editável).
-- Se já rodou o seed.sql, este arquivo basta; ele não duplica nada.
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote ' || replace(p.nome, ' ', '')
 where p.nome in ('FMC 130', 'FMC 150')
on conflict do nothing;

-- ================================================================ 0007_chicote_para_todos_os_rastreadores.sql
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

-- ================================================================ 0008_sem_condicao_novo_usado.sql
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

-- ================================================================ 0009_solicitacoes_e_agendamento.sql
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

-- ================================================================ 0010_solicitacao_dedicada.sql
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
  if s.status <> 'aberta' then raise exception 'Solicitação já encerrada'; end if;
  if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
  select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                      'reservar_para_unidade_id', reservar_para_unidade_id))
    into v_itens from solicitacao_item where solicitacao_id = p_id;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;
