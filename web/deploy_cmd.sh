set -e
cd /opt/vinfast
unzip -o vinfast_web.zip -d web/ > /dev/null
cd web
docker compose --env-file .env build $1 $2 2>&1 | tail -10
docker compose --env-file .env up -d $3
docker compose ps

for name in $4; do
  status=""
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    status=$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || true)
    if echo "$status" | grep -Eq '^running\|(healthy|none)$'; then
      break
    fi
    sleep 3
  done
  echo "$name => $status"
  if ! echo "$status" | grep -Eq '^running\|(healthy|none)$'; then
    echo "Deployment check failed for $name"
    exit 1
  fi
done

dashboard_status=$(docker inspect --format '{{.State.Status}}' vinfast_dashboard 2>/dev/null || true)
echo "vinfast_dashboard => $dashboard_status"
if [ "$dashboard_status" != "running" ]; then
  echo "Deployment check failed for vinfast_dashboard"
  exit 1
fi

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1/api/health > /tmp/vinfast_api_health.json; then
    cat /tmp/vinfast_api_health.json
    break
  fi
  sleep 3
done
if [ ! -s /tmp/vinfast_api_health.json ]; then
  echo "Deployment check failed: /api/health is not reachable through dashboard nginx"
  exit 1
fi
