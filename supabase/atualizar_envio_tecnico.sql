-- Envio para estoque técnico (tela Registrar): registrar_movimentacao aceita tipo 'ENVIO_TECNICO'.
-- Sai do estoque escolhido e entra NA HORA no carro do técnico: grava uma TRANSFERENCIA já
-- 'recebido' (sem trânsito, sem confirmação), então efeito_estoque e o Histórico já a tratam.
-- p: {tipo:'ENVIO_TECNICO', local_id (estoque de origem), tecnico_id (tecnico.id, obrigatório),
--     modo_envio (correios|retirada|transportadora|tecnico, obrigatório), chamado_url (opcional),
--     data, observacao, itens}
-- Idempotente (create or replace). Rode uma vez depois de atualizar_finalidade.sql.
begin;

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

commit;
