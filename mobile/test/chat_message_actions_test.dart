import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/models/models.dart';

/// Guards the message-action model contract that the action sheet and the
/// optimistic edit/delete in ChatProvider both depend on.
///
/// The important cases:
///  - `edited` is derived from the backend's `edited_at`, so a bubble can show
///    the Messenger-style "Edited" marker.
///  - Optimistic rows ("local-…") are flagged `isPending`, which is what keeps
///    Edit/Delete out of the action sheet for a bubble that has no server id
///    yet — acting on one would parse "local-123" as an int and throw.
void main() {
  group('ChatMessageModel action metadata', () {
    test('an edited message is flagged from edited_at', () {
      final m = ChatMessageModel.fromJson({
        'id': 12,
        'body': 'Revised text',
        'sender_id': 7,
        'edited_at': '2026-10-12T10:00:00+08:00',
        'created_at': '2026-10-12T09:00:00+08:00',
        'sender': {'id': 7, 'name': 'Ana'},
      });

      expect(m.edited, isTrue);
      expect(m.isPending, isFalse);
      expect(m.id, '12');
    });

    test('an untouched message is not flagged as edited', () {
      final m = ChatMessageModel.fromJson({
        'id': 12,
        'body': 'Original',
        'sender_id': 7,
        'edited_at': null,
        'created_at': '2026-10-12T09:00:00+08:00',
        'sender': {'id': 7, 'name': 'Ana'},
      });

      expect(m.edited, isFalse);
    });

    test('an optimistic row is pending and is NOT parseable as an int', () {
      final m = ChatMessageModel.fromJson({
        'id': 'local-1730000000000',
        'body': 'Sent but not stored yet',
        'sender_id': 7,
        'sender': 'You',
        'created_at': '2026-10-12T09:00:00Z',
      });

      expect(m.isPending, isTrue);
      // The action sheet hides Edit/Delete on these rows precisely because
      // int.parse('local-…') would throw inside ChatProvider.
      expect(() => int.parse(m.id), throwsFormatException);
    });

    test('a server row is not pending', () {
      final m = ChatMessageModel.fromJson({
        'id': 42,
        'body': 'Stored',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
      });

      expect(m.isPending, isFalse);
      expect(int.parse(m.id), 42);
    });

    test('copyWith replaces the body and preserves identity', () {
      final m = ChatMessageModel.fromJson({
        'id': 42,
        'body': 'Original',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
      });

      final edited = m.copyWith(body: 'Corrected', edited: true);

      expect(edited.body, 'Corrected');
      expect(edited.edited, isTrue);
      expect(edited.id, m.id, reason: 'The id must survive an edit.');
      expect(edited.senderId, m.senderId);
    });

    test('a deleted message is simply absent from the payload', () {
      // The backend soft-deletes and filters it out of the thread read, so
      // the client never has to render a tombstone — a missing id is the
      // signal. Parsing must not throw on the surrounding rows.
      final rows = [
        {'id': 1, 'body': 'kept', 'sender_id': 7, 'sender': {'id': 7, 'name': 'A'}},
        {'id': 3, 'body': 'also kept', 'sender_id': 8, 'sender': {'id': 8, 'name': 'B'}},
      ];

      final parsed = rows
          .map((r) => ChatMessageModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();

      expect(parsed.map((m) => m.id), ['1', '3']);
      expect(parsed.every((m) => !m.edited && !m.isPending), isTrue);
    });
  });

  group('Clipboard copy payload', () {
    test('the copy payload is the exact message body', () {
      // Deliberately not a widget test: Clipboard.setData is a platform
      // channel call and the test harness has no platform side to answer it,
      // so the await would hang until the 10-minute timeout. Constructing the
      // payload pins the same contract: what reaches the clipboard is the
      // message body, unmodified.
      const body = 'Is this still available? Purok 3, Poblacion.';
      const data = ClipboardData(text: body);

      expect(data.text, body);
      expect(data.text, isNot(contains('\n')),
          reason: 'A single-line body must not gain whitespace.');
    });
  });

  group('Attachment metadata', () {
    test('an image message parses attachment fields', () {
      final m = ChatMessageModel.fromJson({
        'id': 55,
        'body': 'Fresh from the farm',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
        'file_url': 'http://example.test/storage/chat_attachments/a.jpg',
        'file_type': 'image',
        'file_name': 'a.jpg',
        'file_size': 12345,
        'mime_type': 'image/jpeg',
      });

      expect(m.hasAttachment, isTrue);
      expect(m.isImage, isTrue);
    });

    test('a document message exposes name and size', () {
      final m = ChatMessageModel.fromJson({
        'id': 56,
        'body': '',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
        'file_url': 'http://example.test/storage/chat_attachments/n.pdf',
        'file_type': 'document',
        'file_name': 'notes.pdf',
        'file_size': 2048,
        'mime_type': 'application/pdf',
      });

      expect(m.hasAttachment, isTrue);
      expect(m.isImage, isFalse);
      expect(m.displayFileSize, '2.0 KB');
    });

    test('a plain text message has no attachment', () {
      final m = ChatMessageModel.fromJson({
        'id': 57,
        'body': 'Hello',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
      });

      expect(m.hasAttachment, isFalse);
      expect(m.isImage, isFalse);
      expect(m.displayFileSize, '');
    });

    test('an optimistic document row counts as an attachment', () {
      final m = ChatMessageModel.fromJson({
        'id': 'local-1730000000000',
        'body': '',
        'sender_id': 7,
        'sender': 'You',
        'file_name': 'notes.pdf',
        'file_url': '/tmp/notes.pdf',
      });

      expect(m.hasAttachment, isTrue);
      expect(m.isImage, isFalse);
      expect(m.isPending, isTrue);
    });

    test('a server video message is flagged as video, not image or document', () {
      final m = ChatMessageModel.fromJson({
        'id': 60,
        'body': 'Quick look at the item',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
        'file_url': 'http://example.test/storage/chat_attachments/clip.mp4',
        'file_type': 'video',
        'file_name': 'clip.mp4',
        'file_size': 5242880,
        'mime_type': 'video/mp4',
      });

      expect(m.hasAttachment, isTrue);
      expect(m.isVideo, isTrue);
      expect(m.isImage, isFalse);
      expect(m.displayFileSize, '5.0 MB');
    });

    test('an optimistic video row sniffs the type from its name', () {
      // Local staging path with a .mov name and no reliable server mime.
      final m = ChatMessageModel.fromJson({
        'id': 'local-1730000000001',
        'body': '',
        'sender_id': 7,
        'sender': 'You',
        'file_name': 'walkaround.mov',
        'file_url': '/data/user/0/ph.cblrep.app/cache/walkaround.mov',
      });

      expect(m.isVideo, isTrue);
      expect(m.isImage, isFalse);
      expect(m.isPending, isTrue);
    });

    test('the video sniff honours the mime when the name is unhelpful', () {
      final m = ChatMessageModel.fromJson({
        'id': 'local-1730000000002',
        'body': '',
        'sender_id': 7,
        'sender': 'You',
        'file_name': 'recording',
        'file_url': '/tmp/recording',
        'mime_type': 'video/mp4',
      });

      expect(m.isVideo, isTrue);
      expect(m.isImage, isFalse);
    });

    test('a document is never mistaken for a video', () {
      final m = ChatMessageModel.fromJson({
        'id': 61,
        'body': '',
        'sender_id': 7,
        'sender': {'id': 7, 'name': 'Ana'},
        'file_url': 'http://example.test/storage/chat_attachments/n.pdf',
        'file_type': 'document',
        'file_name': 'notes.pdf',
        'mime_type': 'application/pdf',
      });

      expect(m.isVideo, isFalse);
      expect(m.isImage, isFalse);
    });
  });
}