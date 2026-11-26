-- Atualização 2026-11-25 (spec2). Rode uma vez depois de atualizar_envio_tecnico.sql. Idempotente.
--  1. Fornecedor sai do sistema (tabela e colunas).
--  2. registrar_transferencia: envio direto (sem pedido), fica em trânsito e o destino confirma.
--  3. Devolução de cliente: modo de envio obrigatório (técnico que entregou, se for técnico), sem dedicado;
--     (kits ficam em item_associado: atualizar_kits.sql).
--  4. Descarte exige justificativa.
--  5. Chip M2M x Voz e Dados (produto.chip_rede); MDVR e DashCAM passam a usar chip;
--     trocar_chip usa o avulso do tipo certo; trocar_chips_entre troca chips entre dois equipamentos.
--  6. O administrador também cria solicitações.
begin;

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

commit;
