#!/usr/bin/env python3
"""Report likely secrets without printing their values."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

RULES = {
    "private key": rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "GitLab token": rb"\bglpat-[A-Za-z0-9_-]{20,}\b",
    "AWS key ID": rb"\b(?:AKIA|ASIA|AIDA|AROA)[A-Z0-9]{16}\b",
    "Google API key": rb"\bAIza[0-9A-Za-z_-]{35}\b",
    "Slack token": rb"\bxox[baprs]-[A-Za-z0-9-]{10,}\b",
    "Slack webhook": rb"https://hooks\.slack\.com/services/[A-Za-z0-9/]{12,}",
    "Stripe secret": rb"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b",
    "OpenAI-style key": rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}",
    "JWT": rb"\beyJ[A-Za-z0-9_-]{12,}\.eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b",
    "URL with embedded credentials": rb"(?i)\b(?:https?|postgres(?:ql)?|redis|mysql|mongodb(?:\+srv)?|amqps?)://[^\s/'\"<>:@]+:[^\s/'\"<>@]+@",
    "inline bearer token": rb"(?i)\bbearer[ \t]+[A-Za-z0-9_./+~-]{24,}",
}
PATTERNS = {name: re.compile(pattern) for name, pattern in RULES.items()}
ASSIGNMENT = re.compile(
    rb"""(?im)\b(?:password|passwd|db_password|api[_-]?key|client[_-]?secret|access[_-]?token|oauth[_-]?token|refresh[_-]?token|auth[_-]?token|secret[_-]?key)["']?\s*[:=]\s*(?:"([^"\r\n]{4,})"|'([^'\r\n]{4,})'|([A-Za-z0-9_./+~@-]{8,}))"""
)
PLACEHOLDER = re.compile(
    rb"(?i)^(?:\$[{(]?[\w. -]+[})]?|<[^>]+>|(?:your|example|dummy|sample|placeholder)[_-].+|changeme|redacted|password|nil|null|none)$"
)
PRIVATE_NAME = re.compile(
    r"(?i)^(?:\.env(?:\..*)?|\.envrc|\.netrc|\.npmrc|\.pypirc|\.git-credentials|"
    r"credentials(?:-[^/]+)?\.json|service-account[^/]*\.json|secrets\..+|"
    r"id_(?:rsa|ed25519|ecdsa|dsa)|inbox(?:-[^/]+)?\.json|\.inbox\.lock|"
    r".+\.(?:pem|key|p12|pfx|keystore|keychain|keychain-db|jks|mobileprovision|provisionprofile|zip|dmg|pkg|tar|tar\.gz|tgz|7z))$"
)


def git(*args, check=True):
    result = subprocess.run(("git", *args), capture_output=True, check=False)
    if check and result.returncode:
        raise RuntimeError("Git could not read the requested data.")
    return result.stdout


def redact(label):
    raw = os.fsencode(label)
    for pattern in PATTERNS.values():
        raw = pattern.sub(b"[redacted]", raw)
    raw = ASSIGNMENT.sub(b"[redacted]", raw)
    return os.fsdecode(raw).encode("unicode_escape").decode("ascii")


def findings(data):
    result = {}
    for name, pattern in PATTERNS.items():
        for match in pattern.finditer(data):
            if name == "URL with embedded credentials" and data[match.start():].startswith(
                b"https://" + b"user:password@" + b"example.org/story"
            ):
                # Existing test fixture for rejecting URL userinfo, on a reserved domain.
                fixture = b"https://" + b"user:password@" + b"example.org/story"
                after = data[match.start() + len(fixture):match.start() + len(fixture) + 1]
                if after in (b'"', b"'", b" ", b"\n", b""):
                    continue
            result[name] = data[: match.start()].count(b"\n") + 1
            break
    if b"\0" not in data:
        for match in ASSIGNMENT.finditer(data):
            value = next(value for value in match.groups() if value is not None).strip()
            if PLACEHOLDER.fullmatch(value) is None:
                result["literal credential assignment"] = data[: match.start()].count(b"\n") + 1
                break
    return result


def check_item(label, data, check_path=True):
    count = 0
    if check_path:
        parts = {part.lower() for part in Path(label).parts}
        private_folders = {"private", "backups", ".ssh", ".aws", ".gnupg", ".kube"}
        if (PRIVATE_NAME.fullmatch(Path(label).name) or private_folders.intersection(parts)
                or ".config/gh/" in label.lower()):
            print(f"{redact(label)}: private file or archive")
            count += 1
    for name, line in findings(data).items():
        print(f"{redact(label)}:{line}: {name}")
        count += 1
    return count


def index_items():
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        fields, path = record.split(b"\t", 1)
        mode, oid, stage = fields.split()
        if mode != b"160000" and stage == b"0":
            yield os.fsdecode(path), git("cat-file", "blob", oid.decode()), True


def history_items():
    names = {}
    for record in git("rev-list", "--all", "--reflog", "--objects").splitlines():
        oid, _, path = record.partition(b" ")
        if path:
            names[oid] = os.fsdecode(path)
    for row in git("cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)").splitlines():
        oid, kind = row.split()
        if kind not in (b"blob", b"commit", b"tag"):
            continue
        kind = kind.decode()
        label = names.get(oid, f"{kind} {oid.decode()[:12]}")
        yield label, git("cat-file", kind, oid.decode()), kind == "blob"


def workspace_items():
    root = Path.cwd()
    for directory, subdirs, files in os.walk(root):
        current = Path(directory)
        subdirs[:] = [
            name for name in subdirs
            if name not in {".git", "build", "DerivedData"} and not (current / name / ".git").exists()
        ]
        for name in files:
            path = current / name
            if name != ".git" and path.is_file() and not path.is_symlink():
                yield path.relative_to(root).as_posix(), path.read_bytes(), True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scope", choices=("index", "history", "workspace"))
    args = parser.parse_args()
    items = {"index": index_items, "history": history_items, "workspace": workspace_items}
    scanned = count = 0
    for label, data, check_path in items[args.scope]():
        count += check_item(label, data, check_path)
        scanned += 1
    print(f"{args.scope}: {scanned} items, {count} finding(s)")
    return int(count != 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError):
        print("Secret check could not complete. Review Git and file permissions.", file=sys.stderr)
        sys.exit(2)
