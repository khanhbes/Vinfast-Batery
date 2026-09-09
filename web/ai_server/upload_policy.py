"""Public uploads never enter Python-object deserializers.

Trusted, locally provisioned legacy models remain supported by the runtime.
"""
import os
import re
import tempfile

MAX_UPLOAD_BYTES = 64 * 1024 * 1024
UPLOAD_EXTENSIONS = {'.onnx', '.tflite'}


def validate_upload(filename, version=None):
    ext = os.path.splitext(filename or '')[1].lower()
    if ext not in UPLOAD_EXTENSIONS:
        raise ValueError('Chỉ nhận model .onnx hoặc .tflite qua upload web')
    if version is not None and (not isinstance(version, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', version)):
        raise ValueError('Version phải có 1–128 ký tự: chữ, số, dấu chấm, gạch ngang hoặc gạch dưới')
    return ext


def copy_upload(stream, ext, limit=MAX_UPLOAD_BYTES):
    """Bound memory/disk use and remove a partial file on every failure."""
    path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as target:
            path = target.name
            size = 0
            while chunk := stream.read(min(1024 * 1024, limit + 1 - size)):
                size += len(chunk)
                if size > limit:
                    raise ValueError('Model vượt giới hạn 64 MiB')
                target.write(chunk)
            if size == 0:
                raise ValueError('File model rỗng')
        return path
    except Exception:
        if path is not None:
            os.unlink(path)
        raise
