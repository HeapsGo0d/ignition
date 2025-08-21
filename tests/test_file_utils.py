import tempfile
import hashlib
from pathlib import Path
import sys

import pytest

sys.path.append(str(Path(__file__).resolve().parents[1]))

from scripts.file_utils import AtomicFileHandler



@pytest.fixture
def handler(tmp_path, monkeypatch):
    """Create an AtomicFileHandler using a temporary models directory."""
    monkeypatch.setenv("COMFYUI_MODELS_DIR", str(tmp_path / "models"))
    return AtomicFileHandler(workspace_root=str(tmp_path))


@pytest.fixture
def temp_file():
    """Create a temporary file with known content."""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(b"test content")
        path = Path(tmp.name)
    try:
        yield path
    finally:
        path.unlink()


def file_info(path: Path):
    data = path.read_bytes()
    return len(data), hashlib.sha256(data).hexdigest()


def test_verify_file_success(handler, temp_file):
    size, digest = file_info(temp_file)
    assert handler.verify_file(temp_file, expected_size=size, expected_hash=digest)


def test_verify_file_wrong_size(handler, temp_file):
    size, digest = file_info(temp_file)
    assert not handler.verify_file(temp_file, expected_size=size + 1, expected_hash=digest)


def test_verify_file_wrong_hash(handler, temp_file):
    size, _ = file_info(temp_file)
    wrong_hash = "0" * 64
    assert not handler.verify_file(temp_file, expected_size=size, expected_hash=wrong_hash)
