-- Atualização: chips dos módulos de telemetria (Claro, Vivo, Arquia Claro, Arquia Vivo), instalar/trocar/descartar chip.
-- Rode UMA vez no SQL Editor do Supabase, em um banco que já tem o banco_completo.sql anterior.
-- (Quem criar o banco do zero com o banco_completo.sql atual não precisa deste arquivo.)
alter type condicao_item add value if not exists 'claro';
alter type condicao_item add value if not exists 'vivo';
alter type condicao_item add value if not exists 'arquia_claro';
alter type condicao_item add value if not exists 'arquia_vivo';
alter type tipo_movimento add value if not exists 'TROCA_CHIP';
alter table produto add column if not exists usa_chip boolean not null default false;
alter table produto add column if not exists chip_tipo text;

-- ================================================================ 0011_chips
-- Chips dos módulos de telemetria. O saldo do módulo é separado pelo chip instalado (coluna "condicao":
-- 'novo' = sem chip). Chips avulsos são itens normais (produto.chip_tipo). "Trocar chip" converte módulos e
-- mexe nos chips avulsos; um chip que não funcionou pode ser descartado.

create or replace function public.fn_rotulo_chip(c text) returns text language sql immutable as $$
  select case c when 'novo' then 'sem chip' when 'claro' then 'Claro' when 'vivo' then 'Vivo'
                when 'arquia_claro' then 'Arquia Claro' when 'arquia_vivo' then 'Arquia Vivo' else c end
$$;

create or replace view efeito_estoque with (security_invoker = true) as
select m.local_destino_id as local_id, i.produto_id, i.condicao,
       coalesce(i.reservar_para_unidade_id, i.reservado_unidade_id) as reservado_unidade_id, i.quantidade as delta
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_destino_id is not null
   and ((m.tipo::text in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE','AJUSTE','TROCA_CHIP') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status = 'recebido'))
union all
select m.local_origem_id, i.produto_id, i.condicao, i.reservado_unidade_id, -i.quantidade
  from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
 where m.local_origem_id is not null
   and ((m.tipo in ('SAIDA_CLIENTE','CONSUMO_INTERNO','DESCARTE') and m.status = 'registrado')
     or (m.tipo = 'TRANSFERENCIA' and m.status in ('em_transito','recebido')));

create or replace function public.fn_verificar_saldo(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select e.local_id, e.produto_id, e.condicao, e.reservado_unidade_id, sum(e.delta) as q
      from efeito_estoque e
     where e.local_id = any (p_locais)
     group by 1,2,3,4
    having sum(e.delta) < 0
     limit 1
  loop
    raise exception 'Saldo insuficiente: %, local %, quantidade faltando %',
      (select nome from produto where id = r.produto_id) ||
      case when exists (select 1 from produto where id = r.produto_id and usa_chip)
           then ' (' || fn_rotulo_chip(r.condicao::text) || ')' else '' end,
      (select nome from local where id = r.local_id), -r.q
      using errcode = 'P0001';
  end loop;
end $$;

create or replace function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb; v_pid integer; v_chip text;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    v_pid := (it->>'produto_id')::int;
    -- só módulos com chip guardam o chip; os demais itens ficam sempre em 'novo'
    v_chip := case when exists (select 1 from produto where id = v_pid and usa_chip)
                   then coalesce(nullif(it->>'condicao',''), 'novo') else 'novo' end;
    if v_chip not in ('novo','claro','vivo','arquia_claro','arquia_vivo') then raise exception 'Chip inválido: %', v_chip; end if;
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov, v_pid, v_chip::condicao_item, (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arquia Claro, Arquia Vivo).
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
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador trocam chip' using errcode = '42501';
  end if;
  if v_local is null or not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if not exists (select 1 from produto where id = v_prod and usa_chip) then raise exception 'Este item não usa chip'; end if;
  if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade deve ser maior que zero'; end if;
  if v_de not in ('novo','claro','vivo','arquia_claro','arquia_vivo') or v_para not in ('novo','claro','vivo','arquia_claro','arquia_vivo') then
    raise exception 'Chip inválido';
  end if;
  -- Mesmo chip de antes só faz sentido para substituir um chip ruim: o antigo é descartado e sai outro avulso.
  if v_de = v_para and (v_de = 'novo' or coalesce(nullif(p->>'chip_retirado',''), 'estoque') <> 'descartar') then
    raise exception 'Para trocar por outro chip da mesma operadora, escolha descartar o chip retirado';
  end if;
  if v_dest not in ('estoque','descartar') then raise exception 'chip_retirado deve ser estoque ou descartar'; end if;
  if v_dest = 'descartar' and v_de <> 'novo' and v_obs is null then
    raise exception 'Descartar chip exige o motivo (ex.: módulo não comunicou)';
  end if;
  if v_de <> 'novo' then select id into v_chip_de from produto where chip_tipo = v_de and ativo order by id limit 1;
    if v_chip_de is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_de); end if; end if;
  if v_para <> 'novo' then select id into v_chip_para from produto where chip_tipo = v_para and ativo order by id limit 1;
    if v_chip_para is null then raise exception 'Não há item de chip avulso cadastrado para %', fn_rotulo_chip(v_para); end if; end if;

  perform fn_travar_locais(array[v_local]);
  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('TROCA_CHIP', 'registrado', coalesce((p->>'data')::date, current_date), v_local,
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
  return v_id;
end $$;
revoke execute on function public.trocar_chip(jsonb) from public, anon;
grant execute on function public.trocar_chip(jsonb) to authenticated;


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
                                      -- p.chips: {"<produto_id>|<unidade dedicada ou vazio>": "claro"}; sem escolha = módulo sem chip
                                      'condicao', coalesce(p->'chips'->>(produto_id::text || '|' || coalesce(reservar_para_unidade_id::text, '')), 'novo')))
    into v_itens from solicitacao_item where solicitacao_id = p_id;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

-- Dados dos chips: quais itens são módulos com chip e quais são chips avulsos.
update produto set usa_chip = true
 where fabricante in ('Ruptela','Teltonika','GalileoSky')
   and categoria_id = (select id from categoria where nome = 'Rastreamento e telemetria');
update produto set chip_tipo = 'claro' where nome = 'Chip Claro M2M';
update produto set chip_tipo = 'vivo'  where nome = 'Chip Vivo M2M';
insert into produto (nome, categoria_id, fornecedor_id, prazo_medio_dias, chip_tipo)
select v.nome, (select id from categoria where nome = 'Comunicação e conectividade'),
       (select id from fornecedor where nome = 'Securitek'), 30, v.tipo
  from (values ('Chip Arqia Claro M2M','arquia_claro'), ('Chip Arqia Vivo M2M','arquia_vivo')) as v(nome, tipo)
on conflict (nome) do nothing;
update produto set chip_tipo = 'arquia_claro' where nome = 'Chip Arqia Claro M2M';
update produto set chip_tipo = 'arquia_vivo'  where nome = 'Chip Arqia Vivo M2M';

