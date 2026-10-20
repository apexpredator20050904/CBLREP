import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';
import '../core/sign_in_gate.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';

/// The report sheet — how a member flags a malicious posting or account.
///
/// The flow is deliberately short: pick a reason, optionally add a line of
/// detail, send. Everything else (whether the target still exists, whether
/// the member already reported it, whether the report is accepted) is
/// decided by the server, and a failure is shown inside the sheet rather
/// than as a crash.
///
/// A report is a statement by a named member, so the sheet asks for a
/// session first: a signed-out member is offered the sign-in form instead of
/// sending a request that could only answer 401.
class ReportSheet extends StatefulWidget {
  /// 'listing' or 'user' (see `ReportTarget`).
  final String reportableType;

  /// The id of the thing being reported.
  final int reportableId;

  /// The thing's title or name — shown so the member can see what they are
  /// about to report.
  final String subjectName;

  const ReportSheet({
    super.key,
    required this.reportableType,
    required this.reportableId,
    required this.subjectName,
  });

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _details = TextEditingController();

  /// The chosen reason; null until the member picks one.
  String? _reason;

  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _isListing => widget.reportableType == ReportTarget.listing;

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Please choose a reason for your report.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await ApiService.instance.submitReport(
        reportableType: widget.reportableType,
        reportableId: widget.reportableId,
        reason: reason,
        // The description is optional, and stripped of markup before it is
        // sent so a moderator never sees raw HTML in a report.
        description: _details.text.trim().isEmpty
            ? null
            : InputSanitizer.text(_details.text, max: 500),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.statusCode == 401
            ? 'Your session has expired. Please sign in again.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black;
    final muted = dark ? Colors.white70 : Colors.black54;

    return Padding(
      // Lift the sheet above the keyboard so the details field stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? CblrepColors.deepForest : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: dark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CblrepColors.dangerRed.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 19,
                      color: CblrepColors.dangerRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isListing ? 'Report this posting' : 'Report this account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subjectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'What is wrong?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 8),
              // The reason list. A radio group rather than a dropdown, so the
              // member sees every option and what it means before choosing.
              for (final reason in ReportReason.all)
                _ReasonTile(
                  reason: reason,
                  selected: _reason == reason,
                  onTap: _sending
                      ? null
                      : () => setState(() {
                            _reason = reason;
                            _error = null;
                          }),
                ),
              const SizedBox(height: 14),
              Text(
                'Add details (optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _details,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                enabled: !_sending,
                decoration: const InputDecoration(
                  hintText: 'Tell us what happened, so a moderator can act faster.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 15, color: CblrepColors.dangerRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: CblrepColors.dangerRed),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: CblrepColors.dangerRed),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.shield_outlined, size: 18),
                  label: Text(_sending ? 'Sending…' : 'Submit report'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reports are reviewed by the community team. We never reveal who '
                'filed a report.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable reason, with the explanation the backend's vocabulary
/// maps to.
class _ReasonTile extends StatelessWidget {
  final String reason;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonTile({
    required this.reason,
    required this.selected,
    this.onTap,
  });

  /// The icon that matches each reason.
  static IconData iconFor(String reason) => switch (reason) {
        ReportReason.scam => Icons.money_off_csred_outlined,
        ReportReason.inappropriateContent => Icons.block_outlined,
        ReportReason.counterfeit => Icons.content_copy_outlined,
        ReportReason.harassment => Icons.person_off_outlined,
        _ => Icons.more_horiz,
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final muted = dark ? Colors.white60 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? CblrepColors.dangerRed.withValues(alpha: 0.10)
            : (dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF6F3EC)),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? CblrepColors.dangerRed.withValues(alpha: 0.55)
                    : (dark ? Colors.white12 : Colors.black12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  iconFor(reason),
                  size: 18,
                  color: selected ? CblrepColors.dangerRed : muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ReportReason.label(reason),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ReportReason.explanation(reason),
                        style: TextStyle(fontSize: 11, color: muted, height: 1.25),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: selected ? CblrepColors.dangerRed : muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the report sheet for a listing or a member.
///
/// Returns true when the report was accepted by the server. A signed-out
/// member is offered the sign-in form first — a report is meaningless
/// without a name attached to it.
Future<bool> showReportSheet(
  BuildContext context, {
  required String reportableType,
  required int reportableId,
  required String subjectName,
}) async {
  if (!await ensureSignedIn(
    context,
    'report this ${ReportTarget.label(reportableType)}',
  )) {
    return false;
  }
  if (!context.mounted) return false;

  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportSheet(
      reportableType: reportableType,
      reportableId: reportableId,
      subjectName: subjectName,
    ),
  );
  return sent == true;
}
