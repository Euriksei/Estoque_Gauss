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
