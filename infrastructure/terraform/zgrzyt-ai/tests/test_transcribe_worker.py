"""Secret and queue failure tests; no AWS credentials, network, or GPU needed."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch


PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("worker", PROJECT / "transcribe_worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class SecretTests(unittest.TestCase):
    def setUp(self):
        self.boto3 = MagicMock()
        self.client = self.boto3.client.return_value
        self.modules = patch.dict("sys.modules", {
            "boto3": self.boto3,
            "botocore": MagicMock(),
            "botocore.config": MagicMock(),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)
        env = patch.dict(os.environ, {
            "AWS_DEFAULT_REGION": "eu-central-1",
            "HF_SECRET_ARN": "arn:aws:secretsmanager:eu-central-1:123456789012:secret:test",
        }, clear=True)
        env.start()
        self.addCleanup(env.stop)

    def run_worker(self, args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = worker.main(args)
        return result, stdout.getvalue() + stderr.getvalue()

    def test_token_stays_in_worker_and_current_version_is_used(self):
        token = "hf_synthetic-test-token"
        self.client.get_secret_value.return_value = {"SecretString": token + "\n"}
        with patch.object(worker, "transcribe") as transcribe:
            result, log = self.run_worker(["audio.mp3", "output.json"])
        self.assertEqual(result, 0)
        transcribe.assert_called_once_with("audio.mp3", "output.json", token)
        self.client.get_secret_value.assert_called_once_with(
            SecretId=os.environ["HF_SECRET_ARN"], VersionStage="AWSCURRENT"
        )
        self.assertNotIn(token, log)
        self.assertNotIn("HF_TOKEN", os.environ)

    def test_preflight_does_not_start_transcription(self):
        self.client.get_secret_value.return_value = {"SecretString": "hf_synthetic-test-token"}
        with patch.object(worker, "transcribe") as transcribe:
            result, log = self.run_worker(["--check-secret"])
        self.assertEqual(result, 0)
        transcribe.assert_not_called()
        self.assertNotIn("hf_synthetic-test-token", log)

    def test_empty_binary_json_and_malformed_values_fail_without_logging_values(self):
        for value in (None, "", "  ", "hf_", "hf_bad token", '{"token":"hf_synthetic"}', 123):
            with self.subTest(value=value):
                self.client.get_secret_value.return_value = {"SecretString": value}
                with patch.object(worker, "transcribe") as transcribe:
                    result, log = self.run_worker(["audio.mp3", "output.json"])
                self.assertEqual(result, worker.SECRET_ERROR)
                transcribe.assert_not_called()
                self.assertNotIn("hf_synthetic", log)
        self.client.get_secret_value.return_value = {"SecretBinary": b"hf_synthetic"}
        self.assertEqual(self.run_worker(["--check-secret"])[0], worker.SECRET_ERROR)

    def test_secret_api_failure_never_logs_exception_contents(self):
        # Covers missing AWSCURRENT, denied IAM access, and unavailable service.
        for failure in (RuntimeError, PermissionError, TimeoutError):
            with self.subTest(failure=failure):
                self.client.get_secret_value.side_effect = failure("hf_must-not-appear")
                result, log = self.run_worker(["--check-secret"])
                self.assertEqual(result, worker.SECRET_ERROR)
                self.assertNotIn("hf_must-not-appear", log)
                self.assertIn("Queue left for retry", log)


class BootScriptTests(unittest.TestCase):
    def run_boot(self, preflight_rc=0, worker_rc=0):
        # Render fixture values without reading tfvars or invoking AWS. Terraform
        # configuration/template validation is also run separately in CI.
        script = (PROJECT / "transcribe.sh").read_text()
        script = script.replace("${hf_secret_arn}", "synthetic-secret-arn")
        script = script.replace("${aws_region}", "eu-central-1")
        script = script.replace("${transcribe_worker}", (PROJECT / "transcribe_worker.py").read_text())
        script = script.replace("$${", "${")
        script = script.split("#!/bin/bash", 1)[1].split("\n--==BOUNDARY==--", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = script.replace("/opt/zgrzyt", str(root / "work"))
            script = script.replace("/var/log/transcribe.log", str(root / "transcribe.log"))
            harness = r'''
shutdown() { echo "shutdown $*" >> "$BOOT_CALLS"; }
pip3() { echo "pip3 $*" >> "$BOOT_CALLS"; }
apt-get() { :; }
python3() { return "$PREFLIGHT_RC"; }
timeout() { return "$WORKER_RC"; }
aws() {
    echo "aws $*" >> "$BOOT_CALLS"
    if [ "$1" = s3 ] && [ "$2" = ls ] && [ "$3" = s3://zgrzyt-ai/mp3/ ]; then
        echo '2026-09-07 12:00:00 123 example.mp3'
    fi
}
'''
            env = dict(os.environ, BOOT_CALLS=str(root / "calls"),
                       PREFLIGHT_RC=str(preflight_rc), WORKER_RC=str(worker_rc))
            result = subprocess.run(["bash", "-c", harness + script], env=env,
                                    capture_output=True, text=True, timeout=10)
            return result.returncode, (root / "calls").read_text(), (root / "transcribe.log").read_text()

    def test_missing_secret_stops_before_queue_and_gpu_dependencies(self):
        rc, calls, log = self.run_boot(preflight_rc=78)
        self.assertEqual(rc, 78)
        self.assertNotIn("aws s3 ls", calls)
        self.assertNotIn("whisperx", calls)
        self.assertNotIn("/failed/", calls)
        self.assertIn("s3://zgrzyt-ai/logs/", calls)
        self.assertIn("shutdown -h now", calls)
        self.assertIn("Processed: 0. Failed: 0", log)

    def test_secret_failure_mid_queue_leaves_audio_for_retry(self):
        rc, calls, log = self.run_boot(worker_rc=78)
        self.assertEqual(rc, 78)
        self.assertNotIn("cp - s3://zgrzyt-ai/failed/", calls)
        self.assertIn("shutdown -h now", calls)
        self.assertIn("stopping without marking example as failed", log)

    def test_audio_failure_still_creates_failure_marker(self):
        rc, calls, log = self.run_boot(worker_rc=1)
        self.assertEqual(rc, 0)
        self.assertIn("cp - s3://zgrzyt-ai/failed/example.json", calls)
        self.assertIn("Failed: 1", log)

    def test_success_uploads_transcript_and_stops(self):
        rc, calls, log = self.run_boot()
        self.assertEqual(rc, 0)
        self.assertIn("s3://zgrzyt-ai/transcripts/raw/example.json", calls)
        self.assertIn("shutdown -h now", calls)
        self.assertIn("Processed: 1. Failed: 0", log)


if __name__ == "__main__":
    unittest.main()
