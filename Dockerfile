# Single-stage python runtime. FastAPI serves the HTMX UI via Jinja2
# templates + StaticFiles (no node, no npm, no SPA bundle).

FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
		gcc \
		postgresql-client \
	&& rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir \
		--timeout 300 \
		--retries 10 \
		-r requirements.txt

COPY backend/ ./backend/
COPY alembic/ ./alembic/
COPY alembic.ini ./

ENV PYTHONUNBUFFERED=1 \
	PYTHONDONTWRITEBYTECODE=1

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "backend.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
