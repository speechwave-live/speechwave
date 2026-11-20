#!/usr/bin/env bash
# Starts the production image locally with the same size limits as fly.toml
# (1 CPU, 512 MB, DB pool of 2) and a throwaway database, then seeds one pro-plan user,
# one talk and one active session. Prints "SLUG API_KEY SESSION_ID".
# All secrets here are fake values for a local throwaway container.
set -euo pipefail
NAME=speechwave-loadtest
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --cpus=1 --cpuset-cpus=0 --memory=512m -p 4000:8080 \
  -e PHX_SERVER=true -e PORT=8080 -e PHX_HOST=localhost -e POOL_SIZE=2 \
  -e DATABASE_PATH=/tmp/loadtest.db -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e ADMIN_PASSWORD=local-only -e RESEND_API_KEY=fake \
  -e RELEASE_NODE=speechwave@127.0.0.1 -e ERL_FLAGS='+MBas aobf +MHas aobf' \
  "${IMAGE:-speechwave-loadtest}" >/dev/null
for _ in $(seq 1 60); do
  curl -fs http://localhost:4000/health >/dev/null 2>&1 && break
  sleep 1
done
curl -fs http://localhost:4000/health >/dev/null || { docker logs "$NAME" | tail -20; exit 1; }
docker exec "$NAME" /app/bin/speechwave rpc '
{:ok, u} = Speechwave.Accounts.register_user(%{email: "load@example.com"})
# The free plan caps a talk at 15 connected people, so the simulated audience
# would be turned away. Load tests run as a pro user (no cap).
u = Speechwave.Repo.update!(Ecto.Changeset.change(u, plan: :pro))
scope = %Speechwave.Accounts.Scope{user: u}
{:ok, t} = Speechwave.Talks.create_talk(scope, %{title: "Load test", slug: Speechwave.Talks.generate_slug("Load test")})
{:ok, s} = Speechwave.Talks.start_session(t)
IO.puts("#{t.slug} #{u.api_key} #{s.id}")
'
