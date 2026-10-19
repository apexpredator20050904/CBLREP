import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';
import 'report_sheet.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// The member profile sheet — who a listing really belongs to.
///
/// A community marketplace is a trust business: a member wants to know the
/// name, the face and the verification status of the neighbour they are
/// about to trade with, before they open a chat. This sheet is that answer,
/// and it is also where a member reports an account whose behaviour is
/// unacceptable.
class MemberProfileSheet extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool verified;

  /// The member's barangay (and purok/sitio when known).
  final String? barangay;
  final String? purokSitio;

  /// The member's id — needed to file a report against them.
  final int? userId;

  /// False for the signed-in member's own profile: you cannot report
  /// yourself, so the action is not offered at all.
  final bool canReport;

  const MemberProfileSheet({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.barangay,
    this.purokSitio,
    this.userId,
    this.canReport = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final muted = dark ? Colors.white70 : Colors.black54;
    final place = [barangay, purokSitio]
        .where((p) => (p ?? '').trim().isNotEmpty)
        .map((p) => p!.trim())
        .join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: dark ? CblrepColors.deepForest : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: dark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              UserAvatar(
                imageUrl: avatarUrl,
                name: name,
                radius: 28,
                borderColor: verified ? CblrepColors.successGreen : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: CblrepColors.actionOrange),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (verified) ...[
                      const SizedBox(height: 7),
                      const VerifiedBadge(),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 6),
          if (canReport && (userId ?? 0) > 0)
            // Wrapped in a transparent Material: a ListTile paints its ink
            // on the nearest Material ancestor, and the sheet's own
            // background is a plain Container.
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.report_gmailerrorred_outlined,
                  color: CblrepColors.dangerRed,
                ),
                title: Text(
                  'Report this member',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                subtitle: Text(
                  'Tell the community team about harassment, scams or abuse.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showReportSheet(
                    context,
                    reportableType: ReportTarget.user,
                    reportableId: userId!,
                    subjectName: name,
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'This is your own account.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the member profile sheet.
Future<void> showMemberProfileSheet(
  BuildContext context, {
  required String name,
  String? avatarUrl,
  bool verified = false,
  String? barangay,
  String? purokSitio,
  int? userId,
  bool canReport = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MemberProfileSheet(
      name: name,
      avatarUrl: avatarUrl,
      verified: verified,
      barangay: barangay,
      purokSitio: purokSitio,
      userId: userId,
      canReport: canReport,
    ),
  );
}
