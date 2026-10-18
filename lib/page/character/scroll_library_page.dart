import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/service/enhancement_pack/enhancement_pack_service.dart';
import 'package:songjiang_reader/service/enhancement_pack/scroll_library.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 在线书卷库：发现并安装别人整理好的「书卷包」（人物 + 关系 + 世界观 + 时间线）。
///
/// 设计取舍：
/// * **地址未配置时不用空白页糊弄**，而是一张「填地址」的引导卡——
///   书卷库是社区资源，不同人可能指向不同镜像。
/// * 安装必须**先选目标书**：书卷包本身不带 bookId，挂错书比装不上更糟。
/// * 任何一步失败都保留列表，只把错误显示出来，不把用户赶回上一页。
class ScrollLibraryPage extends StatefulWidget {
  const ScrollLibraryPage({super.key, this.bookId, this.bookTitle});

  final int? bookId;
  final String? bookTitle;

  @override
  State<ScrollLibraryPage> createState() => _ScrollLibraryPageState();
}

class _ScrollLibraryPageState extends State<ScrollLibraryPage> {
  final _client = ScrollLibraryClient();
  final _urlController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _url = '';
  List<ScrollPackEntry> _entries = const [];
  String? _installingId;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final url = await ScrollLibraryConfig.resolveUrl();
    if (!mounted) return;
    _urlController.text = url;
    setState(() => _url = url);
    if (url.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    await _load(url);
  }

  Future<void> _load(String url) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _client.fetchCatalog(url);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _saveUrlAndLoad() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ScrollLibraryConfig.saveUrl(url);
    if (!mounted) return;
    setState(() => _url = url);
    await _load(url);
  }

  /// 安装：先定目标书，再下载校验，最后导入。
  Future<void> _install(ScrollPackEntry entry) async {
    if (_installingId != null) return;

    int? targetBookId = widget.bookId;
    if (targetBookId == null) {
      final books = await bookDao.selectNotDeleteBooks();
      if (!mounted) return;
      if (books.isEmpty) {
        SjToast.show('书架里还没有书，先导入一本');
        return;
      }
      targetBookId = await _pickBook(books);
      if (targetBookId == null || !mounted) return;
    }

    setState(() => _installingId = entry.id);
    try {
      final bytes = await _client.download(entry);
      final service = EnhancementPackService(characterDao);
      final count = await service.importCharacterGraph(targetBookId, bytes);
      if (!mounted) return;
      SjToast.show('已安装「${entry.name}」：$count 位人物');
    } catch (e) {
      SjLog.warning('ScrollLibrary: 安装失败 ${entry.id}: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Bad state: ', '');
      SjToast.show('安装失败：$msg');
    } finally {
      if (mounted) setState(() => _installingId = null);
    }
  }

  Future<int?> _pickBook(List<Book> books) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('装到哪本书上？'),
              ),
              for (final b in books.take(100))
                ListTile(
                  title: Text(b.title),
                  subtitle: b.author.isEmpty
                      ? null
                      : Text(b.author),
                  onTap: () => Navigator.pop(ctx, b.id),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bookTitle == null ? '书卷库' : '${widget.bookTitle} · 书卷库',
        ),
        actions: [
          if (_url.isNotEmpty)
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : () => _load(_url),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_url.isEmpty) {
      return _buildUrlSetup(
        title: '还没有配置书卷库地址',
        hint: '填一个目录 JSON 的地址（https）。如果你没有，可以先问分享书卷包的人要。',
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.cloud_off,
              size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text('拉取失败：$_error'),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: () => _load(_url),
                child: const Text('重试'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _url = ''),
                child: const Text('换个地址'),
              ),
            ],
          ),
        ],
      );
    }
    if (_entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.library_books_outlined,
              size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          const Text('这个地址下还没有书卷包。'),
          const SizedBox(height: 8),
          Text(
            '目录文件里需要至少一条带 downloadUrl 与 sha256 的条目。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).disabledColor,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _url = ''),
            child: const Text('换个地址'),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _entries[i];
        final installing = _installingId == e.id;
        return ListTile(
          title: Text(e.name),
          subtitle: Text(
            [
              if (e.bookTitle != null && e.bookTitle!.isNotEmpty) e.bookTitle!,
              if (e.author.isNotEmpty) e.author,
              if (e.description.isNotEmpty) e.description,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: installing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _installingId == null ? () => _install(e) : null,
                  child: const Text('安装'),
                ),
        );
      },
    );
  }

  Widget _buildUrlSetup({required String title, required String hint}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).disabledColor,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: '目录地址',
            hintText: 'https://example.com/scrolls-catalog.json',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: _saveUrlAndLoad,
              child: const Text('保存并加载'),
            ),
            if (_error != null) ...[
              const SizedBox(width: 12),
              Expanded(child: Text('失败：$_error')),
            ],
          ],
        ),
      ],
    );
  }
}
