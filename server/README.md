# 松江阅增强后端（造梦空间 DreamSpace Server）

家庭 NAS / 私有部署用后端，集中托管三类资源，与松江阅客户端通过 https 对接：

| 资源 | 客户端对接点 | 端点 |
|---|---|---|
| 插件目录 | `PluginMarketClient.fetchCatalog`（配 `PLUGIN_MIRROR_URL` 指向 `/`） | `GET /plugins/catalog` · `POST /plugins` · `GET /plugins/{id}/download` |
| 增强包 | `EnhancementPackService`（导出/导入 `.sjpack.zip`） | `GET /packs` · `POST /packs` · `GET /packs/{id}/download` |
| 运行时配置 | `RuntimeConfig`（配 `RUNTIME_CONFIG_URL`） | `GET /config/runtime` |

## 安全模型
- **写接口需凭据**：`POST /plugins`、`POST /packs`、`POST /packs/gameplay` 需带
  `X-Songjiang-Token: $SONGJIANG_TOKEN`。**未配置 `SONGJIANG_TOKEN` 时写接口一律 503**
  （fail-closed：宁可不给上传，也不留一个无鉴权的公开写口）。
- **上传大小上限**：默认 64 MiB（`SONGJIANG_MAX_UPLOAD` 可调），超限 413。
- **所有落盘路径都过包含校验**：`name` / `id` 先规范化为单个路径段，再校验拼出的路径必须
  落在 `packs/`（或 `plugins/`）之内；绝对路径与 `../` 一律 400。修复前 `POST /packs` 的表单
  字段 `name` 可写穿到数据目录之外。
- 上传插件必须带 `sha256`，服务端重新计算比对，不符则拒绝（与客户端一致）。
- 可选 `signerPublicKey` + `signatureHex` 记录发布者签名；`main.py` 中 `upload_plugin`
  已标注 TODO，用 `cryptography` 做 Ed25519 验签即可与客户端闭环。
- 部署时务必走 https（反向代理 / TLS 终结），不要暴露到公网明文端口。

## 环境变量
| 变量 | 默认 | 作用 |
|---|---|---|
| `SONGJIANG_DATA` | `/data` | 数据根目录（plugins/ packs/ songjiang.db） |
| `SONGJIANG_HOST` | `127.0.0.1` | 监听地址。裸机默认只听环回；**容器由镜像设为 `0.0.0.0`** |
| `SONGJIANG_PORT` | `8000` | 监听端口 |
| `SONGJIANG_TOKEN` | 空 | 写接口凭据。**留空 = 写接口关闭（503）** |
| `SONGJIANG_MAX_UPLOAD` | `67108864`（64 MiB） | 单次上传字节上限 |
| `SONGJIANG_READ_NEEDS_TOKEN` | 空 | 设为 `1` 时读接口也要求 token（老客户端会读不到目录，按需开启） |

## 运行
```bash
pip install -r requirements.txt
export SONGJIANG_TOKEN="$(head -c 24 /dev/urandom | base64)"   # 写接口凭据
python main.py            # 默认监听 127.0.0.1:8000，数据落在 /data

# 或容器化（适合 UGOS / 群晖 / 飞牛等 NAS）
export SONGJIANG_TOKEN="..."    # compose 会把它透传进容器
docker compose up -d
```

上传示例（写接口都要带 token）：
```bash
curl -X POST http://127.0.0.1:8000/packs \
  -H "X-Songjiang-Token: $SONGJIANG_TOKEN" \
  -F 'name=名著包' -F 'author=me' -F 'description=demo' -F 'pack_type=enhancement' \
  -F 'file=@mypack.sjpack.zip'
```

## 客户端配置（dart-define 注入）
```bash
flutter build apk --dart-define=PLUGIN_MIRROR_URL=https://your-nas:8000/
flutter build apk --dart-define=RUNTIME_CONFIG_URL=https://your-nas:8000/config/runtime
```
