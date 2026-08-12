import sys
import types
import unittest
from unittest.mock import MagicMock


class TestMooncakeTransferEngine(unittest.TestCase):

    def setUp(self):
        self.fake_engine_module = types.ModuleType("mooncake.engine")
        self.fake_transfer_engine = MagicMock()
        self.fake_transfer_engine.initialize.return_value = 0
        self.fake_engine_module.TransferEngine = MagicMock(return_value=self.fake_transfer_engine)
        sys.modules["mooncake.engine"] = self.fake_engine_module

    def test_get_transfer_engine_uses_protocol_and_device_name(self):
        from vllm_ascend.distributed.kv_transfer.utils.mooncake_transfer_engine import GlobalTE

        global_te = GlobalTE()
        engine = global_te.get_transfer_engine("127.0.0.1", device_name="mlx5_0", protocol="rdma")

        self.assertIs(engine, self.fake_transfer_engine)
        self.fake_transfer_engine.initialize.assert_called_once_with(
            "127.0.0.1",
            "P2PHANDSHAKE",
            "rdma",
            "mlx5_0",
        )

    def test_get_transfer_engine_rejects_reinitialize_with_different_config(self):
        from vllm_ascend.distributed.kv_transfer.utils.mooncake_transfer_engine import GlobalTE

        global_te = GlobalTE()
        global_te.get_transfer_engine("127.0.0.1", device_name=None, protocol="ascend")

        with self.assertRaisesRegex(RuntimeError, "already been initialized"):
            global_te.get_transfer_engine("127.0.0.1", device_name="mlx5_0", protocol="rdma")


if __name__ == "__main__":
    unittest.main()
