"""松江阅增强后端 · 安全回归测试。

覆盖（对应安全专项报告 §二）：
  - 写接口 fail-closed：未配置 SONGJIANG_TOKEN => 503；token 错误 => 401；正确 => 200
  - 路径穿越被挡：相对 `../`、绝对路径、反斜杠、空段、纯点、NUL、超长
  - 体积上限：超过 SONGJIANG_MAX_UPLOAD => 413
  - 正常上传成功，且文件一定落在 PACKS_DIR 之内
  - 历史脏数据（修复前写入的 `../` 形式 id）不会被下载端点或目录端点利用

运行方式（两种都可）：
    python -m pytest server/test_main.py -v
    python server/test_main.py          # 无 pytest 时的自带 runner

注意：本文件在 import main 之前把 SONGJIANG_DATA 指向临时目录，
      绝不读写真实数据目录。
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

# --- 必须在 import main 之前设置环境：main.py 导入期就会 mkdir + init_db ---
_TMP_ROOT = Path(tempfile.mkdtemp(prefix="songjiang-server-test-"))
os.environ["SONGJIANG_DATA"] = str(_TMP_ROOT)
TOKEN = "test-token-0123456789abcdef"
os.environ["SONGJIANG_TOKEN"] = TOKEN
os.environ.pop("SONGJIANG_READ_NEEDS_TOKEN", None)
os.environ.pop("SONGJIANG_MAX_UPLOAD", None)

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402

client = TestClient(main.app)
HDR = {"X-Songjiang-Token": TOKEN}
PACK_BYTES = b"PK\x03\x04 fake pack payload"


# --------------------------------------------------------------------------- #
# 工具
# --------------------------------------------------------------------------- #
def _tree(root: Path, exclude: Path | None = None) -> set[str]:
    """目录下所有文件的相对路径；exclude 的子树会被排除。

    用于断言"没有任何文件跑到 PACKS_DIR 之外"。
    """
    out: set[str] = set()
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if exclude is not None and (p == exclude or exclude in p.parents):
            continue
        out.add(str(p.relative_to(root)))
    return out


def _upload(name: str, data: bytes = PACK_BYTES, pack_type: str = "enhancement",
            token: str | None = TOKEN, path: str = "/packs"):
    headers = {} if token is None else {"X-Songjiang-Token": token}
    return client.post(
        path,
        data={"name": name, "author": "tester", "description": "d",
              "pack_type": pack_type},
        files={"file": ("p.sjpack.zip", data, "application/zip")},
        headers=headers,
    )


# --------------------------------------------------------------------------- #
# 1. 写接口 fail-closed / 鉴权
# --------------------------------------------------------------------------- #
def test_write_rejected_when_token_not_configured():
    """未配置 SONGJIANG_TOKEN => 写接口 503（宁可不给上传，也不留公网写口）。"""
    saved = os.environ.pop("SONGJIANG_TOKEN", None)
    try:
        r = _upload("n", token=None)
        assert r.status_code == 503, r.text
        # 也不能因为"没配 token"就把内容写进去
        assert not list((_TMP_ROOT / "packs").glob("n_*.sjpack.zip"))
    finally:
        if saved is not None:
            os.environ["SONGJIANG_TOKEN"] = saved


def test_write_rejected_with_wrong_or_missing_token():
    assert _upload("n", token="wrong-token").status_code == 401
    assert _upload("n", token=None).status_code == 401
    assert _upload("n", token="").status_code == 401


def test_write_accepted_with_correct_token_and_stays_inside_packs_dir():
    """正常上传成功，且落盘位置在 PACKS_DIR 之内。"""
    packs = _TMP_ROOT / "packs"
    outside_before = _tree(_TMP_ROOT, exclude=packs)
    r = _upload("名著包")
    assert r.status_code == 200, r.text
    pid = r.json()["id"]
    assert pid.startswith("名著包_"), pid
    target = packs / f"{pid}.sjpack.zip"
    assert target.exists(), f"未落盘: {target}"
    assert target.read_bytes() == PACK_BYTES
    # 新增文件只出现在 packs/ 下
    assert _tree(_TMP_ROOT, exclude=packs) == outside_before


# --------------------------------------------------------------------------- #
# 2. 路径穿越
# --------------------------------------------------------------------------- #
TRAVERSAL_NAMES = [
    "../evil",
    "../../evil",
    "../../../../../../tmp/evil",
    "/tmp/evil",
    "/etc/evil",
    "a/../../b",
    "..\\evil",
    "....//evil",
    "..",
    ".",
    "",
    "   ",
    "\x00evil",
    "evil\x00/../../x",
    "C:\\Windows\\win.ini",
    "a" * 300,
]


def test_traversal_and_absolute_paths_never_escape_packs_dir():
    """核心断言：任何 name 都不会让文件落到 PACKS_DIR 之外。"""
    packs = _TMP_ROOT / "packs"
    outside_before = _tree(_TMP_ROOT, exclude=packs)
    for bad in TRAVERSAL_NAMES:
        r = _upload(bad)
        assert r.status_code in (200, 400), f"{bad!r} -> {r.status_code} {r.text}"
        if r.status_code == 200:
            pid = r.json()["id"]
            assert "/" not in pid and "\\" not in pid, f"{bad!r} 规范化失败: {pid}"
    outside_after = _tree(_TMP_ROOT, exclude=packs)
    assert outside_after == outside_before, (
        f"有文件被写到 PACKS_DIR 之外: {sorted(outside_after - outside_before)}")


def test_traversal_names_do_not_create_db_rows_with_separators():
    """落库的 id 也不得含路径分隔符（否则目录端点会二次利用）。"""
    _upload("../../../db-evil")
    with main.db() as conn:
        rows = conn.execute("SELECT id FROM packs").fetchall()
    for row in rows:
        assert "/" not in row["id"] and "\\" not in row["id"], row["id"]


def test_legacy_dirty_rows_are_not_usable():
    """修复前写入的 `../` 形式 id：目录不披露、下载端点 404。"""
    evil_id = "../../../../etc/passwd"
    with main.db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO packs (id,name,author,description,filename,pack_type)"
            " VALUES (?,?,?,?,?,?)",
            (evil_id, "legacy", "x", "x", "legacy.sjpack.zip", "gameplay"),
        )
        conn.commit()
    cat = client.get("/gameplay/catalog")
    assert cat.status_code == 200
    assert all("/" not in e["id"] for e in cat.json()["entries"])
    assert client.get("/packs/..%2F..%2Fetc%2Fpasswd/download").status_code == 404


# --------------------------------------------------------------------------- #
# 3. 体积上限
# --------------------------------------------------------------------------- #
def test_upload_size_limit_enforced():
    os.environ["SONGJIANG_MAX_UPLOAD"] = "1024"
    try:
        r = _upload("big", data=b"x" * 4096)
        assert r.status_code == 413, r.text
        assert not list((_TMP_ROOT / "packs").glob("big_*.sjpack.zip"))
        ok = _upload("small", data=b"x" * 512)
        assert ok.status_code == 200, ok.text
    finally:
        os.environ.pop("SONGJIANG_MAX_UPLOAD", None)


# --------------------------------------------------------------------------- #
# 4. 读接口的兼容策略
# --------------------------------------------------------------------------- #
def test_reads_open_by_default_and_gated_when_configured():
    assert client.get("/plugins/catalog").status_code == 200      # 老客户端兼容
    assert client.get("/packs").status_code == 200
    assert client.get("/gameplay/catalog").status_code == 200
    assert client.get("/config/runtime").status_code == 200
    os.environ["SONGJIANG_READ_NEEDS_TOKEN"] = "1"
    try:
        assert client.get("/plugins/catalog").status_code == 401
        assert client.get("/plugins/catalog", headers=HDR).status_code == 200
    finally:
        os.environ.pop("SONGJIANG_READ_NEEDS_TOKEN", None)


# --------------------------------------------------------------------------- #
# 自带 runner（无 pytest 时也能跑）
# --------------------------------------------------------------------------- #
def _run_all() -> int:
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"PASS  {name}")
        except AssertionError as exc:                      # noqa: PERF203
            failed += 1
            print(f"FAIL  {name}: {exc}")
        except Exception as exc:                           # noqa: BLE001
            failed += 1
            print(f"ERROR {name}: {type(exc).__name__}: {exc}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed  (tmp data: {_TMP_ROOT})")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(_run_all())
