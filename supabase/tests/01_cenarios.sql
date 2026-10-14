\set QUIET on
\pset format unaligned
\pset tuples_only on
-- usuários
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','admin@x','{"nome":"Admin"}'),
 ('00000000-0000-0000-0000-0000000000b1','nl@x','{"nome":"Op NL"}'),
 ('00000000-0000-0000-0000-0000000000b2','sbc@x','{"nome":"Op SBC"}'),
 ('00000000-0000-0000-0000-0000000000c1','tec@x','{"nome":"Tec"}'),
 ('00000000-0000-0000-0000-0000000000d1','cons@x','{"nome":"Cons"}');
update usuario set ativo=true, perfil='admin' where email='admin@x';
update usuario set ativo=true, perfil='operador' where email in ('nl@x','sbc@x');
update usuario set ativo=true, perfil='tecnico' where email='tec@x';
update usuario set ativo=true where email='cons@x';
insert into usuario_local select u.id, l.id from usuario u, local l where (u.email='nl@x' and l.nome='Nova Lima') or (u.email='sbc@x' and l.nome like 'São%');
insert into tecnico (nome,vinculo,usuario_id) select 'Tec CLT','clt',id from usuario where email='tec@x';
insert into tecnico (nome,vinculo) values ('Ze PJ','pj');
insert into local (nome,tipo,tecnico_id,base_id) select 'Carro Tec','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Tec CLT';
insert into local (nome,tipo,tecnico_id,base_id) select 'Estoque Ze PJ','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Ze PJ';
insert into cliente(nome) values ('Gerdau'),('CSN'); insert into unidade_cliente(cliente_id,nome) select id,'Ouro Branco' from cliente where nome='Gerdau'; insert into unidade_cliente(cliente_id,nome) select id,'Mineração' from cliente where nome='CSN';
create temp table ids as select
 (select id from local where nome='Nova Lima') nl, (select id from local where nome like 'São%') sbc, (select id from local where nome='Carro Tec') car,
 (select id from produto where nome='FMC 650') fmc, (select id from produto where nome='Chicote Galileo') chi,
 (select id from unidade_cliente where nome='Ouro Branco') u1, (select id from unidade_cliente where nome='Mineração') u2;
grant select on ids to authenticated;
set role authenticated;
\echo '--- 1. Op NL: compra 100 FMC650 no Nova Lima'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'numero_nf','NF1','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',100)))) is not null from ids;
\echo '--- 2. saída de 150 deve falhar'
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',150)))) from ids;
\echo '--- 3. Op NL transfere 10 p/ SBC (em trânsito) e saldos'
\set ON_ERROR_STOP on
select criar_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','sedex','codigo_rastreio','AB123','prazo_chegada','2026-10-20','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',10)))) as transf from ids \gset
select 'NL=' || coalesce((select sum(quantidade) from saldo where local_id=nl and produto_id=fmc),0) || ' SBC=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc),0) || ' (op NL nao ve SBC) em_transito=' || (select count(*) from transferencias_em_transito) from ids;
\set ON_ERROR_STOP off
\echo '--- Op NL tenta confirmar recebimento do próprio envio (deve falhar)'
select confirmar_recebimento(:transf);
\set ON_ERROR_STOP on
\echo '--- Op SBC confirma'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:transf);
select 'SBC=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc),0) from ids;
\echo '--- 4. Técnico pede material, Op NL atende, técnico confirma'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_solicitacao(jsonb_build_object('observacao','preciso','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',8)))) as sol from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol, jsonb_build_object('origem_id',nl,'modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',8)))) as t2 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select 'tecnico ve saldo carro antes=' || coalesce((select sum(quantidade) from saldo where local_id=car),0) || ' saldo NL visível p/ técnico=' || (select count(*) from saldo where local_id=nl) from ids;
select confirmar_recebimento(:t2);
select 'carro=' || (select sum(quantidade) from saldo where local_id=car and produto_id=fmc) || ' linhas_saldo_visiveis=' || (select count(*) from saldo) from ids;
\echo '--- 5. Dedicado: Op NL manda 5 reservados p/ Ouro Branco ao técnico; técnico entrega'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select criar_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservar_para_unidade_id',u1)))) as t3 from ids \gset
select 'NL livre=' || (select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id is null) || ' posição dedicado: ' || (select string_agg(situacao||':'||quantidade, ',') from dedicados_posicao) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select confirmar_recebimento(:t3);
select 'carro livre=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id is null) || ' reservado=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id is not null) from ids;
\set ON_ERROR_STOP off
\echo '--- técnico tenta usar reservado para OUTRA unidade (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservado_unidade_id',u1)))) from ids;
\echo '--- técnico tenta consumo interno (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- técnico tenta dar baixa em estoque do Nova Lima (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- técnico livre: reservado sendo usado como livre (saída de 9 > 8 livres) deve falhar'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',9)))) from ids;
\set ON_ERROR_STOP on
\echo '--- técnico entrega os 5 reservados ao Ouro Branco (sem chamado)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u1,'finalidade','mobilizacao','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservado_unidade_id',u1)))) is not null from ids;
select 'dedicado: ' || (select string_agg(situacao||':'||quantidade, ',') from dedicados_posicao) || ' hist=' || (select count(*) from dedicados_historico);
\echo '--- saída com modo de envio: operador NL sem modo (deve falhar), modo técnico sem técnico (deve falhar), modo técnico PJ sem login (ok)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'chamado_url','','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2)))) is not null from ids;
select 'saídas com técnico: ' || (select string_agg(coalesce(t.nome,'-')||'/'||m.modo_envio, ', ' order by m.id) from movimentacao m left join tecnico t on t.id=m.tecnico_id where m.tipo='SAIDA_CLIENTE');
\echo '--- 6. Dedicado por compra e ajuste (Op NL), depois envio ao estoque do Ze PJ (sem login) confirmado por operador'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'numero_nf','NF2','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',10,'reservar_para_unidade_id',u2)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','contagem','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',2,'reservar_para_unidade_id',u2)))) is not null from ids;
select 'NL chicote livre=' || coalesce((select sum(quantidade) from saldo where local_id=nl and produto_id=chi and reservado_unidade_id is null),0) || ' dedicado Mineração=' || (select sum(quantidade) from saldo where local_id=nl and produto_id=chi and reservado_unidade_id=u2) from ids;
\set ON_ERROR_STOP off
\echo '--- criar dedicado em consumo interno (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1,'reservar_para_unidade_id',u2)))) from ids;
\echo '--- consumo do estoque livre não toca no dedicado (saldo livre é 0; deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
select criar_transferencia(jsonb_build_object('origem_id',nl,'destino_id',(select id from local where nome='Estoque Ze PJ'),'modo_envio','correios','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',4,'reservado_unidade_id',u2)))) as t4 from ids \gset
\echo '--- Op SBC (sem relação com a transferência) tenta confirmar (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
\set ON_ERROR_STOP off
select confirmar_recebimento(:t4);
\set ON_ERROR_STOP on
\echo '--- Op NL (origem e base do técnico) confirma pelo Ze PJ'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select confirmar_recebimento(:t4);
select 'Ze dedicado=' || (select sum(quantidade) from saldo where local_id=(select id from local where nome='Estoque Ze PJ') and reservado_unidade_id=u2) || ' (Op NL não vê o estoque do Ze; confira como admin) NL dedicado=' || (select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u2) from ids;
\echo '--- dedicado Mineração para outra unidade (deve falhar); depois entrega ao cliente certo, por técnico Ze PJ'
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1,'reservado_unidade_id',u2)))) from ids;
\set ON_ERROR_STOP on
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',3,'reservado_unidade_id',u2)))) is not null from ids;
select 'NL dedicado restante=' || (select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u2) from ids;
\echo '--- consulta não escreve; vê tudo'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens','[]'::jsonb)) from ids;
insert into produto(nome) values ('x');
\set ON_ERROR_STOP on
select 'consulta vê saldo linhas=' || (select count(*) from saldo);
\echo '--- operador não estorna; admin estorna'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
select estornar_movimentacao(1,'teste');
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\echo '--- admin estorna a compra de 100 (deve falhar: saldo já usado)'
\set ON_ERROR_STOP off
select estornar_movimentacao(1,'erro de digitação');
\set ON_ERROR_STOP on
select 'auditoria linhas=' || (select count(*) from auditoria);
