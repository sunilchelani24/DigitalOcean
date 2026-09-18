# --- Build/run a minimal Flask "hello world" app ---
FROM python:3.12-slim

WORKDIR /app

# Install deps first so Docker can cache this layer between builds
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user (good practice, and some K8s clusters enforce it)
RUN useradd -m appuser
USER appuser

EXPOSE 8080

# gunicorn instead of Flask's dev server — this is what actually runs in the container
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
