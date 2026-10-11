#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_symbol_move.py —— 「类型搬家」后的符号可达性校验。

为什么需要它
    本次改动只做一件事：把若干**类型/常量定义**从 A 文件搬到 B 文件，并在 A 处
    保留 `export` 以维持向后兼容。这类改动有两个只在**编译期**才会暴露的坑：

      1. Dart 的 `export` **不会**把名字引入到执行 export 的那个库自身的作用域。
         如果一个文件既使用该类型、又只写 `export` 而忘了 `import`，它会编译失败。
      2. 某个引用方既没有 import 新位置，也没有 import 一个 re-export 了它的文件。

    本环境**没有 Dart/Flutter SDK**（`which dart flutter` 为空），无法运行
    `flutter analyze` / `dart compile`。本脚本用静态解析做等价性检查：
    对「被搬家的每个符号」，枚举全部引用它的文件，验证每个引用方都能通过
    import/export 闭包看见新定义位置（并正确处理 `show` / `hide` 子句）。

    它**不是**编译器：不做类型推断、不检查重载/泛型/条件导入。它是"够用于本类改动
    的最小验证"，用于替代无法执行的 analyze。局限见文件末尾。

用法
    python3 verify_symbol_move.py --repo . \\
        --symbol IapPurchaseFlowStatus=lib/enums/iap_purchase_flow_status.dart \\
        --symbol PageTurn=lib/enums/page_turn.dart \\
        --symbol StatisticsDashboardTileType=lib/enums/statistics_dashboard_tile_type.dart \\
        --symbol defaultStatisticsDashboardTiles=lib/enums/statistics_dashboard_tile_type.dart
    # 或从 JSON 清单读取
    python3 verify_symbol_move.py --repo . --manifest moved_symbols.json

退出码
    0  全部引用方都能看见新位置
    1  存在断裂引用（会编译失败）
    2  用法错误

局限（必须与结论一同声明）
    * 只按「标识符文本匹配」判定引用，字符串/注释中的同名文本会被 _blank_comments
      尽量剔除，但仍可能残留误报（例如出现在文档字符串里）。
    * 不处理 `part` / `part of`（本仓库生成物已 gitignore，lib/ 下无 part 目标）。
    * 不处理条件导入（`if (dart.library.io)`），会把所有分支都当成可见。
    * 不验证参数类型/返回值/泛型是否仍匹配——即"能解析到签名"不等于"类型正确"。
      本次改动全部是**原样搬迁**（定义文本逐字复制），故该风险为空；
      若未来有非原样搬迁，必须补真正的编译器验证。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from layer_gate import (                       # 复用同一套 DSL 解析，保证口径一致
        build_graph, layer_of, resolve_import,
    )
except ImportError:                                # pragma: no cover
    print("error: 需要与 layer_gate.py 放在同一目录", file=sys.stderr)
    raise

# 顶层声明：enum / class / mixin / extension / typedef / 顶层常量与变量
_DECL_PATTERNS = (
    re.compile(r"^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+)*enum\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*mixin\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*extension\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*typedef\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*(?:const|final|var)\s+(?:[A-Za-z_][\w<>,?\[\] ]*\s+)?([A-Za-z_]\w*)\s*=", re.M),
)


def strip_comments(text: str) -> str:
    """复用与门禁一致的注释剔除逻辑（保持行号与字符串内容）。"""
    from layer_gate import _blank_comments
    return _blank_comments(text)


def declared_symbols(text: str):
    out = set()
    blanked = strip_comments(text)
    for pat in _DECL_PATTERNS:
        for m in pat.finditer(blanked):
            out.add(m.group(1))
    return out


def parse_directives(text: str):
    """返回 (imports, exports)；每项为 dict(target, show:set|None, hide:set)。"""
    blanked = strip_comments(text)
    imports, exports = [], []
    for m in re.finditer(r"^[ \t]*(import|export)[ \t]+(?:'([^']+)'|\"([^\"]+)\")",
                         blanked, re.M):
        kind, target = m.group(1), (m.group(2) or m.group(3))
        seg_end = blanked.find(";", m.end(), m.end() + 400)
        tail = blanked[m.end():seg_end if seg_end > 0 else m.end()]
        if "import " in tail or "export " in tail:
            tail = tail.split("import ")[0].split("export ")[0]
        rec = {"target": target, "show": None, "hide": set()}
        sm = re.search(r"\bshow\b[ \t]+([^;]+)", tail, re.S)
        hm = re.search(r"\bhide\b[ \t]+([^;]+)", tail, re.S)
        if sm:
            rec["show"] = {x.strip().split(" as ")[0].strip()
                           for x in sm.group(1).split(",") if x.strip()}
        if hm:
            rec["hide"] = {x.strip() for x in hm.group(1).split(",") if x.strip()}
        (imports if kind == "import" else exports).append(rec)
    return imports, exports


#: 只把「类型级声明」当符号。**必须**排除枚举值、局部变量、顶层 const/final ——
#: 否则 `error` / `pending` / `context` 这类名字会产生海量假阳性
#: （阶段 2 初版实测：把 `IapStatus.error`、参数名 `context`、甚至 import URI 里的
#: `providers` / `service` / `tools` 都当成"未解析符号"，报出 16 处假断裂）。
_TYPE_DECL_PATTERNS = (
    re.compile(r"^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*(?:abstract\s+|sealed\s+)*enum\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*mixin\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*extension\s+([A-Za-z_]\w*)", re.M),
    re.compile(r"^\s*typedef\s+([A-Za-z_]\w*)", re.M),
)


def code_only(text: str) -> str:
    """把注释**与字符串字面量**都替换为空白（保留换行/长度）。

    与 `layer_gate._blank_comments` 的区别：那里必须保留字符串内容才能解析 import URI；
    这里做标识符匹配，必须把字符串清空，否则 `import 'package:.../providers/x.dart'`
    里的 `providers` 会被当成一个标识符。
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("'''", i) or text.startswith('"""', i):
            q = text[i] * 3
            for k in range(i, min(i + 3, n)):
                out[k] = " "
            i += 3
            while i < n and not text.startswith(q, i):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            for k in range(i, min(i + 3, n)):
                out[k] = " "
            i += 3
        elif c in "'\"":
            quote = c
            out[i] = " "
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\" and i + 1 < n:
                    out[i] = " "
                    i += 1
                if i < n and text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
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


def type_symbols(text: str):
    """只抽取类型级声明名。"""
    body = code_only(text)
    out = set()
    for pat in _TYPE_DECL_PATTERNS:
        for m in pat.finditer(body):
            out.add(m.group(1))
    return out


def check_destination_self_sufficiency(files, type_decls, texts, symbol_visible,
                                       destinations):
    """检查每个「新家」文件能否解析它**自己**引用的全部项目**类型**符号。

    为什么需要这一步（真实踩坑）：第 2 批把 `AiToolContext` 搬到新文件时，类体里
    引用了 `WidgetRef` 与 6 个 Repository，但**忘了把对应的 import 一起搬过去** ——
    新文件零 import 却引用了 8 个外部符号，必然编译失败。
    原有的可达性检查只验证「别人能不能看见被搬的符号」，**看不见"新家自己是瘸的"**，
    因此漏掉了这个错误。这一节就是补上的那一半。

    判据：对新家文件 D，凡是 **D 的代码部分**（已剔除注释与字符串）出现、
    且声明在项目内某文件的**类型名**，都必须能从 D 解析到。

    刻意不检查的部分（避免假阳性，属已知局限）：
      * 枚举值 / 顶层常量 / 局部变量名（如 `IapStatus.error`、`context`）；
      * 出现在字符串或注释里的同名文本（已由 code_only 剔除）；
      * 第三方/生成物符号（如 `L10n`、`WidgetRef` 若来自包外）。
    """
    owners = defaultdict(set)
    for f, syms in type_decls.items():
        for s in syms:
            owners[s].add(f)

    results = []
    for d in sorted(set(destinations)):
        if d not in files:
            results.append({"file": d, "exists": False, "unresolved": []})
            continue
        body = code_only(texts[d])
        own = type_decls.get(d, set())
        unresolved = []
        for sym in sorted(owners):
            if sym in own:
                continue
            if not re.search(r"\b%s\b" % re.escape(sym), body):
                continue
            if not symbol_visible(d, sym):
                unresolved.append({"symbol": sym,
                                   "declared_in": sorted(owners[sym])})
        results.append({"file": d, "exists": True, "unresolved": unresolved})
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description="类型搬家后的符号可达性校验")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--lib", default="lib")
    ap.add_argument("--symbol", action="append", default=[],
                    metavar="NAME=lib/path.dart",
                    help="被搬家的符号与新定义位置（可重复）")
    ap.add_argument("--manifest",
                    help="JSON: {\"symbols\": [{\"name\":..,\"from\":..,\"to\":..}]}")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    moved = []
    if args.manifest:
        with open(args.manifest, encoding="utf-8") as fh:
            for e in json.load(fh)["symbols"]:
                moved.append((e["name"], e["to"], e.get("from", "")))
    for item in args.symbol:
        if "=" not in item:
            print("error: --symbol 需要 NAME=lib/path.dart 形式: %s" % item,
                  file=sys.stderr)
            return 2
        name, to = item.split("=", 1)
        moved.append((name.strip(), to.strip(), ""))
    if not moved:
        print("error: 至少给一个 --symbol 或 --manifest", file=sys.stderr)
        return 2

    files, adj, external, texts = build_graph(args.repo, args.lib)

    imports_of, exports_of = {}, {}
    for rel in files:
        imp, exp = parse_directives(texts[rel])
        imports_of[rel] = [
            {"lib": resolve_import(rel, i["target"]), "show": i["show"], "hide": i["hide"]}
            for i in imp
        ]
        exports_of[rel] = [
            {"lib": resolve_import(rel, e["target"])} for e in exp
        ]

    decls = {rel: declared_symbols(texts[rel]) for rel in files}
    # 阶段 2 用「类型级声明」做符号表（见 type_symbols 的说明：避免假阳性）
    type_decls = {rel: type_symbols(texts[rel]) for rel in files}

    # export 闭包：lib 自身 + 它 re-export 的全部库（传递）
    reach_cache = {}

    def export_reach(lib, stack=None):
        if lib in reach_cache:
            return reach_cache[lib]
        if stack is None:
            stack = set()
        if lib in stack:                     # 防御循环 export
            return {lib}
        stack = stack | {lib}
        out = {lib}
        for e in exports_of.get(lib, ()):
            t = e["lib"]
            if t and t in files:
                out |= export_reach(t, stack)
        reach_cache[lib] = out
        return out

    def visible_libs(rel):
        """rel 通过 import（含 re-export 传递）+ show/hide 过滤后能看见的库。"""
        seen = {}
        for i in imports_of.get(rel, ()):
            t = i["lib"]
            if not t or t not in files:
                continue
            for L in export_reach(t):
                keep = True
                if i["show"] is not None and L == t:
                    # show 只按名字过滤，不按库过滤：由调用方逐个符号判断
                    keep = True
                seen.setdefault(L, []).append(i)
        return seen

    # 反向索引：哪些文件提到了某符号
    refs = defaultdict(list)
    for rel in files:
        blanked = strip_comments(texts[rel])
        for name, _, _ in moved:
            if re.search(r"\b%s\b" % re.escape(name), blanked):
                refs[name].append(rel)

    # 统一的可见性判定：文件 rel 能否解析到项目符号 name
    def symbol_visible(rel, name):
        if name in decls.get(rel, ()):
            return True                      # 自身声明
        vis = visible_libs(rel)
        for L in vis:
            if name not in decls.get(L, ()):
                continue
            excluded = False
            for imp in vis[L]:
                src_lib = imp["lib"]
                if imp["show"] is not None and src_lib == L and name not in imp["show"]:
                    excluded = True
                if name in imp["hide"]:
                    excluded = True
            if not excluded:
                return True
        return False

    failures, report = [], []
    for name, to_lib, from_lib in moved:
        if to_lib not in files:
            failures.append({"symbol": name, "reason": "新定义位置不存在",
                             "target": to_lib, "refs": []})
            continue
        if name not in decls[to_lib]:
            failures.append({"symbol": name, "reason": "新位置未声明该符号",
                             "target": to_lib, "refs": []})
            continue
        bad, ok = [], []
        for rel in refs[name]:
            (ok if symbol_visible(rel, name) else bad).append(rel)
        report.append({"symbol": name, "from": from_lib, "to": to_lib,
                       "ref_count": len(refs[name]),
                       "resolved": ok, "unresolved": bad})
        for rel in bad:
            failures.append({"symbol": name, "reason": "引用方看不见新位置",
                             "target": to_lib, "refs": [rel]})

    # 阶段 2：「新家」文件自身的引用是否都能解析
    dest_report = check_destination_self_sufficiency(
        files, type_decls, texts, symbol_visible, [t for _, t, _ in moved])
    for r in dest_report:
        if not r["exists"]:
            failures.append({"symbol": "(destination)", "reason": "新家文件不存在",
                             "target": r["file"], "refs": []})
        for u in r["unresolved"]:
            failures.append({"symbol": u["symbol"],
                             "reason": "新家文件自身无法解析该符号",
                             "target": r["file"], "refs": u["declared_in"]})

    if args.json:
        print(json.dumps({"symbols": report, "destinations": dest_report,
                          "failures": failures,
                          "result": "FAIL" if failures else "PASS"},
                         ensure_ascii=False, indent=2))
    else:
        print("=" * 78)
        print("类型搬家符号可达性校验 (verify_symbol_move)")
        print("=" * 78)
        for r in report:
            print("\n  %s" % r["symbol"])
            print("    原位置 : %s" % (r["from"] or "(未提供)"))
            print("    新位置 : %s" % r["to"])
            print("    引用方 : %d 个，可见 %d，断裂 %d" %
                  (r["ref_count"], len(r["resolved"]), len(r["unresolved"])))
            if r["unresolved"]:
                for rel in r["unresolved"]:
                    print("      [断裂] %s" % rel)
        print("\n  阶段 2：新家文件自身引用自检")
        for r in dest_report:
            n = len(r["unresolved"])
            print("    %-62s %s" % (r["file"].replace("lib/", ""),
                                    "OK" if n == 0 and r["exists"] else
                                    ("不存在" if not r["exists"] else "断裂 %d 个" % n)))
            for u in r["unresolved"]:
                print("        [断裂] %s  (声明于 %s)"
                      % (u["symbol"], ", ".join(x.replace("lib/", "")
                                                for x in u["declared_in"])))
        print("\n  结论: %s" % ("FAIL —— 存在断裂引用，会编译失败"
                                if failures else "PASS —— 引用方与所有新家文件均可解析"))

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
