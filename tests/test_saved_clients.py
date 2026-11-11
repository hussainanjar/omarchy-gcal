import contextlib
import io
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/gcal-agenda"


class SavedClientsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name) / "gcalcli"
        self.folder.mkdir()
        env = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.temp.name})
        env.start()
        self.addCleanup(env.stop)
        self.module = runpy.run_path(str(SCRIPT))
        self.globals = self.module["setup"].__globals__

    def client(self, name, client_id="test.apps.googleusercontent.com", secret="test-secret"):
        (self.folder / name).write_text(
            f'export GCALCLI_CLIENT_ID="{client_id}"\nGCALCLI_CLIENT_SECRET="{secret}" # private\n'
        )

    def test_named_clients_are_sorted_and_invalid_files_skipped(self):
        self.client("client.env.work")
        self.client("client.env")
        self.client("client.env.personal")
        (self.folder / "client.env.incomplete").write_text("GCALCLI_CLIENT_ID=missing-secret\n")
        (self.folder / "client.env.malformed").write_text('GCALCLI_CLIENT_SECRET="unterminated\n')
        names = [name for name, _ in self.module["saved_clients"]()]
        self.assertEqual(names, ["client.env", "client.env.personal", "client.env.work"])

    def test_client_file_is_not_executed(self):
        marker = Path(self.temp.name) / "executed"
        (self.folder / "client.env").write_text(
            f'touch {marker}\nGCALCLI_CLIENT_ID=test\nGCALCLI_CLIENT_SECRET="$(touch {marker})"\n'
        )
        self.assertEqual(len(self.module["saved_clients"]()), 1)
        self.assertFalse(marker.exists())

    def test_setup_selects_named_client_and_keeps_secret_out_of_arguments_and_output(self):
        self.client("client.env")
        self.client("client.env.work", "work.apps.googleusercontent.com", "work-secret")
        self.check_setup(["invalid", "9", "2"], saved=True)

    def test_manual_setup_still_works(self):
        self.client("client.env")
        self.check_setup(["0", "n"], saved=False)

    def test_reauthorization_confirms_replacing_existing_token(self):
        self.client("client.env", "work.apps.googleusercontent.com", "work-secret")
        self.check_setup(["1", "y"], saved=True, signed_in=True)

    def check_setup(self, answers, saved, signed_in=False):
        output = io.StringIO()
        with patch.dict(self.globals, {
            "gcalcli_path": lambda opts: "/usr/bin/gcalcli",
            "signed_in": unittest.mock.Mock(side_effect=[signed_in, True]),
            "secure_gcalcli_files": lambda: None,
            "fetch": lambda opts: True,
            "read_json": lambda *args: {"events": []},
        }), patch("builtins.input", side_effect=answers), patch("subprocess.run") as run, contextlib.redirect_stdout(output):
            self.assertEqual(self.module["setup"](object()), 0)
        args = run.call_args.args[0]
        self.assertNotIn("work-secret", repr(args))
        self.assertNotIn("work-secret", output.getvalue())
        if saved:
            self.assertEqual(args, ["/usr/bin/gcalcli", "--noincluderc", "--client-id", "work.apps.googleusercontent.com", "init"])
            self.assertEqual(run.call_args.kwargs["input"], ("y\n" if signed_in else "") + "work-secret\n")
        else:
            self.assertEqual(args, ["/usr/bin/gcalcli", "init"])
            self.assertNotIn("input", run.call_args.kwargs)

    def test_eof_cancels_without_authentication(self):
        self.client("client.env")
        with patch.dict(self.globals, {"gcalcli_path": lambda opts: "/usr/bin/gcalcli"}), patch("builtins.input", side_effect=EOFError), patch("subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.module["setup"](object()), 1)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
