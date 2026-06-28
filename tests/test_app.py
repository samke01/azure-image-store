"""Backend tests for the Flask image store.

Only the Azure boundary is mocked (the module-level blob client and the SAS
signer). Everything else runs for real: routing, the Jinja templates, the
helper functions, and the image-first sort order.
"""

import io
from unittest.mock import MagicMock, patch

import pytest

import app as appmod


@pytest.fixture
def client():
    appmod.app.config.update(TESTING=True)
    return appmod.app.test_client()


def _blob(name, size):
    # Mock(name=...) sets the mock's repr, not a .name attribute, so set it after.
    b = MagicMock()
    b.name = name
    b.size = size
    return b


# ---- Pure helpers, no mocking needed ---------------------------------------

@pytest.mark.parametrize(
    "name,expected",
    [
        ("photo.jpg", True),
        ("PHOTO.JPG", True),
        ("diagram.PNG", True),
        ("clip.webp", True),
        ("notes.txt", False),
        ("archive.tar.gz", False),
        ("noext", False),
    ],
)
def test_is_image(name, expected):
    assert appmod._is_image(name) is expected


@pytest.mark.parametrize(
    "size,expected",
    [
        (None, "0 B"),
        (0, "0 B"),
        (512, "512 B"),
        (1024, "1.0 KB"),
        (1536, "1.5 KB"),
        (1048576, "1.0 MB"),
    ],
)
def test_human_size(size, expected):
    assert appmod._human_size(size) == expected


# ---- Index route ------------------------------------------------------------

def test_index_lists_blobs_images_first(client):
    container = MagicMock()
    # Deliberately out of order: a non-image first, an image second.
    container.list_blobs.return_value = [_blob("report.pdf", 1024), _blob("cat.png", 2048)]

    with patch.object(appmod, "blob_service_client") as bsc, patch.object(
        appmod, "generate_blob_sas", return_value="sig=abc"
    ):
        bsc.get_container_client.return_value = container
        resp = client.get("/")

    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "cat.png" in body
    assert "report.pdf" in body
    # The signed SAS is part of the rendered download link.
    assert "sig=abc" in body
    # The image is sorted ahead of the non-image.
    assert body.index("cat.png") < body.index("report.pdf")


def test_index_empty_state(client):
    container = MagicMock()
    container.list_blobs.return_value = []

    with patch.object(appmod, "blob_service_client") as bsc, patch.object(
        appmod, "generate_blob_sas", return_value="x"
    ):
        bsc.get_container_client.return_value = container
        resp = client.get("/")

    assert resp.status_code == 200
    assert "No files yet" in resp.get_data(as_text=True)


# ---- Upload route -----------------------------------------------------------

def test_upload_get_renders_form(client):
    resp = client.get("/upload")
    assert resp.status_code == 200
    assert "Upload a file" in resp.get_data(as_text=True)


def test_upload_post_stores_blob_and_redirects(client):
    blob_client = MagicMock()

    with patch.object(appmod, "blob_service_client") as bsc:
        bsc.get_blob_client.return_value = blob_client
        resp = client.post(
            "/upload",
            data={"file": (io.BytesIO(b"image-bytes"), "new.png")},
            content_type="multipart/form-data",
        )

    assert resp.status_code == 302
    assert resp.headers["Location"].endswith("/")
    bsc.get_blob_client.assert_called_once_with(
        container=appmod.CONTAINER_NAME, blob="new.png"
    )
    blob_client.upload_blob.assert_called_once()


def test_upload_post_without_file_flashes_and_redirects(client):
    with patch.object(appmod, "blob_service_client") as bsc:
        resp = client.post(
            "/upload", data={}, content_type="multipart/form-data"
        )

    assert resp.status_code == 302
    assert resp.headers["Location"].endswith("/upload")
    # Nothing is written to storage when no file was provided.
    bsc.get_blob_client.assert_not_called()
