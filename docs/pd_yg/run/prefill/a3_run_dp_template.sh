unset ftp_proxy
unset https_proxy
unset http_proxy
rm -rf ~/ascend/log

nic_name="${NIC_NAME:-xxxxxx}" # eg. "enp67s0f0np0"
local_ip="${LOCAL_IP:-$(hostname -I | awk -F " " '{print $1}')}"
prefill_model_path="${PREFILL_MODEL_PATH:-/mnt/weight/DeepSeek-V4-Flash-w8a8-mtp}"
transfer_protocol="${MOONCAKE_TRANSFER_PROTOCOL:-ascend}"
transfer_device_name="${MOONCAKE_TRANSFER_DEVICE_NAME:-}"

export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
export HCCL_OP_EXPANSION_MODE="AIV"
export TASK_QUEUE_ENABLE=1
export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
export HCCL_EXEC_TIMEOUT=204
export HCCL_CONNECT_TIMEOUT=1200

export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_BUFFSIZE=1024

export ASCEND_RT_VISIBLE_DEVICES=$1
export TASK_QUEUE_ENABLE=1

vllm serve "$prefill_model_path" \
    --host 0.0.0.0 \
    --port $2 \
    --data-parallel-size $3 \
    --data-parallel-rank $4 \
    --data-parallel-address $5 \
    --data-parallel-rpc-port $6 \
    --tensor-parallel-size $7 \
    --enable-expert-parallel \
    --seed 1024 \
    --served-model-name dsv4 \
    --max-model-len 135000 \
    --max-num-batched-tokens 4096 \
    --max-num-seqs 16 \
    --block-size 128 \
    --enforce-eager \
    --async-scheduling \
    --no-disable-hybrid-kv-cache-manager \
    --enable-prefix-caching \
    --trust-remote-code \
    --gpu-memory-utilization 0.9 \
    --quantization ascend \
    --safetensors-load-strategy 'prefetch' \
    --model-loader-extra-config='{"enable_multithread_load": "true", "num_threads": 128}' \
    --tokenizer-mode deepseek_v4 \
    --tool-call-parser deepseek_v4 \
    --enable-auto-tool-choice \
    --reasoning-parser deepseek_v4 \
    --additional-config '{"enable_cpu_binding": true, "enable_shared_expert_dp": true}' \
    --speculative-config '{"num_speculative_tokens": 1, "method": "mtp","enforce_eager": true}' \
    --kv-transfer-config \
    '{"kv_connector": "MooncakeHybridConnector",
    "kv_role": "kv_producer",
    "kv_port": "30000",
    "engine_id": "0",
    "kv_connector_extra_config": {
                "protocol": "'"$transfer_protocol"'",
                "device_name": "'"$transfer_device_name"'",
                "heterogeneous_pd": true,
                "enable_heterogeneous_transfer": true,
                "prefill": {
                    "device_type": "A3",
                    "dp_size": 8,
                    "tp_size": 1
                },
                "decode": {
                    "device_type": "A5",
                    "dp_size": 4,
                    "tp_size": 1
                }
        }
    }'
