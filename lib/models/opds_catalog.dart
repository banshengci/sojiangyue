/// OPDS 书源目录 / 条目模型。
class OpdsCatalog {
  const OpdsCatalog({
    required this.id,
    required this.name,
    required this.url,
    this.username,
    this.password,
  });

  final String id;
  final String name;
  final String url;
  final String? username;
  final String? password;

  bool get hasAuth =>
      (username != null && username!.isNotEmpty) ||
      (password != null && password!.isNotEmpty);

  OpdsCatalog copyWith({
    String? id,
    String? name,
    String? url,
    String? username,
    String? password,
  }) {
    return OpdsCatalog(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (username != null && username!.isNotEmpty) 'username': username,
        if (password != null && password!.isNotEmpty) 'password': password,
      };

  factory OpdsCatalog.fromJson(Map<String, dynamic> json) {
    return OpdsCatalog(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
    );
  }
}

/// OPDS acquisition 链接（可下载的书）。
class OpdsAcquisitionLink {
  const OpdsAcquisitionLink({
    required this.href,
    required this.type,
    this.title,
    this.length,
  });

  final String href;
  final String type;
  final String? title;
  final int? length;

  String get fileExtension {
    final lower = type.toLowerCase();
    if (lower.contains('epub')) return 'epub';
    if (lower.contains('pdf')) return 'pdf';
    if (lower.contains('mobipocket') || lower.contains('mobi')) return 'mobi';
    if (lower.contains('azw')) return 'azw3';
    if (lower.contains('fb2')) return 'fb2';
    if (lower.contains('cbz') || lower.contains('zip')) return 'cbz';
    if (lower.contains('txt')) return 'txt';
    // 从 URL 扩展名兜底
    final uri = Uri.tryParse(href);
    final path = uri?.path ?? href;
    final dot = path.lastIndexOf('.');
    if (dot > 0 && dot < path.length - 1) {
      return path.substring(dot + 1).toLowerCase();
    }
    return 'bin';
  }
}

/// OPDS 条目：书或子目录。
class OpdsEntry {
  const OpdsEntry({
    required this.title,
    this.author,
    this.summary,
    this.id,
    this.coverUrl,
    this.acquisitions = const [],
    this.subsectionUrl,
  });

  final String title;
  final String? author;
  final String? summary;
  final String? id;
  final String? coverUrl;
  final List<OpdsAcquisitionLink> acquisitions;
  final String? subsectionUrl;

  bool get isNavigation =>
      subsectionUrl != null && acquisitions.isEmpty;
  bool get isBook => acquisitions.isNotEmpty;
}

/// 一次 OPDS feed 解析结果。
class OpdsFeed {
  const OpdsFeed({
    required this.title,
    this.entries = const [],
    this.nextUrl,
    this.selfUrl,
  });

  final String title;
  final List<OpdsEntry> entries;
  final String? nextUrl;
  final String? selfUrl;
}
