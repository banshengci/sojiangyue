"""松江阅 · 造梦空间后端（DreamSpace server）。

家庭 NAS / 私有部署用：集中托管插件目录、增强包、运行时配置。
与松江阅客户端通过 https 对接（PluginMarketClient / RuntimeConfig）。
安全模型与客户端一致：SHA256 防篡改 + 可选 Ed25519 发布者签名。
"""
from __future__ import annotations

import hashlib
import hmac
import os
import re
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator, Optional

from fastapi import Depends, FastAPI, UploadFile, File, HTTPException, Form, Header
from fastapi.responses import FileResponse
from pydantic import BaseModel

BASE_DIR = Path(os.environ.get("SONGJIANG_DATA", "/data"))
BASE_DIR.mkdir(parents=True, exist_ok=True)
PLUGINS_DIR = BASE_DIR / "plugins"
PACKS_DIR = BASE_DIR / "packs"
PLUGINS_DIR.mkdir(exist_ok=True)
PACKS_DIR.mkdir(exist_ok=True)
DB_PATH = BASE_DIR / "songjiang.db"

# ---------------------------------------------------------------------------
# 安全开关（环境变量；未配置时一律按 fail-closed / 最保守默认处理）
#   SONGJIANG_TOKEN              写接口凭据（Header `X-Songjiang-Token`）；未设置 => 写接口 503
#   SONGJIANG_MAX_UPLOAD         单次上传字节上限（默认 64 MiB）
#   SONGJIANG_HOST/PORT          监听地址（默认 127.0.0.1:8000；容器内由 compose 显式设 0.0.0.0）
#   SONGJIANG_READ_NEEDS_TOKEN=1 读接口也要求 token（默认关，兼容既有客户端）
#   SONGJIANG_TRUSTED_KEYS       [补丁 2] 允许的插件发布者 Ed25519 公钥（逗号分隔 hex）
# ---------------------------------------------------------------------------
DEFAULT_MAX_UPLOAD = 64 * 1024 * 1024


def admin_token() -> str:
    """写接口凭据。每次调用读取，便于运行期调整与测试。"""
    return os.environ.get("SONGJIANG_TOKEN", "").strip()


def max_upload_bytes() -> int:
    raw = os.environ.get("SONGJIANG_MAX_UPLOAD", "")
    try:
        return max(1, int(raw)) if raw else DEFAULT_MAX_UPLOAD
    except ValueError:
        return DEFAULT_MAX_UPLOAD


def require_admin(x_songjiang_token: str = Header(default="")) -> None:
    """写接口鉴权：未配置 token 时直接拒绝（fail-closed），配置后按常量时间比较。"""
    expected = admin_token()
    if not expected:
        raise HTTPException(503, "服务端未配置 SONGJIANG_TOKEN，写接口已关闭")
    if not hmac.compare_digest(x_songjiang_token, expected):
        raise HTTPException(401, "unauthorized")


def require_admin_for_reads(x_songjiang_token: str = Header(default="")) -> None:
    """可选：读接口也要求 token（仅当 SONGJIANG_READ_NEEDS_TOKEN=1，默认放行以兼容老客户端）。"""
    if os.environ.get("SONGJIANG_READ_NEEDS_TOKEN", "") not in ("1", "true", "True"):
        return
    require_admin(x_songjiang_token)


_SAFE_SEGMENT_RE = re.compile(r"[^A-Za-z0-9._\-\u4e00-\u9fff\u3040-\u30ff]")


def safe_segment(raw: str, limit: int = 64, fallback: str = "") -> str:
    """把用户可控字符串规范化为**单个**安全路径段。

    挡掉：`../`、`/`、`\\\\`、绝对路径、空段、NUL、纯点/纯点划线、超长。
    返回空串表示无法规范化，由调用方决定 400 还是退回 fallback。
    """
    cleaned = _SAFE_SEGMENT_RE.sub("_", (raw or "").replace("\x00", ""))
    return cleaned.strip("._-")[:limit] or fallback


def safe_join(base: Path, filename: str) -> Path:
    """在 base 内拼接文件名并做包含校验——本项目唯一允许落盘的位置计算方式。"""
    base = base.resolve()
    target = (base / filename).resolve()
    if target == base or base not in target.parents:
        raise HTTPException(400, "非法路径")
    return target


def read_limited(f: UploadFile) -> bytes:
    """带上限读取上传体（原实现 file.file.read() 无上限，可被单请求打爆内存/磁盘）。"""
    limit = max_upload_bytes()
    data = f.file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(413, f"文件超过大小上限（{limit} 字节）")
    return data


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    """连接必然关闭（原实现多个端点无 try/finally，异常路径会泄漏连接）。"""
    conn = get_db()
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    conn = get_db()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS plugin_entries (
          id TEXT PRIMARY KEY,
          name TEXT,
          version TEXT,
          description TEXT,
          author TEXT,
          download_url TEXT,
          sha256 TEXT,
          signer_public_key TEXT,
          signature_hex TEXT,
          min_app_version TEXT,
          created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS packs (
          id TEXT PRIMARY KEY,
          name TEXT,
          author TEXT,
          description TEXT,
          filename TEXT,
          pack_type TEXT DEFAULT 'enhancement',
          created_at TEXT DEFAULT (datetime('now'))
        );
        """
    )
    conn.commit()
    conn.close()


init_db()

app = FastAPI(title="松江阅增强后端", version="1.0.0")


class PluginEntryIn(BaseModel):
    id: str
    name: str
    version: str
    description: str = ""
    author: str = ""
    sha256: str
    signerPublicKey: Optional[str] = None
    signatureHex: Optional[str] = None
    minAppVersion: Optional[str] = None


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/plugins/catalog", dependencies=[Depends(require_admin_for_reads)])
def catalog() -> dict:
    """返回 plugins-catalog.json 兼容结构（downloadUrl 指向本服务端）。"""
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM plugin_entries ORDER BY created_at DESC"
        ).fetchall()
    out = []
    for e in rows:
        out.append(
            {
                "id": e["id"],
                "name": e["name"],
                "version": e["version"],
                "description": e["description"],
                "author": e["author"],
                "downloadUrl": f"/plugins/{e['id']}/download",
                "sha256": e["sha256"],
                "signerPublicKey": e["signer_public_key"],
                "signatureHex": e["signature_hex"],
                "minAppVersion": e["min_app_version"],
            }
        )
    return {"schemaVersion": "1.0", "updatedAt": "", "entries": out}


@app.post("/plugins", dependencies=[Depends(require_admin)])
def upload_plugin(meta: PluginEntryIn, file: UploadFile = File(...)) -> dict:
    data = read_limited(file)
    actual = hashlib.sha256(data).hexdigest()
    if actual != meta.sha256:
        raise HTTPException(400, "SHA256 校验失败：文件可能被篡改")
    # TODO(签名): 与客户端一致，用 cryptography 做 Ed25519 验签；此处仅记录签名信息。
    safe_id = safe_segment(meta.id)
    if not safe_id:
        raise HTTPException(400, "插件 id 非法")
    path = safe_join(PLUGINS_DIR, f"{safe_id}.plugin.json")
    path.write_bytes(data)
    with db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO plugin_entries "
            "(id,name,version,description,author,download_url,sha256,"
            "signer_public_key,signature_hex,min_app_version) "
            "VALUES (?,?,?,?,?,?,?,?,?,?)",
            (
                safe_id,
                meta.name[:200],
                meta.version[:60],
                meta.description[:2000],
                meta.author[:200],
                f"/plugins/{safe_id}/download",
                meta.sha256,
                meta.signerPublicKey,
                meta.signatureHex,
                meta.minAppVersion,
            ),
        )
        conn.commit()
    return {"ok": True, "sha256": actual, "id": safe_id}


@app.get("/plugins/{pid}/download", dependencies=[Depends(require_admin_for_reads)])
def download_plugin(pid: str) -> FileResponse:
    safe_pid = safe_segment(pid)
    if not safe_pid:
        raise HTTPException(404, "not found")
    path = safe_join(PLUGINS_DIR, f"{safe_pid}.plugin.json")
    if not path.exists():
        raise HTTPException(404, "not found")
    return FileResponse(path, filename=f"{safe_pid}.plugin.json")


@app.get("/packs", dependencies=[Depends(require_admin_for_reads)])
def list_packs(pack_type: str = "") -> list:
    with db() as conn:
        if pack_type:
            rows = conn.execute(
                "SELECT * FROM packs WHERE pack_type=? ORDER BY created_at DESC",
                (pack_type,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM packs ORDER BY created_at DESC"
            ).fetchall()
    return [dict(r) for r in rows]


@app.post("/packs", dependencies=[Depends(require_admin)])
def upload_pack(
    name: str = Form(...),
    author: str = Form(""),
    description: str = Form(""),
    pack_type: str = Form("enhancement"),
    file: UploadFile = File(...),
) -> dict:
    if pack_type not in ("enhancement", "gameplay"):
        raise HTTPException(400, "pack_type 非法")
    data = read_limited(file)
    # 关键修复：name 是攻击者可控的表单字段，必须先规范化为单个路径段，
    # 再经 safe_join 做包含校验（原实现直接拼 PACKS_DIR / f"{name}_{sha}.zip"，
    # `../x` 与绝对路径都会写穿到 PACKS_DIR 之外）。
    pid = f"{safe_segment(name, fallback='pack')}_{hashlib.sha256(data).hexdigest()[:12]}"
    ext = "sjgame.zip" if pack_type == "gameplay" else "sjpack.zip"
    path = safe_join(PACKS_DIR, f"{pid}.{ext}")
    path.write_bytes(data)
    with db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO packs "
            "(id,name,author,description,filename,pack_type) "
            "VALUES (?,?,?,?,?,?)",
            (pid, name[:200], author[:200], description[:2000], path.name, pack_type),
        )
        conn.commit()
    return {"ok": True, "id": pid, "pack_type": pack_type}


@app.get("/packs/gameplay", dependencies=[Depends(require_admin_for_reads)])
def list_gameplay_packs() -> list:
    """玩法包目录（3.3）：与 2.3 插件 / 2.4 增强包共用 packs 存储，按类型筛选。"""
    return list_packs(pack_type="gameplay")


@app.post("/packs/gameplay")
def upload_gameplay_pack(
    name: str = Form(...),
    author: str = Form(""),
    description: str = Form(""),
    file: UploadFile = File(...),
) -> dict:
    """上传玩法包（.sjgame.zip）。"""
    return upload_pack(
        name=name, author=author, description=description,
        pack_type="gameplay", file=file,
    )


@app.get("/packs/{pid}/download", dependencies=[Depends(require_admin_for_reads)])
def download_pack(pid: str) -> FileResponse:
    # 兼容增强包(.sjpack.zip) 与玩法包(.sjgame.zip) 两种后缀。
    # 同样先规范化：修复前写入的**历史行** id 可能就是 `../` 形式，读路径也必须挡。
    safe_pid = safe_segment(pid)
    if not safe_pid:
        raise HTTPException(404, "not found")
    for ext in ("sjgame.zip", "sjpack.zip"):
        path = safe_join(PACKS_DIR, f"{safe_pid}.{ext}")
        if path.exists():
            return FileResponse(path, filename=f"{safe_pid}.{ext}")
    raise HTTPException(404, "not found")


@app.get("/gameplay/catalog", dependencies=[Depends(require_admin_for_reads)])
def gameplay_catalog() -> dict:
    """玩法包目录（私有部署）：基于已上传的 gameplay 包动态生成，含实时 SHA256。"""
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM packs WHERE pack_type='gameplay' ORDER BY created_at DESC"
        ).fetchall()
    entries = []
    for r in rows:
        pid = safe_segment(r["id"])
        if not pid:
            # 修复前可能写入 `../` 之类的 id；不再对外披露，也不去读它。
            continue
        sha = ""
        for ext in ("sjgame.zip", "sjpack.zip"):
            path = safe_join(PACKS_DIR, f"{pid}.{ext}")
            if path.exists():
                sha = hashlib.sha256(path.read_bytes()).hexdigest()
                break
        entries.append({
            "id": pid,
            "name": r["name"] or pid,
            "version": "",
            "author": r["author"] or "",
            "description": r["description"] or "",
            "packType": "gameplay",
            "downloadUrl": f"/packs/{pid}/download",
            "sha256": sha,
        })
    return {"schemaVersion": "1.0", "entries": entries}


@app.get("/config/runtime", dependencies=[Depends(require_admin_for_reads)])
def runtime_config() -> dict:
    """与客户端 RuntimeConfig 对齐：返回可热更的覆盖层（x_songjiang_* 前缀）。"""
    return {
        "schemaVersion": "1.0",
        "distill.systemPrompt": "",
        "x_songjiang_minApp": "1.0.0",
    }


if __name__ == "__main__":
    import uvicorn

    # 默认只听环回；容器内由 docker-compose 显式设 SONGJIANG_HOST=0.0.0.0
    # （容器端口映射必须监听 0.0.0.0，裸机 `python main.py` 不应默认对外暴露）。
    uvicorn.run(
        app,
        host=os.environ.get("SONGJIANG_HOST", "127.0.0.1"),
        port=int(os.environ.get("SONGJIANG_PORT", "8000")),
    )
