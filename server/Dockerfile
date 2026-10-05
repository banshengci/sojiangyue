FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# 数据卷挂载点：插件 / 增强包 / sqlite 落在此处。
ENV SONGJIANG_DATA=/data
VOLUME ["/data"]

EXPOSE 8000

CMD ["python", "main.py"]
