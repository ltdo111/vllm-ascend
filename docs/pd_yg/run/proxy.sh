#!/usr/bin/env bash
set -euo pipefail

proxy_entrypoint="${PROXY_ENTRYPOINT:-launch_proxy.py}"
proxy_host="${PROXY_HOST:-0.0.0.0}"
proxy_port="${PROXY_PORT:-8000}"
prefill_hosts="${PREFILL_HOSTS:-http://x.x.x.x:7000,http://x.x.x.x:7001,http://x.x.x.x:7002,http://x.x.x.x:7003,http://x.x.x.x:7004,http://x.x.x.x:7005,http://x.x.x.x:7006,http://x.x.x.x:7007}"
decode_hosts="${DECODE_HOSTS:-http://x.x.x.x:7100,http://x.x.x.x:7101,http://x.x.x.x:7102,http://x.x.x.x:7103}"

python "$proxy_entrypoint" \
    --host "$proxy_host" \
    --port "$proxy_port" \
    --prefill-hosts "$prefill_hosts" \
    --decode-hosts "$decode_hosts"
