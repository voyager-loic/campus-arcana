#!/usr/bin/env python3
"""Allow non-threaded Godot web exports to run from private LAN addresses.

Godot 4.7's generated loader treats every non-secure context as fatal, even
when the export does not use threads. Its AudioWorklet driver also requires a
secure context. For explicit LAN mode, keep the guard for public hosts, allow
RFC1918 addresses, and use Godot's Dummy audio driver. The result supports
keyboard/mouse gameplay over HTTP but intentionally has no browser audio or
voice input.
"""

from pathlib import Path
import sys


SOURCE = "if (!Features.isSecureContext()) {"
PATCHED = (
    "if (!Features.isSecureContext() && "
    "!/^(localhost|127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2\\d|3[01])\\.)/"
    ".test(window.location.hostname)) {"
)
AUDIO_SOURCE = '"args":[]'
AUDIO_PATCHED = '"args":["--audio-driver","Dummy"]'


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web/index.js")
    text = path.read_text(encoding="utf-8")

    if PATCHED not in text:
        count = text.count(SOURCE)
        if count != 1:
            raise SystemExit(
                f"Expected one Godot secure-context check in {path}, found {count}. "
                "The generated loader may have changed."
            )
        path.write_text(text.replace(SOURCE, PATCHED, 1), encoding="utf-8")

    html_path = path.with_name("index.html")
    html = html_path.read_text(encoding="utf-8")
    if AUDIO_PATCHED not in html:
        audio_count = html.count(AUDIO_SOURCE)
        if audio_count != 1:
            raise SystemExit(
                f"Expected one empty Godot argument list in {html_path}, "
                f"found {audio_count}. The generated shell may have changed."
            )
        html_path.write_text(
            html.replace(AUDIO_SOURCE, AUDIO_PATCHED, 1), encoding="utf-8"
        )

    print(f"Enabled private-LAN HTTP clients in {path.parent}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
