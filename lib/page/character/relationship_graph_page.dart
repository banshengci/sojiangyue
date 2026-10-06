import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'character_detail_page.dart';
import 'characters_page_strings.dart';

/// 关系图谱页：用 graphview 把人物画成节点、关系画成连线。
///
/// - 节点大小随 [CharacterCard.importance]（0-100）变化；
/// - 连线颜色随 [CharacterRelation.trust] 正负变化：正向=江青，负向=砂朱；
/// - 连线粗细随 |trust| 变化。
///
/// 布局算法用 graphview 的 [FruchterNakaoAlgorithm]（力导向，天然支持含环的
/// 一般图，不会因关系成环而崩溃）。如需更紧凑的层次布局，可替换为
/// `BuchheimWalkerAlgorithm(config, ArrowEdgeRenderer(config))`。
class RelationshipGraphPage extends StatefulWidget {
  const RelationshipGraphPage({super.key, required this.bookId, this.bookTitle});

  final int bookId;
  final String? bookTitle;

  @override
  State<RelationshipGraphPage> createState() => _RelationshipGraphPageState();
}

class _RelationshipGraphPageState extends State<RelationshipGraphPage> {
  Graph? _graph;
  Algorithm? _algorithm;
  final _controller = TransformationController();
  final Map<String, CharacterCard> _byName = {};
  bool _loading = true;
  String? _error;

  // 与 SjColors 对齐的固定色（边在构图阶段上色，此时无 context）。
  static const Color _positive = Color(0xFF3D8C7D); // 江青
  static const Color _negative = Color(0xFFC4543D); // 砂朱

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _buildGraph() async {
    try {
      final cards = await characterDao.getCharacters(widget.bookId);
      final relations = await characterDao.getRelations(widget.bookId);
      if (!mounted) return;
      for (final c in cards) _byName[c.name] = c;

      final graph = Graph()..isTree = false;
      final nodeCache = <String, Node>{};
      Node nodeFor(String name) =>
          nodeCache.putIfAbsent(name, () => Node.Id(name));

      for (final card in cards) {
        graph.addNode(nodeFor(card.name));
      }
      for (final r in relations) {
        final a = nodeFor(r.sourceName);
        final b = nodeFor(r.targetName);
        final trust = r.trust;
        final color = trust >= 0 ? _positive : _negative;
        final width = (1 + (trust.abs() / 20).clamp(0, 5) * 1.0).clamp(1, 6);
        graph.addEdge(
          a,
          b,
          paint: Paint()
            ..color = color
            ..strokeWidth = width
            ..style = PaintingStyle.stroke,
        );
      }

      final algorithm = FruchterNakaoAlgorithm(300, 1.0, graph);

      if (!mounted) return;
      setState(() {
        _graph = graph;
        _algorithm = algorithm;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openDetail(String name) {
    final card = _byName[name];
    if (card == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterDetailPage(
          bookId: widget.bookId,
          character: card,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bookTitle != null
              ? '${widget.bookTitle} · ${CharactersPageText.viewGraph}'
              : CharactersPageText.viewGraph,
        ),
        actions: [
          IconButton(
            tooltip: CharactersPageText.close,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _buildGraph();
            },
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : _error != null
              ? Center(child: Text(_error!, style: SjText.body(c.inkSoft)))
              : _graph == null || _graph!.nodeCount == 0
                  ? EmptyStateHint(
                      icon: Icons.account_tree_outlined,
                      title: CharactersPageText.viewGraph,
                      subtitle: CharactersPageText.noRelation,
                    )
                  : _GraphView(
                      graph: _graph!,
                      algorithm: _algorithm!,
                      controller: _controller,
                      byName: _byName,
                      onTapNode: _openDetail,
                    ),
    );
  }
}

class _GraphView extends StatelessWidget {
  const _GraphView({
    required this.graph,
    required this.algorithm,
    required this.controller,
    required this.byName,
    required this.onTapNode,
  });

  final Graph graph;
  final Algorithm algorithm;
  final TransformationController controller;
  final Map<String, CharacterCard> byName;
  final void Function(String name) onTapNode;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InteractiveViewer(
      transformationController: controller,
      minScale: 0.3,
      maxScale: 3.5,
      child: GraphView.builder(
        graph: graph,
        algorithm: algorithm,
        paint: Paint()
          ..color = c.inkSoft
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        autoZoomToFit: true,
        builder: (node) {
          final name = node.key?.value?.toString() ?? '';
          final card = byName[name];
          final importance = card?.importance ?? 50;
          final box = (56 + importance / 100 * 40).clamp(56.0, 96.0);
          return GestureDetector(
            onTap: () => onTapNode(name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: c.divider,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: BoxConstraints(minWidth: box, maxWidth: 160),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: SjText.cardTitle(c.ink)
                    .copyWith(fontSize: importance > 75 ? 16 : 14),
              ),
            ),
          );
        },
      ),
    );
  }
}
