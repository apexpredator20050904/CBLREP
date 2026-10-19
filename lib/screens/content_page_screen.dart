import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../core/api_service.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';

/// Full-screen viewer for one published municipal content page
/// (`GET /api/page/{slug}`) — the mobile counterpart of the admin console's
/// public `/page/:slug` web route.
///
/// The backend serves only published pages: an unknown slug and a draft slug
/// both answer 404, so both land in the error state below and unpublished
/// content is never rendered.
class ContentPageScreen extends StatefulWidget {
  final String slug;
  const ContentPageScreen({super.key, required this.slug});

  @override
  State<ContentPageScreen> createState() => _ContentPageScreenState();
}

class _ContentPageScreenState extends State<ContentPageScreen> {
  ContentPageModel? page;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    // No setState here: the initial state already shows the spinner.
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await ApiService.instance.fetchPage(widget.slug);
      if (!mounted) return;
      setState(() {
        page = ContentPageModel.fromJson(data);
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      loading = true;
      error = null;
    });
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(page?.title ?? 'Information')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorView(dark)
              : _pageView(dark),
    );
  }

  /// Loaded state — title, publication date and the authored HTML body.
  Widget _pageView(bool dark) {
    final published = page!.publishedAt;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page!.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
          if (published != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.event_available,
                  size: 13, color: dark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 4),
              Text(
                'Published ${DateFormat.yMMMMd().format(published.toLocal())}',
                style: TextStyle(
                    fontSize: 11, color: dark ? Colors.white54 : Colors.black45),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          HtmlWidget(page!.body),
        ],
      ),
    );
  }

  /// Failure state — mirrors the home feed's connection-error card so a wrong
  /// base URL or a draft slug never looks like an empty page: it names the
  /// host the app tried and offers a retry.
  Widget _errorView(bool dark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? CblrepColors.darkCardGreen : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CblrepColors.dangerRed.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.wifi_off, color: CblrepColors.dangerRed, size: 20),
              const SizedBox(width: 8),
              Text('Could not load page',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: dark ? Colors.white : Colors.black87)),
            ]),
            const SizedBox(height: 8),
            Text(error ?? 'Unknown error.',
                style: TextStyle(
                    fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.dns_outlined,
                  size: 12, color: dark ? Colors.white54 : Colors.black45),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Trying ${ApiService.instance.baseUrlHost}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white54 : Colors.black45)),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CblrepColors.actionOrange,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
