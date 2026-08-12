#!/usr/bin/env bash
set -euo pipefail

template="${1:-a3}"
dp_address="${DP_ADDRESS:-x.x.x.x}"
dp_rpc_port="${DP_RPC_PORT:-12320}"
vllm_start_port="${VLLM_START_PORT:-7000}"

case "$template" in
    a2)
        run_template="a2_run_dp_template.sh"
        ;;
    a3)
        run_template="a3_run_dp_template.sh"
        ;;
    *)
        echo "Unknown prefill template: $template" >&2
        exit 1
        ;;
esac

python launch_online_dp.py \
    --run-template "$run_template" \
    --dp-size 8 \
    --tp-size 1 \
    --dp-size-local 8 \
    --dp-rank-start 0 \
    --dp-address "$dp_address" \
    --dp-rpc-port "$dp_rpc_port" \
    --vllm-start-port "$vllm_start_port"
