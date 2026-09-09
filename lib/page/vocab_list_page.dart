import 'package:songjiang_reader/dao/vocab.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/vocab_item.dart';
import 'package:flutter/material.dart';

/// 生词 / 难句本：浏览、搜索、标记复习、删除。
class VocabListPage extends StatefulWidget {
  const VocabListPage({super.key});

  @override
  State<VocabListPage> createState() => _VocabListPageState();
}

class _VocabListPageState extends State<VocabListPage> {
  List<VocabItem> _items = [];
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload([String? keyword]) async {
    setState(() => _loading = true);
    final items = await vocabDao.selectAll(keyword: keyword);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _markReviewed(VocabItem item) async {
    if (item.id == null) return;
    await vocabDao.markReviewed(item.id!);
    await _reload(_searchController.text);
  }

  Future<void> _delete(VocabItem item) async {
    if (item.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).commonDelete),
        content: Text(item.term),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.of(context).commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await vocabDao.delete(item.id!);
    await _reload(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).vocabTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: L10n.of(context).vocabSearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _reload,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            L10n.of(context).vocabEmptyHint,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(
                                item.term,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.chapter != null &&
                                      item.chapter!.isNotEmpty)
                                    Text(
                                      item.chapter!,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  if (item.bookTitle != null &&
                                      item.bookTitle!.isNotEmpty)
                                    Text(
                                      item.bookTitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey),
                                    ),
                                  Text(
                                    L10n.of(context).vocabReviewCount(
                                        item.reviewCount),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'review') {
                                    _markReviewed(item);
                                  } else if (value == 'delete') {
                                    _delete(item);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'review',
                                    child: Text(L10n.of(context).vocabMarkReviewed),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(L10n.of(context).commonDelete),
                                  ),
                                ],
                              ),
                              onTap: () => _markReviewed(item),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
