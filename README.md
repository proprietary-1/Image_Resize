---
title: Image Resizer
emoji: 🖼️
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
---

# Image Resizer

A website that lets you upload an image and either:

- **Change its resolution**: 480p, 720p, 1080p, 1440p or 4K. The shorter side becomes the chosen size and the image keeps its shape.
- **Reduce its file size**: by 20%, 50%, 75% or any percentage you choose. Width and height stay the same, and the result is saved as JPG.

The image processing is written in MATLAB ([matlab/process_image.m](matlab/process_image.m)). On the live site it runs in GNU Octave, a free MATLAB-compatible engine, so it can be hosted for free.

## How it works

```
Browser (static/)  ->  Flask server (app.py)  ->  Octave runs process_image.m  ->  result sent back
```

Uploaded images are deleted as soon as the result is sent back.

## Use the MATLAB code directly

In MATLAB, from the project folder:

```matlab
addpath matlab
process_image('photo.jpg', 'photo_720p.jpg', 'resolution', 720)
process_image('photo.jpg', 'photo_small.jpg', 'filesize', 50)
```

## Run the website on your own PC (with MATLAB)

```powershell
pip install flask
$env:IMAGE_ENGINE = "matlab"
python app.py
```

Then open http://localhost:7860. Each request starts MATLAB, so expect a wait of 10–60 seconds locally. The live site with Octave is much faster.

## Deploy to Hugging Face Spaces (free)

1. Create a free account at https://huggingface.co.
2. Go to **New Space**, give it a name (e.g. `image-resizer`), choose **Docker** → **Blank**, hardware **CPU basic (free)**, and click **Create Space**.
3. Upload the project files (Files → Add file → Upload files): `Dockerfile`, `README.md`, `app.py`, and the `matlab` and `static` folders. You can also push them with git.
4. Wait for the build to finish (about 5–10 minutes the first time). The site is then live at
   `https://<your-username>-image-resizer.hf.space`.

## Keep it awake (free)

Free Spaces go to sleep after 48 hours with no visitors. To prevent that:

- **GitHub Actions**: put this project in a GitHub repository, then add a repository variable `SPACE_URL` set to your site's address (Settings → Secrets and variables → Actions → Variables). The workflow in `.github/workflows/keep-awake.yml` visits the site every 12 hours. GitHub pauses scheduled workflows after 60 days with no commits, so push a small change now and then.
- **Or** use https://cron-job.org (free) to open `https://<your-username>-image-resizer.hf.space/health` every 12 hours.
