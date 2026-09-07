"""Check committed Kubernetes Secrets for SOPS envelopes, without decrypting."""

import base64
import binascii
import json
from pathlib import Path
import re
import subprocess
import sys

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    """Reject ambiguous mappings instead of silently keeping the last value."""

    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                if key in result:
                    raise yaml.constructor.ConstructorError(
                        None, None, "Duplicate YAML key", key_node.start_mark
                    )
                result[key] = self.construct_object(value_node, deep=deep)
            except TypeError:
                raise yaml.constructor.ConstructorError(
                    None, None, "Invalid YAML key", key_node.start_mark
                ) from None
        return result


ENVELOPE = re.compile(
    r"ENC\[AES256_GCM,data:([A-Za-z0-9+/=]*),"
    r"iv:([A-Za-z0-9+/=]+),tag:([A-Za-z0-9+/=]+),type:str\]"
)


def is_encrypted(value):
    if not isinstance(value, str):
        return False
    match = ENVELOPE.fullmatch(value)
    if not match:
        return False
    try:
        _, iv, tag = [base64.b64decode(part, validate=True) for part in match.groups()]
        return len(iv) == 32 and len(tag) == 16
    except binascii.Error:
        return False


def check_secret(secret):
    errors = []
    metadata = secret.get("sops")
    if not isinstance(metadata, dict):
        errors.append("Secret is missing SOPS metadata")
    else:
        if not isinstance(metadata.get("version"), str) or not metadata["version"]:
            errors.append("SOPS metadata is missing a version")
        if not is_encrypted(metadata.get("mac")):
            errors.append("SOPS metadata is missing a valid encrypted MAC envelope")
        if metadata.get("encrypted_regex") != "^(data|stringData)$":
            errors.append("SOPS encrypted_regex must cover data and stringData")
        recipients = metadata.get("age")
        if not isinstance(recipients, list) or not recipients or any(
            not isinstance(entry, dict)
            or not isinstance(entry.get("recipient"), str)
            or not entry["recipient"].startswith("age1")
            or not isinstance(entry.get("enc"), str)
            or not entry["enc"].startswith("-----BEGIN AGE ENCRYPTED FILE-----")
            or not entry["enc"].rstrip().endswith("-----END AGE ENCRYPTED FILE-----")
            for entry in recipients
        ):
            errors.append("SOPS metadata is missing age recipients or wrapped keys")
    for field in ("data", "stringData"):
        if field not in secret:
            continue
        values = secret[field]
        if not isinstance(values, dict):
            errors.append(f"Secret {field} must be a mapping")
        elif any(not isinstance(key, str) or not is_encrypted(value)
                 for key, value in values.items()):
            errors.append(f"Secret contains an unencrypted or malformed value in {field}")
    return errors


def check_document(document):
    if not isinstance(document, dict):
        return 0, []
    kind = document.get("kind")
    if kind == "Secret":
        return 1, check_secret(document)
    if kind in ("List", "SecretList"):
        items = document.get("items")
        if not isinstance(items, list):
            return 0, ["Kubernetes List items must be a list"]
        count, errors = 0, []
        for item in items:
            if not isinstance(item, dict):
                errors.append("Kubernetes List items must be objects")
                continue
            if kind == "SecretList":
                item = {**item, "kind": "Secret"}
            item_count, item_errors = check_document(item)
            count += item_count
            errors.extend(item_errors)
        return count, errors
    return 0, []


def check_file(path):
    count, errors = 0, []
    if path.is_symlink():
        return 0, ["YAML symlinks are not supported by the SOPS check"]
    try:
        with path.open(encoding="utf-8") as stream:
            for index, document in enumerate(yaml.load_all(stream, Loader=UniqueKeyLoader), 1):
                found, document_errors = check_document(document)
                count += found
                errors.extend(f"Document {index}: {error}" for error in document_errors)
    except yaml.YAMLError as error:
        mark = getattr(error, "problem_mark", None)
        location = f" at line {mark.line + 1}" if mark else ""
        errors.append(f"Invalid YAML{location} (including duplicate keys)")
    except (OSError, UnicodeError, RecursionError):
        errors.append("Cannot read YAML or unsupported recursive YAML structure")
    return count, errors


def main():
    # Git's NUL-delimited list supports spaces and newlines in filenames.
    files = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.yaml", "*.yml"],
        check=True, capture_output=True,
    ).stdout.split(b"\0")
    count, failures = 0, 0
    for filename in filter(None, files):
        path = Path(filename.decode("utf-8", errors="surrogateescape"))
        # A local deletion may still be in Git's index before it is staged.
        if not path.exists() and not path.is_symlink():
            continue
        found, errors = check_file(path)
        count += found
        failures += len(errors)
        for error in errors:
            # JSON quoting prevents filenames from injecting lines into CI logs.
            print(f"ERROR {json.dumps(str(path))}: {error}")
    print(f"Checked {count} Kubernetes Secrets; {failures} error(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
