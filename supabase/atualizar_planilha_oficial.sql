-- Catálogo e saldos oficiais pela planilha (11/2026) + regra do kit de tablet.
-- Rode uma vez depois de atualizar_clientes_admin.sql. Idempotente: rodar de novo não muda nada.
--  1. Nomes iguais aos da planilha (renomeia mantendo o id e o histórico; cria o que falta). As linhas
--     "Módulo X Vivo/Claro/Arqia/S/ Chip", "MDVR ... " e "DashCAM ..." são o mesmo item, com o saldo por chip.
--  2. Item ativo fora da planilha: com histórico é desativado; sem histórico é excluído (regra do excluir_item).
--  3. Kit de tablet: grupo "Suporte" (Suporte Tablet | Suporte Tablet Ventosa) e grupo "Case"; cada case traz
--     o seu plug e o seu carregador (o tablet não leva mais carregador direto).
--  4. Saldo LIVRE de Nova Lima = planilha, por um AJUSTE "Inventário oficial (planilha 11/2026)" (só a diferença).
--     Dedicado, São Bernardo e carros de técnico não mudam. Sem nenhum administrador cadastrado (banco novo),
--     o ajuste é pulado com aviso: rode este arquivo de novo depois de criar o administrador.
begin;

create temp table _planilha (nome text, condicao text, qtd integer) on commit drop;
insert into _planilha (nome, condicao, qtd) values
  ('Buzzer', 'novo', 179),
  ('Cabo rede', 'novo', 22),
  ('Camera Contexto DashCAM', 'novo', 100),
  ('Camera contexto DVR', 'novo', 233),
  ('Camera Fadiga DVR', 'novo', 66),
  ('Camera Fadiga DashCAM', 'novo', 42),
  ('Camera frontal (Adas) DVR', 'novo', 86),
  ('Camera IP', 'novo', 27),
  ('Cartão Memória 128GB', 'novo', 107),
  ('Cartão Memória 128GB MICRO SD', 'novo', 0),
  ('Cartão Memória 256GB', 'novo', 0),
  ('Cartão Memória 256GB MICRO SD', 'novo', 0),
  ('Cartão RFID 125', 'novo', 1400),
  ('Cartão RFID 13,56', 'novo', 50),
  ('Chicote ECO 5', 'novo', 126),
  ('Chicote ECO-LIGHT +S', 'novo', 0),
  ('Chicote FMB920', 'novo', 0),
  ('Chicote FMC130', 'novo', 0),
  ('Chicote FMC150', 'novo', 56),
  ('Chicote FMC650', 'novo', 44),
  ('Chicote Galileo 7x / 10HUB', 'novo', 33),
  ('Chicote Pro4', 'novo', 0),
  ('Chicote Pro5', 'novo', 109),
  ('Chicote SUNTECH Plug Play', 'novo', 0),
  ('Chicote Trace5', 'novo', 0),
  ('Chip Arqia M2M', 'novo', 0),
  ('Chip Arqia Voz e Dados', 'novo', 0),
  ('Chip Claro M2M', 'novo', 0),
  ('Chip Claro Voz e Dados', 'novo', 0),
  ('Chip Vivo M2M', 'novo', 9),
  ('Chip Vivo Voz e Dados', 'novo', 10),
  ('Conversor locomotiva 1 Amper', 'novo', 0),
  ('Conversor locomotiva 15 Amper', 'novo', 0),
  ('Conversor locomotiva 3 Amper', 'novo', 0),
  ('DashCAM', 'vivo', 4),
  ('DashCAM', 'claro', 0),
  ('DashCAM', 'novo', 0),
  ('MDVR 5404', 'vivo', 24),
  ('MDVR 5404', 'claro', 0),
  ('MDVR 5404', 'novo', 9),
  ('MDVR 3404', 'vivo', 42),
  ('MDVR 3404', 'claro', 6),
  ('MDVR 3404', 'novo', 7),
  ('Extensão cameras MDVR', 'novo', 65),
  ('Extensão cameras DashCAM', 'novo', 245),
  ('Galileo Rotograma falado', 'novo', 105),
  ('KIT CTA Comboio', 'novo', 0),
  ('KIT CTA Posto fixo', 'novo', 0),
  ('Leitor EasyCAN', 'novo', 0),
  ('Leitor RFID 125', 'novo', 0),
  ('Leitor RFID 13,56', 'novo', 125),
  ('Leitor RFID 13,56 / 125', 'novo', 0),
  ('Módulo ECO 5', 'novo', 47),
  ('Módulo ECO 5', 'vivo', 11),
  ('Módulo ECO 5', 'claro', 0),
  ('Módulo ECO 5', 'arqia', 0),
  ('Módulo ECO-LIGHT +S', 'novo', 0),
  ('Módulo ECO-LIGHT +S', 'vivo', 0),
  ('Módulo ECO-LIGHT +S', 'claro', 0),
  ('Módulo ECO-LIGHT +S', 'arqia', 0),
  ('Módulo FMB920', 'novo', 0),
  ('Módulo FMB920', 'vivo', 0),
  ('Módulo FMB920', 'claro', 0),
  ('Módulo FMB920', 'arqia', 0),
  ('Módulo FMC 130', 'novo', 1),
  ('Módulo FMC 130', 'vivo', 7),
  ('Módulo FMC 130', 'claro', 0),
  ('Módulo FMC 130', 'arqia', 0),
  ('Módulo FMC 150', 'novo', 25),
  ('Módulo FMC 150', 'vivo', 26),
  ('Módulo FMC 150', 'claro', 2),
  ('Módulo FMC 150', 'arqia', 0),
  ('Módulo FMC 650', 'novo', 50),
  ('Módulo FMC 650', 'vivo', 11),
  ('Módulo FMC 650', 'claro', 19),
  ('Módulo FMC 650', 'arqia', 0),
  ('Módulo Galileo 7x / 10HUB', 'novo', 3),
  ('Módulo Galileo 7x / 10HUB', 'vivo', 5),
  ('Módulo Galileo 7x / 10HUB', 'claro', 8),
  ('Módulo Galileo 7x / 10HUB', 'arqia', 0),
  ('Módulo GF Pro4', 'novo', 28),
  ('Módulo GF Pro4', 'vivo', 0),
  ('Módulo GF Pro4', 'claro', 0),
  ('Módulo GF Pro4', 'arqia', 0),
  ('Módulo HCV5', 'novo', 0),
  ('Módulo HCV5', 'vivo', 0),
  ('Módulo HCV5', 'claro', 0),
  ('Módulo HCV5', 'arqia', 0),
  ('Módulo PRO5 Lite', 'novo', 114),
  ('Módulo PRO5 Lite', 'vivo', 38),
  ('Módulo PRO5 Lite', 'claro', 13),
  ('Módulo PRO5 Lite', 'arqia', 0),
  ('Módulo SUNTECH PLUG PLAY', 'novo', 0),
  ('Módulo TRACE 5', 'novo', 0),
  ('Módulo TRACE 5', 'vivo', 0),
  ('Módulo TRACE 5', 'claro', 0),
  ('Módulo TRACE 5', 'arqia', 0),
  ('Monitor de alarme (SmartWach)', 'novo', 63),
  ('Relé Bloqueio 12 Volts', 'novo', 36),
  ('Relé Bloqueio 24 Volts', 'novo', 29),
  ('Relé Finder', 'novo', 0),
  ('Sensor Betoneira', 'novo', 1),
  ('Sensor de temperatura', 'novo', 0),
  ('Smartlink Carretinha', 'novo', 0),
  ('Carregador Tablet 4 Vias', 'novo', 26),
  ('Carregador Tablet 10 Vias (Roboflex)', 'novo', 11),
  ('Case Tablet 4 pinos', 'novo', 13),
  ('Case Tablet 10 pinos', 'novo', 11),
  ('Case Tablet Tipo C', 'novo', 5),
  ('Suporte Tablet', 'novo', 29),
  ('Suporte Tablet Ventosa', 'novo', 2),
  ('Switch cabo rede Intelbras', 'novo', 0),
  ('Tablet Multilaser', 'novo', 0),
  ('Tablet Samsung', 'novo', 22),
  ('Plug Carregador Tablet 4 pinos', 'novo', 38),
  ('Plug Carregador Tablet 10 pinos', 'novo', 12),
  ('Antena GPS', 'novo', 25),
  ('Antena GSM Macho', 'novo', 136),
  ('Antena GSM Femea', 'novo', 63),
  ('Antena Wifi', 'novo', 64),
  ('Chicote MDVR', 'novo', 12),
  ('Chicote DashCAM', 'novo', 5);

-- ---------------------------------------------------------------- 1. Nomes e itens novos
do $$
declare r record;
begin
  for r in select * from (values
      ('Carregador DC/DC 12V Tablet Roboflex', 'Carregador Tablet 10 Vias (Roboflex)'),
      ('Carregador DC/DC 12V Tablet', 'Carregador Tablet 10 Vias (Roboflex)'),
      ('Suporte Ventosa', 'Suporte Tablet Ventosa'),
      ('Galielo Rotograma falado', 'Galileo Rotograma falado'),
      ('Extensão cameras', 'Extensão cameras MDVR')) as v(velho, novo)
  loop
    if exists (select 1 from produto where nome = r.velho) and not exists (select 1 from produto where lower(nome) = lower(r.novo)) then
      update produto set nome = r.novo where nome = r.velho;
      raise notice 'Renomeado: % -> %', r.velho, r.novo;
    end if;
  end loop;
end $$;

insert into produto (nome, categoria_id)
select 'Carregador Tablet 4 Vias', (select id from categoria where nome = 'Tablets e acessórios')
 where not exists (select 1 from produto where lower(nome) = lower('Carregador Tablet 4 Vias'));

-- chicotes sem categoria vão para a dos chicotes
update produto set categoria_id = (select id from categoria where nome = 'Cabos, chicotes e conexões')
 where categoria_id is null and nome like 'Chicote %';

do $$ declare v text; begin
  select string_agg(distinct p.nome, ', ') into v from _planilha p
   where not exists (select 1 from produto x where x.nome = p.nome);
  if v is not null then raise exception 'Itens da planilha que não existem no catálogo: %', v; end if;
  select string_agg(distinct p.nome, ', ') into v from _planilha p join produto x on x.nome = p.nome
   where p.condicao <> 'novo' and not x.usa_chip;
  if v is not null then raise exception 'Itens com saldo por chip que não usam chip: %', v; end if;
end $$;

-- itens da planilha ficam ativos
update produto set ativo = true where not ativo and nome in (select nome from _planilha);

-- ---------------------------------------------------------------- 2. Fora da planilha: desativa ou exclui
do $$
declare r record; v_exc text; v_des text;
begin
  for r in select id, nome from produto where ativo and nome not in (select nome from _planilha) order by nome loop
    if not exists (select 1 from item_associado where associado_id = r.id) then
      begin
        delete from item_associado where produto_id = r.id;
        delete from produto where id = r.id;
        v_exc := concat_ws(', ', v_exc, r.nome);
        continue;
      exception when foreign_key_violation then
        null;
      end;
    end if;
    update produto set ativo = false where id = r.id;
    v_des := concat_ws(', ', v_des, r.nome);
  end loop;
  raise notice 'Fora da planilha - excluídos: %', coalesce(v_exc, 'nenhum');
  raise notice 'Fora da planilha - desativados: %', coalesce(v_des, 'nenhum');
end $$;

-- ---------------------------------------------------------------- 3. Kit de tablet
delete from item_associado ia using produto t, produto c
 where ia.produto_id = t.id and ia.associado_id = c.id
   and t.nome in ('Tablet Samsung', 'Tablet Multilaser') and c.nome = 'Carregador Tablet 10 Vias (Roboflex)';

insert into item_associado (produto_id, associado_id, quantidade, opcional, grupo)
select p.id, a.id, 1, false, v.grupo
  from (values
    ('Tablet Samsung', 'Suporte Tablet', 'Suporte'), ('Tablet Samsung', 'Suporte Tablet Ventosa', 'Suporte'),
    ('Tablet Samsung', 'Case Tablet 4 pinos', 'Case'), ('Tablet Samsung', 'Case Tablet 10 pinos', 'Case'),
    ('Tablet Samsung', 'Case Tablet Tipo C', 'Case'),
    ('Tablet Multilaser', 'Suporte Tablet', 'Suporte'), ('Tablet Multilaser', 'Suporte Tablet Ventosa', 'Suporte'),
    ('Tablet Multilaser', 'Case Tablet 4 pinos', 'Case'), ('Tablet Multilaser', 'Case Tablet 10 pinos', 'Case'),
    ('Tablet Multilaser', 'Case Tablet Tipo C', 'Case'),
    ('Case Tablet 4 pinos', 'Plug Carregador Tablet 4 pinos', null), ('Case Tablet 4 pinos', 'Carregador Tablet 4 Vias', null),
    ('Case Tablet 10 pinos', 'Plug Carregador Tablet 10 pinos', null),
    ('Case Tablet 10 pinos', 'Carregador Tablet 10 Vias (Roboflex)', null)
  ) as v(prod, assoc, grupo)
  join produto p on p.nome = v.prod
  join produto a on a.nome = v.assoc
on conflict (produto_id, associado_id) do update set quantidade = 1, opcional = false, grupo = excluded.grupo;

delete from item_associado ia using produto c where ia.produto_id = c.id and c.nome = 'Case Tablet Tipo C';

-- ---------------------------------------------------------------- 4. Saldo livre de Nova Lima = planilha
do $$
declare v_nl integer; v_adm uuid; v_mov bigint; v_n integer;
begin
  select id into v_nl from local where nome = 'Nova Lima' and tipo = 'estoque';
  if v_nl is null then raise exception 'Estoque Nova Lima não encontrado'; end if;
  select id into v_adm from usuario where perfil = 'admin' and ativo order by criado_em limit 1;

  create temp table _dif on commit drop as
  with alvo as (
    -- planilha; condições de chip que a planilha não lista (ex.: MDVR Arqia) ficam 0
    select x.id as produto_id, p.condicao, p.qtd from _planilha p join produto x on x.nome = p.nome
    union all
    select x.id, c.condicao, 0 from produto x cross join (values ('novo'), ('claro'), ('vivo'), ('arqia')) c(condicao)
     where x.usa_chip and x.nome in (select nome from _planilha)
       and not exists (select 1 from _planilha p where p.nome = x.nome and p.condicao = c.condicao)
  ), atual as (
    select e.produto_id, e.condicao::text as condicao, sum(e.delta) as qtd
      from efeito_estoque e where e.local_id = v_nl and e.reservado_unidade_id is null group by 1, 2
  )
  select a.produto_id, a.condicao, a.qtd - coalesce(t.qtd, 0) as delta
    from alvo a left join atual t on t.produto_id = a.produto_id and t.condicao = a.condicao
   where a.qtd - coalesce(t.qtd, 0) <> 0;

  select count(*) into v_n from _dif;
  if v_n = 0 then raise notice 'Saldo de Nova Lima já igual à planilha: nada gravado'; return; end if;
  if v_adm is null then
    raise notice 'Nenhum administrador cadastrado: saldo da planilha NÃO gravado (% linhas). Rode este arquivo de novo depois de criar o administrador.', v_n;
    return;
  end if;

  insert into movimentacao (tipo, status, data, local_destino_id, observacao, criado_por)
  values ('AJUSTE', 'registrado', fn_hoje(), v_nl, 'Inventário oficial (planilha 11/2026)', v_adm)
  returning id into v_mov;
  insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade)
  select v_mov, produto_id, condicao::condicao_item, delta from _dif;
  perform fn_verificar_saldo(array[v_nl]);
  raise notice 'Ajuste % gravado em Nova Lima: % linhas', v_mov, v_n;
end $$;

commit;
