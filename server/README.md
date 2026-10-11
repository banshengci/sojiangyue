# 松江阅增强后端（造梦空间 DreamSpace Server）

家庭 NAS / 私有部署用后端，集中托管三类资源，与松江阅客户端通过 https 对接：

| 资源 | 客户端对接点 | 端点 |
|---|---|---|
| 插件目录 | `PluginMarketClient.fetchCatalog`（配 `PLUGIN_MIRROR_URL` 指向 `/`） | `GET /plugins/catalog` · **`GET /plugins-catalog.json`（别名，客户端实际请求的就是它）** · `POST /plugins` · `GET /plugins/{id}/download` |
| 增强包 | `EnhancementPackService`（导出/导入 `.sjpack.zip`） | `GET /packs` · `POST /packs` · `GET /packs/{id}/download` |
| 玩法包目录 | `GameplayPackMarketClient.fetchCatalog`（配 `GAMEPACK_MIRROR_URL`） | `GET /gameplay/catalog` · **`GET /gameplay-catalog.json`（别名）** · `POST /packs/gameplay` |
| 运行时配置 | `RuntimeConfig`（配 `RUNTIME_CONFIG_URL`） | `GET /config/runtime` |

> 别名路由是必须的：客户端拼的是 `${镜像根}plugins-catalog.json` / `${镜像根}gameplay-catalog.json`，
> 原先只有 `/plugins/catalog` 与 `/gameplay/catalog`，自托管用户按本 README 配置后会 404，
> 而客户端会**静默回退到随包示例**（看起来正常，实际永远只有两个示例插件）。

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
# 自建 NAS（内网 https 或 http 都行，见下面"随包/内网"说明）
flutter build apk \
  --dart-define=PLUGIN_MIRROR_URL=https://your-nas:8000/ \
  --dart-define=GAMEPACK_MIRROR_URL=https://your-nas:8000/ \
  --dart-define=RUNTIME_CONFIG_URL=https://your-nas:8000/config/runtime \
  --dart-define=PLUGIN_SIGNER_KEYS=<你自己的 Ed25519 公钥 hex>
```

### 内网镜像与安全策略的关系（重要）
客户端 `PluginSecurity.isSafeUrl` 默认拒绝一切内网/回环地址（防 SSRF），所以"把镜像指向自家 NAS"
必须走**受控例外**，规则如下：

1. **例外名单只来自你填的 dart-define**：库会解析 `PLUGIN_MIRROR_URL` / `GAMEPACK_MIRROR_URL` /
   `RUNTIME_CONFIG_URL` 的主机名作为 `trustedHosts`。攻击者控制的目录响应**无法**把自己加进白名单
   —— 这是"自托管可用"与"不放开内网 SSRF"能同时成立的关键。
2. **明文 `http` 的例外，只在"已固定发布者公钥"时生效**（即必须同时配 `PLUGIN_SIGNER_KEYS`）。
   铁律：**先固定公钥，再允许 LAN http**。理由：TLS 保证机密性、签名保证完整性；内网 NAS 用自签
   证书时客户端 TLS 校验会失败，此时若没有签名固定就放行明文，等于把完整性校验一并拆掉。
3. 公钥固定后，未在名单内的发布者一律拒装；过渡期可用 `--dart-define=PLUGIN_ALLOW_UNPINNED=true`
   临时放行（默认 `false`，**不要**用在正式分发构建里）。
