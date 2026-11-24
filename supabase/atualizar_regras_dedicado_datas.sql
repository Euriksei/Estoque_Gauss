-- Atualização: datas, meio de envio e regras do estoque dedicado.
-- Rode uma vez, depois de atualizar_permissoes_funcoes.sql. Pode rodar de novo sem problema.
--  * Datas: nenhuma movimentação aceita data no futuro (data da movimentação, data de envio da
--    transferência, data da troca de chip). "Hoje" é a data de São Paulo (America/Sao_Paulo).
--    Sem data informada, vale hoje em São Paulo. O prazo de chegada da transferência pode ser futuro.
--  * Meio de envio: "sedex" deixa de existir; tudo vira "correios". O valor continua no tipo do banco
--    (tirar valor de enum no PostgreSQL exige recriar o tipo), mas os registros são migrados e uma
--    regra da tabela impede gravar "sedex" daqui pra frente.
--  * Dedicado só nasce por devolução de cliente, recebimento de transferência com "Dedicado para" e
--    ajuste de inventário. Entrada por compra não cria mais dedicado.
--  * Todo ou nada: o que tirar saldo dedicado de uma unidade num local (saída, transferência, consumo,
--    descarte, ajuste para menos) tem que levar todo o dedicado daquela unidade naquele local, de todos
--    os itens e chips. A troca de chip só mexe no estoque livre.
-- Tudo roda numa transação só: se der erro, nada é gravado.

begin;

-- ---------------------------------------------------------------- 1. Hoje em São Paulo e data da movimentação
create or replace function public.fn_hoje() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

-- Data informada (ou hoje em São Paulo, se vier vazia); data no futuro é recusada.
create or replace function public.fn_data_movimento(p_data text) returns date
language plpgsql stable set search_path = public as $$
declare v date := coalesce(nullif(p_data, '')::date, fn_hoje());
begin
  if v > fn_hoje() then
    raise exception 'A data não pode ser no futuro (hoje é %)', to_char(fn_hoje(), 'DD/MM/YYYY');
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------- 2. Meio de envio: sedex vira correios
update movimentacao set modo_envio = 'correios' where modo_envio = 'sedex';
alter table movimentacao drop constraint if exists movimentacao_sem_sedex;
alter table movimentacao add constraint movimentacao_sem_sedex check (modo_envio is distinct from 'sedex');

-- ---------------------------------------------------------------- 3. Dedicado vai inteiro
-- Para cada unidade cujo dedicado esta movimentação tirou de um local, confere que não sobrou nada
-- dela naquele local (somando todos os itens e chips). Chamada depois de fn_verificar_saldo.
create or replace function public.fn_verificar_dedicado_inteiro(p_mov bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_resta integer;
begin
  for r in
    select distinct x.local_id, x.unidade_id from (
      select m.local_origem_id as local_id, i.reservado_unidade_id as unidade_id
        from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
       where i.movimentacao_id = p_mov and m.local_origem_id is not null and i.reservado_unidade_id is not null
         and m.tipo in ('SAIDA_CLIENTE','CONSUMO_INTERNO','DESCARTE','TRANSFERENCIA')
      union
      select m.local_destino_id, coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id)
        from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
       where i.movimentacao_id = p_mov and m.local_destino_id is not null and i.quantidade < 0
         and coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) is not null
         and m.tipo in ('AJUSTE','TROCA_CHIP')
    ) x
  loop
    select coalesce(sum(e.delta), 0) into v_resta
      from efeito_estoque e where e.local_id = r.local_id and e.reservado_unidade_id = r.unidade_id;
    if v_resta <> 0 then
      raise exception 'O estoque dedicado de % em % precisa ir inteiro: faltam % itens',
        (select c.nome || ' - ' || u.nome from unidade_cliente u join cliente c on c.id = u.cliente_id where u.id = r.unidade_id),
        (select nome from local where id = r.local_id), v_resta
        using errcode = 'P0001';
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- 4. registrar_movimentacao
-- p: {tipo, data, local_id, unidade_id, fornecedor_id, numero_nf, finalidade, chamado_url, observacao,
--     modo_envio, codigo_rastreio, tecnico_id,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
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
  v_data date;
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
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      select t.id into v_tec from tecnico t where t.usuario_id = auth.uid();
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

-- ---------------------------------------------------------------- 5. criar_transferencia (só data, meio de envio e dedicado inteiro)
-- p: {origem_id, destino_id, data, modo_envio, codigo_rastreio, prazo_chegada, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
create or replace function public.criar_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_origem  integer := (p->>'origem_id')::int;
  v_destino integer := (p->>'destino_id')::int;
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_data date;
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
  if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
  v_data := fn_data_movimento(p->>'data');

  perform fn_travar_locais(array[v_origem, v_destino]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, modo_envio, codigo_rastreio,
                            prazo_chegada, observacao, criado_por)
  values ('TRANSFERENCIA', 'em_transito', v_data, v_origem, v_destino,
          v_modo, nullif(p->>'codigo_rastreio',''),
          nullif(p->>'prazo_chegada','')::date, nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  perform fn_gravar_itens(v_id, p->'itens');
  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  perform fn_verificar_saldo(array[v_origem]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 6. trocar_chip (só a data)
-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arqia), sempre no estoque livre.
-- Instalar chip avulso baixa o chip avulso; o chip retirado volta ao estoque avulso ou é descartado.
-- p: {local_id, produto_id, quantidade, de, para, chip_retirado ('estoque'|'descartar'), observacao, data}
create or replace function public.trocar_chip(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_local integer := (p->>'local_id')::int; v_prod integer := (p->>'produto_id')::int;
  v_qtd integer := (p->>'quantidade')::int;
  v_de text := coalesce(nullif(p->>'de',''), 'novo'); v_para text := coalesce(nullif(p->>'para',''), 'novo');
  v_dest text := coalesce(nullif(p->>'chip_retirado',''), 'estoque');
  v_id bigint; v_chip_de integer; v_chip_para integer; v_obs text := nullif(p->>'observacao','');
  v_data date;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arqia') or v_para not in ('novo','claro','vivo','arqia') then
    raise exception 'Chip inválido';
  end if;
  -- Mesmo chip de antes só faz sentido para substituir um chip ruim: o antigo é descartado e sai outro avulso.
  if v_de = v_para and (v_de = 'novo' or v_dest <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  v_data := fn_data_movimento(p->>'data');
  if v_de <> 'novo' then select id into v_chip_de from produto where chip_tipo = v_de and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_de); end if; end if;
  if v_para <> 'novo' then select id into v_chip_para from produto where chip_tipo = v_para and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_para); end if; end if;

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

-- ---------------------------------------------------------------- 7. Permissões das funções novas
-- (no Supabase função nova já nasce liberada para anon e authenticated)
revoke execute on function public.fn_data_movimento(text), public.fn_verificar_dedicado_inteiro(bigint)
  from public, anon, authenticated;
revoke execute on function public.fn_hoje() from public, anon;
grant execute on function public.fn_hoje() to authenticated;
revoke execute on function public.registrar_movimentacao(jsonb), public.criar_transferencia(jsonb), public.trocar_chip(jsonb)
  from public, anon;
grant execute on function public.registrar_movimentacao(jsonb), public.criar_transferencia(jsonb), public.trocar_chip(jsonb)
  to authenticated;

commit;
