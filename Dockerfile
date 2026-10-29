# Image Resizer: runs the MATLAB code (matlab/process_image.m) in GNU Octave.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      octave octave-image python3-flask gunicorn \
 && rm -rf /var/lib/apt/lists/*

# Hugging Face Spaces runs containers as user 1000.
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user
WORKDIR /home/user/app

COPY --chown=user matlab ./matlab
COPY --chown=user static ./static
COPY --chown=user app.py .

ENV IMAGE_ENGINE=octave
ENV PORT=7860
EXPOSE 7860
# PORT is set by the host (Render uses its own); one worker keeps memory low on free plans.
CMD gunicorn --bind 0.0.0.0:$PORT --workers 1 --threads 2 --timeout 200 app:app
