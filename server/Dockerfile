FROM python:3.12-slim

LABEL org.opencontainers.image.title="Super-Papagei Server" \
      org.opencontainers.image.description="Hörbuch-Server für die Super-Papagei-App: liest /audiobooks, verwaltet Konten und Hörfortschritt." \
      org.opencontainers.image.version="1.1.12"

# Start page details; release.sh fills them from release.local for your own image.
ARG PUBLIC_URL=""
ARG OPERATOR_NAME=""
ARG OPERATOR_URL=""

# Everything below can be changed in the NAS Docker UI when creating the container.
ENV PUBLIC_URL="${PUBLIC_URL}" \
    OPERATOR_NAME="${OPERATOR_NAME}" \
    OPERATOR_URL="${OPERATOR_URL}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SERVER_NAME="Super-Papagei" \
    ADMIN_USERNAME="admin" \
    ADMIN_PASSWORD="" \
    SCAN_INTERVAL_MINUTES="30" \
    SCAN_THREADS="4" \
    TZ="Europe/Berlin" \
    PUID="" \
    PGID="" \
    PORT="8080" \
    LIBRARY_PATH="/audiobooks" \
    DATA_PATH="/data"

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
# Android app for the download link on the start page (built from ../app).
COPY download ./download
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /data /audiobooks

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s \
  CMD python3 -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/api/health' % os.environ.get('PORT','8080'))" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
