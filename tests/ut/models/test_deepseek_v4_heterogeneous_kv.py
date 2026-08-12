from unittest import mock

from vllm_ascend.models.layer.attention.layer import get_dsv4_block_sizes
from vllm_ascend.utils import AscendDeviceType


def _make_vllm_config(extra_config):
    kv_transfer_config = mock.MagicMock(is_kv_producer=True)
    kv_transfer_config.get_from_extra_config.side_effect = lambda key, default=None: extra_config.get(key, default)
    return mock.MagicMock(kv_transfer_config=kv_transfer_config)


def test_dsv4_block_sizes_use_a5_layout_for_heterogeneous_prefill_to_a5():
    vllm_config = _make_vllm_config(
        {
            "enable_heterogeneous_transfer": True,
            "decode": {"device_type": "A5"},
        }
    )

    with mock.patch(
        "vllm_ascend.utils.get_ascend_device_type",
        return_value=AscendDeviceType.A2,
    ):
        block_sizes = get_dsv4_block_sizes(vllm_config)

    assert block_sizes[128] == [[128, 128, 8, 16], [16896, 81920]]


def test_dsv4_block_sizes_keep_a2_layout_without_heterogeneous_transfer():
    vllm_config = _make_vllm_config({"decode": {"device_type": "A5"}})

    with mock.patch(
        "vllm_ascend.utils.get_ascend_device_type",
        return_value=AscendDeviceType.A2,
    ):
        block_sizes = get_dsv4_block_sizes(vllm_config)

    assert block_sizes[128] == [[128, 128, 8, 32], [16640, 131072]]
