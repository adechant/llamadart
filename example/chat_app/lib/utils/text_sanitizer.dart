String sanitizeForTextLayout(String input) {
  if (input.isEmpty) {
    return input;
  }

  final units = input.codeUnits;
  final output = StringBuffer();

  for (var i = 0; i < units.length; i++) {
    final current = units[i];

    if (_isLeadingSurrogate(current)) {
      if (i + 1 < units.length && _isTrailingSurrogate(units[i + 1])) {
        output.writeCharCode(current);
        output.writeCharCode(units[i + 1]);
        i++;
      } else {
        output.writeCharCode(0xFFFD);
      }
      continue;
    }

    if (_isTrailingSurrogate(current)) {
      output.writeCharCode(0xFFFD);
      continue;
    }

    output.writeCharCode(current);
  }

  return output.toString();
}

bool _isLeadingSurrogate(int codeUnit) {
  return codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
}

bool _isTrailingSurrogate(int codeUnit) {
  return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
