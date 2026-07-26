ARG PYTHON_RUNTIME_IMAGE
FROM ${PYTHON_RUNTIME_IMAGE:?PYTHON_RUNTIME_IMAGE_REQUIRED}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app/src/backend
WORKDIR /app
COPY src/backend/requirements-backend.lock /app/src/backend/requirements-backend.lock
RUN python -m pip install --no-cache-dir -r /app/src/backend/requirements-backend.lock
COPY src/backend /app/src/backend
USER 65532:65532
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "edgemint.services.billing:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--no-server-header"]
