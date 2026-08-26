import importlib.util
from pathlib import Path
import sys
import unittest


MODULE_PATH = Path(__file__).with_name("linear_bridge.py")
SPEC = importlib.util.spec_from_file_location("linear_bridge", MODULE_PATH)
linear_bridge = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = linear_bridge
SPEC.loader.exec_module(linear_bridge)


class LinearBridgeTests(unittest.TestCase):
    def test_extracts_created_and_prompted_text(self):
        self.assertEqual(
            linear_bridge.prompt_text({"action": "created", "promptContext": "issue context"}),
            "issue context",
        )
        self.assertEqual(
            linear_bridge.prompt_text(
                {"data": {"action": "prompted", "agentActivity": {"body": "follow up"}}}
            ),
            "follow up",
        )

    def test_requires_human_assignee(self):
        self.assertTrue(
            linear_bridge.has_human_assignee(
                {"agentSession": {"issue": {"assignee": {"id": "human"}}}}
            )
        )
        self.assertFalse(
            linear_bridge.has_human_assignee(
                {"agentSession": {"issue": {"assignee": {"id": "app", "isApp": True}}}}
            )
        )
        self.assertFalse(linear_bridge.has_human_assignee({"promptContext": "<issue/>"}))

    def test_session_ids_are_stable_and_role_isolated(self):
        first = linear_bridge.stable_hermes_session("developer", "linear-session")
        self.assertEqual(first, linear_bridge.stable_hermes_session("developer", "linear-session"))
        self.assertNotEqual(first, linear_bridge.stable_hermes_session("ops", "linear-session"))

    def test_parses_sse(self):
        lines = iter(
            [
                b"event: run.completed\n",
                b'data: {"output":"done"}\n',
                b"\n",
            ]
        )
        self.assertEqual(
            list(linear_bridge.parse_sse(lines)),
            [{"event": "run.completed", "output": "done"}],
        )

    def test_approval_vocabulary_excludes_permanent_choices(self):
        self.assertIn("approve once", linear_bridge.APPROVE_ONCE)
        self.assertNotIn("always", linear_bridge.APPROVE_ONCE)
        self.assertNotIn("session", linear_bridge.APPROVE_ONCE)


if __name__ == "__main__":
    unittest.main()
