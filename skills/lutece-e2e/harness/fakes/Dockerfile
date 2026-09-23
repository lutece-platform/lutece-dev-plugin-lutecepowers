FROM python:3.12-slim
COPY app.py fakes-cert.pem fakes-key.pem /app/
WORKDIR /app
RUN mkdir -p /app/extra
EXPOSE 9030 9443
CMD ["python", "-u", "app.py"]
