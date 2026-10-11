#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""analyze_roadmap.py —— SCC 拆解归因与分批路线图。

对 `lib/` 建图（复用 layer_gate.py 的 DSL 解析），然后：

  1. 逐处拆环的**单独归因**：只应用某一处改动的边删除，看 SCC 变化（回答"这处改动到底值多少"）。
  2. **类别批量**：按"依赖类别"（而不是逐条边）批量删边，看 SCC 变化。
     逐个删边在 241 节点的大分量里几乎无效（见下），批量类别才是正确的施力单位。
  3. **贪心累加**：按风险从低到高累加类别，给出每批之后的 SCC 数字。

用法
    python3 analyze_roadmap.py --repo . [--json out/roadmap.json]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layer_gate import build_graph, find_sccs, layer_of, scc_snapshot  # noqa: E402


# ---------------------------------------------------------------------------
# 类别定义：每个类别 = 一组「应当切断的边」+ 风险评级 + 说明
# ---------------------------------------------------------------------------
CATEGORIES = [
    {
        "key": "A",
        "name": "models → service/providers/page/widgets",
        "risk": "低",
        "why": "models 是纯数据层，正向依赖只应是 enums/models。违规点全部是"
               "「类型定义放错文件」（枚举/常量住在 UI 或 service 里），搬到 enums/ 即可。",
        "matcher": lambda a, b: layer_of(a) == "models" and
                               layer_of(b) in ("service", "providers", "page", "widgets"),
    },
    {
        "key": "B",
        "name": "utils/config → widgets/page/service",
        "risk": "低",
        "why": "与 A 同类，仍是「枚举/常量放错文件」为主（PageTurn、StatisticsDashboardTileType"
               "、富文本渲染 helper）。工具层反向依赖 UI 是纯设计事故，修法明确。",
        "matcher": lambda a, b: layer_of(a) in ("utils", "config") and
                               layer_of(b) in ("widgets", "page", "service"),
    },
    {
        "key": "C",
        "name": "widgets → dao",
        "risk": "中",
        "why": "docs/DEVELOPMENT.md 明文的第 1 条。但注意：切断它对 SCC **没有影响**"
               "（widgets 与 dao 之间还有 provider 等其它路径），收益在"
               "「组件可独立测试」而非「消除循环」。所以它可以先做门禁、后做重构。",
        "matcher": lambda a, b: layer_of(a) == "widgets" and layer_of(b) == "dao",
    },
    {
        "key": "D",
        "name": "dao → providers/page/widgets/service",
        "risk": "中",
        "why": "只有 1 条边（reading_time → Sync() 单例），但修法需要依赖注入/回调，"
               "涉及调用点变化，不属于「纯类型搬家」。",
        "matcher": lambda a, b: layer_of(a) == "dao" and
                               layer_of(b) in ("providers", "page", "widgets", "service"),
    },
    {
        "key": "E",
        "name": "service → page/widgets（UI 组件）",
        "risk": "中高",
        "why": "需要把「service 调用页面动作」改成「返回结果 + UI 层编排」。"
               "涉及 book.dart / tts 三个后端 / initialization_check，是真正的重构，"
               "必须配测试后再动。",
        "matcher": lambda a, b: layer_of(a) == "service" and
                               layer_of(b) in ("page", "widgets"),
    },
    {
        "key": "F",
        "name": "非 root 层 → main.dart（全局 navigatorKey 等）",
        "risk": "高",
        "why": "**收益最大的一类**（28 条边：241 → 174）。根因是 `main.dart` 被当作"
               "全局服务定位器（导出 navigatorKey / audioHandler / heroineController）。"
               "修法是把这些全局量下沉到独立 leaf 模块（如 utils/app_globals.dart 或"
               "providers/*），main.dart 只做 bootstrap。这条改动面广、触及启动流程，"
               "必须最后做且需要端到端验证。",
        "matcher": lambda a, b: layer_of(b) == "(root)" and layer_of(a) != "(root)",
    },
]


def report(adj, files, label, show_small=0):
    sccs = find_sccs(files, adj)
    snap = scc_snapshot(sccs)
    print("  %-46s 环数=%-3d 环内=%-4d 最大SCC=%-4d %s" %
          (label, snap["cycle_count"], snap["files_in_cycles"],
           snap["max_scc"], snap["sizes"][:6]))
    return snap, sccs


def cut(adj, edges):
    out = {k: set(v) for k, v in adj.items()}
    for a, b in edges:
        out.get(a, set()).discard(b)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="SCC 拆解归因与分批路线图")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--lib", default="lib")
    ap.add_argument("--json", help="把结果写到 JSON")
    args = ap.parse_args(argv)

    files, adj, external, texts = build_graph(args.repo, args.lib)
    total_edges = sum(len(v) for v in adj.values())
    print("=" * 96)
    print("SCC 拆解归因与分批路线图   repo=%s  lib文件=%d  内部边=%d" %
          (os.path.abspath(args.repo), len(files), total_edges))
    print("=" * 96)

    base_snap, _ = report(adj, files, "[baseline]")

    # ---- 每个类别的边集合 ----
    cat_edges = {}
    for c in CATEGORIES:
        es = {(a, b) for a in adj for b in adj[a] if c["matcher"](a, b)}
        cat_edges[c["key"]] = es

    print("\n[1] 单类别效果（只切这一类）")
    results = {}
    for c in CATEGORIES:
        snap, _ = report(cut(adj, cat_edges[c["key"]]), files,
                         "%s %s (%d 边)" % (c["key"], c["name"][:34],
                                            len(cat_edges[c["key"]])))
        results[c["key"]] = snap

    print("\n[2] 单个边删除的效果（证明「逐条拆边」是错的施力单位）")
    single = []
    for a in sorted(adj):
        for b in sorted(adj[a]):
            snap, _ = report(cut(adj, {(a, b)}), files,
                             "cut %s -> %s" % (a.replace("lib/", ""), b.replace("lib/", "")))
            single.append({"from": a, "to": b, "snap": snap})
    no_effect = [s for s in single if s["snap"]["files_in_cycles"] == base_snap["files_in_cycles"]]
    print("\n  => %d / %d 条单边删除对 SCC **无任何影响**（环内文件数不变）"
          % (len(no_effect), len(single)))

    print("\n[3] 贪心累加（风险从低到高：A → B → C → D → E → F）")
    order = ["A", "B", "C", "D", "E", "F"]
    acc, cum = set(), []
    for k in order:
        acc |= cat_edges[k]
        snap, sccs = report(cut(adj, acc), files,
                            "累加至 %s（累计 %d 边）" % (k, len(acc)))
        cum.append({"through": k, "cumulative_edges": len(acc), "scc": snap})

    print("\n[4] 全部切断（目标态）")
    allsnap, allsccs = report(cut(adj, acc), files, "A+B+C+D+E+F 全部切断")
    print("\n    剩余最大分量成员（前 25 个，即「不是靠分层规则能拆掉」的部分）:")
    for m in allsccs[0][:25] if allsccs else []:
        print("      %s" % m)

    data = {
        "repo": os.path.abspath(args.repo),
        "lib_file_count": len(files),
        "internal_edges": total_edges,
        "baseline": base_snap,
        "per_category": {c["key"]: {"name": c["name"], "risk": c["risk"],
                                    "why": c["why"],
                                    "edge_count": len(cat_edges[c["key"]]),
                                    "edges": sorted("%s -> %s" % (a, b)
                                                    for a, b in cat_edges[c["key"]]),
                                    "scc": results[c["key"]]}
                         for c in CATEGORIES},
        "single_edge_no_effect": len(no_effect),
        "single_edge_total": len(single),
        "greedy_cumulative": cum,
        "all_categories": allsnap,
    }
    if args.json:
        os.makedirs(os.path.dirname(args.json) or ".", exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("\n已写出: %s" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
