-- ATUALIZAÇÃO ÚNICA para quem JÁ aplicou a migração 0004: junta as migrações 0005 a 0008
-- (dedicados e confirmação, chicotes dos rastreadores, sem condição novo/usado). Pode rodar de novo sem duplicar nada.

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
