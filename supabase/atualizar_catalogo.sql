-- Atualização: catálogo novo de itens (77 itens) e chip Arqia como uma operadora só.
-- Rode uma vez, depois de atualizar_regras_solicitacao.sql.
--  * renomeia itens (o id continua o mesmo, então o histórico continua ligado);
--  * cria os itens novos;
--  * APAGA todo item que não está na lista, junto com as linhas dele em movimentações,
--    solicitações, pedidos de compra e itens associados (o banco só tinha saldo de teste);
--  * Arquia Claro e Arquia Vivo viram "Arqia" (chip do módulo e chip avulso).
-- Tudo roda numa transação só: se der erro, nada é gravado. Pode rodar de novo sem problema.

begin;

-- ---------------------------------------------------------------- 1. Arqia: uma operadora só
-- Renomear o valor do enum mantém as linhas existentes; o que era arquia_vivo passa para arqia.
-- Aceita qualquer estado anterior: arquia_claro/arquia_vivo (chips antigos), arquia (nome provisório) ou arqia.
do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'condicao_item' and e.enumlabel = 'arqia') then
    if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                where t.typname = 'condicao_item' and e.enumlabel = 'arquia') then
      alter type condicao_item rename value 'arquia' to 'arqia';
    elsif exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                   where t.typname = 'condicao_item' and e.enumlabel = 'arquia_claro') then
      alter type condicao_item rename value 'arquia_claro' to 'arqia';
    end if;
  end if;
end $$;
update movimentacao_item set condicao = 'arqia' where condicao::text in ('arquia', 'arquia_claro', 'arquia_vivo');
update produto set chip_tipo = 'arqia' where chip_tipo in ('arquia', 'arquia_claro', 'arquia_vivo');

create or replace function public.fn_rotulo_chip(c text) returns text language sql immutable as $$
  select case c when 'novo' then 'sem chip' when 'claro' then 'Claro' when 'vivo' then 'Vivo'
                when 'arqia' then 'Arqia' else c end
$$;

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
    if v_chip not in ('novo','claro','vivo','arqia') then raise exception 'Chip inválido: %', v_chip; end if;
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov, v_pid, v_chip::condicao_item, (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- Trocar chip: converte módulos de "de" para "para" (sem chip, Claro, Vivo, Arqia).
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

-- Chip avulso da Arqia: "Chip Arqia M2M". O que estava em Arqia Claro/Vivo M2M passa para ele.
update produto set chip_tipo = 'arqia' where nome = 'Chip Arqia M2M';
update movimentacao_item set produto_id = (select id from produto where nome = 'Chip Arqia M2M')
 where produto_id in (select id from produto where nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M'));
update pedido_compra set produto_id = (select id from produto where nome = 'Chip Arqia M2M')
 where produto_id in (select id from produto where nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M'));
-- Solicitações: a linha (solicitação, item, reservas) é única. Soma na linha do Chip Arqia M2M
-- quando ela já existe; senão cria. As linhas antigas saem no passo 4, junto com os dois produtos.
create temporary table arqia_sol as
select si.solicitacao_id, si.reservar_para_unidade_id, si.reservado_unidade_id, sum(si.quantidade) as qtd
  from solicitacao_item si join produto p on p.id = si.produto_id
 where p.nome in ('Chip Arqia Claro M2M', 'Chip Arqia Vivo M2M')
 group by 1, 2, 3;
update solicitacao_item si set quantidade = si.quantidade + a.qtd
  from arqia_sol a
 where si.produto_id = (select id from produto where nome = 'Chip Arqia M2M')
   and si.solicitacao_id = a.solicitacao_id
   and coalesce(si.reservar_para_unidade_id, 0) = coalesce(a.reservar_para_unidade_id, 0)
   and coalesce(si.reservado_unidade_id, 0) = coalesce(a.reservado_unidade_id, 0);
insert into solicitacao_item (solicitacao_id, produto_id, quantidade, reservar_para_unidade_id, reservado_unidade_id)
select a.solicitacao_id, (select id from produto where nome = 'Chip Arqia M2M'), a.qtd,
       a.reservar_para_unidade_id, a.reservado_unidade_id
  from arqia_sol a
 where not exists (select 1 from solicitacao_item si
                    where si.produto_id = (select id from produto where nome = 'Chip Arqia M2M')
                      and si.solicitacao_id = a.solicitacao_id
                      and coalesce(si.reservar_para_unidade_id, 0) = coalesce(a.reservar_para_unidade_id, 0)
                      and coalesce(si.reservado_unidade_id, 0) = coalesce(a.reservado_unidade_id, 0));
drop table arqia_sol;

-- ---------------------------------------------------------------- 2. Renomear
update produto p set nome = v.novo
  from (values
    ('ECO 5', 'Módulo ECO 5'),
    ('ECO-LIGHT +S', 'Módulo ECO-LIGHT +S'),
    ('FMB920', 'Módulo FMB920'),
    ('FMC 130', 'Módulo FMC 130'),
    ('FMC 150', 'Módulo FMC 150'),
    ('FMC 650', 'Módulo FMC 650'),
    ('Galileo 7x / 10HUB', 'Módulo Galileo 7x / 10HUB'),
    ('GF Pro4', 'Módulo GF Pro4'),
    ('HCV5', 'Módulo HCV5'),
    ('PRO5 Lite', 'Módulo PRO5 Lite'),
    ('TRACE 5', 'Módulo TRACE 5'),
    ('SUNTECH Plug Play', 'Módulo SUNTECH PLUG PLAY'),
    ('Camera Contexto (3Fios)', 'Camera contexto DVR'),
    ('Camera Contexto (3Fios) DashCAM', 'Camera Contexto DashCAM'),
    ('Camera Fadiga (T)', 'Camera Fadiga DVR'),
    ('Camera Fadiga (T) DashCAM', 'Camera Fadiga DashCAM'),
    ('Camera frontal (vermelha)', 'Camera frontal (Adas) DVR'),
    ('Monitor de alarme', 'Monitor de alarme (SmartWach)'),
    ('Cabo rede 3 metros', 'Cabo rede'),
    ('Chicote Galileo', 'Chicote Galileo 7x / 10HUB'),
    ('Extensão cameras Intelbras', 'Extensão cameras'),
    ('Extensão cameras Intelbras DashCAM', 'Extensão cameras DashCAM'),
    ('Tablet Multilaser 7''''', 'Tablet Multilaser'),
    ('Suporte Case Tablet Multilaser 7"', 'Case Tablet Multilaser'),
    ('Suporte Case Tablet Samsung 8"', 'Case Tablet Samsung'),
    ('Suporte Tablet Multilaser 7"', 'Suporte Tablet Multilaser'),
    ('Suporte Tablet Samsung 8"', 'Suporte Tablet Samsung'),
    ('Leitor RFID 125 SGBRAS', 'Leitor RFID 125'),
    ('Leitor RFID 13,56 SGBRAS', 'Leitor RFID 13,56')
  ) as v(antigo, novo)
 where p.nome = v.antigo
   and not exists (select 1 from produto x where x.nome = v.novo);

-- ---------------------------------------------------------------- 2b. MDVR e monitores (lista de 2026-11-23)
-- Renomeia (mesmo id, o histórico continua ligado). Os dois MDVRs Intelbras continuam separados.
update produto p set nome = v.novo
  from (values
    ('DVR DashCAM', 'DashCAM'),
    ('DVR Intelbras 3404', 'MDVR Intelbras 3404'),
    ('DVR Intelbras 5404', 'MDVR Intelbras 5404')
  ) as v(antigo, novo)
 where p.nome = v.antigo
   and not exists (select 1 from produto x where x.nome = v.novo);

-- ---------------------------------------------------------------- 3. Itens novos
insert into produto (nome, categoria_id, fornecedor_id, prazo_medio_dias)
values
  ('Camera frontal (Adas) DashCAM', (select id from categoria where nome = 'Câmeras'),
   (select id from fornecedor where nome = 'Intelbrás'), 30),
  ('Chicote SUNTECH Plug Play', (select id from categoria where nome = 'Cabos, chicotes e conexões'),
   (select id from fornecedor where nome = 'Suntech'), 15)
on conflict (nome) do nothing;

-- O módulo Suntech sai com o chicote dele (sugestão editável, "Com chicote").
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote SUNTECH Plug Play'
 where p.nome = 'Módulo SUNTECH PLUG PLAY'
on conflict do nothing;

-- ---------------------------------------------------------------- 4. Apagar o que não está na lista
drop table if exists catalogo_novo, produto_apagar;
create temporary table catalogo_novo (nome text primary key);
insert into catalogo_novo (nome) values
  ('Baterias Plug&Play M11'), ('Buzzer'), ('Cabo rede'), ('Camera Contexto DashCAM'), ('Camera contexto DVR'),
  ('Camera Fadiga DVR'), ('Camera Fadiga DashCAM'), ('Camera frontal (Adas) DVR'), ('Camera frontal (Adas) DashCAM'),
  ('Camera IP'), ('Carregador DC/DC 12V Tablet Roboflex'), ('Carregador Plug Play'), ('Cartão Memória 128GB'),
  ('Cartão Memória 128GB MICRO SD'), ('Cartão Memória 256GB'), ('Cartão Memória 256GB MICRO SD'), ('Cartão RFID 125'),
  ('Cartão RFID 13,56'), ('Chicote ECO 5'), ('Chicote ECO-LIGHT +S'), ('Chicote FMB920'), ('Chicote FMC130'),
  ('Chicote FMC150'), ('Chicote FMC650'), ('Chicote Galileo 7x / 10HUB'), ('Chicote Pro4'), ('Chicote Pro5'),
  ('Chicote SUNTECH Plug Play'), ('Chicote Trace5'), ('Chip Arqia M2M'), ('Chip Arqia Voz e Dados'), ('Chip Claro M2M'),
  ('Chip Claro Voz e Dados'), ('Chip Vivo M2M'), ('Chip Vivo Voz e Dados'), ('Conversor locomotiva 1 Amper'),
  ('Conversor locomotiva 15 Amper'), ('Conversor locomotiva 3 Amper'), ('DashCAM'), ('MDVR Intelbras 3404'),
  ('MDVR Intelbras 5404'), ('Extensão cameras'), ('Extensão cameras DashCAM'), ('Galielo Rotograma falado'),
  ('KIT CTA Comboio'), ('KIT CTA Posto fixo'), ('Leitor EasyCAN'), ('Leitor RFID 125'), ('Leitor RFID 13,56'),
  ('Leitor RFID 13,56 / 125'), ('Módulo ECO 5'), ('Módulo ECO-LIGHT +S'), ('Módulo FMB920'), ('Módulo FMC 130'),
  ('Módulo FMC 150'), ('Módulo FMC 650'), ('Módulo Galileo 7x / 10HUB'), ('Módulo GF Pro4'), ('Módulo HCV5'),
  ('Módulo PRO5 Lite'), ('Módulo SUNTECH PLUG PLAY'), ('Módulo TRACE 5'), ('Monitor de alarme (SmartWach)'),
  ('Relé Bloqueio 12 Volts'), ('Relé Bloqueio 24 Volts'), ('Relé Finder'), ('Sensor Betoneira'),
  ('Sensor de temperatura'), ('Smartlink Carretinha'), ('Case Tablet Multilaser'), ('Case Tablet Samsung'),
  ('Suporte Tablet Multilaser'), ('Suporte Tablet Samsung'), ('Suporte Ventosa'), ('Switch cabo rede Intelbras'),
  ('Tablet Multilaser'), ('Tablet Samsung');

create temporary table produto_apagar as
select id, nome from produto where nome not in (select nome from catalogo_novo);

do $$ declare r record; begin
  for r in select nome from produto_apagar order by nome loop raise notice 'Apagando: %', r.nome; end loop;
end $$;

delete from item_associado where produto_id in (select id from produto_apagar) or associado_id in (select id from produto_apagar);
delete from solicitacao_item where produto_id in (select id from produto_apagar);
delete from pedido_compra where produto_id in (select id from produto_apagar);
delete from movimentacao_item where produto_id in (select id from produto_apagar);
delete from produto where id in (select id from produto_apagar);

-- Conferência: tem que haver exatamente os 77 itens da lista.
do $$ declare v_faltando text; v_total int; begin
  select string_agg(c.nome, ', ') into v_faltando from catalogo_novo c where not exists (select 1 from produto p where p.nome = c.nome);
  if v_faltando is not null then raise exception 'Itens da lista que não existem no banco: %', v_faltando; end if;
  select count(*) into v_total from produto;
  if v_total <> 77 then raise exception 'Esperava 77 itens, o banco tem %', v_total; end if;
end $$;

drop table catalogo_novo, produto_apagar;
commit;
