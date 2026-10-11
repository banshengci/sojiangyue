FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# 数据卷挂载点：插件 / 增强包 / sqlite 落在此处。
ENV SONGJIANG_DATA=/data
# 容器内必须监听 0.0.0.0：docker 的端口映射是从容器网卡进来的，绑 127.0.0.1 会收不到。
# 裸机 `python main.py` 的默认值是 127.0.0.1（不对外暴露），容器里由这里显式覆盖。
ENV SONGJIANG_HOST=0.0.0.0
VOLUME ["/data"]

EXPOSE 8000

CMD ["python", "main.py"]
