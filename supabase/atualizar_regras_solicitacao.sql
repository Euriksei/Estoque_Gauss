-- Atualização: regras de solicitação (agendamento só do estoque dele para técnico, com cliente; item pode sair de dedicado;
-- operador só dá andamento nas solicitações do seu estoque). Rode UMA vez no SQL Editor, depois de atualizar_chips.sql.
-- (Quem criar o banco do zero com o banco_completo.sql atual não precisa deste arquivo.)
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

