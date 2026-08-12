# Prefill A2 Decode A5 1P1D PD Disaggregation Plan

## 背景

本文基于 `docs/PD_yg/pd_yg.pptx` 中的 PD 分离异构方案信息，整理 Prefill 使用 A2、Decode 使用 A5 的 1P1D 异构 PD 分离推理服务实现方案与代码修改点。

当前结论是：A2/A3 与 A5 的 PD 异构在材料中被标注为未验证、不推荐直接生产；如果要进行功能打通，应先按最小闭环做验证，避免同时引入 Pool、Layerwise、非对称 TP、KV 量化转换等复杂变量。

## PPT 信息提取

### PD 分离价值

- Prefill 阶段偏计算密集，时延主要受算力影响。
- Decode 阶段偏内存带宽密集，时延主要受访存带宽影响。
- 混合部署时 Prefill 和 Decode 互相干扰，容易导致 TTFT/TPOT 抖动。
- PD 分离可以让 P/D 独立扩缩容，分别优化 TTFT 和 TPOT。

### 异构部署约束

- P 节点角色：Prefill，KV Cache Producer。
- D 节点角色：Decode，KV Cache Consumer。
- P/D 之间 KV Cache 传输要求：
  - Connector 对齐。
  - 传输协议对齐。
  - KV dtype 对齐。
  - KV layout 对齐。
  - block size 对齐。
  - TP/PP/PCP/DCP 映射关系对齐。

### A2/A3 与 A5 现状

- PPT 中明确指出 A2/A3 与 A5 的 KV Cache P2P 和 Pool 传输整体未验证。
- A2/A3 与 A5 实现 PD 分离需要依赖 NDR / host RDMA 能力。
- A2/A3 理论上支持相关链路，但材料中不建议直接进行 A2/A3 与 A5 异构生产部署。
- A2/A2、A3/A3 的 PD 分离方案相对完善。
- A3 推荐使用超节点，默认不主推 RoCE 组网。

### Connector 选择

P2P 方案：

| Connector | 方向 | 特点 | 本阶段建议 |
|---|---|---|---|
| `MooncakeConnectorV1` | PULL | D 节点从 P 节点拉取完整 KV Cache，流程简单 | 第一阶段优先 |
| `MooncakeLayerwiseConnector` | PUSH | P 节点逐层推送 KV Cache，计算与传输可流水 | 暂不纳入第一阶段 |
| `MooncakeHybridConnector` | PULL | 支持混合注意力场景 | 仅模型需要时再评估 |

Pool 方案：

| Connector | 特点 | 本阶段建议 |
|---|---|---|
| `AscendStoreConnector` | vLLM-Ascend KV Pool，支持多后端 | 暂不纳入第一阶段 |
| `MooncakeStoreConnector` | 上游 vLLM KV Pool，异构理论支持但未验证 | 暂不纳入第一阶段 |

## 第一阶段目标

第一阶段只做最小功能闭环：

```text
Prefill: A2, kv_producer
Decode : A5, kv_consumer
Topology: 1P1D
Connector: MooncakeConnectorV1
Transfer mode: PULL
Pool: disabled
PP: 1
PCP: 1
DCP: 1
KV dtype: same on P and D
KV layout: same on P and D
block_size: same on P and D
TP: P TP == D TP first, or reuse existing P TP > D TP support
```

暂不支持：

- `MooncakeLayerwiseConnector`。
- KV Pool / `AscendStoreConnector`。
- `P TP < D TP`。
- FP8/C8 KV Cache 异构转换。
- PP、PCP、DCP 组合。
- HND layout 改造。
- A2/A3 混入同一个 P 池。

## 当前代码观察

### Connector 注册

`vllm_ascend/distributed/kv_transfer/__init__.py` 已注册：

- `MooncakeConnectorV1`
- `MooncakeHybridConnector`
- `MooncakeLayerwiseConnector`
- `AscendStoreConnector`
- `MultiConnector`

因此第一阶段不需要新增 Connector，只需要扩展现有 `MooncakeConnectorV1` 的配置能力和校验能力。

### TransferEngine 协议硬编码

当前 `vllm_ascend/distributed/kv_transfer/utils/mooncake_transfer_engine.py` 中 `TransferEngine.initialize()` 的 protocol 参数硬编码为 `ascend`：

```python
ret_value = self.transfer_engine.initialize(hostname, "P2PHANDSHAKE", "ascend", device_name)
```

这会限制 A2 -> A5 场景按不同传输协议进行验证，也不利于把 PPT 中提到的 host RDMA/NDR 路径显式配置出来。

### P/D TP 校验

当前 `vllm_ascend/ascend_config.py` 已读取 `prefill.tp_size` 和 `decode.tp_size`，并要求：

```python
prefill_tp_size % decode_tp_size == 0
```

这意味着现有逻辑偏向支持 `P TP == D TP` 或 `P TP > D TP`，不支持 `P TP < D TP`。第一阶段应保留该限制，并把错误信息改得更清晰。

### KV 元数据

`MooncakeAgentMetadata` 已包含：

- `block_size`
- `kv_caches_base_addr`
- `block_size_scale`
- `block_lens`
- `block_strides`

这些字段已经覆盖部分 KV block/layout 传输元数据。第一阶段需要增加更明确的协议和兼容性校验，避免 A2/A5 不兼容时在 RDMA 读写或 Decode 阶段才失败。

## 需要修改的代码点

### 1. TransferEngine 初始化支持协议配置

修改文件：

- `vllm_ascend/distributed/kv_transfer/utils/mooncake_transfer_engine.py`

建议将 `get_transfer_engine()` 从：

```python
def get_transfer_engine(self, hostname: str, device_name: str | None):
```

扩展为：

```python
def get_transfer_engine(
    self,
    hostname: str,
    device_name: str | None,
    protocol: str = "ascend",
):
```

并将初始化协议从硬编码改为：

```python
ret_value = self.transfer_engine.initialize(
    hostname,
    "P2PHANDSHAKE",
    protocol,
    device_name,
)
```

默认值保持 `ascend`，减少对现有同构场景的影响。

### 2. MooncakeConnectorV1 读取传输配置

修改文件：

- `vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_connector.py`

从 `kv_transfer_config.kv_connector_extra_config` 中读取：

```json
{
  "protocol": "ascend",
  "device_name": ""
}
```

并传给 `global_te.get_transfer_engine()`。

示例：

```python
extra_config = vllm_config.kv_transfer_config.kv_connector_extra_config or {}
protocol = extra_config.get("protocol", "ascend")
device_name = extra_config.get("device_name", device_name)
```

注意：`device_name` 需要兼容现有 PP 场景中根据 `torch.npu.current_device()` 推导的逻辑，不能直接覆盖掉已有行为。

### 3. 同步更新其他 TransferEngine 调用点

修改文件：

- `vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_hybrid_connector.py`
- `vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_layerwise_connector.py`
- `vllm_ascend/distributed/kv_transfer/kv_pool/ascend_store/backend/mooncake_backend.py`

原因：`global_te.get_transfer_engine()` 是公共入口，签名变更后所有调用点都要兼容。

要求：

- 未配置时保持原行为。
- P2P 和 Pool 的配置入口不要混淆。
- Pool 当前仍不作为 A2 -> A5 第一阶段目标，只保证不被签名变更破坏。

### 4. 增加 1P1D 异构配置校验

修改文件候选：

- `vllm_ascend/ascend_config.py`
- 或 `vllm_ascend/utils.py` 中现有 KV transfer 校验逻辑附近

建议校验：

- `kv_connector` 必须是 `MooncakeConnectorV1`。
- `kv_connector_extra_config.protocol` P/D 两端必须一致。
- `prefill.dp_size == 1`。
- `decode.dp_size == 1`。
- `prefill.pp_size == 1`。
- `decode.pp_size == 1`。
- 第一阶段不支持 `prefill.tp_size < decode.tp_size`。
- 明确提示 A2/A5 异构需要 host RDMA/NDR 环境验证。

这里不建议新增环境变量；使用 `kv_connector_extra_config` 即可，避免引入新的全局配置。

### 5. 增强握手元数据或校验日志

修改文件：

- `vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_connector.py`

建议在握手或远端元数据获取后校验：

- `protocol`
- `block_size`
- `block_lens`
- `block_strides`
- KV Cache tensor 数量
- 可选：dtype/layout 描述

如果暂时无法可靠提取 dtype/layout，可以先补充日志，至少把 P/D 端的 block metadata 打出来，方便硬件调试。

### 6. 文档和示例配置

建议后续新增一个最小启动示例，内容包括：

- P 侧 `vllm serve` 命令。
- D 侧 `vllm serve` 命令。
- Proxy 启动命令。
- P/D `kv-transfer-config` 示例。
- A2/A5 环境依赖检查项。

示例配置骨架：

```json
{
  "kv_connector": "MooncakeConnectorV1",
  "kv_role": "kv_producer",
  "kv_port": 30000,
  "kv_connector_extra_config": {
    "protocol": "ascend",
    "device_name": "",
    "prefill": {
      "tp_size": 1,
      "dp_size": 1,
      "pp_size": 1
    },
    "decode": {
      "tp_size": 1,
      "dp_size": 1,
      "pp_size": 1
    }
  }
}
```

D 侧将 `kv_role` 改为 `kv_consumer`，其余 P/D 拓扑信息保持一致。

## 测试计划

### 单元测试

建议新增或更新：

- `tests/ut/kv_offload/test_mooncake_connector.py`
- `tests/ut/distributed/mooncake/test_mooncake_kv_transfer.py`
- `tests/ut/test_ascend_config.py`

覆盖点：

- `GlobalTE` 未配置时默认使用 `ascend`。
- `MooncakeConnectorV1` 能读取 `kv_connector_extra_config.protocol`。
- `MooncakeConnectorV1` 能读取或保留 `device_name`。
- `P TP < D TP` 第一阶段明确报错。
- `prefill.dp_size != 1` 或 `decode.dp_size != 1` 时明确报错。
- `prefill.pp_size != 1` 或 `decode.pp_size != 1` 时明确报错。

### 硬件验证

A2 + A5 环境需要验证：

1. 单请求功能打通。
2. 多请求并发。
3. 长 prompt。
4. KV transfer 日志和传输耗时。
5. TTFT、TPOT、错误率。
6. NPU 显存占用和 OOM 情况。
7. P/D 进程退出后的 block 释放是否正常。

### 验收标准

- P 侧只做 Prefill 并返回 `kv_transfer_params`。
- D 侧能基于 P 侧 KV Cache 正常 Decode。
- 单请求输出与非 PD 基线语义一致。
- 多请求无 KV transfer timeout、metadata mismatch、block release 泄漏。
- 配置不满足第一阶段约束时能 fail fast，并给出可读错误。

## 风险和后续增强

### 第一阶段风险

- A2 -> A5 的 NDR/host RDMA 链路未验证。
- PPT 明确不推荐 A2/A3 与 A5 直接异构生产部署。
- 协议配置打通不代表硬件链路一定可用。
- 如果模型使用 MLA、DSA、Hybrid Attention、C8/FP8 KV Cache，需要额外验证 KV block shape 和 dtype。

### 后续增强

- 支持 `MooncakeLayerwiseConnector`，降低 TTFT。
- 支持 `P TP < D TP`。
- 支持 HND KV layout。
- 支持 FP8/C8 KV Cache 传输。
- 支持 KV Pool。
- 支持 PP、PCP、DCP 组合。
- 支持 A2/A3/A5 多池调度和自动负载均衡。

