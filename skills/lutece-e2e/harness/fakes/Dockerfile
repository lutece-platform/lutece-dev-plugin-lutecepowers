FROM python:3.12-slim
COPY app.py /app/app.py
WORKDIR /app
RUN mkdir -p /app/extra
EXPOSE 9030
CMD ["python", "-u", "app.py"]
