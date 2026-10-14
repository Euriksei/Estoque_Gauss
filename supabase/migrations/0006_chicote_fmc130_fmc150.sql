-- Migração 0006: módulos FMC 130 e FMC 150 levam o chicote correspondente (sugestão editável).
-- Se já rodou o seed.sql, este arquivo basta; ele não duplica nada.
insert into item_associado (produto_id, associado_id, quantidade)
select p.id, a.id, 1 from produto p join produto a on a.nome = 'Chicote ' || replace(p.nome, ' ', '')
 where p.nome in ('FMC 130', 'FMC 150')
on conflict do nothing;
