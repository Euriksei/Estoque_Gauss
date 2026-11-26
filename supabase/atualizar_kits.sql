-- Kits (spec3): catálogo novo de periféricos e kits em item_associado ("Com kit" na tela).
-- Rode uma vez depois de atualizar_2026_11_25.sql. Idempotente.
-- item_associado ganha: opcional (aparece desmarcado na tela) e grupo (mesmo grupo = escolhe um só).
-- A case de tablet tem o seu plug como associado: ao escolher a case, a tela traz o plug dela (1 nível).
begin;

-- ---------------------------------------------------------------- 1. Catálogo
update produto set nome = 'MDVR 3404' where nome = 'MDVR Intelbras 3404'
   and not exists (select 1 from produto where nome = 'MDVR 3404');
update produto set nome = 'MDVR 5404' where nome = 'MDVR Intelbras 5404'
   and not exists (select 1 from produto where nome = 'MDVR 5404');

insert into produto (nome, categoria_id)
select v.nome, (select id from categoria where nome = v.cat)
  from (values
    ('Antena GPS', 'Comunicação e conectividade'), ('Antena GSM Macho', 'Comunicação e conectividade'),
    ('Antena GSM Femea', 'Comunicação e conectividade'), ('Antena Wifi', 'Comunicação e conectividade'),
    ('Chicote MDVR', 'Cabos, chicotes e conexões'), ('Chicote DashCAM', 'Cabos, chicotes e conexões'),
    ('Case Tablet 4 pinos', 'Tablets e acessórios'), ('Case Tablet 10 pinos', 'Tablets e acessórios'),
    ('Case Tablet Tipo C', 'Tablets e acessórios'), ('Suporte Tablet', 'Tablets e acessórios'),
    ('Plug Carregador Tablet 4 pinos', 'Tablets e acessórios'), ('Plug Carregador Tablet 10 pinos', 'Tablets e acessórios')
  ) as v(nome, cat)
 where not exists (select 1 from produto p where lower(p.nome) = lower(v.nome));

-- Saem: apaga se nunca foi usado; com histórico (movimentação, saldo, pedido...) fica inativo.
do $$
declare r record;
begin
  for r in select id, nome from produto
            where nome in ('Case Tablet Samsung', 'Case Tablet Multilaser', 'Suporte Tablet Samsung', 'Suporte Tablet Multilaser')
  loop
    delete from item_associado where produto_id = r.id or associado_id = r.id;
    begin
      delete from produto where id = r.id;
    exception when foreign_key_violation then
      update produto set ativo = false where id = r.id;
      raise notice '% tem movimentação/saldo/pedido: ficou inativo, não foi apagado', r.nome;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------- 2. Kits em item_associado
alter table item_associado add column if not exists opcional boolean not null default false;
alter table item_associado add column if not exists grupo text;

insert into item_associado (produto_id, associado_id, quantidade, opcional, grupo)
select p.id, a.id, 1, v.opcional, v.grupo
  from (values
    ('Módulo FMC 650', 'Chicote FMC650', false, null), ('Módulo FMC 650', 'Antena GPS', false, null),
    ('Módulo FMC 650', 'Antena GSM Femea', false, null),
    ('Módulo Galileo 7x / 10HUB', 'Chicote Galileo 7x / 10HUB', false, null), ('Módulo Galileo 7x / 10HUB', 'Antena GPS', false, null),
    ('Módulo Galileo 7x / 10HUB', 'Antena GSM Macho', false, null), ('Módulo Galileo 7x / 10HUB', 'Antena Wifi', true, null),
    ('MDVR 3404', 'Chicote MDVR', false, null), ('MDVR 3404', 'Antena GPS', false, null),
    ('MDVR 3404', 'Antena GSM Macho', false, null), ('MDVR 3404', 'Antena Wifi', true, null),
    ('MDVR 5404', 'Antena GPS', false, null), ('MDVR 5404', 'Antena GSM Macho', false, null),
    ('MDVR 5404', 'Antena Wifi', true, null),
    ('DashCAM', 'Chicote DashCAM', false, null),
    ('Camera contexto DVR', 'Extensão cameras', false, null), ('Camera Fadiga DVR', 'Extensão cameras', false, null),
    ('Camera frontal (Adas) DVR', 'Extensão cameras', false, null),
    ('Camera Contexto DashCAM', 'Extensão cameras DashCAM', false, null), ('Camera Fadiga DashCAM', 'Extensão cameras DashCAM', false, null),
    ('Camera frontal (Adas) DashCAM', 'Extensão cameras DashCAM', false, null),
    ('Camera IP', 'Cabo rede', false, null),
    ('Tablet Samsung', 'Suporte Tablet', false, null), ('Tablet Samsung', 'Carregador DC/DC 12V Tablet Roboflex', false, null),
    ('Tablet Samsung', 'Case Tablet 4 pinos', false, 'Case'), ('Tablet Samsung', 'Case Tablet 10 pinos', false, 'Case'),
    ('Tablet Samsung', 'Case Tablet Tipo C', false, 'Case'),
    ('Tablet Multilaser', 'Suporte Tablet', false, null), ('Tablet Multilaser', 'Carregador DC/DC 12V Tablet Roboflex', false, null),
    ('Tablet Multilaser', 'Case Tablet 4 pinos', false, 'Case'), ('Tablet Multilaser', 'Case Tablet 10 pinos', false, 'Case'),
    ('Tablet Multilaser', 'Case Tablet Tipo C', false, 'Case'),
    ('Case Tablet 4 pinos', 'Plug Carregador Tablet 4 pinos', false, null),
    ('Case Tablet 10 pinos', 'Plug Carregador Tablet 10 pinos', false, null)
  ) as v(prod, assoc, opcional, grupo)
  join produto p on p.nome = v.prod
  join produto a on a.nome = v.assoc
on conflict (produto_id, associado_id) do update
  set quantidade = 1, opcional = excluded.opcional, grupo = excluded.grupo;

-- Demais módulos: ficam só com o chicote que já tinham (nenhuma antena).
-- Conferência: avisa se algum nome da lista não existe no catálogo.
do $$ declare v text; begin
  select string_agg(n, ', ') into v from unnest(array['Módulo FMC 650','Módulo Galileo 7x / 10HUB','MDVR 3404','MDVR 5404',
    'DashCAM','Camera contexto DVR','Camera Fadiga DVR','Camera frontal (Adas) DVR','Camera Contexto DashCAM',
    'Camera Fadiga DashCAM','Camera frontal (Adas) DashCAM','Camera IP','Tablet Samsung','Tablet Multilaser',
    'Extensão cameras','Extensão cameras DashCAM','Cabo rede','Chicote FMC650','Chicote Galileo 7x / 10HUB',
    'Carregador DC/DC 12V Tablet Roboflex']) n
   where not exists (select 1 from produto where nome = n);
  if v is not null then raise notice 'Itens não encontrados (kit não criado para eles): %', v; end if;
end $$;

commit;
