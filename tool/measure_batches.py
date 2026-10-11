#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""measure_batches.py —— 统一复算各批次改动的 SCC / 2-环指标。

存在理由：`layer_gate.py` 的 `resolve_import` 早期版本漏解析了 Dart 的**裸相对
import**（`import 'base_tool.dart';`，本仓库 86 处），导致 import 图少 86 条边，
从而让 SCC 规模被系统性低估。修复后必须用**同一套算法**把所有批次的数字重算一遍，
避免新旧数字混用。

本脚本对「已落地的改动树」逐一测量，输出：
  * 内部边数
  * 环数量（SCC 规模 > 1 的个数）
  * 环内文件数
  * 最大 SCC
  * SCC 规模分布
  * **2-环（互相依赖对）数量** ← 拆「注册表 <-> 实现」这类改动的主要指标
  * 相对基线的脱离/新增文件

用法
    python3 measure_batches.py --baseline <干净树> --case <标签>=<树路径> [--case ...]
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layer_gate import build_graph, find_sccs, scc_snapshot  # noqa: E402


def two_cycles(adj):
    """互相依赖对（A->B 且 B->A），按 (min,max) 去重。"""
    out = set()
    for a in adj:
        for b in adj[a]:
            if a in adj.get(b, ()):
                out.add((a, b) if a < b else (b, a))
    return out


def measure(root):
    files, adj, ext, texts = build_graph(root)
    sccs = find_sccs(files, adj)
    snap = scc_snapshot(sccs)
    big = max(sccs, key=len) if sccs else []
    return {
        "root": root,
        "edges": sum(len(v) for v in adj.values()),
        "files": len(files),
        "scc": snap,
        "two_cycles": len(two_cycles(adj)),
        "big_members": set(big),
        "isolated": sorted([len(c) for c in sccs if len(c) <= 10], reverse=True),
    }


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", required=True, help="基线干净树路径")
    ap.add_argument("--case", action="append", required=True,
                    metavar="LABEL=PATH", help="待测树；label=path")
    ap.add_argument("--json", help="输出 JSON")
    args = ap.parse_args(argv)

    base = measure(args.baseline)
    cases = []
    for item in args.case:
        label, path = item.split("=", 1)
        cases.append((label.strip(), measure(path.strip())))

    hdr = "%-40s %6s %5s %6s %7s %7s  %s"
    print("=" * 132)
    print("统一复算（resolve_import 已修复：支持裸相对 import）")
    print("基线: %s" % os.path.abspath(args.baseline))
    print("=" * 132)
    print(hdr % ("改动", "内部边", "环数", "环内", "最大SCC", "2-环", "SCC 规模分布"))
    print("-" * 132)
    print(hdr % ("[baseline]",
                 base["edges"], base["scc"]["cycle_count"],
                 base["scc"]["files_in_cycles"], base["scc"]["max_scc"],
                 base["two_cycles"], base["scc"]["sizes"][:5]))
    rows = []
    for label, m in cases:
        print(hdr % (label,
                     m["edges"], m["scc"]["cycle_count"],
                     m["scc"]["files_in_cycles"], m["scc"]["max_scc"],
                     m["two_cycles"], m["scc"]["sizes"][:5]))
        left = sorted(base["big_members"] - m["big_members"])
        ent = sorted(m["big_members"] - base["big_members"])
        rows.append({"label": label, "scc": m["scc"], "edges": m["edges"],
                     "two_cycles": m["two_cycles"],
                     "delta_in_cycle": m["scc"]["files_in_cycles"] - base["scc"]["files_in_cycles"],
                     "delta_max_scc": m["scc"]["max_scc"] - base["scc"]["max_scc"],
                     "delta_two_cycles": m["two_cycles"] - base["two_cycles"],
                     "left_big_scc": left, "entered_big_scc": ent,
                     "isolated_scc_sizes": m["isolated"]})

    print("-" * 132)
    print("\n相对基线的变化：")
    print("%-40s %+6s %+6s %+7s %+7s" % ("改动", "Δ内部边", "Δ环内", "Δ最大SCC", "Δ2-环"))
    print("-" * 132)
    for r in rows:
        print("%-40s %+6d %+6d %+7d %+7d" % (
            r["label"], r["edges"] - base["edges"],
            r["delta_in_cycle"], r["delta_max_scc"], r["delta_two_cycles"]))

    print("\n脱离大分量的文件：")
    for r in rows:
        if r["left_big_scc"]:
            print("  %s (%d 个):" % (r["label"], len(r["left_big_scc"])))
            for x in r["left_big_scc"]:
                print("      - %s" % x)
    entered = [(r["label"], r["entered_big_scc"]) for r in rows if r["entered_big_scc"]]
    print("\n新进入大分量的文件: %s" %
          ("无" if not entered else "; ".join("%s: %s" % (l, v) for l, v in entered)))

    print("\n小分量（隔离环）规模变化:  baseline %s" % base["isolated"])
    for r in rows:
        print("    %-36s %s" % (r["label"], r["isolated_scc_sizes"]))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"baseline": {k: v for k, v in base.items()
                                    if k != "big_members"},
                       "cases": rows}, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("\n已写出: %s" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
