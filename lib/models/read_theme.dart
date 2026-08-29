import 'dart:convert';
import 'dart:core';

class ReadTheme {
  int? id;

  /// 主题名。松江阅的预置主题走中文意象命名（宣纸 / 松烟 / 竹月…），
  /// 用户自建主题留空即可（界面会回退显示「自定义」）。
  String name;
  String backgroundColor;
  String textColor;
  String backgroundImagePath;

  ReadTheme(
      {this.id,
      this.name = '',
      required this.backgroundColor,
      required this.textColor,
      required this.backgroundImagePath});

  Map<String, Object?> toMap() {
    return {
      if (name.isNotEmpty) 'name': name,
      'background_color': backgroundColor,
      'text_color': textColor,
      'background_image_path': backgroundImagePath
    };
  }

  String toJson() {
    return '''
    {
      "id": $id,
      "name": "$name",
      "backgroundColor": "$backgroundColor",
      "textColor": "$textColor",
      "backgroundImagePath": "$backgroundImagePath"
    }
    ''';
  }

  factory ReadTheme.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    return ReadTheme(
      id: data['id'],
      name: data['name'] as String? ?? '',
      backgroundColor: data['backgroundColor'],
      textColor: data['textColor'],
      backgroundImagePath: data['backgroundImagePath'],
    );
  }

  factory ReadTheme.fromDb(Map<String, dynamic> map) {
    return ReadTheme(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      backgroundColor: map['background_color'] as String? ?? 'FFFBF7EE',
      textColor: map['text_color'] as String? ?? 'FF2E2A24',
      backgroundImagePath: map['background_image_path'] as String? ?? '',
    );
  }

  ReadTheme copyWith({
    int? id,
    String? name,
    String? backgroundColor,
    String? textColor,
    String? backgroundImagePath,
  }) {
    return ReadTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
    );
  }
}
