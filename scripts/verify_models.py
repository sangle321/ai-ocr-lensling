"""Verify the installed, pinned OCR package before packaging the mobile app."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import urlparse
from urllib.request import url2pathname

root = Path(__file__).resolve().parent.parent
lock = json.loads((root / "models.lock.json").read_text(encoding="utf8"))
config_file = root / ".dart_tool/package_config.json"
if not config_file.exists():
    sys.exit("Run flutter pub get first.")
config = json.loads(config_file.read_text(encoding="utf8"))
package = next(p for p in config["packages"] if p["name"] == lock["package"])
uri = urlparse(package["rootUri"])
package_root = (Path(url2pathname(uri.path)) if uri.scheme == "file"
                else (config_file.parent / package["rootUri"]).resolve())
failed = False
for entry in lock["files"]:
    file = package_root / entry["path"]
    digest = hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else "MISSING"
    ok = digest == entry["sha256"]
    failed |= not ok
    print(f'{"OK" if ok else "FAILED"} {entry["path"]}'
          f' ({file.stat().st_size:,} bytes)' if file.exists()
          else f'MISSING {entry["path"]}')
if failed:
    sys.exit("Model integrity check failed. Do not ship this build.")
print("All four PP-OCRv6 small assets match the reviewed checksums.")
