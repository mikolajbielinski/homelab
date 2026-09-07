"""Regression tests using synthetic data only; no decryption keys required."""

import base64
from contextlib import redirect_stdout
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import yaml

import check_sops


def envelope():
    iv = base64.b64encode(bytes(32)).decode()
    tag = base64.b64encode(bytes(16)).decode()
    return f"ENC[AES256_GCM,data:dGVzdA==,iv:{iv},tag:{tag},type:str]"


def secret():
    return {
        "apiVersion": "v1", "kind": "Secret",
        "data": {"token": envelope()},
        "sops": {
            "version": "3.12.1", "mac": envelope(),
            "encrypted_regex": "^(data|stringData)$",
            "age": [{"recipient": "age1synthetic", "enc": (
                "-----BEGIN AGE ENCRYPTED FILE-----\n"
                "synthetic\n-----END AGE ENCRYPTED FILE-----\n"
            )}],
        },
    }


class CheckSopsTests(unittest.TestCase):
    def check_text(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "secret with spaces.yml"
            path.write_text(text, encoding="utf-8")
            return check_sops.check_file(path)

    def test_accepts_envelopes_in_both_fields(self):
        document = secret()
        document["stringData"] = {"password": envelope()}
        self.assertEqual(check_sops.check_document(document), (1, []))

    def test_plaintext_and_base64_are_rejected_even_with_metadata(self):
        for field in ("data", "stringData"):
            for value in ("plaintext-example", "cGxhaW50ZXh0", None, 123, {}, []):
                with self.subTest(field=field, value=value):
                    document = secret()
                    document[field] = {"password": value}
                    self.assertTrue(check_sops.check_secret(document))

    def test_missing_or_incomplete_metadata(self):
        for metadata in (None, {}, {"version": "3.12.1"}):
            document = secret()
            document["sops"] = metadata
            self.assertTrue(check_sops.check_secret(document))
        for key in ("version", "mac", "age", "encrypted_regex"):
            document = secret()
            del document["sops"][key]
            self.assertTrue(check_sops.check_secret(document))

    def test_rejects_fake_encryption_prefix(self):
        for value in ("ENC[AES256_GCM,plaintext]", envelope() + "plaintext",
                      envelope().replace("dGVzdA==", "a")):
            self.assertFalse(check_sops.is_encrypted(value))

    def test_rejects_non_mapping_secret_data(self):
        for value in (None, [], "plaintext-example"):
            document = secret()
            document["data"] = value
            self.assertTrue(check_sops.check_secret(document))

    def test_checks_every_yaml_document(self):
        bad = secret()
        bad["data"]["token"] = "plaintext-example"
        count, errors = self.check_text(yaml.safe_dump_all([secret(), bad]))
        self.assertEqual(count, 2)
        self.assertTrue(errors)
        self.assertTrue(all(error.startswith("Document 2:") for error in errors))

    def test_duplicate_keys_are_rejected_without_printing_values(self):
        _, errors = self.check_text(
            "kind: Secret\nstringData:\n  password: first-example\n"
            "  password: second-example\n"
        )
        self.assertTrue(errors)
        self.assertNotIn("first-example", str(errors))
        self.assertNotIn("second-example", str(errors))

    def test_syntax_error_does_not_print_source(self):
        _, errors = self.check_text("kind: Secret\nstringData: [PRIVATE_EXAMPLE\n")
        self.assertTrue(errors)
        self.assertNotIn("PRIVATE_EXAMPLE", str(errors))

    def test_ignores_configmap_values(self):
        self.assertEqual(self.check_text("kind: ConfigMap\ndata:\n  port: '8080'\n"),
                         (0, []))

    def test_checks_list_and_secretlist(self):
        for kind in ("List", "SecretList"):
            document = secret()
            if kind == "SecretList":
                del document["kind"]
            self.assertEqual(check_sops.check_document({"kind": kind, "items": [document]}),
                             (1, []))

    def test_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "secret.yaml"
            path.symlink_to(Path(directory) / "missing.yaml")
            self.assertTrue(check_sops.check_file(path)[1])

    def test_main_fails_on_plaintext_without_logging_it(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "secret with spaces.yml"
            path.write_text("kind: Secret\nstringData:\n  password: PRIVATE_EXAMPLE\n")
            result = subprocess.CompletedProcess([], 0, stdout=str(path).encode() + b"\0")
            output = io.StringIO()
            with patch("check_sops.subprocess.run", return_value=result):
                with redirect_stdout(output):
                    self.assertEqual(check_sops.main(), 1)
            self.assertIn("Checked 1 Kubernetes Secrets", output.getvalue())
            self.assertNotIn("PRIVATE_EXAMPLE", output.getvalue())


if __name__ == "__main__":
    unittest.main()
