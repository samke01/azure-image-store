"""Two page image store backed by Azure Blob Storage.

All access is managed identity based. DefaultAzureCredential() uses the App Service system assigned identity in Azure and falls back to the developer az login locally. No connection string, account key or stored secret appears anywhere in this code or in the app settings. Download links are signed with a user delegation key obtained from Azure AD via that same identity, so private blobs are served directly from Storage without ever issuing an account key to the app.
"""

import os
from datetime import datetime, timedelta, timezone

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from flask import Flask, render_template, request, redirect, url_for, flash

app = Flask(__name__)
# Stable across restarts and gunicorn workers when FLASK_SECRET_KEY is set (it is, as an
# app setting). Falls back to a random per process key for local development.
app.secret_key = os.environ.get("FLASK_SECRET_KEY") or os.urandom(24)

ACCOUNT_NAME = os.environ["STORAGE_ACCOUNT_NAME"]
CONTAINER_NAME = os.environ["IMAGES_CONTAINER_NAME"]
ACCOUNT_URL = f"https://{ACCOUNT_NAME}.blob.core.windows.net"

# Extensions the browser can render inline, used to decide whether a blob gets a
# thumbnail and lightbox preview rather than a generic file card.
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".avif"}

# Built once at module load and reused across requests, since each construction would otherwise pay a token acquisition round trip.
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(account_url=ACCOUNT_URL, credential=credential)


def _is_image(name):
    """True when the blob name has an extension a browser can render inline."""
    return os.path.splitext(name)[1].lower() in IMAGE_EXTENSIONS


def _human_size(num_bytes):
    """Format a byte count as a short human readable string (e.g. '1.2 MB')."""
    size = float(num_bytes or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            # Whole numbers for bytes, one decimal place for larger units.
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024


@app.route("/")
def index():
    """Page 1. List every blob with a short lived signed download link."""
    # Request a user delegation key from Azure AD via the managed identity, scoped only to signing. No account key is involved. The start time is backdated a few minutes so minor clock skew between this host and Storage does not make a freshly signed key look not yet valid.
    now = datetime.now(timezone.utc)
    delegation_key = blob_service_client.get_user_delegation_key(
        key_start_time=now - timedelta(minutes=5),
        key_expiry_time=now + timedelta(hours=1),
    )

    blobs = []
    for blob in blob_service_client.get_container_client(CONTAINER_NAME).list_blobs():
        sas = generate_blob_sas(
            account_name=ACCOUNT_NAME,
            container_name=CONTAINER_NAME,
            blob_name=blob.name,
            user_delegation_key=delegation_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.now(timezone.utc) + timedelta(hours=1),
        )
        url = f"{ACCOUNT_URL}/{CONTAINER_NAME}/{blob.name}?{sas}"
        blobs.append(
            {
                "name": blob.name,
                "url": url,
                "size": _human_size(blob.size),
                "is_image": _is_image(blob.name),
            }
        )

    # Newest-feeling first: keep images grouped at the top of the gallery.
    blobs.sort(key=lambda b: (not b["is_image"], b["name"].lower()))
    return render_template("index.html", blobs=blobs)


@app.route("/upload", methods=["GET", "POST"])
def upload():
    """Page 2. Upload a file into the images container."""
    if request.method == "POST":
        file = request.files.get("file")
        if not file or file.filename == "":
            flash("No file selected.", "error")
            return redirect(url_for("upload"))

        # Stream straight to the SDK. overwrite=True avoids a 409 when the same name is uploaded again.
        blob_service_client.get_blob_client(
            container=CONTAINER_NAME, blob=file.filename
        ).upload_blob(file.stream, overwrite=True)

        flash(f"Uploaded '{file.filename}' successfully.", "success")
        # Redirect after the POST so a browser refresh does not repeat the upload.
        return redirect(url_for("index"))

    return render_template("upload.html")


if __name__ == "__main__":
    app.run()
