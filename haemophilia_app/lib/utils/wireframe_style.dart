import 'package:flutter/material.dart';

Color wireframeColor(String form) {
  final status = form.toLowerCase();
  if (status.contains('incorrect')) return Colors.redAccent;
  if (status == 'correct') return Colors.greenAccent;
  if (status == 'adjusting') return Colors.amberAccent;
  return Colors.blueGrey.shade300;
}
