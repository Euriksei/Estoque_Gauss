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
