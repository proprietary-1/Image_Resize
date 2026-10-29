const MAX_BYTES = 10 * 1024 * 1024;
const TYPES = ["image/jpeg", "image/png"];

const $ = (id) => document.getElementById(id);

const state = {
  file: null,
  width: 0,
  height: 0,
  mode: "resolution",
  resolution: 720,
  percent: 50,
  resultUrl: null,
  previewUrl: null,
};

// ---------- helpers ----------
function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function resolutionLabel(value) {
  return value === 2160 ? "4K" : `${value}p`;
}

function targetSize(value) {
  const { width: w, height: h } = state;
  return h <= w
    ? { width: Math.round((w * value) / h), height: value }
    : { width: value, height: Math.round((h * value) / w) };
}

function showError(message) {
  $("error").textContent = message;
  $("error").hidden = !message;
}

// ---------- upload ----------
function loadFile(file) {
  showError("");
  if (!file) return;
  if (!TYPES.includes(file.type)) {
    showError("Please choose a JPG or PNG image.");
    return;
  }
  if (file.size > MAX_BYTES) {
    showError(`This image is ${formatBytes(file.size)}. The limit is 10 MB.`);
    return;
  }

  if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
  const url = URL.createObjectURL(file);
  const img = $("preview-img");
  img.onload = () => {
    state.file = file;
    state.previewUrl = url;
    state.width = img.naturalWidth;
    state.height = img.naturalHeight;
    $("file-name").textContent = file.name;
    $("file-meta").textContent = `${state.width} × ${state.height} px · ${formatBytes(file.size)}`;
    $("dropzone").hidden = true;
    $("preview").hidden = false;
    $("options-card").setAttribute("aria-disabled", "false");
    $("result-card").hidden = true;
    update();
  };
  img.onerror = () => {
    URL.revokeObjectURL(url);
    showError("This file could not be opened as an image.");
  };
  img.src = url;
}

const dropzone = $("dropzone");
$("file-input").addEventListener("change", (e) => loadFile(e.target.files[0]));
["dragenter", "dragover"].forEach((type) =>
  dropzone.addEventListener(type, (e) => {
    e.preventDefault();
    dropzone.classList.add("dragging");
  })
);
["dragleave", "drop"].forEach((type) =>
  dropzone.addEventListener(type, (e) => {
    e.preventDefault();
    dropzone.classList.remove("dragging");
  })
);
dropzone.addEventListener("drop", (e) => loadFile(e.dataTransfer.files[0]));
$("change-file").addEventListener("click", () => $("file-input").click());

// ---------- options ----------
document.querySelectorAll(".tab").forEach((tab) =>
  tab.addEventListener("click", () => {
    state.mode = tab.dataset.mode;
    document.querySelectorAll(".tab").forEach((t) => {
      t.classList.toggle("active", t === tab);
      t.setAttribute("aria-selected", t === tab);
    });
    $("panel-resolution").hidden = state.mode !== "resolution";
    $("panel-filesize").hidden = state.mode !== "filesize";
    showError("");
    update();
  })
);

function selectChip(container, chip) {
  container.querySelectorAll(".chip").forEach((c) => c.classList.toggle("selected", c === chip));
}

$("resolution-chips").addEventListener("click", (e) => {
  const chip = e.target.closest(".chip");
  if (!chip) return;
  selectChip(e.currentTarget, chip);
  state.resolution = Number(chip.dataset.value);
  update();
});

$("filesize-chips").addEventListener("click", (e) => {
  const chip = e.target.closest(".chip");
  if (!chip) return;
  selectChip(e.currentTarget, chip);
  state.percent = Number(chip.dataset.value);
  $("custom-percent").value = "";
  update();
});

$("custom-percent").addEventListener("input", (e) => {
  const value = Number(e.target.value);
  selectChip($("filesize-chips"), null);
  state.percent = Number.isInteger(value) && value >= 1 && value <= 95 ? value : null;
  update();
});

function update() {
  const btn = $("process-btn");
  const label = btn.querySelector(".btn-label");

  if (!state.file) {
    btn.disabled = true;
    label.textContent = "Upload an image first";
    return;
  }

  if (state.mode === "resolution") {
    const size = targetSize(state.resolution);
    $("resolution-estimate").textContent =
      `${state.width} × ${state.height} → ${size.width} × ${size.height} px`;
    $("upscale-warning").hidden = state.resolution <= Math.min(state.width, state.height);
    btn.disabled = false;
    label.textContent = `Convert to ${resolutionLabel(state.resolution)}`;
  } else {
    if (state.percent === null) {
      $("filesize-estimate").textContent = "Enter a number from 1 to 95.";
      btn.disabled = true;
      label.textContent = "Reduce file size";
      return;
    }
    const target = state.file.size * (1 - state.percent / 100);
    $("filesize-estimate").textContent =
      `${formatBytes(state.file.size)} → about ${formatBytes(Math.round(target))}`;
    btn.disabled = false;
    label.textContent = `Reduce by ${state.percent}%`;
  }
}

// ---------- process ----------
$("process-btn").addEventListener("click", async () => {
  const btn = $("process-btn");
  const label = btn.querySelector(".btn-label");
  const previousLabel = label.textContent;

  showError("");
  btn.disabled = true;
  btn.classList.add("loading");
  label.textContent = "Processing…";

  const form = new FormData();
  form.append("image", state.file);
  form.append("mode", state.mode);
  form.append("value", state.mode === "resolution" ? state.resolution : state.percent);

  try {
    const response = await fetch("api/process", { method: "POST", body: form });
    if (!response.ok) {
      let message = "Something went wrong. Please try again.";
      try {
        message = (await response.json()).error || message;
      } catch {}
      throw new Error(message);
    }
    const blob = await response.blob();
    showResult(blob, response.headers);
  } catch (err) {
    showError(err.message === "Failed to fetch"
      ? "Could not reach the server. Check your connection and try again."
      : err.message);
  } finally {
    btn.disabled = false;
    btn.classList.remove("loading");
    label.textContent = previousLabel;
  }
});

function showResult(blob, headers) {
  if (state.resultUrl) URL.revokeObjectURL(state.resultUrl);
  state.resultUrl = URL.createObjectURL(blob);

  const width = headers.get("X-Width");
  const height = headers.get("X-Height");
  const filename = headers.get("X-Filename") || "image";

  $("result-img").src = state.resultUrl;
  $("before-stats").textContent = `${state.width} × ${state.height} px · ${formatBytes(state.file.size)}`;
  $("after-stats").textContent = `${width} × ${height} px · ${formatBytes(blob.size)}`;

  const download = $("download-btn");
  download.href = state.resultUrl;
  download.download = filename;

  const notes = [];
  if (state.mode === "filesize") {
    const target = state.file.size * (1 - state.percent / 100);
    const saved = Math.round((1 - blob.size / state.file.size) * 100);
    if (blob.size > target) {
      notes.push(`This is the smallest this image can get at its current resolution (${Math.max(saved, 0)}% smaller). Try the Resolution tab to shrink it further.`);
    }
    if (state.file.type === "image/png") notes.push("Saved as JPG so the file could be made smaller.");
  }
  $("result-note").textContent = notes.join(" ");
  $("result-note").hidden = notes.length === 0;

  $("result-card").hidden = false;
  $("result-card").scrollIntoView({ behavior: "smooth", block: "start" });
}

// ---------- restart ----------
$("restart-btn").addEventListener("click", () => {
  if (state.resultUrl) URL.revokeObjectURL(state.resultUrl);
  if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
  Object.assign(state, { file: null, width: 0, height: 0, resultUrl: null, previewUrl: null });
  $("file-input").value = "";
  $("dropzone").hidden = false;
  $("preview").hidden = true;
  $("result-card").hidden = true;
  $("options-card").setAttribute("aria-disabled", "true");
  showError("");
  update();
  window.scrollTo({ top: 0, behavior: "smooth" });
});

update();
