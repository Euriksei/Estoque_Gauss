-- Usuários e cadastros usados pelos testes de tela (senha de todos: teste123).
create role authenticator login password 'x' noinherit; grant authenticated, anon to authenticator;
alter table auth.users add column if not exists senha text;
insert into auth.users (id,email,raw_user_meta_data,senha) values
 ('00000000-0000-0000-0000-00000000000a','admin@x.com','{"nome":"Admin Teste"}','teste123'),
 ('00000000-0000-0000-0000-0000000000b1','nl@x.com','{"nome":"Operador NL"}','teste123'),
 ('00000000-0000-0000-0000-0000000000b2','sbc@x.com','{"nome":"Operador SBC"}','teste123'),
 ('00000000-0000-0000-0000-0000000000c1','tec@x.com','{"nome":"Tecnico Joao"}','teste123'),
 ('00000000-0000-0000-0000-0000000000d1','cons@x.com','{"nome":"Consulta"}','teste123'),
 ('00000000-0000-0000-0000-0000000000e1','ag@x.com','{"nome":"Agendamento"}','teste123');
update usuario set ativo=true, perfil='operador' where email in ('nl@x.com','sbc@x.com');
update usuario set ativo=true, perfil='tecnico' where email='tec@x.com';
update usuario set ativo=true, perfil='consulta' where email='cons@x.com';
update usuario set ativo=true, perfil='agendamento' where email='ag@x.com';
insert into usuario_local select u.id, l.id from usuario u, local l where (u.email='nl@x.com' and l.nome='Nova Lima') or (u.email='sbc@x.com' and l.nome like 'São%');
insert into tecnico (nome,vinculo,usuario_id) select 'Joao CLT','clt',id from usuario where email='tec@x.com';
insert into tecnico (nome,vinculo) values ('Ze PJ','pj');
insert into local (nome,tipo,tecnico_id,base_id) select 'Estoque técnico CLT - Joao CLT','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Joao CLT';
insert into local (nome,tipo,tecnico_id,base_id) select 'Estoque técnico PJ - Ze PJ','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Ze PJ';
insert into cliente(nome) values ('Gerdau'),('CSN'); insert into unidade_cliente(cliente_id,nome) select id,'Ouro Branco' from cliente where nome='Gerdau'; insert into unidade_cliente(cliente_id,nome) select id,'Mineração' from cliente where nome='CSN';
