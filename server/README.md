# 松江阅增强后端（造梦空间 DreamSpace Server）

家庭 NAS / 私有部署用后端，集中托管三类资源，与松江阅客户端通过 https 对接：

| 资源 | 客户端对接点 | 端点 |
|---|---|---|
| 插件目录 | `PluginMarketClient.fetchCatalog`（配 `PLUGIN_MIRROR_URL` 指向 `/`） | `GET /plugins/catalog` · `POST /plugins` · `GET /plugins/{id}/download` |
| 增强包 | `EnhancementPackService`（导出/导入 `.sjpack.zip`） | `GET /packs` · `POST /packs` · `GET /packs/{id}/download` |
| 运行时配置 | `RuntimeConfig`（配 `RUNTIME_CONFIG_URL`） | `GET /config/runtime` |

## 安全模型
- 上传插件必须带 `sha256`，服务端重新计算比对，不符则拒绝（与客户端一致）。
- 可选 `signerPublicKey` + `signatureHex` 记录发布者签名；`main.py` 中 `upload_plugin`
  已标注 TODO，用 `cryptography` 做 Ed25519 验签即可与客户端闭环。
- 部署时务必走 https（反向代理 / TLS 终结），不要暴露到公网明文端口。

## 运行
```bash
pip install -r requirements.txt
python main.py            # 默认监听 0.0.0.0:8000，数据落在 /data

# 或容器化（适合 UGOS / 群晖 / 飞牛等 NAS）
docker compose up -d
```

## 客户端配置（dart-define 注入）
```bash
flutter build apk --dart-define=PLUGIN_MIRROR_URL=https://your-nas:8000/
flutter build apk --dart-define=RUNTIME_CONFIG_URL=https://your-nas:8000/config/runtime
```
