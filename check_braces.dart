import 'dart:io';

void main() {
  final file = File('D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/sales_screen.dart');
  final lines = file.readAsLinesSync();
  int open = 0;
  int close = 0;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    int lineOpen = 0;
    int lineClose = 0;
    for (int j = 0; j < line.length; j++) {
      if (line[j] == '{') { open++; lineOpen++; }
      if (line[j] == '}') { close++; lineClose++; }
    }
    if (lineOpen > 0 || lineClose > 0) {
      // print('Line ${i + 1}: +$lineOpen, -$lineClose (Total: $open, $close)');
    }
    if (open == close && open > 0) {
      // This means a top-level block (like a method or class) might have ended.
      print('Line ${i + 1} ends a top-level block. Total open/close: $open');
    }
  }
}
