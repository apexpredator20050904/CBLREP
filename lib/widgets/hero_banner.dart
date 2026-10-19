import 'package:flutter/material.dart';
import '../config/community.dart';
import '../theme/cblrep_theme.dart';
import 'user_avatar.dart';

/// The localized greeting for the current time of day.
///
/// Cebuano is the everyday language of this part of Bohol, and the app is
/// used by neighbours, not by an English-only administration — so the home
/// screen greets a member the way a neighbour would.
enum _Greeting {
  morning('Maayong Buntag', 'Good morning'),
  afternoon('Maayong Hapon', 'Good afternoon'),
  evening('Maayong Gabi', 'Good evening');

  const _Greeting(this.local, this.english);

  /// The Cebuano greeting, shown in the banner.
  final String local;

  /// The English gloss, used for the accessibility label.
  final String english;

  /// The greeting that fits the current clock.
  static _Greeting forNow([DateTime? at]) {
    final hour = (at ?? DateTime.now()).hour;
    if (hour >= 5 && hour < 12) return _Greeting.morning;
    if (hour >= 12 && hour < 18) return _Greeting.afternoon;
    return _Greeting.evening;
  }
}

/// The warm welcome banner at the top of the home feed.
///
/// Carries the localized greeting, the member's name, the line that explains
/// what the portal is for, and the quick-filter bar for Trinidad's
/// barangays — the fastest way for a member to see what their own
/// neighbourhood is sharing.
class HeroBanner extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  /// The barangay the feed is currently filtered by ('' = all of them).
  final String selectedBarangay;

  final ValueChanged<String> onBarangaySelected;

  const HeroBanner({
    super.key,
    required this.name,
    this.avatarUrl,
    this.selectedBarangay = '',
    required this.onBarangaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = _Greeting.forNow();
    final hasPhoto = avatarUrl != null && avatarUrl!.isNotEmpty;
    final firstName = name.trim().split(RegExp(r'\s+')).first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF35613F), Color(0xFF1B382B), Color(0xFF123026)],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The member's own photo, or the branded initials chip.
              if (hasPhoto)
                UserAvatar(
                  imageUrl: avatarUrl,
                  name: name,
                  radius: 21,
                  borderColor: Colors.white24,
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CblrepColors.actionOrange,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    firstName.isEmpty ? 'M' : firstName.characters.take(1).toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: '${greeting.english}, $name',
                      child: Text(
                        '${greeting.local}, $firstName!',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'What would you like to barter today?',
                      maxLines: 2,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.map_outlined, size: 13, color: Colors.white60),
              const SizedBox(width: 5),
              const Text(
                'Barangay',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 8),
              // The current choice takes the remaining width and ellipsizes,
              // so a long barangay name can never push the row past the
              // banner's edge.
              Expanded(
                child: Text(
                  selectedBarangay.isEmpty ? 'All of Trinidad' : selectedBarangay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The quick-filter bar. Horizontally scrollable because there are
          // twenty barangays and a phone is narrower than the longest of
          // their names.
          SizedBox(
            height: 30,
            child: ListView.separated(
              key: const Key('home-barangay-chips'),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: trinidadBarangays.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final value = index == 0 ? '' : trinidadBarangays[index - 1];
                final selected = value == selectedBarangay;
                return _BarangayChip(
                  label: value.isEmpty ? 'All' : value,
                  selected: selected,
                  onTap: () => onBarangaySelected(value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One pill in the hero's barangay quick-filter bar.
class _BarangayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BarangayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CblrepColors.actionOrange : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? CblrepColors.actionOrange : Colors.white24,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
