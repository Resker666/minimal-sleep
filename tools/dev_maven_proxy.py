"""Local build-only Maven relay for machines where Java TLS is interrupted.

Run with Python, then set MINIMAL_SLEEP_MAVEN_PROXY=http://127.0.0.1:8765/m2.
It fetches only public artifacts from official Google, Maven Central and
Gradle Plugin repositories. It is never packaged in the Android app.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import json
import shutil
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".tools" / "maven-relay-cache"
SOURCES = (
    "https://repo.maven.apache.org/maven2/",
    "https://dl.google.com/dl/android/maven2/",
    "https://plugins.gradle.org/m2/",
)


class Relay(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.serve_artifact(head_only=True)

    def do_GET(self):
        self.serve_artifact(head_only=False)

    def serve_artifact(self, head_only: bool):
        path = self.path.split("?", 1)[0]
        if not path.startswith("/m2/"):
            self.send_error(404)
            return
        relative = path[4:]
        if not relative or ".." in Path(relative).parts or "\\" in relative:
            self.send_error(400)
            return
        target = CACHE / relative
        upstream_relative = relative
        if relative.endswith((".aar", ".jar")):
            parts = relative.split("/")
            if len(parts) >= 3:
                artifact, version = parts[-3], parts[-2]
                module = CACHE.joinpath(*parts[:-1], f"{artifact}-{version}.module")
                if module.is_file():
                    try:
                        metadata = json.loads(module.read_text(encoding="utf-8"))
                        for variant in metadata.get("variants", []):
                            for file in variant.get("files", []):
                                if file.get("name") == parts[-1] and file.get("url"):
                                    upstream_relative = "/".join(parts[:-1] + [file["url"]])
                                    break
                    except (OSError, ValueError):
                        pass
        if not target.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative.startswith(("com/android/", "androidx/", "com/google/android/")):
                sources = (SOURCES[1], SOURCES[0], SOURCES[2])
            else:
                sources = SOURCES
            last_error = None
            had_network_error = False
            for base in sources:
                for attempt in range(2):
                    temp_path = None
                    try:
                        request = Request(base + upstream_relative, headers={"User-Agent": "minimal-sleep-build-relay/1"})
                        with urlopen(request, timeout=40) as response:
                            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temp:
                                temp_path = Path(temp.name)
                                shutil.copyfileobj(response, temp)
                        temp_path.replace(target)
                        break
                    except HTTPError as error:
                        last_error = error
                        if error.code == 404:
                            break
                        had_network_error = True
                    except (URLError, TimeoutError, OSError) as error:
                        last_error = error
                        had_network_error = True
                    finally:
                        if temp_path is not None and temp_path.exists():
                            temp_path.unlink()
                if target.is_file():
                    break
            if not target.is_file():
                self.send_error(502 if had_network_error else 404)
                return
        self.send_response(200)
        self.send_header("Content-Length", str(target.stat().st_size))
        self.end_headers()
        if not head_only:
            with target.open("rb") as source:
                shutil.copyfileobj(source, self.wfile)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    CACHE.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 8765), Relay)
    print("Maven relay ready on 127.0.0.1:8765", flush=True)
    server.serve_forever()
