import 'package:flutter/material.dart';

/// Одно правило подсветки: список фраз (или regex) → стиль.
class HighlightRule {
  final List<String> phrases; // regexp по умолчанию, регистро-независимо
  final TextStyle? textStyle;
  const HighlightRule({required this.phrases, this.textStyle});
}

/// Разбирает DSL подсветки:
///   word@red
///   фраза@#ff6600
///   {
///   группа1
///   группа2
///   }@blue; background-color: #000;
/// Возвращает список правил + список ошибок (в формате: "строка N: …").
({List<HighlightRule> rules, List<String> errors}) parseHighlightDsl(
    String text) {
  final rules = <HighlightRule>[];
  final errors = <String>[];
  final lines = text.split(RegExp(r'\r?\n'));
  var i = 0;
  while (i < lines.length) {
    final raw = lines[i].trim();
    if (raw.isEmpty) {
      i++;
      continue;
    }
    // Группа
    if (raw.startsWith('{')) {
      final groupPhrases = <String>[];
      i++;
      while (i < lines.length) {
        final l = lines[i].trimRight();
        if (l.trim().startsWith('}')) {
          // '}@style' — стиль после '}'
          final afterClose = l.trim().substring(1).trim();
          final atIndex = afterClose.indexOf('@');
          if (atIndex == -1) {
            errors.add('строка ${i + 1}: не указан стиль после }');
            i++;
            break;
          }
          final styleStr = afterClose.substring(atIndex + 1).trim();
          rules.add(HighlightRule(
            phrases: groupPhrases,
            textStyle: _parseStyle(styleStr),
          ));
          i++;
          break;
        }
        if (l.trim().isNotEmpty) {
          groupPhrases.add(l.trim());
        }
        i++;
      }
      continue;
    }
    // Одиночное правило: phrase@style[; комментарий]
    final atIndex = raw.indexOf('@');
    if (atIndex == -1) {
      errors.add('строка ${i + 1}: не указан @стиль');
      i++;
      continue;
    }
    final phrase = raw.substring(0, atIndex).trim();
    final styleStr = raw.substring(atIndex + 1).trim();
    rules.add(HighlightRule(
      phrases: [phrase],
      textStyle: _parseStyle(styleStr),
    ));
    i++;
  }
  return (rules: rules, errors: errors);
}

/// Парсит строку CSS-стиля в TextStyle. Поддержка:
///   color, background-color (background), opacity,
///   font-size, font-weight, font-style, font-family,
///   text-decoration (и -color / -style / -thickness),
///   letter-spacing, word-spacing, line-height, text-shadow.
/// Свойства не относящиеся к тексту (padding, border, display) игнорируются.
/// Короткая форма: "red" / "#ff0" — воспринимается как color.
TextStyle? _parseStyle(String s) {
  Color? color;
  Color? bg;
  double? fontSize;
  FontWeight? fontWeight;
  FontStyle? fontStyle;
  String? fontFamily;
  double? letterSpacing;
  double? wordSpacing;
  double? height; // line-height
  double? opacity; // 0..1
  TextDecoration? decoration;
  Color? decorationColor;
  TextDecorationStyle? decorationStyle;
  double? decorationThickness;
  List<Shadow>? shadows;

  final parts = s.split(';');
  for (var part in parts) {
    part = part.trim();
    if (part.isEmpty) continue;
    final colonIdx = part.indexOf(':');
    if (colonIdx == -1) {
      // короткая форма: "red" / "#ff0" — считаем цветом текста
      final c = _parseColor(part);
      if (c != null) {
        color ??= c;
      }
      continue;
    }
    final key = part.substring(0, colonIdx).trim().toLowerCase();
    final value = part.substring(colonIdx + 1).trim();
    switch (key) {
      case 'color':
        color = _parseColor(value) ?? color;
        break;
      case 'background-color':
      case 'background':
        bg = _parseColor(value) ?? bg;
        break;
      case 'opacity':
        final n = double.tryParse(value);
        if (n != null) opacity = n.clamp(0.0, 1.0);
        break;
      case 'font-size':
        final n = _parseLength(value);
        if (n != null) fontSize = n;
        break;
      case 'font-weight':
        final lv = value.toLowerCase();
        switch (lv) {
          case 'normal':
          case '400':
            fontWeight = FontWeight.w400;
            break;
          case 'bold':
          case '700':
            fontWeight = FontWeight.w700;
            break;
          case '100':
            fontWeight = FontWeight.w100;
            break;
          case '200':
            fontWeight = FontWeight.w200;
            break;
          case '300':
          case 'light':
            fontWeight = FontWeight.w300;
            break;
          case '500':
          case 'medium':
            fontWeight = FontWeight.w500;
            break;
          case '600':
          case 'semibold':
          case 'demibold':
            fontWeight = FontWeight.w600;
            break;
          case '800':
            fontWeight = FontWeight.w800;
            break;
          case '900':
          case 'black':
          case 'heavy':
            fontWeight = FontWeight.w900;
            break;
        }
        break;
      case 'font-style':
        final lv = value.toLowerCase();
        if (lv == 'italic' || lv == 'oblique') {
          fontStyle = FontStyle.italic;
        } else if (lv == 'normal') {
          fontStyle = FontStyle.normal;
        }
        break;
      case 'font-family':
        // CSS может содержать список через запятую — берём первый,
        // убирая кавычки. Работает только если шрифт зарегистрирован в apk.
        final first = value.split(',').first.trim();
        fontFamily = first.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
        if (fontFamily.isEmpty) fontFamily = null;
        break;
      case 'text-decoration':
      case 'text-decoration-line':
        // CSS shorthand: "underline dotted red"
        final tokens = value.toLowerCase().split(RegExp(r'\s+'));
        final lines = <TextDecoration>[];
        for (final t in tokens) {
          switch (t) {
            case 'underline':
              lines.add(TextDecoration.underline);
              break;
            case 'line-through':
            case 'strikethrough':
              lines.add(TextDecoration.lineThrough);
              break;
            case 'overline':
              lines.add(TextDecoration.overline);
              break;
            case 'none':
              lines.clear();
              break;
            default:
              // возможно стиль линии или цвет в shorthand
              final maybeStyle = _parseDecorationStyle(t);
              if (maybeStyle != null) {
                decorationStyle = maybeStyle;
                break;
              }
              final maybeColor = _parseColor(t);
              if (maybeColor != null) decorationColor = maybeColor;
          }
        }
        if (lines.isNotEmpty) decoration = TextDecoration.combine(lines);
        break;
      case 'text-decoration-color':
        decorationColor = _parseColor(value) ?? decorationColor;
        break;
      case 'text-decoration-style':
        decorationStyle = _parseDecorationStyle(value) ?? decorationStyle;
        break;
      case 'text-decoration-thickness':
        final n = _parseLength(value);
        if (n != null) decorationThickness = n;
        break;
      case 'letter-spacing':
        final n = _parseLength(value);
        if (n != null) letterSpacing = n;
        break;
      case 'word-spacing':
        final n = _parseLength(value);
        if (n != null) wordSpacing = n;
        break;
      case 'line-height':
        // В CSS line-height может быть число (множитель), длина, или %.
        // Flutter `height` — это множитель относительно fontSize.
        final asNum = double.tryParse(value);
        if (asNum != null) {
          height = asNum;
        } else if (value.endsWith('%')) {
          final p = double.tryParse(value.substring(0, value.length - 1));
          if (p != null) height = p / 100.0;
        } else {
          final n = _parseLength(value);
          if (n != null && fontSize != null && fontSize > 0) {
            height = n / fontSize;
          }
        }
        break;
      case 'text-shadow':
        // "x y blur color" (простой вариант, без списков через запятую)
        final sh = _parseShadow(value);
        if (sh != null) shadows = [sh];
        break;
    }
  }

  // Применяем opacity к color (если задан)
  if (opacity != null && color != null) {
    color = color.withAlpha((opacity * 255).round());
  }

  final nothing = color == null &&
      bg == null &&
      fontSize == null &&
      fontWeight == null &&
      fontStyle == null &&
      fontFamily == null &&
      letterSpacing == null &&
      wordSpacing == null &&
      height == null &&
      decoration == null &&
      decorationColor == null &&
      decorationStyle == null &&
      decorationThickness == null &&
      shadows == null;
  if (nothing) return null;

  return TextStyle(
    color: color,
    backgroundColor: bg,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    fontFamily: fontFamily,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    height: height,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
    shadows: shadows,
  );
}

/// Парсит длину: "18px" / "1.2em" / "1.5rem" / "0.05em" / "-0.5px" → double в lp.
double? _parseLength(String v) {
  final m = RegExp(r'(-?[\d.]+)\s*(px|em|rem|pt)?', caseSensitive: false)
      .firstMatch(v);
  if (m == null) return null;
  final num = double.tryParse(m.group(1)!);
  if (num == null) return null;
  final unit = (m.group(2) ?? 'px').toLowerCase();
  switch (unit) {
    case 'em':
    case 'rem':
      return num * 14.0; // базовый размер
    case 'pt':
      return num * 1.333;
    case 'px':
    default:
      return num;
  }
}

TextDecorationStyle? _parseDecorationStyle(String v) {
  switch (v.toLowerCase()) {
    case 'solid':
      return TextDecorationStyle.solid;
    case 'double':
      return TextDecorationStyle.double;
    case 'dotted':
      return TextDecorationStyle.dotted;
    case 'dashed':
      return TextDecorationStyle.dashed;
    case 'wavy':
      return TextDecorationStyle.wavy;
  }
  return null;
}

/// Парсит "1px 1px 2px #000" → Shadow. Если одна из частей — цвет, он берётся.
Shadow? _parseShadow(String v) {
  final tokens = v.split(RegExp(r'\s+'));
  final nums = <double>[];
  Color? col;
  for (final t in tokens) {
    final n = _parseLength(t);
    if (n != null && nums.length < 3) {
      nums.add(n);
    } else {
      col ??= _parseColor(t);
    }
  }
  if (nums.length < 2) return null;
  return Shadow(
    offset: Offset(nums[0], nums[1]),
    blurRadius: nums.length >= 3 ? nums[2] : 0,
    color: col ?? const Color(0x80000000),
  );
}

/// Парсинг цвета: #hex (3/6/8 digits) или CSS-имя.
Color? _parseColor(String v) {
  v = v.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v.startsWith('#')) {
    final hex = v.substring(1);
    if (hex.length == 3) {
      final r = int.tryParse(hex[0] * 2, radix: 16);
      final g = int.tryParse(hex[1] * 2, radix: 16);
      final b = int.tryParse(hex[2] * 2, radix: 16);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(0xFF, r, g, b);
      }
    } else if (hex.length == 6) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(0xFF000000 | n);
    } else if (hex.length == 8) {
      // В CSS #RRGGBBAA, в Dart Color — 0xAARRGGBB.
      final n = int.tryParse(hex, radix: 16);
      if (n != null) {
        final r = (n >> 24) & 0xFF;
        final g = (n >> 16) & 0xFF;
        final b = (n >> 8) & 0xFF;
        final a = n & 0xFF;
        return Color.fromARGB(a, r, g, b);
      }
    }
  }
  return _cssColors[v];
}

/// Полный набор CSS named colors (CSS Color Module Level 4).
const Map<String, Color> _cssColors = {
  'aliceblue': Color(0xFFF0F8FF),
  'antiquewhite': Color(0xFFFAEBD7),
  'aqua': Color(0xFF00FFFF),
  'aquamarine': Color(0xFF7FFFD4),
  'azure': Color(0xFFF0FFFF),
  'beige': Color(0xFFF5F5DC),
  'bisque': Color(0xFFFFE4C4),
  'black': Color(0xFF000000),
  'blanchedalmond': Color(0xFFFFEBCD),
  'blue': Color(0xFF0000FF),
  'blueviolet': Color(0xFF8A2BE2),
  'brown': Color(0xFFA52A2A),
  'burlywood': Color(0xFFDEB887),
  'cadetblue': Color(0xFF5F9EA0),
  'chartreuse': Color(0xFF7FFF00),
  'chocolate': Color(0xFFD2691E),
  'coral': Color(0xFFFF7F50),
  'cornflowerblue': Color(0xFF6495ED),
  'cornsilk': Color(0xFFFFF8DC),
  'crimson': Color(0xFFDC143C),
  'cyan': Color(0xFF00FFFF),
  'darkblue': Color(0xFF00008B),
  'darkcyan': Color(0xFF008B8B),
  'darkgoldenrod': Color(0xFFB8860B),
  'darkgray': Color(0xFFA9A9A9),
  'darkgreen': Color(0xFF006400),
  'darkgrey': Color(0xFFA9A9A9),
  'darkkhaki': Color(0xFFBDB76B),
  'darkmagenta': Color(0xFF8B008B),
  'darkolivegreen': Color(0xFF556B2F),
  'darkorange': Color(0xFFFF8C00),
  'darkorchid': Color(0xFF9932CC),
  'darkred': Color(0xFF8B0000),
  'darksalmon': Color(0xFFE9967A),
  'darkseagreen': Color(0xFF8FBC8F),
  'darkslateblue': Color(0xFF483D8B),
  'darkslategray': Color(0xFF2F4F4F),
  'darkslategrey': Color(0xFF2F4F4F),
  'darkturquoise': Color(0xFF00CED1),
  'darkviolet': Color(0xFF9400D3),
  'deeppink': Color(0xFFFF1493),
  'deepskyblue': Color(0xFF00BFFF),
  'dimgray': Color(0xFF696969),
  'dimgrey': Color(0xFF696969),
  'dodgerblue': Color(0xFF1E90FF),
  'firebrick': Color(0xFFB22222),
  'floralwhite': Color(0xFFFFFAF0),
  'forestgreen': Color(0xFF228B22),
  'fuchsia': Color(0xFFFF00FF),
  'gainsboro': Color(0xFFDCDCDC),
  'ghostwhite': Color(0xFFF8F8FF),
  'gold': Color(0xFFFFD700),
  'goldenrod': Color(0xFFDAA520),
  'gray': Color(0xFF808080),
  'green': Color(0xFF008000),
  'greenyellow': Color(0xFFADFF2F),
  'grey': Color(0xFF808080),
  'honeydew': Color(0xFFF0FFF0),
  'hotpink': Color(0xFFFF69B4),
  'indianred': Color(0xFFCD5C5C),
  'indigo': Color(0xFF4B0082),
  'ivory': Color(0xFFFFFFF0),
  'khaki': Color(0xFFF0E68C),
  'lavender': Color(0xFFE6E6FA),
  'lavenderblush': Color(0xFFFFF0F5),
  'lawngreen': Color(0xFF7CFC00),
  'lemonchiffon': Color(0xFFFFFACD),
  'lightblue': Color(0xFFADD8E6),
  'lightcoral': Color(0xFFF08080),
  'lightcyan': Color(0xFFE0FFFF),
  'lightgoldenrodyellow': Color(0xFFFAFAD2),
  'lightgray': Color(0xFFD3D3D3),
  'lightgreen': Color(0xFF90EE90),
  'lightgrey': Color(0xFFD3D3D3),
  'lightpink': Color(0xFFFFB6C1),
  'lightsalmon': Color(0xFFFFA07A),
  'lightseagreen': Color(0xFF20B2AA),
  'lightskyblue': Color(0xFF87CEFA),
  'lightslategray': Color(0xFF778899),
  'lightslategrey': Color(0xFF778899),
  'lightsteelblue': Color(0xFFB0C4DE),
  'lightyellow': Color(0xFFFFFFE0),
  'lime': Color(0xFF00FF00),
  'limegreen': Color(0xFF32CD32),
  'linen': Color(0xFFFAF0E6),
  'magenta': Color(0xFFFF00FF),
  'maroon': Color(0xFF800000),
  'mediumaquamarine': Color(0xFF66CDAA),
  'mediumblue': Color(0xFF0000CD),
  'mediumorchid': Color(0xFFBA55D3),
  'mediumpurple': Color(0xFF9370DB),
  'mediumseagreen': Color(0xFF3CB371),
  'mediumslateblue': Color(0xFF7B68EE),
  'mediumspringgreen': Color(0xFF00FA9A),
  'mediumturquoise': Color(0xFF48D1CC),
  'mediumvioletred': Color(0xFFC71585),
  'midnightblue': Color(0xFF191970),
  'mintcream': Color(0xFFF5FFFA),
  'mistyrose': Color(0xFFFFE4E1),
  'moccasin': Color(0xFFFFE4B5),
  'navajowhite': Color(0xFFFFDEAD),
  'navy': Color(0xFF000080),
  'oldlace': Color(0xFFFDF5E6),
  'olive': Color(0xFF808000),
  'olivedrab': Color(0xFF6B8E23),
  'orange': Color(0xFFFFA500),
  'orangered': Color(0xFFFF4500),
  'orchid': Color(0xFFDA70D6),
  'palegoldenrod': Color(0xFFEEE8AA),
  'palegreen': Color(0xFF98FB98),
  'paleturquoise': Color(0xFFAFEEEE),
  'palevioletred': Color(0xFFDB7093),
  'papayawhip': Color(0xFFFFEFD5),
  'peachpuff': Color(0xFFFFDAB9),
  'peru': Color(0xFFCD853F),
  'pink': Color(0xFFFFC0CB),
  'plum': Color(0xFFDDA0DD),
  'powderblue': Color(0xFFB0E0E6),
  'purple': Color(0xFF800080),
  'rebeccapurple': Color(0xFF663399),
  'red': Color(0xFFFF0000),
  'rosybrown': Color(0xFFBC8F8F),
  'royalblue': Color(0xFF4169E1),
  'saddlebrown': Color(0xFF8B4513),
  'salmon': Color(0xFFFA8072),
  'sandybrown': Color(0xFFF4A460),
  'seagreen': Color(0xFF2E8B57),
  'seashell': Color(0xFFFFF5EE),
  'sienna': Color(0xFFA0522D),
  'silver': Color(0xFFC0C0C0),
  'skyblue': Color(0xFF87CEEB),
  'slateblue': Color(0xFF6A5ACD),
  'slategray': Color(0xFF708090),
  'slategrey': Color(0xFF708090),
  'snow': Color(0xFFFFFAFA),
  'springgreen': Color(0xFF00FF7F),
  'steelblue': Color(0xFF4682B4),
  'tan': Color(0xFFD2B48C),
  'teal': Color(0xFF008080),
  'thistle': Color(0xFFD8BFD8),
  'tomato': Color(0xFFFF6347),
  'transparent': Color(0x00000000),
  'turquoise': Color(0xFF40E0D0),
  'violet': Color(0xFFEE82EE),
  'wheat': Color(0xFFF5DEB3),
  'white': Color(0xFFFFFFFF),
  'whitesmoke': Color(0xFFF5F5F5),
  'yellow': Color(0xFFFFFF00),
  'yellowgreen': Color(0xFF9ACD32),
};

/// Применяет правила подсветки к [text] и возвращает список TextSpan'ов.
/// Правила обрабатываются регистро-независимо, считаются regex'ами.
/// Если правила пусты или ни одно не сработало — вернёт один span с базовым стилем.
List<TextSpan> applyHighlight(
  String text,
  List<HighlightRule> rules, {
  TextStyle? baseStyle,
}) {
  if (rules.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  // Собираем все совпадения (offset, end, style)
  final matches = <(int, int, TextStyle)>[];
  for (final rule in rules) {
    final style = rule.textStyle;
    if (style == null) continue;
    for (final phrase in rule.phrases) {
      if (phrase.isEmpty) continue;
      RegExp? re;
      // 1. unicode-aware: [а-я] с caseSensitive:false тогда покрывает и
      //    заглавные кириллические — без этого "путин[а-я]*" не матчит "Путин".
      try {
        re = RegExp(phrase, caseSensitive: false, unicode: true);
      } catch (_) {}
      // 2. Fallback: без unicode — если паттерн невалиден в unicode-mode
      //    (например, из-за strict escape правил).
      if (re == null) {
        try {
          re = RegExp(phrase, caseSensitive: false);
        } catch (_) {}
      }
      // 3. Последний шанс — экранированный литерал (если фраза вообще не regex).
      if (re == null) {
        try {
          re = RegExp(RegExp.escape(phrase),
              caseSensitive: false, unicode: true);
        } catch (_) {
          continue;
        }
      }
      for (final m in re.allMatches(text)) {
        if (m.end > m.start) {
          matches.add((m.start, m.end, style));
        }
      }
    }
  }
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  // Сортируем по старту; если пересечения — приоритет у первого (уже отсортированного)
  matches.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int, TextStyle)>[];
  for (final m in matches) {
    if (merged.isEmpty || m.$1 >= merged.last.$2) {
      merged.add(m);
    }
    // иначе пересекается — пропускаем, не дублируем
  }
  // Строим TextSpan'ы из плоского списка
  final spans = <TextSpan>[];
  var pos = 0;
  for (final m in merged) {
    if (pos < m.$1) {
      spans.add(TextSpan(text: text.substring(pos, m.$1), style: baseStyle));
    }
    spans.add(TextSpan(
      text: text.substring(m.$1, m.$2),
      style: (baseStyle ?? const TextStyle()).merge(m.$3),
    ));
    pos = m.$2;
  }
  if (pos < text.length) {
    spans.add(TextSpan(text: text.substring(pos), style: baseStyle));
  }
  return spans;
}
