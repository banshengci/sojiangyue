#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""teeth_tests.py —— 门禁有效性验证（注入测试）。

证明 `layer_gate.py` 真的能抓住各类退化，而不是"自己给自己打分"。所有注入都在
临时副本（/tmp）上进行，不改动仓库。

用法
    python3 teeth_tests.py --base-tree <基线树> --base-json <基线JSON> [--work <工作副本>]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from layer_gate import build_graph, find_sccs  # noqa: E402

GATE = os.path.join(HERE, "layer_gate.py")


def run_gate(work, base_json, extra=()):
    p = subprocess.run([sys.executable, GATE, "--repo", work,
                        "--baseline", base_json, *extra],
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def reset(work, base_tree):
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(base_tree, work)


def show_delta(out):
    lines = out.splitlines()
    for i, l in enumerate(lines):
        if "新进入环" in l:
            for x in lines[i:i + 6]:
                print("         " + x)
            break


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-tree", required=True)
    ap.add_argument("--base-json", required=True)
    ap.add_argument("--work", default="/tmp/teeth_work")
    args = ap.parse_args()

    results = []

    def case(title, expect, injections=None, extra=()):
        if injections:
            injections(args.work)
        rc, out = run_gate(args.work, args.base_json, extra)
        ok = (rc == expect)
        results.append((title, rc, expect, ok))
        print("  [%s] %s  (exit=%d, 期望 %d)" % ("PASS" if ok else "FAIL", title, rc, expect))
        show_delta(out)
        reset(args.work, args.base_tree)      # 每个用例后回到干净态

    print("=" * 78)
    print("门禁有效性注入测试")
    print("  基线树  : %s" % args.base_tree)
    print("  基线 JSON: %s" % args.base_json)
    print("=" * 78)

    # ---- 0) 对照：不加注入应 PASS ----
    reset(args.work, args.base_tree)
    case("未注入（对照）", 0)

    # ---- 1) R1: widgets -> dao ----
    def inj_r1(work):
        p = os.path.join(work, "lib/widgets/reading_page/widget_title.dart")
        s = open(p, encoding="utf-8").read()
        s = s.replace("import 'package:flutter/material.dart';",
                      "import 'package:songjiang_reader/dao/book.dart';\n"
                      "import 'package:flutter/material.dart';", 1)
        open(p, "w", encoding="utf-8", newline="").write(s)
    case("注入 widgets -> dao（R1，文档第 1 条）", 1, inj_r1)

    # ---- 2) R4: service -> SmartDialog ----
    def inj_r4(work):
        p = os.path.join(work, "lib/service/vibration_service.dart")
        lines = open(p, encoding="utf-8").read().split("\n")
        lines.insert(0, "import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';")
        open(p, "w", encoding="utf-8", newline="").write("\n".join(lines))
    case("注入 service -> SmartDialog（R4，文档第 3 条）", 1, inj_r4)

    # ---- 3) 无规则违规、纯「既有文件被拖入环」 ----
    def inj_drag(work):
        files, adj, ext, texts = build_graph(work)
        incyc = {m for c in find_sccs(files, adj) for m in c}
        outside = sorted(files - incyc)
        pick = None
        for F in outside:
            for H in incyc:
                if F in adj.get(H, ()):
                    pick = (F, H)
                    break
            if pick:
                break
        if not pick:
            raise SystemExit("找不到可构造回退的候选")
        F, H = pick
        body = open(os.path.join(work, F), encoding="utf-8").read().split("\n")
        body.insert(0, "import 'package:songjiang_reader/%s';" % H[len("lib/"):])
        open(os.path.join(work, F), "w", encoding="utf-8", newline="").write("\n".join(body))
        print("        注入: %s -> %s  （既有文件：环外 -> 环内）"
              % (F[len("lib/"):], H[len("lib/"):]))
    case("注入无规则违规的纯耦合回退（既有文件被拖入环）", 1, inj_drag)

    # ---- 4) 破损状态下 --update-baseline 必须拒绝 ----
    reset(args.work, args.base_tree)
    inj_drag(args.work)
    rc, out = run_gate(args.work, args.base_json, ("--update-baseline",))
    ok = (rc == 1 and "拒绝刷新基线" in out)
    results.append(("--update-baseline 拒绝放宽（既有文件被拖入环）", rc, 1, ok))
    print("  [%s] --update-baseline 拒绝放宽  (exit=%d)" % ("PASS" if ok else "FAIL", rc))
    reset(args.work, args.base_tree)

    # ---- 5) 仅新建文件进入环 → 允许 ----
    rc, out = run_gate(args.work, args.base_json)
    print()
    print("  参考：仅新建文件进入环的情形需在「批次 2」树上验证，见 README 记录。")

    bad = [r for r in results if not r[3]]
    print()
    print("结果: %d 个用例, 通过 %d, 失败 %d"
          % (len(results), len(results) - len(bad), len(bad)))
    print("门禁有效性验证%s" % ("通过" if not bad else "存在未通过用例"))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
