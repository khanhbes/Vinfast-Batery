"""Inspect packaged filenames/text assets; not a whole-binary or Git-history audit."""
import argparse
import json
import re
import zipfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("apk")
    args = parser.parse_args()
    findings, inspected = [], 0
    with zipfile.ZipFile(args.apk) as archive:
        for item in archive.infolist():
            name = item.filename
            if re.search(r"(?i)(firebase-adminsdk|serviceAccountKey|(?:^|/)\.env(?:\.|$)|\.(?:jks|keystore|pfx)$)", name):
                findings.append({"path": name, "kind": "credential-file"})
            if name.endswith((".json", ".yaml", ".yml", ".txt", ".csv", ".pem", ".key")) and item.file_size < 8 * 1024 * 1024:
                inspected += 1
                payload = archive.read(item)
                if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", payload):
                    findings.append({"path": name, "kind": "private-key"})
                if re.search(rb'''(?i)(?:cloudAuthKey|auth_key|GEMINI_API_KEY)["']?\s*[:=]\s*["'][a-zA-Z0-9_./+\-=]{24,}["']''', payload):
                    findings.append({"path": name, "kind": "literal-secret"})
    print(json.dumps({"textAssetsInspected": inspected, "findings": findings,
        "scope": "APK member names and small text assets; excludes compiled binary strings, model contents and Git history"}))
    return 1 if findings else 0

if __name__ == "__main__":
    raise SystemExit(main())
