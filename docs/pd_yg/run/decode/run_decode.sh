#!/usr/bin/env bash
set -euo pipefail

dp_address="${DP_ADDRESS:-x.x.x.x}"
dp_rpc_port="${DP_RPC_PORT:-12321}"
vllm_start_port="${VLLM_START_PORT:-7100}"

python launch_online_dp.py \
    --run-template a5_run_dp_template.sh \
    --dp-size 4 \
    --tp-size 1 \
    --dp-size-local 4 \
    --dp-rank-start 0 \
    --dp-address "$dp_address" \
    --dp-rpc-port "$dp_rpc_port" \
    --vllm-start-port "$vllm_start_port"
