import 'package:flutter/material.dart';

class NoteTypeOption {
  final String type;
  final IconData icon;

  const NoteTypeOption({
    required this.type,
    required this.icon,
  });
}

const List<String> notesColors = [
  '66CCFF',
  'FF0000',
  '00FF00',
  'EB3BFF',
  'FFD700',
];

const List<NoteTypeOption> notesType = [
  NoteTypeOption(
    type: 'highlight',
    icon: Icons.highlight_alt,
  ),
  NoteTypeOption(
    type: 'underline',
    icon: Icons.format_underline,
  ),
];
