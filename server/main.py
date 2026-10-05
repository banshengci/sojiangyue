"""松江阅 · 造梦空间后端（DreamSpace server）。

家庭 NAS / 私有部署用：集中托管插件目录、增强包、运行时配置。
与松江阅客户端通过 https 对接（PluginMarketClient / RuntimeConfig）。
安全模型与客户端一致：SHA256 防篡改 + 可选 Ed25519 发布者签名。
"""
from __future__ import annotations

import hashlib
import os
import sqlite3
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.responses import FileResponse
from pydantic import BaseModel

BASE_DIR = Path(os.environ.get("SONGJIANG_DATA", "/data"))
BASE_DIR.mkdir(parents=True, exist_ok=True)
PLUGINS_DIR = BASE_DIR / "plugins"
PACKS_DIR = BASE_DIR / "packs"
PLUGINS_DIR.mkdir(exist_ok=True)
PACKS_DIR.mkdir(exist_ok=True)
DB_PATH = BASE_DIR / "songjiang.db"


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


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


@app.get("/plugins/catalog")
def catalog() -> dict:
    """返回 plugins-catalog.json 兼容结构（downloadUrl 指向本服务端）。"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM plugin_entries ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
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


@app.post("/plugins")
def upload_plugin(meta: PluginEntryIn, file: UploadFile = File(...)) -> dict:
    data = file.file.read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != meta.sha256:
        raise HTTPException(400, "SHA256 校验失败：文件可能被篡改")
    # TODO(签名): 与客户端一致，用 cryptography 做 Ed25519 验签；此处仅记录签名信息。
    path = PLUGINS_DIR / f"{meta.id}.plugin.json"
    path.write_bytes(data)
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO plugin_entries "
        "(id,name,version,description,author,download_url,sha256,"
        "signer_public_key,signature_hex,min_app_version) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (
            meta.id,
            meta.name,
            meta.version,
            meta.description,
            meta.author,
            f"/plugins/{meta.id}/download",
            meta.sha256,
            meta.signerPublicKey,
            meta.signatureHex,
            meta.minAppVersion,
        ),
    )
    conn.commit()
    conn.close()
    return {"ok": True, "sha256": actual}


@app.get("/plugins/{pid}/download")
def download_plugin(pid: str) -> FileResponse:
    path = PLUGINS_DIR / f"{pid}.plugin.json"
    if not path.exists():
        raise HTTPException(404, "not found")
    return FileResponse(path, filename=f"{pid}.plugin.json")


@app.get("/packs")
def list_packs(pack_type: str = "") -> list:
    conn = get_db()
    if pack_type:
        rows = conn.execute(
            "SELECT * FROM packs WHERE pack_type=? ORDER BY created_at DESC",
            (pack_type,),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM packs ORDER BY created_at DESC"
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


@app.post("/packs")
def upload_pack(
    name: str = Form(...),
    author: str = Form(""),
    description: str = Form(""),
    pack_type: str = Form("enhancement"),
    file: UploadFile = File(...),
) -> dict:
    data = file.file.read()
    pid = f"{name}_{hashlib.sha256(data).hexdigest()[:12]}"
    ext = "sjgame.zip" if pack_type == "gameplay" else "sjpack.zip"
    path = PACKS_DIR / f"{pid}.{ext}"
    path.write_bytes(data)
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO packs "
        "(id,name,author,description,filename,pack_type) "
        "VALUES (?,?,?,?,?,?)",
        (pid, name, author, description, path.name, pack_type),
    )
    conn.commit()
    conn.close()
    return {"ok": True, "id": pid, "pack_type": pack_type}


@app.get("/packs/gameplay")
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


@app.get("/packs/{pid}/download")
def download_pack(pid: str) -> FileResponse:
    # 兼容增强包(.sjpack.zip) 与玩法包(.sjgame.zip) 两种后缀。
    for ext in ("sjgame.zip", "sjpack.zip"):
        path = PACKS_DIR / f"{pid}.{ext}"
        if path.exists():
            return FileResponse(path, filename=f"{pid}.{ext}")
    raise HTTPException(404, "not found")


@app.get("/gameplay/catalog")
def gameplay_catalog() -> dict:
    """玩法包目录（私有部署）：基于已上传的 gameplay 包动态生成，含实时 SHA256。"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM packs WHERE pack_type='gameplay' ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    entries = []
    for r in rows:
        pid = r["id"]
        sha = ""
        for ext in ("sjgame.zip", "sjpack.zip"):
            path = PACKS_DIR / f"{pid}.{ext}"
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


@app.get("/config/runtime")
def runtime_config() -> dict:
    """与客户端 RuntimeConfig 对齐：返回可热更的覆盖层（x_songjiang_* 前缀）。"""
    return {
        "schemaVersion": "1.0",
        "distill.systemPrompt": "",
        "x_songjiang_minApp": "1.0.0",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
