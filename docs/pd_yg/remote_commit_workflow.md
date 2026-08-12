# Remote Commit Workflow

本文记录本次在远端 Linux 机器提交 `PD_PA2A3_DA5` 分支的流程，后续同类需求可按此执行。

## 适用场景

- 本地 Windows 仓库已有代码修改。
- 远端 Linux 机器已准备好 `/workspace/lt/vllm-ascend` 仓库。
- 需要在远端执行 `dos2unix`、提交，并推送到 GitHub 分支。

## 远端信息

```text
host: 71.10.29.143
user: c00974073
repo: /workspace/lt/vllm-ascend
branch: PD_PA2A3_DA5
github remote: git@github.com:ltdo111/vllm-ascend.git
```

不要把服务器密码或 GitHub token 写入仓库文档。

## 1. 登录远端并进入仓库

```bash
ssh c00974073@71.10.29.143
cd /workspace/lt/vllm-ascend
```

如果 Git 提示 dubious ownership，先把该目录加入安全目录：

```bash
git config --global --add safe.directory /workspace/lt/vllm-ascend
```

## 2. 检查分支和工作区

```bash
git status --short --branch
git log -1 --oneline
git remote -v
```

确认当前分支为目标分支：

```bash
git checkout PD_PA2A3_DA5
```

## 3. 提交前执行 dos2unix

提交前对将要提交的文件执行 `dos2unix`。如需对全部 tracked 文件执行：

```bash
git ls-files -z | xargs -0 dos2unix
```

如果只处理本次特性文件，先列出目标文件，再执行：

```bash
dos2unix \
  vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_hybrid_connector.py \
  vllm_ascend/distributed/kv_transfer/utils/mooncake_transfer_engine.py \
  vllm_ascend/utils.py \
  tests/ut/kv_offload/test_mooncake_hybrid_connector.py \
  tests/ut/kv_offload/test_mooncake_transfer_engine.py \
  tests/ut/kv_offload/test_pd_yg_scripts.py \
  tests/ut/test_utils.py \
  docs/pd_yg/prefill_a2_decode_a5_1p1d_plan.md \
  docs/pd_yg/设计文档.md \
  docs/pd_yg/run/prefill/a2_run_dp_template.sh \
  docs/pd_yg/run/prefill/a3_run_dp_template.sh \
  docs/pd_yg/run/decode/a5_run_dp_template.sh \
  docs/pd_yg/run/run_prefill.sh \
  docs/pd_yg/run/run_decode.sh \
  docs/pd_yg/run/proxy.sh
```

## 4. 执行基础验证

Python 语法检查：

```bash
python3 -m py_compile \
  vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_hybrid_connector.py \
  vllm_ascend/distributed/kv_transfer/utils/mooncake_transfer_engine.py \
  vllm_ascend/utils.py \
  tests/ut/kv_offload/test_mooncake_hybrid_connector.py \
  tests/ut/kv_offload/test_mooncake_transfer_engine.py \
  tests/ut/kv_offload/test_pd_yg_scripts.py \
  tests/ut/test_utils.py
```

Shell 脚本语法检查：

```bash
bash -n docs/pd_yg/run/prefill/a2_run_dp_template.sh
bash -n docs/pd_yg/run/prefill/a3_run_dp_template.sh
bash -n docs/pd_yg/run/decode/a5_run_dp_template.sh
bash -n docs/pd_yg/run/run_prefill.sh
bash -n docs/pd_yg/run/run_decode.sh
bash -n docs/pd_yg/run/proxy.sh
```

有完整依赖和硬件环境时，再补充执行相关 `pytest` 或 NPU e2e 测试。

## 5. 暂存和提交

只暂存本次需求相关文件，避免把无关日志、临时脚本带入提交：

```bash
git add \
  vllm_ascend/distributed/kv_transfer/kv_p2p/mooncake_hybrid_connector.py \
  vllm_ascend/distributed/kv_transfer/utils/mooncake_transfer_engine.py \
  vllm_ascend/utils.py \
  tests/ut/kv_offload/test_mooncake_hybrid_connector.py \
  tests/ut/kv_offload/test_mooncake_transfer_engine.py \
  tests/ut/kv_offload/test_pd_yg_scripts.py \
  tests/ut/test_utils.py \
  docs/pd_yg/prefill_a2_decode_a5_1p1d_plan.md \
  docs/pd_yg/设计文档.md \
  docs/pd_yg/run/prefill/a2_run_dp_template.sh \
  docs/pd_yg/run/prefill/a3_run_dp_template.sh \
  docs/pd_yg/run/decode/a5_run_dp_template.sh \
  docs/pd_yg/run/run_prefill.sh \
  docs/pd_yg/run/run_decode.sh \
  docs/pd_yg/run/proxy.sh
```

提交必须带 sign-off：

```bash
git commit -s -m "feat(kv-transfer): add hetero PD layout validation" \
  -m "Add fail-fast KV cache dtype and layout validation for heterogeneous PD disaggregation, plus DeepSeek-V4 Flash A2/A3 prefill and A5 decode scripts and tests."
```

本次远端提交为：

```text
c41e14fdc feat(kv-transfer): add hetero PD layout validation
```

## 6. 关联 GitHub 远端仓库

```bash
if git remote get-url ltdo111 >/dev/null 2>&1; then
  git remote set-url ltdo111 git@github.com:ltdo111/vllm-ascend.git
else
  git remote add ltdo111 git@github.com:ltdo111/vllm-ascend.git
fi

git remote -v | grep '^ltdo111'
```

## 7. 配置 GitHub SSH key

如果远端机器没有 GitHub 写权限，先生成 key：

```bash
ssh-keygen -t ed25519 -C "ltdo111@github" -f ~/.ssh/id_ed25519_github
cat ~/.ssh/id_ed25519_github.pub
```

将公钥添加到 GitHub 账号 `ltdo111`：

```text
GitHub -> Settings -> SSH and GPG keys -> New SSH key
```

如果 GitHub 22 端口不可达，使用 443 端口：

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_github
EOF

chmod 600 ~/.ssh/config
ssh-keyscan -p 443 ssh.github.com >> ~/.ssh/known_hosts
ssh -T git@github.com
```

`ssh -T` 成功后再推送。

## 8. 推送分支

```bash
git push -u ltdo111 PD_PA2A3_DA5
```

如果出现以下错误：

```text
ssh: connect to host github.com port 22: Connection timed out
```

说明远端机器访问 GitHub 22 端口失败，按第 7 节切换到 `ssh.github.com:443`。

如果出现以下错误：

```text
git@ssh.github.com: Permission denied (publickey)
```

说明远端机器没有可用的 GitHub SSH key，或该 key 未添加到目标 GitHub 账号。

## 9. 推送后确认

```bash
git status --short --branch
git branch -vv
git log -1 --oneline
```

确认分支已关联到远端：

```text
PD_PA2A3_DA5 ... [ltdo111/PD_PA2A3_DA5]
```
