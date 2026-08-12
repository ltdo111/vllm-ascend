import json
import re
from pathlib import Path


RUN_DIR = Path(__file__).parents[3] / "docs" / "pd_yg" / "run"


def _extract_kv_transfer_config(script_path: Path) -> dict:
    content = script_path.read_text(encoding="utf-8")
    match = re.search(r"--kv-transfer-config\s+\\\s*\n\s*'(?P<json>\{.*?\})'", content, re.DOTALL)
    assert match is not None, f"Cannot find --kv-transfer-config in {script_path}"
    raw = match.group("json")
    raw = raw.replace('"' "$transfer_protocol" '"', "ascend")
    raw = raw.replace('"' "$transfer_device_name" '"', "")
    config = json.loads(raw)
    extra_config = config["kv_connector_extra_config"]
    extra_config["protocol"] = extra_config["protocol"].strip("'")
    extra_config["device_name"] = extra_config["device_name"].strip("'")
    return config


def test_prefill_and_decode_templates_have_valid_kv_transfer_config():
    scripts = [
        RUN_DIR / "prefill" / "a2_run_dp_template.sh",
        RUN_DIR / "prefill" / "a3_run_dp_template.sh",
        RUN_DIR / "decode" / "a5_run_dp_template.sh",
    ]

    configs = [_extract_kv_transfer_config(script) for script in scripts]

    assert configs[0]["kv_role"] == "kv_producer"
    assert configs[1]["kv_role"] == "kv_producer"
    assert configs[2]["kv_role"] == "kv_consumer"
    for config in configs:
        assert config["kv_connector"] == "MooncakeHybridConnector"
        extra_config = config["kv_connector_extra_config"]
        assert extra_config["heterogeneous_pd"] is True
        assert extra_config["enable_heterogeneous_transfer"] is True
        assert extra_config["prefill"]["dp_size"] == 8
        assert extra_config["prefill"]["tp_size"] == 1
        assert extra_config["decode"] == {"device_type": "A5", "dp_size": 4, "tp_size": 1}
        assert extra_config["protocol"] == "ascend"
        assert extra_config["device_name"] == ""
    assert configs[0]["kv_connector_extra_config"]["prefill"]["device_type"] == "A2"
    assert configs[1]["kv_connector_extra_config"]["prefill"]["device_type"] == "A3"
    assert configs[2]["kv_connector_extra_config"]["prefill"]["device_type"] == "A2"
