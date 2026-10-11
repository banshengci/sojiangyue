#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""layer_gate.py —— 松江阅（SongJiang Reader）分层依赖门禁。

用途
    1. 重建 `lib/` 的 import/export 依赖图；
    2. 用 Tarjan 算法求强连通分量（SCC），报告循环依赖规模；
    3. 检查 `docs/DEVELOPMENT.md` 里写明的分层规则 + 评审补充的反向依赖规则；
    4. 以「棘轮（ratchet）基线」方式工作：允许存量违规，禁止新增违规，
       禁止 SCC 规模回退。

为什么是自研 Python 脚本（选型理由）
    * `import_lint` / `custom_lint` / `dart_code_metrics` 都是 Dart 包，必须先有可用
      的 Dart/Flutter SDK 并成功 `pub get`。本仓库有一批指向作者个人 fork 的 git
      依赖（见 pubspec.yaml 头部注释），`pub get` 需要联网访问 GitHub；一旦依赖解析
      失败，门禁本身也跑不起来——门禁恰好最该在这种时刻仍可用。
    * `import-linter` 只支持 Python 模块，不解析 Dart。
    * 本源文件零第三方依赖、零编译，仅需 Python 3.8+（GitHub ubuntu runner 预装），
      因此**在没有 Flutter SDK 的环境里也能独立运行**（本评审即在此条件下产出全部数字）。
    * 代价：只做**文本级**解析，不做符号解析。因此规则以「文件→文件」的 import 关系
      为准，不判断实际用到了目标文件里的哪个符号。这是有意的取舍：宁可简单可审计，
      不引入编译器依赖。词法边界已在 _iter_imports() 中处理（剥离注释与字符串）。

用法
    # 基线冻结后日常门禁（阻塞模式，有新增违规 → 退出码 1）
    python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json

    # 非阻塞（只告警，用于提交流水线观察期）
    python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json --warn-only

    # 改进后刷新基线（会放宽 allow 列表；SCC 只允许收紧）
    python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json --update-baseline

    # 人工排查：完整违规清单 + SCC 明细 + 依赖图 DOT
    python3 tool/layer_gate.py --repo . --list-all --scc-detail --graph-out graph.dot

    # 机器消费
    python3 tool/layer_gate.py --repo . --baseline ... --json

退出码
    0  通过（无新增违规；SCC 未回退）
    1  门禁失败（存在新增违规，或 SCC 规模回退）
    2  用法/环境错误（仓库路径不存在、基线文件损坏等）

已知局限（必须在评审结论里与数字一同声明）
    * 文本级解析：`part` / `part of` 不建图（生成物 *.g.dart / *.freezed.dart 已被
      .gitignore 排除，本就不在仓库里）。
    * 条件编译（`if (dart.library.xxx)`）的 import 会被计入，不做平台裁剪。
    * 仅覆盖 `lib/`；`test/`、平台壳目录不参与。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone

SCHEMA = 1
DEFAULT_LIB = "lib"
DEFAULT_BASELINE = "tool/layer_gate_baseline.json"

# ---------------------------------------------------------------------------
# 分层模型
# ---------------------------------------------------------------------------

#: `lib/` 下的一级目录即「层」。`main.dart` 等一级文件归为 '(root)'。
LAYERS = (
    "page", "widgets", "providers", "service", "dao", "models",
    "config", "utils", "enums", "constants", "theme", "design", "plugin", "l10n",
)
ROOT_LAYER = "(root)"


def layer_of(path: str) -> str:
    """`lib/widgets/a/b.dart` -> `widgets`；`lib/main.dart` -> `(root)`。"""
    parts = path.split("/")
    if len(parts) > 2:
        return parts[1]
    return ROOT_LAYER


def _layer_pred(*layers: str):
    """生成谓词：目标文件所属层 ∈ layers。"""
    want = set(layers)
    return lambda tgt: layer_of(tgt) in want


def _path_pred(*prefixes: str):
    """生成谓词：目标文件路径以这些前缀之一开头。"""
    pre = tuple("lib/" + p for p in prefixes)
    return lambda tgt: tgt.startswith(pre)


# ---------------------------------------------------------------------------
# 规则定义
# ---------------------------------------------------------------------------

class Rule:
    """一条分层规则。

    source_layers : 规则约束的源层
    matches       : 判定「项目内目标文件是否违规」的谓词
    deny_packages : 禁止直接 import 的第三方 package 前缀（可选）
    doc           : True = docs/DEVELOPMENT.md 原文；False = 本评审补充
    """

    def __init__(self, rid, title, source_layers, matches, doc=True,
                 rationale="", fix_hint="", deny_packages=()):
        self.id = rid
        self.title = title
        self.source_layers = set(source_layers)
        self.matches = matches
        self.doc = doc
        self.rationale = rationale
        self.fix_hint = fix_hint
        self.deny_packages = tuple(deny_packages)


#: 视为「UI 提示库」的第三方 package（R4 用）。
UI_PACKAGES = ("package:flutter_smart_dialog/",)


RULES = [
    # ---------------- 文档原文 4 条 ----------------
    Rule(
        "R1",
        "widgets 不直接 import dao（需要数据时走 providers/ 或 service/）",
        ("widgets",),
        _layer_pred("dao"),
        rationale="docs/DEVELOPMENT.md「分层规则」第 1 条。widgets 直接读写 DAO 会绕过 "
                  "provider 的缓存/通知机制，也让组件无法被独立 widget 测试。",
        fix_hint="把数据访问上移到 providers/ 或 service/，组件通过 provider 取值。",
    ),
    Rule(
        "R2",
        "models 不依赖 service / providers / page / widgets（保持纯数据模型）",
        ("models",),
        _layer_pred("service", "providers", "page", "widgets"),
        rationale="docs/DEVELOPMENT.md「分层规则」第 2 条（原文为『models 不依赖 service』；"
                  "本门禁把 providers/page/widgets 一并纳入，因为评审已在 lib/models/iap_state.dart "
                  "观察到 models → providers 的实际违规）。纯数据模型才能被无 IO 单测。",
        fix_hint="把模型需要的类型下沉到 enums/ 或 models/；把运行时取值改为参数注入。",
    ),
    Rule(
        "R3",
        "service 不调 UI 组件（不 import page/ 与 widgets/）",
        ("service",),
        _layer_pred("page", "widgets"),
        rationale="docs/DEVELOPMENT.md 分层拓扑图：page/widgets → providers/service → dao，"
                  "反向边即违规。service 依赖 UI 会导致其无法在无 Flutter UI 环境下实例化，"
                  "这是 DAO/同步/导入层写不出单测的直接原因。",
        fix_hint="改为返回结果对象 / 抛异常，由 UI 层决定如何呈现；需要页面动作时注入回调。",
    ),
    Rule(
        "R4",
        "service 不调 Toast / SmartDialog 等 UI 提示",
        ("service",),
        _path_pred("utils/toast"),
        deny_packages=UI_PACKAGES,
        rationale="docs/DEVELOPMENT.md「分层规则」第 3 条原文。service 直接弹提示会把「业务结果」"
                  "与「呈现方式」焊死，无法在小工具/后台任务中复用，也无法断言执行结果。"
                  "本规则按 import 计数；若按调用点计数会更多（见评审报告 1.2 的说明）。",
        fix_hint="service 返回结果对象（成功/失败+原因），由调用方决定 Toast/弹窗文案。",
    ),
    # ---------------- 评审补充：反向依赖 ----------------
    Rule(
        "R5",
        "dao 不得反向依赖 providers / page / widgets / service",
        ("dao",),
        _layer_pred("providers", "page", "widgets", "service"),
        doc=False,
        rationale="评审补充。dao 是最底层持久化层，反向依赖会让持久化逻辑无法脱离 App 运行时测试。",
        fix_hint="DAO 只依赖 models/enums；需要触发上层动作时由调用方编排。",
    ),
    Rule(
        "R6",
        "utils / config 不得反向依赖 widgets / page / service",
        ("utils", "config"),
        _layer_pred("widgets", "page", "service"),
        doc=False,
        rationale="评审补充。utils 与 config 在文档拓扑里被广泛依赖，一旦反向依赖 UI，"
                  "它们就会成为循环依赖的中转站（当前 241 文件大环即由此类边串联）。",
        fix_hint="把被复用的类型（枚举/常量）下沉到 enums/ 或 constants/。",
    ),
    Rule(
        "R7",
        "config/*_prefs.dart 只依赖 models/enums/constants/config（领域 Prefs 模式）",
        ("config",),
        _layer_pred("dao", "providers", "page", "widgets"),
        doc=False,
        rationale="评审补充，呼应 docs/DEVELOPMENT.md「领域 Prefs 模式」。Prefs 是配置读写层，"
                  "不应知道业务 DAO 或 provider 的存在。",
        fix_hint="Prefs 只做 get/set + JSON 序列化，业务编排交给 service。",
    ),
]




# ---------------------------------------------------------------------------
# 依赖图构建
# ---------------------------------------------------------------------------

# 注意 1：行首必须是 [ \t]* 而不是 \s*。\s 会跨行匹配，导致「import 前有空行」时
#         m.start() 落在空行上，报出的行号系统性地少 1（本脚本 v1 实测踩到过）。
# 注意 2：URI 必须与 import/export 关键字同行，但 `show A, B;` / `as x;` 可能换行
#         （本仓库有 4 处多行写法，其中 1 处正是 config→widgets 的违规边）。
#         因此只匹配「关键字 + URI」这一行，再向后扫描到分号取 show/hide。
_IMPORT_HEAD_RE = re.compile(
    r"""^[ \t]*(?:import|export)[ \t]+(?:'([^']+)'|"([^"]+)")""",
    re.M | re.X,
)
_SHOW_RE = re.compile(r"\bshow\b[ \t]+([^;]+)", re.S)
_HIDE_RE = re.compile(r"\bhide\b[ \t]+([^;]+)", re.S)

#: 从 URI 结束位置向后扫描分号的最大跨度（字符）。防止畸形文件吞掉后续代码。
_TAIL_WINDOW = 400


def _blank_comments(text: str) -> str:
    """把注释区域替换为等长空白（保留换行），从而：

    * 行号完全不变，证据行可精确定位；
    * 块注释里的 `import` 不会造成误报；
    * 字符串字面量（含三引号多行字符串，本仓库有大量中文提示词）里的
      `//`、`/*` 不会被误判成注释，避免漏报。
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        # --- 三引号字符串（优先判断） ---
        if text.startswith("'''", i) or text.startswith('"""', i):
            q = text[i] * 3
            i += 3
            while i < n and not text.startswith(q, i):
                i += 1
            i = min(i + 3, n)
        # --- 单引号/双引号字符串 ---
        elif c in "'\"":
            quote = c
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                if i < n and text[i] == "\n":   # 未闭合的字符串，避免死循环
                    break
                i += 1
            i += 1
        # --- 行注释 ---
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        # --- 块注释 ---
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            out[i] = out[i + 1] = " "
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i + 1 < n:
                out[i] = out[i + 1] = " "
                i += 2
        else:
            i += 1
    return "".join(out)


def _iter_imports(text: str):
    """产出 (行号, URI, show 子句, 证据行文本)。

    证据行取「关键字所在行」；多行 show/hide 时同时附上紧随其后的行，
    以便人工核对（用 ` \\` 连接）。
    """
    blanked = _blank_comments(text)
    raw_lines = text.split("\n")
    for m in _IMPORT_HEAD_RE.finditer(blanked):
        target = m.group(1) or m.group(2)
        line_no = blanked.count("\n", 0, m.start()) + 1
        # 向后找分号，限定窗口内且中间不能再出现新的 import/export 关键字
        seg_start = m.end()
        seg_end = blanked.find(";", seg_start, seg_start + _TAIL_WINDOW)
        if seg_end < 0:
            seg_end = seg_start
        tail = blanked[seg_start:seg_end]
        if "import " in tail or "export " in tail:
            tail = tail.split("import ")[0].split("export ")[0]
        sm, hm = _SHOW_RE.search(tail), _HIDE_RE.search(tail)
        show = sm.group(1).strip() if sm and not (hm and hm.start() < sm.start()) else ""
        evidence = raw_lines[line_no - 1].strip() if line_no - 1 < len(raw_lines) else ""
        if show or tail.strip():
            extra = " ".join(tail.split())
            if extra:
                evidence = "%s %s" % (evidence, extra)
        yield line_no, target, show, evidence


def resolve_import(origin: str, target: str, package_name: str = "songjiang_reader"):
    """把 import/export 串解析为仓库内相对路径；非本项目文件返回 None。

    Dart 的相对 import 有两种合法写法，**都必须支持**：
      * `import './foo.dart';` / `import '../a/foo.dart';`
      * `import 'foo.dart';`        ← 裸相对（本仓库有 86 处）

    早期版本只处理了以 `.` 开头的那种，导致裸相对 import 被当成"第三方包"丢弃，
    import 图少 86 条边（含 `base_tool.dart` × 13 这种关键边）。这是一个真实的
    解析缺陷，已修复——修复后 SCC 等全部指标都要重算。
    """
    prefix = "package:%s/" % package_name
    if target.startswith(prefix):
        return "lib/" + target[len(prefix):]
    # 带 scheme 的（dart: / 其它 package: / http: 等）不是本项目内文件
    head = target.split("/", 1)[0]
    if ":" in head:
        return None
    # 其余一律按「相对当前文件所在目录」解析
    resolved = os.path.normpath(os.path.join(os.path.dirname(origin), target))
    return resolved.replace("\\", "/")


def build_graph(repo: str, lib: str = DEFAULT_LIB):
    """返回 (files, adj, external, texts)。

    files : set[str]            lib/ 下全部 .dart（相对仓库路径）
    adj   : dict[str,set[str]]  项目内 import/export 邻接表
    external : list[dict]       指向第三方 package / dart: 的记录（供 R4 判定）
    texts : dict[str,str]       文件正文（已去 BOM），供规则检查复用，避免二次读盘
    """
    lib_root = os.path.join(repo, lib)
    if not os.path.isdir(lib_root):
        raise FileNotFoundError("找不到 %s 目录：%s" % (lib, lib_root))

    files, texts = set(), {}
    for dirpath, dirnames, filenames in os.walk(lib_root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for fn in sorted(filenames):
            if not fn.endswith(".dart"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, repo).replace("\\", "/")
            files.add(rel)
            try:
                with open(full, encoding="utf-8-sig", errors="replace") as fh:
                    texts[rel] = fh.read()
            except OSError as exc:                       # pragma: no cover
                print("warning: 无法读取 %s: %s" % (rel, exc), file=sys.stderr)

    adj = defaultdict(set)
    external = []
    for rel in sorted(files):
        for line_no, target, show, evidence in _iter_imports(texts[rel]):
            resolved = resolve_import(rel, target)
            if resolved is None:
                external.append({
                    "from": rel, "line": line_no, "import": target,
                    "show": show, "evidence": evidence,
                })
            elif resolved in files:
                adj[rel].add(resolved)
            # resolved 但不在 files 中：生成物（*.g.dart 等）或目录外，忽略
    return files, adj, external, texts


# ---------------------------------------------------------------------------
# SCC（Tarjan，迭代实现，避免深图递归溢出）
# ---------------------------------------------------------------------------

def find_sccs(files, adj):
    """返回全部规模 > 1 的强连通分量（每个为排序后的 list）。"""
    index, low, on_stack, stack = {}, {}, set(), []
    counter = [0]
    result = []

    def strongconnect(root):
        work = [[root, iter(sorted(adj.get(root, ())))]]
        index[root] = low[root] = counter[0]
        counter[0] += 1
        stack.append(root)
        on_stack.add(root)
        while work:
            node, it = work[-1]
            advanced = False
            for nxt in it:
                if nxt not in files:
                    continue
                if nxt not in index:
                    index[nxt] = low[nxt] = counter[0]
                    counter[0] += 1
                    stack.append(nxt)
                    on_stack.add(nxt)
                    work.append([nxt, iter(sorted(adj.get(nxt, ())))])
                    advanced = True
                    break
                if nxt in on_stack:
                    low[node] = min(low[node], index[nxt])
            if advanced:
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
            if low[node] == index[node]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == node:
                        break
                if len(comp) > 1:
                    result.append(sorted(comp))

    for f in sorted(files):
        if f not in index:
            strongconnect(f)
    result.sort(key=lambda c: (-len(c), c[0]))
    return result


def scc_snapshot(sccs):
    sizes = sorted((len(c) for c in sccs), reverse=True)
    return {
        "cycle_count": len(sccs),
        "files_in_cycles": sum(sizes),
        "max_scc": sizes[0] if sizes else 0,
        "sizes": sizes,
        "members": sorted(m for c in sccs for m in c),
    }


# ---------------------------------------------------------------------------
# 规则检查
# ---------------------------------------------------------------------------

def check_rules(files, texts, external):
    """返回违规列表（按 rule/from/to 排序）。"""
    violations = []
    for src in sorted(files):
        src_layer = layer_of(src)
        for rule in RULES:
            if src_layer not in rule.source_layers:
                continue
            for line_no, target, show, evidence in _iter_imports(texts[src]):
                resolved = resolve_import(src, target)
                if resolved is None:
                    # 第三方包：仅当规则显式声明了禁用的 package 前缀
                    if any(target.startswith(p) for p in rule.deny_packages):
                        violations.append(_v(rule, src, line_no, target,
                                             target, show, evidence, src_layer))
                    continue
                if resolved not in files:
                    continue
                if rule.matches(resolved):
                    violations.append(_v(rule, src, line_no, resolved,
                                         target, show, evidence, src_layer))
    return sorted(violations, key=lambda x: (x["rule"], x["from"], x["to"]))


def _v(rule, src, line_no, resolved, import_target, show, evidence, src_layer):
    return {
        "rule": rule.id,
        "title": rule.title,
        "doc": rule.doc,
        "from": src,
        "from_layer": src_layer,
        "line": line_no,
        "to": resolved,
        "to_layer": (layer_of(resolved) if resolved.startswith("lib/")
                     else "external:%s" % resolved.split("/")[0]),
        "import": import_target,
        "show": show,
        "evidence": evidence,
    }


# ---------------------------------------------------------------------------
# 基线
# ---------------------------------------------------------------------------

def _key(v):
    return "%s|%s|%s" % (v["rule"], v["from"], v["to"])


def load_baseline(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def baseline_lib_files(repo, commit):
    """用 git 取基线 commit 的 `lib/` 文件清单（用于区分「新增文件」与「既有文件」）。

    为什么需要：SCC 棘轮若只看「环内文件数」，会把**我们自己新加的接线文件**也算成
    耦合增长，从而拒绝一个合法的重构。第 2 批就撞到了这个：把 `AiToolContext` 拆到新文件
    后，`环内文件数 +1`，但**没有任何既有文件被拖进环**（新进入环的只有那个新文件本身）。

    因此棘轮的判据改为：「**既有**文件中是否有新的进入环」——
      环内新增文件 ∩ 基线文件清单 ≠ ∅  →  回退（真正的耦合增长）
      环内新增文件 ⊆ 本次新建文件      →  不是回退（可审计，会在报告里单独列出）

    取不到 git 信息时返回 None，调用方退回严格判定（把新增文件也视为回退）。
    """
    import subprocess
    try:
        out = subprocess.run(
            ["git", "-C", repo, "ls-tree", "-r", "--name-only", commit, "--", "lib"],
            capture_output=True, text=True, timeout=20, check=True,
        ).stdout
    except Exception:                                   # pragma: no cover
        return None
    files = {l.strip() for l in out.splitlines() if l.strip()}
    return files or None


def make_baseline(violations, snap, commit, lib_files):
    """生成棘轮基线。

    `lib_files` 会整份写入 JSON。这是有意的：SCC 棘轮需要知道「基线当时存在哪些文件」，
    才能把「本次新建的接线文件进入环」（可接受）与「既有文件被拖进环」（回退）分开。
    代价是基线文件变大（约 +530 行），但换来的是棘轮可执行且不会误杀合法重构。
    """
    lib_files = sorted(lib_files)
    return {
        "schema": SCHEMA,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "commit": commit,
        "lib_file_count": len(lib_files),
        "lib_files": lib_files,
        "allow": [
            {"rule": v["rule"], "from": v["from"], "to": v["to"],
             "line": v["line"], "evidence": v["evidence"]}
            for v in violations
        ],
        "scc": snap,
        "note": "存量违规冻结基线。允许存量，禁止新增；SCC 规模只允许收紧。",
    }


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

def render_markdown(violations, snap, baseline, new, fixed, scc_regression,
                    commit, lib_count):
    """生成 Markdown 汇总（可直接贴 PR 评论 / 写 GitHub Step Summary）。"""
    by_rule = defaultdict(list)
    for v in violations:
        by_rule[v["rule"]].append(v)
    result = "FAIL" if (new or scc_regression) else "PASS"
    L = []
    L.append("### 分层依赖门禁 (layer_gate): **%s**" % result)
    L.append("")
    L.append("commit `%s` · lib 文件 %d · 违规 %d（新增 %d / 已修复 %d）"
             % (commit[:12] or "(unknown)", lib_count, len(violations),
                len(new), len(fixed)))
    L.append("")
    L.append("| 规则 | 来源 | 状态 | 数量 | 说明 |")
    L.append("|---|---|---|---|---|")
    for r in RULES:
        hits = by_rule.get(r.id, [])
        L.append("| %s | %s | %s | %d | %s |"
                 % (r.id, "文档" if r.doc else "补充",
                    "OK" if not hits else "违规", len(hits),
                    r.title.replace("|", "\\|")))
    L.append("")
    L.append("| 循环依赖 (SCC) | 当前 | 基线 | 变化 |")
    L.append("|---|---|---|---|")
    b = (baseline or {}).get("scc", {})
    L.append("| 环数量 | %d | %s | %s |"
             % (snap["cycle_count"], b.get("cycle_count", "—"),
                "—" if not b else "%+d" % (snap["cycle_count"] - b.get("cycle_count", 0))))
    L.append("| 环内文件 | %d | %s | %s |"
             % (snap["files_in_cycles"], b.get("files_in_cycles", "—"),
                "—" if not b else "%+d" % (snap["files_in_cycles"] - b.get("files_in_cycles", 0))))
    L.append("| 最大 SCC | %d | %s | %s |"
             % (snap["max_scc"], b.get("max_scc", "—"),
                "—" if not b else "%+d" % (snap["max_scc"] - b.get("max_scc", 0))))
    if new:
        L.append("")
        L.append("**新增违规（会阻塞 CI）**")
        L.append("")
        L.append("| 规则 | 位置 | 目标 |")
        L.append("|---|---|---|")
        for v in new[:50]:
            L.append("| %s | `%s:%d` | `%s` |"
                     % (v["rule"], v["from"], v["line"], v["to"]))
        if len(new) > 50:
            L.append("")
            L.append("_（仅显示前 50 条，共 %d 条）_" % len(new))
    if fixed:
        L.append("")
        L.append("**本次修复了 %d 处存量违规** → 可执行 "
                 "`python3 tool/layer_gate.py --update-baseline` 收紧基线。"
                 % len(fixed))
    return "\n".join(L) + "\n"


def print_human(violations, snap, baseline, new, fixed, scc_regression,
                scc_detail=False, scc_dragged=(), scc_new_files=()):
    print("=" * 78)
    print("松江阅分层依赖门禁 (layer_gate)")
    print("=" * 78)

    # --- 规则概览 ---
    by_rule = defaultdict(list)
    for v in violations:
        by_rule[v["rule"]].append(v)
    print("\n[1] 分层规则检查")
    for rule in RULES:
        hits = by_rule.get(rule.id, [])
        tag = "文档" if rule.doc else "补充"
        status = "OK  " if not hits else "违规"
        print("  %-3s [%s] %-4s %-58s %3d 处" %
              (rule.id, tag, status, rule.title[:58], len(hits)))

    # --- 违规明细 ---
    if violations:
        print("\n[2] 违规明细（当前全量，共 %d 处）" % len(violations))
        allow = {_key(x) for x in (baseline or {}).get("allow", [])}
        for v in violations:
            mark = "NEW " if _key(v) not in allow else "old "
            print("  %s %-3s %s:%d" % (mark, v["rule"], v["from"], v["line"]))
            print("        -> %s" % v["to"])
            print("        %s" % v["evidence"])

    # --- SCC ---
    print("\n[3] 循环依赖（SCC，Tarjan）")
    print("  环数量           : %d" % snap["cycle_count"])
    print("  环内文件数       : %d" % snap["files_in_cycles"])
    print("  最大 SCC         : %d" % snap["max_scc"])
    print("  SCC 规模分布     : %s" % snap["sizes"][:10])
    if baseline and "scc" in baseline:
        b = baseline["scc"]
        print("  --- 相对基线 ---")
        print("  环内文件  %d -> %d  (%+d)" %
              (b.get("files_in_cycles", 0), snap["files_in_cycles"],
               snap["files_in_cycles"] - b.get("files_in_cycles", 0)))
        print("  最大 SCC  %d -> %d  (%+d)" %
              (b.get("max_scc", 0), snap["max_scc"],
               snap["max_scc"] - b.get("max_scc", 0)))

    if scc_new_files:
        print("  新进入环的**新建**文件（不算回退，仅供审阅）: %d 个" % len(scc_new_files))
        for x in scc_new_files:
            print("      + %s" % x)
    if scc_dragged:
        print("  新进入环的**既有**文件（= SCC 回退）: %d 个" % len(scc_dragged))
        for x in scc_dragged:
            print("      ! %s" % x)

    if scc_detail:
        print("\n[3b] SCC 成员（最多列 5 个分量）")
        for c in find_sccs(_current_files, _current_adj)[:5]:
            print("  --- size %d ---" % len(c))
            for m in c[:40]:
                print("      %s" % m)

    # --- 结论 ---
    print("\n[4] 门禁结论")
    print("  存量违规（基线已允许）: %d" % (len(violations) - len(new)))
    print("  已修复（基线里有、现在没了）: %d" % len(fixed))
    if fixed:
        print("      > 建议刷新基线： --update-baseline")
    print("  新增违规: %d" % len(new))
    print("  SCC 回退: %s%s" % ("是" if scc_regression else "否",
          "（既有文件被拖入环：%s）" % ", ".join(scc_dragged) if scc_dragged else ""))
    if new:
        print("\n  [FAIL] 新增违规清单：")
        for v in new:
            print("      %-3s %s:%d -> %s" % (v["rule"], v["from"], v["line"], v["to"]))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

_current_files, _current_adj = set(), {}


def main(argv=None):
    global _current_files, _current_adj
    ap = argparse.ArgumentParser(
        description="松江阅分层依赖门禁（零依赖 Python 实现）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("--repo", default=".", help="仓库根目录（含 lib/），默认当前目录")
    ap.add_argument("--lib", default=DEFAULT_LIB, help="源码根目录，默认 lib")
    ap.add_argument("--baseline", default=DEFAULT_BASELINE,
                    help="棘轮基线 JSON 路径（不存在则视为空基线）")
    ap.add_argument("--warn-only", action="store_true",
                    help="非阻塞模式：报告违规但始终以退出码 0 结束")
    ap.add_argument("--update-baseline", action="store_true",
                    help="把当前状态写入基线（放宽 allow；SCC 只允许收紧）")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--list-all", action="store_true", help="打印全部违规明细")
    ap.add_argument("--scc-detail", action="store_true", help="打印 SCC 成员")
    ap.add_argument("--graph-out", metavar="FILE",
                    help="把依赖图导出为 Graphviz DOT（SCC 成员用红色标注）")
    ap.add_argument("--markdown-out", metavar="FILE",
                    help="写一份 Markdown 汇总（适合贴 PR 评论 / GitHub Step Summary）")
    args = ap.parse_args(argv)

    if not os.path.isdir(os.path.join(args.repo, args.lib)):
        print("error: %s 下找不到 %s/ 目录" % (args.repo, args.lib), file=sys.stderr)
        return 2

    try:
        files, adj, external, texts = build_graph(args.repo, args.lib)
    except FileNotFoundError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2

    _current_files, _current_adj = files, adj
    sccs = find_sccs(files, adj)
    snap = scc_snapshot(sccs)
    violations = check_rules(files, texts, external)

    baseline_path = args.baseline
    if not os.path.isabs(baseline_path):
        baseline_path = os.path.join(args.repo, baseline_path)
    baseline = None
    try:
        baseline = load_baseline(baseline_path)
    except (OSError, ValueError) as exc:
        print("error: 基线文件损坏 %s: %s" % (baseline_path, exc), file=sys.stderr)
        return 2

    allow = {_key(x) for x in (baseline or {}).get("allow", [])}
    cur = {_key(v): v for v in violations}
    new = [cur[k] for k in sorted(set(cur) - allow)]
    fixed = sorted(allow - set(cur))

    # ---- SCC 棘轮 ----
    # 判据：「**既有**文件是否有新的进入环」。
    # 只看 files_in_cycles 的增减会误杀合法重构（本次把 AiToolContext 拆到新文件，
    # 环内 +1，但那是新建的接线文件，没有任何既有文件被拖进环）。
    scc_regression = False
    scc_improved = False
    scc_dragged = []       # 新进入环的「既有文件」→ 回退
    scc_new_files = []     # 新进入环的「新建文件」→ 允许，但会单独列出
    if baseline and "scc" in baseline:
        b = baseline["scc"]
        b_members = set(b.get("members", []))
        newly = set(snap["members"]) - b_members
        bl_files = set(baseline.get("lib_files") or [])
        if not bl_files:                      # 老基线没有文件清单：退回 git，再退回严格
            bl_files = baseline_lib_files(args.repo, baseline.get("commit", "")) or set()
        if bl_files:
            scc_dragged = sorted(newly & bl_files)
            scc_new_files = sorted(newly - bl_files)
        else:                                 # 无法区分 → 严格：一律视为回退
            scc_dragged = sorted(newly)
        scc_regression = bool(scc_dragged)
        if snap["files_in_cycles"] < b.get("files_in_cycles", 0):
            scc_improved = True

    commit = ""
    head = os.path.join(args.repo, ".git", "HEAD")
    try:
        with open(head, encoding="utf-8") as fh:
            ref = fh.read().strip()
        if ref.startswith("ref: "):
            ref_file = os.path.join(args.repo, ".git", ref[5:])
            if os.path.exists(ref_file):
                with open(ref_file, encoding="utf-8") as fh:
                    commit = fh.read().strip()
        else:
            commit = ref
    except OSError:
        pass

    if args.update_baseline:
        prev_in_cycle = (baseline or {}).get("scc", {}).get("files_in_cycles")
        if prev_in_cycle is not None and snap["files_in_cycles"] > prev_in_cycle:
            print("error: 拒绝刷新基线——环内文件数从 %d 回退到 %d。"
                  "请先拆掉新增的环。" % (prev_in_cycle, snap["files_in_cycles"]),
                  file=sys.stderr)
            return 1
        data = make_baseline(violations, snap, commit, files)
        os.makedirs(os.path.dirname(baseline_path) or ".", exist_ok=True)
        with open(baseline_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=False)
            fh.write("\n")
        print("已刷新基线: %s（allow=%d, 环内=%d, 最大SCC=%d）" %
              (baseline_path, len(data["allow"]), snap["files_in_cycles"],
               snap["max_scc"]))
        return 0

    if args.graph_out:
        cycles = set(m for c in sccs for m in c)
        with open(args.graph_out, "w", encoding="utf-8") as fh:
            fh.write("digraph layergate {\n  rankdir=LR;\n  node [shape=box,fontsize=9];\n")
            for f in sorted(files):
                color = "red" if f in cycles else "black"
                fh.write('  "%s" [color=%s];\n' % (f, color))
            for a in sorted(adj):
                for b in sorted(adj[a]):
                    fh.write('  "%s" -> "%s";\n' % (a, b))
            fh.write("}\n")
        # 诊断信息必须走 stderr：--json 的 stdout 要保持纯 JSON 可被直接解析。
        print("已导出依赖图: %s" % args.graph_out, file=sys.stderr)

    md = render_markdown(violations, snap, baseline, new, fixed, scc_regression,
                         commit, len(files))
    if args.markdown_out:
        with open(args.markdown_out, "w", encoding="utf-8") as fh:
            fh.write(md)
        print("已写出 Markdown 汇总: %s" % args.markdown_out, file=sys.stderr)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        try:
            with open(summary_path, "a", encoding="utf-8") as fh:
                fh.write(md + "\n")
        except OSError:
            pass

    if args.json:
        print(json.dumps({
            "schema": SCHEMA,
            "commit": commit,
            "lib_file_count": len(files),
            "rules": [{"id": r.id, "title": r.title, "doc": r.doc,
                       "source_layers": sorted(r.source_layers)} for r in RULES],
            "violations": violations if args.list_all else {"count": len(violations)},
            "new_violations": new,
            "fixed_violations": fixed,
            "scc": snap,
            "scc_regression": scc_regression,
            "scc_improved": scc_improved,
            "baseline": {"path": baseline_path, "loaded": baseline is not None,
                         "allow_count": len(allow)},
            "result": "FAIL" if (new or scc_regression) else "PASS",
        }, ensure_ascii=False, indent=2))
    else:
        print_human(violations, snap, baseline, new, fixed, scc_regression,
                    args.scc_detail, scc_dragged, scc_new_files)

    failed = bool(new) or scc_regression
    if failed and args.warn_only:
        print("\n[warn-only] 存在问题但按非阻塞模式返回 0。")
        return 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
