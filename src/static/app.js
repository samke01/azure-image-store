// Client-side enhancements: gallery lightbox preview and upload preview.
// Vanilla JS, no dependencies. The app works without it; this only adds polish.

(function () {
  "use strict";

  /* ---------- Gallery lightbox ---------- */
  const lightbox = document.getElementById("lightbox");
  if (lightbox) {
    const img = document.getElementById("lightbox-img");
    const nameEl = document.getElementById("lightbox-name");
    const download = document.getElementById("lightbox-download");

    function openLightbox(url, name) {
      img.src = url;
      img.alt = name;
      nameEl.textContent = name;
      download.href = url;
      download.setAttribute("download", name);
      lightbox.hidden = false;
      document.body.style.overflow = "hidden";
    }

    function closeLightbox() {
      lightbox.hidden = true;
      img.src = "";
      document.body.style.overflow = "";
    }

    // Delegate clicks from every [data-preview] trigger (thumbnail or button).
    document.addEventListener("click", function (e) {
      const trigger = e.target.closest("[data-preview]");
      if (trigger) {
        e.preventDefault();
        openLightbox(trigger.dataset.url, trigger.dataset.name);
        return;
      }
      if (e.target.closest("[data-close]")) {
        closeLightbox();
      }
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !lightbox.hidden) {
        closeLightbox();
      }
    });
  }

  /* ---------- Upload preview ---------- */
  const form = document.getElementById("upload-form");
  if (form) {
    const input = document.getElementById("file");
    const dropzone = document.getElementById("dropzone");
    const prompt = document.getElementById("dropzone-prompt");
    const preview = document.getElementById("dropzone-preview");
    const previewImg = document.getElementById("preview-img");
    const previewName = document.getElementById("preview-name");
    const previewSize = document.getElementById("preview-size");
    const submitBtn = document.getElementById("submit-btn");
    const clearBtn = document.getElementById("clear-btn");

    function humanSize(bytes) {
      if (!bytes) return "0 B";
      const units = ["B", "KB", "MB", "GB"];
      let i = 0;
      let n = bytes;
      while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
      }
      return (i === 0 ? n : n.toFixed(1)) + " " + units[i];
    }

    function showFile(file) {
      if (!file || !file.type.startsWith("image/")) {
        resetPreview();
        return;
      }
      const reader = new FileReader();
      reader.onload = function (e) {
        previewImg.src = e.target.result;
      };
      reader.readAsDataURL(file);
      previewName.textContent = file.name;
      previewSize.textContent = humanSize(file.size);
      prompt.hidden = true;
      preview.hidden = false;
      submitBtn.disabled = false;
    }

    function resetPreview() {
      input.value = "";
      previewImg.src = "";
      prompt.hidden = false;
      preview.hidden = true;
      submitBtn.disabled = true;
    }

    input.addEventListener("change", function () {
      showFile(input.files[0]);
    });

    // Clear button must not re-trigger the file dialog via the wrapping label.
    clearBtn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      resetPreview();
    });

    // Drag & drop onto the dropzone.
    ["dragenter", "dragover"].forEach(function (evt) {
      dropzone.addEventListener(evt, function (e) {
        e.preventDefault();
        dropzone.classList.add("is-dragover");
      });
    });
    ["dragleave", "dragend", "drop"].forEach(function (evt) {
      dropzone.addEventListener(evt, function (e) {
        e.preventDefault();
        dropzone.classList.remove("is-dragover");
      });
    });
    dropzone.addEventListener("drop", function (e) {
      const file = e.dataTransfer.files[0];
      if (file) {
        input.files = e.dataTransfer.files;
        showFile(file);
      }
    });
  }
})();
