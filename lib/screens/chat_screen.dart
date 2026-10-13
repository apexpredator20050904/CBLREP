import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/cblrep_theme.dart';

/// Secure 1:1 chat thread with 3s live polling, optimistic sending,
/// Messenger-style message actions and photo/document attachments.
///
/// Long-pressing a bubble opens an action sheet:
///   Copy   — always available (message text, or the file link for attachments)
///   Edit   — your own text messages only
///   Delete — your own messages only
///
/// The (+) button beside the composer opens Gallery / Camera / Document
/// picking with a pre-send preview bar (X to remove). Images render inline
/// with rounded corners + tap-to-expand; documents render as file cards with
/// a tap-to-open action.
class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String title;

  /// Optional opening message pre-filled into the composer (not auto-sent) so
  /// a member can start a listing negotiation in one tap and then edit it.
  final String? initialDraft;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.initialDraft,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final composerFocus = FocusNode();
  final _picker = ImagePicker();

  bool sending = false;
  int _knownCount = -1;

  /// Non-null while a message is being edited; holds that message's server id.
  String? _editingId;

  /// Text the composer held when editing began, so cancelling restores it.
  String _draftBeforeEdit = '';

  /// File staged via the (+) picker, shown in the preview bar until sent.
  File? _stagedFile;

  /// True when [_stagedFile] is a photo (inline thumb) vs a document (file card).
  bool _stagedIsImage = false;

  /// Name shown in the preview bar for the staged file.
  String _stagedName = '';

  @override
  void initState() {
    super.initState();
    // Seed the composer with a tailored opener when one was supplied.
    if (widget.initialDraft != null && widget.initialDraft!.trim().isNotEmpty) {
      input.text = widget.initialDraft!.trim();
      input.selection = TextSelection.fromPosition(TextPosition(offset: input.text.length));
    }
    Future.microtask(() {
      if (!mounted) return;
      context.read<ChatProvider>().bindSelf(
            context.read<AuthProvider>().user?.id ?? 0,
          );
      context.read<ChatProvider>().open(widget.conversationId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final count = context.watch<ChatProvider>().messages.length;
    if (count != _knownCount && count > 0) {
      _knownCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  bool get isEditing => _editingId != null;

  void _scrollToBottom() {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    // ChatProvider is app-scoped, so its 3s poll timer outlives this screen
    // unless it is stopped here — that kept hammering
    // /conversations/{id}/messages for the rest of the app's life and drained
    // the battery on a backgrounded app.
    //
    // close() clears the timer *and* the retained message list, so returning
    // to the inbox does not hold another member's conversation in memory.
    if (mounted) context.read<ChatProvider>().close(notify: false);
    input.dispose();
    scroll.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  // ── Message actions ─────────────────────────────────────────────────────

  /// Bottom sheet matching modern chat apps: Copy always, Edit (text-only) and
  /// Delete only for the member's own messages.
  Future<void> _openActions(ChatMessageModel message, {required bool mine}) async {
    if (!mounted) return;
    // Text captions are editable; file bodies are immutable once stored —
    // editing an attachment would orphan the file, so the option is hidden.
    final canEdit = mine && !message.isPending && !message.hasAttachment;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? CblrepColors.dialogGreen
          : Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview of what the actions apply to, so a long-press on the
            // wrong bubble is obvious before anything happens.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                message.body.isNotEmpty
                    ? message.body
                    : (message.fileName ?? 'Attachment'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            _sheetTile(Icons.copy_rounded, 'Copy'),
            // Own messages only — the backend enforces this too (403), the
            // menu just avoids offering an action that would fail.
            if (canEdit) _sheetTile(Icons.edit_outlined, 'Edit'),
            if (mine && !message.isPending)
              _sheetTile(Icons.delete_outline, 'Delete', danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'copy':
        await _copy(message);
      case 'edit':
        _beginEdit(message);
      case 'delete':
        await _confirmDelete(message);
    }
  }

  Widget _sheetTile(IconData icon, String label, {bool danger = false}) {
    final color = danger ? CblrepColors.dangerRed : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () => Navigator.pop(context, label),
    );
  }

  Future<void> _copy(ChatMessageModel message) async {
    // For attachments with no caption, copy the shareable file link so the
    // member still gets something useful on the clipboard.
    final text = message.body.isNotEmpty
        ? message.body
        : (message.resolvedFileUrl ?? message.fileUrl ?? '');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    Feedback.info(context, 'Copied to clipboard');
  }

  /// Loads the message into the composer and switches to editing mode.
  /// Attachments are immutable — only the text caption is editable, so the
  /// option is hidden for file messages in the action sheet.
  void _beginEdit(ChatMessageModel message) {
    _draftBeforeEdit = input.text;
    // Editing never carries an attachment — drop any staged file first.
    _stagedFile = null;
    _stagedIsImage = false;
    _stagedName = '';
    setState(() {
      _editingId = message.id;
      input.text = message.body;
      input.selection = TextSelection.fromPosition(TextPosition(offset: input.text.length));
    });
    composerFocus.requestFocus();
    Feedback.info(context, 'Editing message');
  }

  void _cancelEdit() {
    setState(() {
      // Restore whatever the member had typed before editing began.
      input.text = _draftBeforeEdit;
      _editingId = null;
      _draftBeforeEdit = '';
    });
    composerFocus.requestFocus();
  }

  Future<void> _confirmDelete(ChatMessageModel message) async {
    if (!mounted) return;
    final confirmed = await Feedback.confirm(
      context,
      title: 'Delete this message?',
      message: 'It will disappear from the conversation for both of you. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await context.read<ChatProvider>().deleteMessage(message.id);
      if (mounted) Feedback.success(context, 'Message deleted');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    }
  }

  // ── Attachments ─────────────────────────────────────────────────────────

  /// (+) option picker: Gallery Photo / Camera Capture / Document File.
  Future<void> _pickAttachment() async {
    if (!mounted || sending) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? CblrepColors.dialogGreen
          : Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Share to this chat',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery Photo',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('JPG, PNG or WebP up to 10 MB'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera Capture',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Take a photo to send'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document File',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('PDF, DOCX or TXT up to 10 MB'),
              onTap: () => Navigator.pop(sheetContext, 'document'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == 'document') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
          withData: false,
        );
        final path = result?.files.single.path;
        if (path == null || !mounted) return;
        final file = File(path);
        if (await file.length() > 10 * 1024 * 1024) {
          if (mounted) Feedback.error(context, 'File must be 10 MB or less.');
          return;
        }
        setState(() {
          _stagedFile = file;
          _stagedIsImage = false;
          _stagedName = result?.files.single.name ?? path.split('/').last;
        });
        composerFocus.requestFocus();
      } else {
        final source =
            choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
        final picked =
            await _picker.pickImage(source: source, imageQuality: 85);
        if (picked == null || !mounted) return;
        final file = File(picked.path);
        if (await file.length() > 10 * 1024 * 1024) {
          if (mounted) Feedback.error(context, 'Photo must be 10 MB or less.');
          return;
        }
        setState(() {
          _stagedFile = file;
          _stagedIsImage = true;
          _stagedName = picked.name.isNotEmpty
              ? picked.name
              : picked.path.split('/').last;
        });
        composerFocus.requestFocus();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        Feedback.error(context, 'Could not open picker: ${e.message ?? e.code}');
      }
    } catch (_) {
      if (mounted) Feedback.error(context, 'Could not pick that file.');
    }
  }

  void _removeStaged() {
    setState(() {
      _stagedFile = null;
      _stagedIsImage = false;
      _stagedName = '';
    });
  }

  bool get _hasStaged => _stagedFile != null;

  // ── Sending ─────────────────────────────────────────────────────────────

  Future<void> send() async {
    final text = input.text.trim();
    if ((text.isEmpty && !_hasStaged) || sending) return;
    // Editing mode never carries an attachment — staged files are cleared when
    // editing begins (see _beginEdit), so this branch is text-only by design.
    if (isEditing) {
      await _submitEdit(text);
      return;
    }
    setState(() => sending = true);
    try {
      final chat = context.read<ChatProvider>();
      if (_hasStaged) {
        await chat.sendAttachment(_stagedFile!, caption: text);
        if (!mounted) return;
        input.clear();
        _removeStaged();
      } else {
        await chat.send(text);
        if (!mounted) return;
        input.clear();
      }
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _submitEdit(String text) async {
    setState(() => sending = true);
    try {
      await context.read<ChatProvider>().editMessage(_editingId!, text);
      if (mounted) Feedback.success(context, 'Message updated');
      if (!mounted) return;
      input.clear();
      setState(() {
        _editingId = null;
        _draftBeforeEdit = '';
      });
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final me = context.watch<AuthProvider>().user?.id ?? 0;
    final msgs = chat.messages.map((e) => ChatMessageModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final progress = chat.uploadProgress;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 15))),
      body: Column(children: [
        Expanded(
          child: chat.loading
              ? const Center(child: CircularProgressIndicator())
              : msgs.isEmpty
                  ? const Center(child: Text('Say hello to start the exchange chat.'))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final mine = m.senderId == me;
                        return _Bubble(
                          message: m,
                          mine: mine,
                          highlighted: m.id == _editingId,
                          dark: dark,
                          onLongPress: () => _openActions(m, mine: mine),
                        );
                      },
                    ),
        ),
        // Determinate upload progress while a photo/document streams, so
        // slow networks show movement rather than a dead composer.
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              ),
              const SizedBox(width: 8),
              Text('${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11)),
            ]),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Editing-mode banner above the composer.
                if (isEditing) _EditingBanner(onCancel: _cancelEdit),
                // Pre-send attachment preview with an X remove button.
                if (_hasStaged)
                  _AttachmentPreview(
                    file: _stagedFile!,
                    isImage: _stagedIsImage,
                    name: _stagedName,
                    onRemove: sending ? null : _removeStaged,
                  ),
                Row(children: [
                  // (+) trigger beside the text field.
                  IconButton(
                    onPressed: (sending || isEditing) ? null : _pickAttachment,
                    tooltip: 'Attach photo or document',
                    icon: const Icon(Icons.add_circle_outline, size: 26),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      focusNode: composerFocus,
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) => send(),
                      decoration: InputDecoration(
                        hintText: isEditing
                            ? 'Edit your message…'
                            : (_hasStaged
                                ? 'Add a caption…'
                                : 'Type a secure message…'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: sending ? null : send,
                    style: isEditing
                        ? FilledButton.styleFrom(backgroundColor: CblrepColors.compPaid)
                        : null,
                    child: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(isEditing ? Icons.check : Icons.send, size: 18),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Pre-send attachment preview bar with an "X" remove button.
class _AttachmentPreview extends StatelessWidget {
  final File file;
  final bool isImage;
  final String name;
  final VoidCallback? onRemove;

  const _AttachmentPreview({
    required this.file,
    required this.isImage,
    required this.name,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isImage
              ? Image.file(file, width: 52, height: 52, fit: BoxFit.cover)
              : Container(
                  width: 52,
                  height: 52,
                  color: CblrepColors.compPaid.withValues(alpha: 0.15),
                  child: const Icon(Icons.description_outlined,
                      color: CblrepColors.compPaid),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              Text(
                isImage ? 'Photo ready to send' : 'Document ready to send',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRemove,
          tooltip: 'Remove attachment',
          icon: const Icon(Icons.close, size: 18),
        ),
      ]),
    );
  }
}

/// A single message bubble.
///
/// Wrapped in [GestureDetector] for the long-press action sheet. The text
/// uses [Flexible] so a long message wraps inside the bubble's maxWidth
/// instead of overflowing.
class _Bubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool mine;
  final bool highlighted;
  final bool dark;
  final VoidCallback onLongPress;

  const _Bubble({
    required this.message,
    required this.mine,
    required this.highlighted,
    required this.dark,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final muted = dark ? Colors.white70 : Colors.black54;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        // Right-click / trackpad long-press on desktop and web builds too.
        onSecondaryTap: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: highlighted
                ? (mine ? CblrepColors.compPaid : CblrepColors.actionOrange)
                : mine
                    ? CblrepColors.actionOrange
                    : (dark ? CblrepColors.darkCardGreen : Colors.white),
            borderRadius: BorderRadius.circular(14),
            // A visible ring marks which message the composer is editing.
            border: highlighted
                ? Border.all(color: CblrepColors.goldHighlight, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine)
                Text(message.sender, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: muted)),
              if (message.hasAttachment && message.isImage)
                _ImageAttachment(message: message, mine: mine),
              if (message.hasAttachment && !message.isImage)
                _DocumentAttachment(message: message, mine: mine),
              if (message.body.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                      top: message.hasAttachment ? 6 : 0),
                  child: Text(
                    message.body,
                    style: TextStyle(
                        fontSize: 13,
                        color: mine ? Colors.white : Colors.black87),
                  ),
                ),
              if (message.edited)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Edited',
                    style: TextStyle(
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                      color: mine ? Colors.white70 : muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Image attachment: rounded thumbnail with tap-to-expand preview.
class _ImageAttachment extends StatelessWidget {
  final ChatMessageModel message;
  final bool mine;

  const _ImageAttachment({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final url = message.resolvedFileUrl;
    final raw = message.fileUrl ?? '';
    final isLocal = raw.startsWith('/') && message.fileType == 'image';
    Widget image;
    if (isLocal) {
      image = Image.file(
        File(raw),
        width: 200,
        height: 150,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    } else if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        width: 200,
        height: 150,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                width: 200,
                height: 150,
                alignment: Alignment.center,
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                ),
              ),
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    } else {
      image = _imageFallback();
    }
    return GestureDetector(
      onTap: (url == null || isLocal)
          ? null
          : () => _openImagePreview(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: image,
      ),
    );
  }

  Widget _imageFallback() => Container(
        width: 200,
        height: 120,
        alignment: Alignment.center,
        color: mine ? Colors.white24 : Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined),
      );

  static void _openImagePreview(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Could not load image.',
                          style: TextStyle(color: Colors.white)),
                    )),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Document attachment: file card with icon, name, size + tap-to-open.
class _DocumentAttachment extends StatelessWidget {
  final ChatMessageModel message;
  final bool mine;

  const _DocumentAttachment({required this.message, required this.mine});

  IconData get _icon {
    final name = (message.fileName ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.article_outlined;
    }
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _openDocument(context),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: 0.18)
              : (dark ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(_icon,
              size: 30, color: mine ? Colors.white : CblrepColors.compPaid),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.fileName ?? 'Document',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: mine ? Colors.white : Colors.black87,
                  ),
                ),
                if (message.displayFileSize.isNotEmpty)
                  Text(
                    message.displayFileSize,
                    style: TextStyle(
                      fontSize: 10,
                      color: mine ? Colors.white70 : Colors.black54,
                    ),
                  ),
                Text(
                  'Tap to open',
                  style: TextStyle(
                    fontSize: 10,
                    color: mine ? Colors.white70 : CblrepColors.compPaid,
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _openDocument(BuildContext context) async {
    final url = message.resolvedFileUrl;
    // A local staging path is not shareable yet — the upload is still in
    // flight or the poll has not reconciled the server copy.
    if (url == null || url.isEmpty || url.startsWith('/')) {
      Feedback.info(context, 'File is still uploading…');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      Feedback.error(context, 'File link is invalid.');
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          Feedback.info(context, 'Link copied — open it in a browser');
        }
      }
    } catch (_) {
      if (context.mounted) Feedback.error(context, 'Could not open file.');
    }
  }
}

/// "Editing message" strip with a cancel action, shown above the composer.
class _EditingBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _EditingBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: CblrepColors.compPaid.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CblrepColors.compPaid.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          const Icon(Icons.edit_outlined, size: 15, color: CblrepColors.compPaid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing message',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ]),
      ),
    );
  }
}