#!/usr/bin/env bash
# Roda os testes de tela do Estoque Gauss do zero: sobe um PostgreSQL local, a API (PostgREST), um login de teste
# e o app, e dirige um navegador (Playwright) pelas telas. Não usa o seu Supabase real.
#
# Pré-requisitos: PostgreSQL 15+ instalado (binários em PG_BIN), Node 18+, e um Chromium
# (defina CHROMIUM=/caminho/do/chrome, ou rode `npx playwright-core install chromium`).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
WORK="${WORK:-/tmp/estoque-gauss-testes}"
POSTGREST_VERSAO="${POSTGREST_VERSAO:-v12.2.3}"
export PGPORT=5544 PSQL="$PG_BIN/psql"
APP_PORT=3100
export APP_URL="http://127.0.0.1:$APP_PORT"

# O servidor do PostgreSQL não roda como root: se for o seu caso, usa o usuário "postgres".
como_pg() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
psql_t() { "$PSQL" -h 127.0.0.1 -p "$PGPORT" -U postgres -d t -v ON_ERROR_STOP=1 -q "$@"; }

PIDS=()
limpar() {
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done
  como_pg "$PG_BIN/pg_ctl -D $WORK/d stop -m fast" >/dev/null 2>&1 || true
}
trap limpar EXIT

rm -rf "$WORK"; mkdir -p "$WORK"
[ "$(id -u)" = 0 ] && chown postgres "$WORK"

echo "== banco local"
como_pg "$PG_BIN/initdb -D $WORK/d -A trust >/dev/null"
como_pg "$PG_BIN/pg_ctl -D $WORK/d -o '-p $PGPORT -k $WORK -c listen_addresses=127.0.0.1' -l $WORK/pg.log -w start" >/dev/null
"$PSQL" -h 127.0.0.1 -p "$PGPORT" -U postgres -d postgres -q -c "create database t"
psql_t -f "$AQUI/stub_auth_postgrest.sql"
psql_t -1 -f "$RAIZ/supabase/banco_completo.sql" 2>&1 | grep -v NOTICE || true
psql_t -f "$AQUI/usuarios_de_teste.sql"

echo "== API (PostgREST)"
if [ -z "${POSTGREST:-}" ]; then
  POSTGREST="$AQUI/.cache/postgrest"
  if [ ! -x "$POSTGREST" ]; then
    mkdir -p "$AQUI/.cache"
    curl -sSL "https://github.com/PostgREST/postgrest/releases/download/$POSTGREST_VERSAO/postgrest-$POSTGREST_VERSAO-linux-static-x64.tar.xz" | tar xJ -C "$AQUI/.cache"
  fi
fi
cat > "$WORK/postgrest.conf" <<CONF
db-uri = "postgres://authenticator:x@127.0.0.1:$PGPORT/t"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "super-secret-jwt-token-with-at-least-32-characters-long"
server-port = 3300
CONF
"$POSTGREST" "$WORK/postgrest.conf" > "$WORK/postgrest.log" 2>&1 & PIDS+=($!)
node "$AQUI/authproxy.js" > "$WORK/proxy.log" 2>&1 & PIDS+=($!)

echo "== app"
( cd "$RAIZ/web" && [ -d node_modules ] || npm install --silent )
( cd "$RAIZ/web" && NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=teste \
    npx next dev -p "$APP_PORT" > "$WORK/next.log" 2>&1 ) & PIDS+=($!)
( cd "$AQUI" && [ -d node_modules ] || npm install --silent )
for i in $(seq 1 60); do curl -s -o /dev/null "$APP_URL/login" && break; sleep 1; done

echo "== testes"
cd "$AQUI"
FALHAS=0
for t in 1_varredura 2_registrar 3_tecnico_e_solicitacoes 4_dedicados_filtros_perfis 5_extras; do
  echo; echo "### $t"
  node "$t.js" || FALHAS=$((FALHAS+1))
done
echo; [ "$FALHAS" = 0 ] && echo "TUDO CERTO" || { echo "$FALHAS arquivo(s) de teste com falha (linhas marcadas com ✘)"; exit 1; }
