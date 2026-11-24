-- Atualização: finalidade da solicitação (mobilização ou manutenção).
-- Rode uma vez, depois de atualizar_ver_como.sql. Pode rodar de novo sem problema.
-- Obrigatória nas solicitações novas do agendamento (enviar_cliente, enviar_dedicado, retirar_dedicado).
-- Pedidos de transferência e pedidos antigos (legado) ficam sem finalidade.

begin;

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

commit;
