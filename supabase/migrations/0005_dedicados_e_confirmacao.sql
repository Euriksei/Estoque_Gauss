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
