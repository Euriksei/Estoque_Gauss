\set QUIET on
\pset format unaligned
\pset tuples_only on
-- usuários
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','admin@x','{"nome":"Admin"}'),
 ('00000000-0000-0000-0000-0000000000b1','nl@x','{"nome":"Op NL"}'),
 ('00000000-0000-0000-0000-0000000000b2','sbc@x','{"nome":"Op SBC"}'),
 ('00000000-0000-0000-0000-0000000000c1','tec@x','{"nome":"Tec"}'),
 ('00000000-0000-0000-0000-0000000000d1','cons@x','{"nome":"Cons"}'),
 ('00000000-0000-0000-0000-0000000000e1','ag@x','{"nome":"Agenda"}');
update usuario set ativo=true, perfil='admin' where email='admin@x';
update usuario set ativo=true, perfil='operador' where email in ('nl@x','sbc@x');
update usuario set ativo=true, perfil='tecnico' where email='tec@x';
update usuario set ativo=true where email='cons@x';
update usuario set ativo=true, perfil='agendamento' where email='ag@x';
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
insert into usuario_local (usuario_id, local_id) select '00000000-0000-0000-0000-0000000000e1', sbc from ids;  -- estoque do agendamento
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
\echo '--- 7. Solicitações: técnico pede só da base dele; agendamento pede transferência mas não atende nem movimenta'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_solicitacao(jsonb_build_object('origem_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2)))) as sol2 from ids \gset
select 'pedido do técnico: origem=' || (select l.nome from solicitacao s join local l on l.id=s.origem_id where s.id=:sol2) || ' (tentou SBC) destino=' || (select l.nome from solicitacao s join local l on l.id=s.destino_id where s.id=:sol2);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select criar_solicitacao(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',3)))) as sol3 from ids \gset
select 'agendamento vê solicitações=' || (select count(*) from solicitacao) || ' e saldo linhas>0=' || ((select count(*) from saldo) > 0);
\set ON_ERROR_STOP off
\echo '--- agendamento tenta atender, transferir e registrar (devem falhar)'
select atender_solicitacao(:sol3, '{"modo_envio":"correios"}'::jsonb);
select criar_transferencia(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento sem origem (deve falhar)'
select criar_solicitacao(jsonb_build_object('destino_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- Op SBC não opera Nova Lima: não atende o pedido do técnico (origem NL) (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select atender_solicitacao(:sol2, '{"modo_envio":"correios"}'::jsonb);
\set ON_ERROR_STOP on
\echo '--- Op NL atende o pedido do técnico (origem NL, destino carro)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol2, jsonb_build_object('modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',(select fmc from ids),'quantidade',2)))) is not null;
select 'transferência em trânsito para o carro: ' || (select count(*) from transferencias_em_transito t where t.local_destino_id=(select car from ids));
\echo '--- 8. Solicitação para estoque dedicado: técnico pede 2 dedicados à Mineração; Op NL atende; chegam como dedicados'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_solicitacao(jsonb_build_object('itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2,'reservar_para_unidade_id',u2), jsonb_build_object('produto_id',fmc,'quantidade',1)))) as sol4 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol4, '{"modo_envio":"tecnico"}'::jsonb) as t5 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select confirmar_recebimento(:t5);
select 'carro dedicado Mineração=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id=u2) from ids;
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

\echo '--- 9. Aceitar solicitação: aberta -> em_producao (prazo 1 dia); técnico não aceita; só operador/admin cancelam depois'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_solicitacao(jsonb_build_object('itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) as sol5 from ids \gset
\set ON_ERROR_STOP off
\echo '--- técnico tenta aceitar a própria solicitação (deve falhar)'
select aceitar_solicitacao(:sol5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select aceitar_solicitacao(:sol5);
select 'status=' || status::text || ' prazo≈1 dia: ' || (prazo_producao - now() between interval '23 hours' and interval '25 hours') from solicitacao where id=:sol5;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
\set ON_ERROR_STOP off
\echo '--- técnico tenta cancelar solicitação já em produção (deve falhar)'
select cancelar_solicitacao(:sol5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol5, '{"modo_envio":"tecnico"}'::jsonb) is not null;
select 'status final=' || status::text from solicitacao where id=:sol5;

\echo '--- 10. Chips: módulo com chip, instalar chip avulso, trocar de operadora, descartar chip ruim'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select (select id from local where nome='Nova Lima') as nl2, (select id from produto where nome='FMC 150') as fm, (select id from produto where nome='Chip Claro M2M') as chc, (select id from produto where nome='Chip Vivo M2M') as chv, (select id from produto where nome='Buzzer') as bz \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',:nl2,'itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',10,'condicao','novo'),jsonb_build_object('produto_id',:fm,'quantidade',4,'condicao','claro'),jsonb_build_object('produto_id',:chc,'quantidade',6),jsonb_build_object('produto_id',:chv,'quantidade',3)))) is not null;
select 'FMC150 sem chip=' || coalesce((select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='novo' and reservado_unidade_id is null),0) || ' claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro');
\echo '--- instalar Claro em 3 módulos sem chip (chip avulso Claro 6 -> 3)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',3,'de','novo','para','claro')) is not null;
select 'sem chip=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='novo' and reservado_unidade_id is null) || ' claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro') || ' chipClaro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chc);
\echo '--- trocar Claro por Vivo em 2 módulos: Claro volta ao avulso (+2), Vivo avulso -2'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',2,'de','claro','para','vivo')) is not null;
select 'claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro') || ' vivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='vivo') || ' chipClaro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chc) || ' chipVivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chv);
\echo '--- módulo não comunicou: tira o chip Vivo e descarta (módulo volta a sem chip, chip avulso não volta)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','vivo','para','novo','chip_retirado','descartar','observacao','não comunicou no teste')) is not null;
select 'vivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='vivo') || ' chipVivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chv);
\set ON_ERROR_STOP off
\echo '--- descartar sem motivo (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','claro','para','novo','chip_retirado','descartar')) is not null;
\echo '--- instalar chip sem chip avulso suficiente (deve falhar): 5 Vivo, só restam 1'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',5,'de','novo','para','vivo')) is not null;
\echo '--- trocar chip em item que não usa chip (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:bz,'quantidade',1,'de','novo','para','claro')) is not null;
\echo '--- saída de módulo com chip que não existe em estoque (deve falhar): 9 Vivo'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',:nl2,'itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',9,'condicao','vivo')))) is not null;
\echo '--- técnico não troca chip (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','novo','para','claro')) is not null;
\set ON_ERROR_STOP on

\echo '--- 11. Regras de solicitação: agendamento, cliente, dedicado e quem dá andamento'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select 'agendamento: origem=' || (select l.nome from solicitacao s join local l on l.id=s.origem_id where s.id=:sol3) || ' destino carro, cliente=' || (select un.nome from solicitacao s join unidade_cliente un on un.id=s.unidade_id where s.id=:sol3);
\set ON_ERROR_STOP off
\echo '--- agendamento tenta estoque -> estoque (deve falhar)'
select criar_solicitacao(jsonb_build_object('destino_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento sem cliente (deve falhar)'
select criar_solicitacao(jsonb_build_object('destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento tenta criar dedicado (deve falhar)'
select criar_solicitacao(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'reservar_para_unidade_id',u2)))) from ids;
\set ON_ERROR_STOP on
\echo '--- agendamento pede item do dedicado de OUTRO cliente (u2) para o cliente u1: o pedido é aceito (o alerta é na tela)'
select criar_solicitacao(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'reservado_unidade_id',u2)))) as sol6 from ids \gset
select 'item sai do dedicado: ' || (select un.nome from solicitacao_item i join unidade_cliente un on un.id=i.reservado_unidade_id where i.solicitacao_id=:sol6);
\set ON_ERROR_STOP off
\echo '--- operador SBC não aceita pedido com origem em Nova Lima (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select criar_solicitacao(jsonb_build_object('origem_id',(select nl from ids),'destino_id',(select sbc from ids),'itens',jsonb_build_array(jsonb_build_object('produto_id',(select fmc from ids),'quantidade',1)))) as sol7 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select aceitar_solicitacao(:sol7);
\echo '--- operador NL (origem) aceita; administrador também poderia'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select aceitar_solicitacao(:sol7);
select 'status=' || status::text from solicitacao where id=:sol7;
