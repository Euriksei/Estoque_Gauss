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
