import 'package:flutter/material.dart';

import '../theme/cblrep_theme.dart';

/// Member profile photo with an initials fallback.
///
/// Replaces the plain coloured `CircleAvatar`-with-a-letter used across the
/// app, so a member who has uploaded a photo is recognisable anywhere their
/// name appears while everyone else still renders cleanly.
///
/// A broken or expired photo URL falls back to the initial rather than the
/// platform's grey error glyph, and while the photo is still loading the
/// coloured circle shows — so the layout never jumps.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 20,
    this.backgroundColor = CblrepColors.brandGreen,
    this.borderColor,
  });

  /// Absolute URL from the API (`avatar_url`), already host-rewritten.
  final String? imageUrl;

  /// Used for the initials fallback and the semantic label.
  final String name;

  final double radius;
  final Color backgroundColor;

  /// Optional ring, e.g. to mark a verified resident.
  final Color? borderColor;

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.take(1).toString().toUpperCase();
  }

  TextStyle get _initialStyle => TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.8,
      );

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasPhoto = url != null && url.isNotEmpty;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                // A photo that fails to load degrades to the initial instead
                // of the platform's broken-image glyph.
                errorBuilder: (_, _, _) => Text(_initial, style: _initialStyle),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
            )
          : Text(_initial, style: _initialStyle),
    );

    return Semantics(
      label: name,
      image: hasPhoto,
      child: borderColor == null
          ? avatar
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor!, width: 2),
              ),
              child: avatar,
            ),
    );
  }
}
