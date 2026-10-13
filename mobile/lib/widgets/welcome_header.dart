import 'package:flutter/material.dart';
import '../theme/cblrep_theme.dart';

/// Branded welcome header — official logo + greeting + subtitle.
class WelcomeHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  const WelcomeHeader({super.key, required this.name, required this.subtitle});

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'M';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CblrepGradientHeader(
      child: Row(children: [
        const CblrepLogo(radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Good day, $name!',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: CblrepColors.actionOrange, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
