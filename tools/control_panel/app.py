from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from flask import Flask, Response, abort, redirect, render_template, request, url_for
import subprocess

ROOT_DIR = Path(__file__).resolve().parents[2]
LOG_DIR = ROOT_DIR / "logs" / "control-panel"
LOG_DIR.mkdir(parents=True, exist_ok=True)

SCRIPTS: tuple[str, ...] = (
    "ubuntu_stack_installer.sh",
    "install_full_stack.sh",
    "zeaz_ai_full_stack_installer.sh",
    "start-zLineBot-automos.sh",
    "one-click-deploy-config-installer-starter.sh",
    "stack-workflow-manager.sh",
    "master_installer.sh",
)

app = Flask(__name__)


def _available_scripts() -> list[str]:
    return [script for script in SCRIPTS if (ROOT_DIR / script).exists()]


def _safe_log_path(name: str) -> Path:
    if "/" in name or "\\" in name or name.startswith("."):
        abort(400, "Invalid log name")

    candidate = LOG_DIR / name
    if not candidate.resolve().is_relative_to(LOG_DIR.resolve()):
        abort(400, "Invalid log name")
    return candidate


def _timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _spawn_script(script_name: str) -> Path:
    if script_name not in SCRIPTS:
        abort(400, "Script is not allow-listed")

    script_path = ROOT_DIR / script_name
    if not script_path.exists():
        abort(404, "Script not found")

    log_name = f"{script_path.stem}-{_timestamp()}.log"
    log_path = LOG_DIR / log_name

    with log_path.open("w", encoding="utf-8") as handle:
        handle.write(f"# started: {_timestamp()}\n")
        handle.write(f"# script: {script_name}\n\n")
        handle.flush()

        subprocess.Popen(
            ["bash", str(script_path)],
            cwd=ROOT_DIR,
            stdout=handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    return log_path


def _iter_log_lines(log_path: Path) -> Iterable[str]:
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            yield line


@app.get("/")
def index() -> str:
    logs = sorted((p.name for p in LOG_DIR.glob("*.log")), reverse=True)
    return render_template(
        "index.html",
        scripts=_available_scripts(),
        logs=logs,
    )


@app.post("/run")
def run_script() -> Response:
    script_name = request.form.get("script", "")
    log_path = _spawn_script(script_name)
    return redirect(url_for("view_log", log_name=log_path.name))


@app.get("/logs/<log_name>")
def view_log(log_name: str) -> str:
    log_path = _safe_log_path(log_name)
    if not log_path.exists():
        abort(404, "Log not found")

    return render_template(
        "log.html",
        log_name=log_name,
        log_text="".join(_iter_log_lines(log_path)),
    )


@app.get("/logs/<log_name>/stream")
def stream_log(log_name: str) -> Response:
    log_path = _safe_log_path(log_name)
    if not log_path.exists():
        abort(404, "Log not found")

    def event_stream() -> Iterable[str]:
        with log_path.open("r", encoding="utf-8", errors="replace") as handle:
            while True:
                line = handle.readline()
                if line:
                    yield f"data: {line.rstrip()}\n\n"
                else:
                    time.sleep(0.75)

    return Response(event_stream(), mimetype="text/event-stream")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=True)
