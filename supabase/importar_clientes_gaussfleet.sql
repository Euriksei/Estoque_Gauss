-- Importa os clientes do GaussFleet (coluna Customer), agrupados por empresa.
-- Lista revisada em docs/clientes-gaussfleet.csv.
-- Idempotente: insere cliente e unidade so se nao existir (comparacao sem
-- diferenciar maiusculas/acentos). Nada e apagado nem renomeado.
begin;

create temp table _gf (cliente text, unidade text) on commit drop;
insert into _gf (cliente, unidade) values
  ('AngloGold', 'Principal'),
  ('Aperam', 'Principal'),
  ('Aperam', 'Pátios'),
  ('ArcelorMittal', 'Principal'),
  ('ArcelorMittal', 'Bobinas'),
  ('ArcelorMittal', 'Ferroviário'),
  ('Ardo Construtora', 'Principal'),
  ('Armac', 'Principal'),
  ('BASF', 'Principal'),
  ('BASF', 'Pátios'),
  ('Bemon Engenharia', 'Principal'),
  ('BPort', 'Principal'),
  ('Cal Trevo', 'Principal'),
  ('Cavalca Construções e Mineração', 'Principal'),
  ('CBSI', 'Principal'),
  ('CHB Rental', 'Principal'),
  ('Construtora Terraço', 'Principal'),
  ('CSN', 'Cimentos'),
  ('CSN', 'Cimentos UPV - Pátios'),
  ('CSN', 'ERSA'),
  ('CSN', 'Ferroviário'),
  ('CSN', 'Frota Leve'),
  ('CSN', 'Mineração'),
  ('CSN', 'Mineração Casa de Pedra'),
  ('CSN', 'Rodoviário'),
  ('CSN', 'Steel Demo'),
  ('CSN', 'Tecar'),
  ('CSN', 'Tecon'),
  ('CSN', 'UPV Pátios'),
  ('Damasco Penna', 'Principal'),
  ('Eldorado Brasil Celulose', 'Principal'),
  ('Equimac', 'Principal'),
  ('Frum', 'Principal'),
  ('FTL', 'Principal'),
  ('GaussFleet', 'Principal'),
  ('Gerdau', 'Araçariguama (GSP)'),
  ('Gerdau', 'Açonorte'),
  ('Gerdau', 'Açonorte Pátios'),
  ('Gerdau', 'Cearense'),
  ('Gerdau', 'Charqueadas'),
  ('Gerdau', 'Charqueadas Pátios'),
  ('Gerdau', 'Cosigua'),
  ('Gerdau', 'Cosigua - Gestão de Pátios'),
  ('Gerdau', 'Cumbica'),
  ('Gerdau', 'Divinópolis'),
  ('Gerdau', 'ES - Pátios'),
  ('Gerdau', 'Midlothian'),
  ('Gerdau', 'Midlothian Yards'),
  ('Gerdau', 'Mineração'),
  ('Gerdau', 'Ouro Branco'),
  ('Gerdau', 'Ouro Branco Ferroviário'),
  ('Gerdau', 'Pindamonhangaba'),
  ('Gerdau', 'Riograndense'),
  ('Gerdau', 'São José dos Campos'),
  ('Gerdau', 'São José dos Campos - Gestão de Pátios'),
  ('Gerdau', 'São Paulo (GSP) - Pátios'),
  ('Gerdau', 'Vitória'),
  ('Grupo Lara', 'Principal'),
  ('Grupo Renova', 'Principal'),
  ('JSL', 'Principal'),
  ('Lafaete Locações', 'Principal'),
  ('Logimodal', 'Principal'),
  ('Lokamig', 'Principal'),
  ('M3A', 'Principal'),
  ('Makro', 'Principal'),
  ('Mills', 'Principal'),
  ('Milplan', 'Principal'),
  ('PH Transportes', 'Principal'),
  ('Santos Brasil', 'Principal'),
  ('Simak', 'Principal'),
  ('Sinobras', 'Principal'),
  ('Skava Minas', 'Principal'),
  ('Super San', 'Principal'),
  ('Suzano', 'Principal'),
  ('TB Green', 'Principal'),
  ('Terrabel', 'Principal'),
  ('TLOC Locação de Equipamentos', 'Principal'),
  ('Tora Transportes', 'Principal'),
  ('Tradimaq', 'Principal'),
  ('Traterra Construções', 'Principal'),
  ('Usiminas', 'Cubatão'),
  ('Usiminas', 'Cubatão Ferroviário'),
  ('Usiminas', 'Ipatinga'),
  ('Usiminas', 'Ipatinga - Ferroviário'),
  ('Usiminas', 'Ipatinga - Obras'),
  ('Usiminas', 'Ipatinga Almoxarifado Central'),
  ('Usiminas', 'Mecânica'),
  ('Vale', 'Principal'),
  ('Vallourec', 'Principal'),
  ('Vallourec', 'Pátios'),
  ('Veracel', 'Principal'),
  ('VIX Logística', 'Principal'),
  ('VIX Logística', 'TPS'),
  ('Wamag', 'Principal'),
  ('Wilson Sons', 'Principal');

-- chave de comparacao: minusculas, sem acentos, espacos normalizados
create or replace function pg_temp.gf_chave(t text) returns text language sql immutable as $$
  select regexp_replace(trim(translate(lower(t),
    'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn')), '\s+', ' ', 'g')
$$;

insert into cliente (nome)
select distinct g.cliente from _gf g
where not exists (select 1 from cliente c where pg_temp.gf_chave(c.nome) = pg_temp.gf_chave(g.cliente));

insert into unidade_cliente (cliente_id, nome)
select distinct on (c.id, pg_temp.gf_chave(g.unidade)) c.id, g.unidade
from _gf g
join lateral (select c.id from cliente c where pg_temp.gf_chave(c.nome) = pg_temp.gf_chave(g.cliente)
              order by c.id limit 1) c on true
where not exists (select 1 from unidade_cliente u
                  where u.cliente_id = c.id and pg_temp.gf_chave(u.nome) = pg_temp.gf_chave(g.unidade));

commit;
