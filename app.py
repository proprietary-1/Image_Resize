"""Web server for the Image Resizer.

Receives an uploaded image, runs matlab/process_image.m on it and sends the
result back. On the server the .m file runs in GNU Octave; for local testing
on a PC with MATLAB, set IMAGE_ENGINE=matlab.
"""

import io
import logging
import os
import shutil
import subprocess
import tempfile

from flask import Flask, jsonify, request, send_file
from werkzeug.utils import secure_filename

APP_DIR = os.path.dirname(os.path.abspath(__file__))
MATLAB_DIR = os.path.join(APP_DIR, "matlab")

ENGINE = os.environ.get("IMAGE_ENGINE", "octave")  # "octave" or "matlab"
MATLAB_EXE = os.environ.get("MATLAB_EXE", "matlab")

MAX_BYTES = 10 * 1024 * 1024
RESOLUTIONS = {480, 720, 1080, 1440, 2160}
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}

app = Flask(__name__, static_folder="static", static_url_path="")
app.config["MAX_CONTENT_LENGTH"] = MAX_BYTES + 1024 * 1024  # room for form fields
logging.basicConfig(level=logging.INFO)


def error(message, status=400):
    return jsonify(error=message), status


def matlab_str(text):
    """Quote a value as a MATLAB/Octave string literal."""
    return "'" + text.replace("'", "''") + "'"


def run_engine(in_path, out_path, mode, value):
    call = (f"process_image({matlab_str(in_path)}, {matlab_str(out_path)}, "
            f"{matlab_str(mode)}, {value})")
    setup = f"addpath({matlab_str(MATLAB_DIR)});"

    if ENGINE == "matlab":
        cmd = [MATLAB_EXE, "-batch", f"{setup} {call}"]
    else:
        cmd = ["octave-cli", "--norc", "--quiet", "--eval",
               f"pkg load image; {setup} {call}"]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)

    values = {}
    for line in result.stdout.splitlines():
        key, sep, val = line.strip().partition("=")
        if sep:
            values[key] = val
    return values


@app.get("/")
def index():
    return app.send_static_file("index.html")


@app.get("/health")
def health():
    return "ok"


@app.post("/api/process")
def process():
    upload = request.files.get("image")
    if upload is None or not upload.filename:
        return error("Please choose an image first.")

    stem, ext = os.path.splitext(secure_filename(upload.filename) or "image.jpg")
    ext = ext.lower()
    if ext not in TYPES:
        return error("Only JPG and PNG images are supported.")

    mode = request.form.get("mode")
    try:
        value = int(request.form.get("value", ""))
    except ValueError:
        return error("Invalid option.")

    if mode == "resolution":
        if value not in RESOLUTIONS:
            return error("Choose 480p, 720p, 1080p, 1440p or 4K.")
        out_ext = ".png" if ext == ".png" else ".jpg"
        label = "4K" if value == 2160 else f"{value}p"
    elif mode == "filesize":
        if not 1 <= value <= 95:
            return error("The reduction must be between 1% and 95%.")
        out_ext = ".jpg"
        label = f"{value}pct-smaller"
    else:
        return error("Invalid option.")

    work = tempfile.mkdtemp(prefix="resize-")
    try:
        in_path = os.path.join(work, "input" + ext)
        out_path = os.path.join(work, "output" + out_ext)
        upload.save(in_path)

        original_bytes = os.path.getsize(in_path)
        if original_bytes > MAX_BYTES:
            return error("The image is larger than 10 MB.", 413)

        try:
            info = run_engine(in_path, out_path, mode, value)
        except subprocess.TimeoutExpired:
            return error("Processing took too long. Try a smaller image.", 504)
        except RuntimeError as exc:
            app.logger.warning("Processing failed: %s", exc)
            return error("This file could not be read as an image.", 422)

        with open(out_path, "rb") as f:
            data = f.read()
    finally:
        shutil.rmtree(work, ignore_errors=True)  # images are never kept

    filename = f"{stem or 'image'}_{label}{out_ext}"
    response = send_file(io.BytesIO(data), mimetype=TYPES[out_ext],
                         as_attachment=True, download_name=filename)
    response.headers["X-Filename"] = filename
    response.headers["X-Original-Bytes"] = str(original_bytes)
    for key in ("WIDTH", "HEIGHT", "QUALITY"):
        if key in info:
            response.headers[f"X-{key.title()}"] = info[key]
    return response


@app.errorhandler(413)
def too_large(_):
    return error("The image is larger than 10 MB.", 413)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 7860)), debug=False)
