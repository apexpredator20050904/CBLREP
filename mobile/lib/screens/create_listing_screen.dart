import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Feedback;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../core/listing_draft_store.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/location_picker.dart';
import '../widgets/post_limit_dialog.dart';
import 'verification_screen.dart';

/// Post Listing — offers & needs with category, condition, barangay and
/// camera/gallery photo upload.
///
/// An OFFER and a NEED are the same listing seen from opposite ends, so the
/// form changes with the direction:
///
///   OFFER ("I have it")  → you share something. The price is what you ask,
///                          the condition is the item's state, the photos are
///                          of the item, and Free is a legal choice (a gift).
///   NEED  ("I want it")  → you are looking for something. The price is your
///                          budget ceiling, the condition is what you can
///                          accept, the photos are references of the thing you
///                          want, Free is NOT a legal choice (a need is
///                          answered with a trade or a payment — asking for
///                          something free is what posting an offer is for),
///                          and you can say how much you need.
class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});
  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController(), purok = TextEditingController();
  final price = TextEditingController();
  // The return side of a barter — what the member hopes to receive. Ignored
  // for free/paid listings, which have no return side.
  final wanted = TextEditingController();
  // How much is needed. Only meaningful on a NEED ("5 kg of rice").
  final quantity = TextEditingController();
  String category = 'Tools';
  String type = 'offer', condition = 'Good', barangay = trinidadBarangays.first;
  // Flexible compensation: free | barter | paid.
  String compensation = 'barter';
  // Paid-only: whether the seller welcomes a counter-offer.
  bool priceNegotiable = false;
  // Exact pin, when the poster dropped one on the map. Null keeps the backend's
  // barangay-anchor fallback.
  LatLng? pinLocation;
  // Ordered photo gallery, capped at the backend's six. The first is the cover.
  final List<File> images = [];
  static const maxPhotos = 6;
  // A NEED has no item to photograph, so only a couple of reference pictures
  // make sense ("the chair I am looking for").
  static const maxReferencePhotos = 2;
  bool saving = false;

  // Local draft bookkeeping. `_posted`/`_discarded` stop the dispose-time save
  // from resurrecting a draft after the member has finished with the form.
  Timer? _draftTimer;
  bool _posted = false;
  bool _discarded = false;
  bool _draftRestored = false;
  // The draft is scoped to the member who is posting. Captured once in
  // initState so dispose() can persist without touching the (deactivated)
  // BuildContext.
  int _draftOwner = 0;
  // True once the form holds anything worth keeping, so the AppBar offers a
  // "discard draft" action only when there is a draft to discard.
  bool _hasContent = false;

  static const categories = ['Tools', 'Food', 'Clothing', 'Furniture', 'Electronics', 'Books', 'Skills', 'Services', 'Plants', 'Other'];

  /// The condition vocabulary depends on the direction. On an offer it states
  /// the item's state; on a need the poster cannot rate something they do not
  /// own, so it states what they are willing to accept.
  static const _offerConditions = ['New', 'Good', 'Needs repair'];
  static const _needConditions = ['Any', 'Like new', 'Working'];

  static const _compensationCopy = {
    'free': 'Free sharing — you are giving this away at no cost.',
    'barter': 'Barter — a neighbour offers an item or skill in return.',
    'paid': 'Paid — set a price and neighbours can inquire to buy.',
  };

  /// The need variants of the same three explanations.
  static const _needCompensationCopy = {
    'barter': 'Barter — you can trade an item or skill for what you need.',
    'paid': 'Paid — set a budget and neighbours can offer to supply it.',
  };

  /// True when the form is composing a NEED rather than an OFFER.
  bool get _isNeed => type == 'request';

  /// The condition options that apply to the current direction.
  List<String> get _conditions => _isNeed ? _needConditions : _offerConditions;

  /// The photo cap for the current direction: a need has no item to shoot, so
  /// only a couple of reference pictures make sense.
  int get _photoCap => _isNeed ? maxReferencePhotos : maxPhotos;

  /// Switch the direction, keeping the form consistent with it.
  ///
  /// A NEED cannot be free (the backend rejects that cell of the matrix), so
  /// flipping to "Need" while "Free" is selected moves the member to Barter
  /// rather than leaving a form that would 422 on submit.
  void _setType(String next) {
    setState(() {
      type = next;
      if (_isNeed) {
        if (compensation == 'free') compensation = 'barter';
        if (!_needConditions.contains(condition)) condition = 'Any';
        priceNegotiable = false;
      } else if (!_offerConditions.contains(condition)) {
        condition = 'Good';
      }
    });
    _onFieldChanged();
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();

    // Prefill from the member's saved location so the common case (posting
    // from where they live) is one less thing to retype. Only values the API
    // would accept are used, so a legacy/odd profile cannot seed the form with
    // something it would then reject on submit.
    final savedBarangay = auth.user?.barangay;
    if (savedBarangay != null && trinidadBarangays.contains(savedBarangay)) {
      barangay = savedBarangay;
    }
    final savedPurok = auth.user?.purokSitio;
    if (savedPurok != null && savedPurok.isNotEmpty && isValidPurokSitio(savedPurok)) {
      purok.text = savedPurok;
    }

    // The active-listing cap lives server-side. Fetch the envelope only for an
    // unverified member who does not already have it (the Profile screen loads
    // it too), so the notice below can name their real usage; a verified member
    // skips the round trip entirely.
    final listings = context.read<ListingsProvider>();
    if (auth.user?.verified == false && listings.myLimits.isEmpty) {
      listings.loadMine(showSpinner: false);
    }

    // Bring back an unfinished draft, if the member left one behind.
    _draftOwner = auth.user?.id ?? 0;
    _restoreDraft();

    // Autosave on any change to the text fields (debounced in _scheduleDraftSave),
    // and flip the "has content" flag so the discard action appears.
    for (final controller in [title, description, purok, price, wanted]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // A form abandoned without posting (back button, app switch) keeps its
    // draft — unless the member posted or explicitly discarded it.
    if (!_posted && !_discarded) {
      _persistDraft();
    }
    title.dispose(); description.dispose(); purok.dispose(); price.dispose(); wanted.dispose(); super.dispose();
  }

  /// Reload a saved draft into the form. Only values the API would accept are
  /// applied, and only photo files that still exist on disk — a draft must never
  /// seed the form with something it would then reject.
  Future<void> _restoreDraft() async {
    final draft = await ListingDraftStore.load(_draftOwner);
    if (draft == null || !mounted) return;

    String asString(dynamic v) => v is String ? v : '';
    setState(() {
      title.text = asString(draft['title']);
      description.text = asString(draft['description']);
      wanted.text = asString(draft['wanted']);
      price.text = asString(draft['price']);
      final p = asString(draft['purok']);
      if (p.isEmpty || isValidPurokSitio(p)) purok.text = p;
      final b = asString(draft['barangay']);
      if (trinidadBarangays.contains(b)) barangay = b;
      final c = asString(draft['category']);
      if (categories.contains(c)) category = c;
      final t = asString(draft['type']);
      if (t == 'offer' || t == 'request') type = t;
      final cond = asString(draft['condition']);
      if (_conditions.contains(cond)) condition = cond;
      final comp = asString(draft['compensation']);
      if (['free', 'barter', 'paid'].contains(comp)) compensation = comp;
      // A need cannot be free — an old draft may predate that rule.
      if (type == 'request' && compensation == 'free') compensation = 'barter';
      quantity.text = asString(draft['quantity']);
      priceNegotiable = draft['priceNegotiable'] == true;
      final lat = draft['latitude'];
      final lng = draft['longitude'];
      if (lat is num && lng is num) {
        pinLocation = LatLng(lat.toDouble(), lng.toDouble());
      }
      images
        ..clear()
        ..addAll((draft['images'] as List?)
                ?.whereType<String>()
                .map((path) => File(path))
                .where((file) => file.existsSync())
                .take(maxPhotos) ??
            const []);
      _draftRestored = title.text.isNotEmpty ||
          description.text.isNotEmpty ||
          purok.text.isNotEmpty ||
          images.isNotEmpty;
      _hasContent = _draftRestored;
    });
  }

  /// Debounced autosave, so a burst of keystrokes writes once.
  void _scheduleDraftSave() {
    if (_posted || _discarded) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), _persistDraft);
  }

  /// setState + autosave, for the non-text controls (segments, dropdowns,
  /// switches, pin, photos) that are not backed by a TextEditingController.
  void _touch(VoidCallback change) {
    setState(change);
    _onFieldChanged();
  }

  /// Single entry point for "the form changed": autosaves (debounced) and keeps
  /// the AppBar's discard action in step with whether anything is filled in.
  void _onFieldChanged() {
    final hasContent = title.text.trim().isNotEmpty ||
        description.text.trim().isNotEmpty ||
        purok.text.trim().isNotEmpty ||
        price.text.trim().isNotEmpty ||
        wanted.text.trim().isNotEmpty ||
        images.isNotEmpty ||
        pinLocation != null;
    if (hasContent != _hasContent && mounted) {
      setState(() => _hasContent = hasContent);
    }
    _scheduleDraftSave();
  }

  /// Snapshot the form. An untouched form clears any stale draft rather than
  /// saving an empty one.
  ///
  /// Deliberately does not check `mounted`: it touches no BuildContext and no
  /// setState, and dispose() calls it to save the form on the way out.
  Future<void> _persistDraft() async {
    if (_posted || _discarded) return;
    bool blank(String v) => v.trim().isEmpty;
    final empty = blank(title.text) &&
        blank(description.text) &&
        blank(purok.text) &&
        blank(price.text) &&
        blank(wanted.text) &&
        blank(quantity.text) &&
        images.isEmpty &&
        pinLocation == null;
    if (empty) {
      await ListingDraftStore.clear(_draftOwner);
      return;
    }
    await ListingDraftStore.save(_draftOwner, {
      'title': title.text,
      'description': description.text,
      'wanted': wanted.text,
      'price': price.text,
      'quantity': quantity.text,
      'purok': purok.text,
      'barangay': barangay,
      'category': category,
      'type': type,
      'condition': condition,
      'compensation': compensation,
      'priceNegotiable': priceNegotiable,
      'latitude': pinLocation?.latitude,
      'longitude': pinLocation?.longitude,
      'images': images.map((f) => f.path).toList(),
    });
  }

  /// Throw the draft away and reset the form to its prefilled defaults.
  Future<void> _discardDraft() async {
    _discarded = true;
    _draftTimer?.cancel();
    await ListingDraftStore.clear(_draftOwner);
    if (!mounted) return;
    setState(() {
      title.clear();
      description.clear();
      wanted.clear();
      price.clear();
      quantity.clear();
      images.clear();
      pinLocation = null;
      priceNegotiable = false;
      compensation = 'barter';
      type = 'offer';
      condition = 'Good';
      category = 'Tools';
      _draftRestored = false;
      _hasContent = false;
    });
    Feedback.info(context, 'Draft discarded.');
  }

  Future<void> pickImage(ImageSource source) async {
    if (images.length >= _photoCap) {
      Feedback.info(context, _isNeed
          ? 'You can add up to $_photoCap reference photos.'
          : 'You can add up to $maxPhotos photos.');
      return;
    }
    if (source == ImageSource.camera) {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (picked != null && mounted && images.length < _photoCap) {
        _touch(() => images.add(File(picked.path)));
      }
      return;
    }
    // Gallery: multi-select, trimmed so the total never exceeds the cap.
    final remaining = _photoCap - images.length;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600, limit: remaining);
    if (picked.isEmpty || !mounted) return;
    _touch(() {
      for (final file in picked.take(remaining)) {
        images.add(File(file.path));
      }
    });
  }

  void _photoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () { Navigator.pop(c); pickImage(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), subtitle: Text(_isNeed ? 'Up to $_photoCap reference photos' : 'Up to $maxPhotos photos'), onTap: () { Navigator.pop(c); pickImage(ImageSource.gallery); }),
          if (images.isNotEmpty) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove all photos'), onTap: () { Navigator.pop(c); _touch(() => images.clear()); }),
        ]),
      ),
    );
  }

  /// Open the map to drop an exact pin. It opens near the chosen barangay's
  /// anchor (or the existing pin, when editing it), so the member is already in
  /// the right neighbourhood when the map appears.
  Future<void> _pickLocation() async {
    final anchor = coordinatesForBarangay(barangay);
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initial: pinLocation ?? LatLng(anchor.$1, anchor.$2),
        ),
      ),
    );
    if (picked != null && mounted) _touch(() => pinLocation = picked);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      await context.read<ListingsProvider>().create(
            title: title.text.trim(),
            type: type,
            description: description.text.trim(),
            category: category,
            condition: condition,
            location: '$barangay, ${purok.text.trim()}',
            barangay: barangay,
            purokSitio: purok.text.trim(),
            // Only a paid listing carries a price; free/barter send none.
            compensationType: compensation,
            price: compensation == 'paid' ? double.tryParse(price.text.trim()) : null,
            // A need's price is a budget ceiling, so it is never negotiable.
            priceNegotiable: compensation == 'paid' && !_isNeed && priceNegotiable,
            wantedItem: compensation == 'barter' ? wanted.text.trim() : null,
            // NEED-only: how much is needed.
            quantity: _isNeed ? quantity.text.trim() : null,
            // The exact pin, when the poster dropped one. Null keeps the
            // backend's barangay-anchor fallback so the listing still appears
            // on the community map.
            latitude: pinLocation?.latitude,
            longitude: pinLocation?.longitude,
            images: images,
          );
      if (!mounted) return;
      // The draft has become a real listing; drop the local copy.
      _posted = true;
      await ListingDraftStore.clear(_draftOwner);
      if (!mounted) return;
      Feedback.success(context, 'Resource posted successfully.');
      Navigator.pop(context, true);
    } on ApiException catch (exception) {
      if (!mounted) return;
      // Progressive-trust cap: the member has used every active-listing slot
      // an unverified account gets (the only 403 store() returns). Offer the
      // way forward instead of a bare retry that would fail again.
      if (exception.statusCode == 403) {
        await showUnverifiedPostLimitDialog(context, exception.message);
      } else {
        Feedback.error(context, exception.message, onRetry: save);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final listings = context.watch<ListingsProvider>();
    final postLimit = listings.activePostLimit;
    final showLimitNotice = auth.user?.verified == false && postLimit != null;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(
        title: const Text('Post a resource', style: TextStyle(fontSize: 16)),
        actions: [
          if (_hasContent)
            IconButton(
              tooltip: 'Discard draft',
              onPressed: _discardDraft,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_draftRestored) ...[
            _DraftRestoredNotice(onDiscard: _discardDraft),
            const SizedBox(height: 12),
          ],
          if (showLimitNotice) ...[
            _UnverifiedLimitNotice(
              used: listings.activePostCount,
              limit: postLimit,
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'offer', label: Text('Offer'), icon: Icon(Icons.volunteer_activism)), ButtonSegment(value: 'request', label: Text('Need'), icon: Icon(Icons.help_outline))],
            selected: {type},
            onSelectionChanged: (value) => _setType(value.first),
          ),
          const SizedBox(height: 8),
          // Say which direction the form is in, so the labels below are never
          // ambiguous — the two directions read the same fields differently.
          Text(
            _isNeed
                ? 'Posting a NEED — you are looking for this.'
                : 'Posting an OFFER — you have this to share.',
            style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: title, decoration: InputDecoration(labelText: 'Title', helperText: _isNeed ? 'Name the thing you want, not "looking for".' : null), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: description, maxLines: 4, decoration: InputDecoration(labelText: _isNeed ? 'Why do you need it, and by when?' : 'Description (what, why, pickup notes)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            // isExpanded bounds the button to the field width so a long category
            // name cannot overflow the form on a narrow phone.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (value) => _touch(() => category = value ?? category),
          ),
          const SizedBox(height: 12),
          // How the member wants to share: Free, Barter or Paid. This is the
          // flexible-compensation choice the whole portal is built around.
          //
          // A NEED has no "Free" option: asking for something for nothing is
          // not a want ad — posting it as a Free OFFER is how you give
          // something away. A need is answered with a trade or a payment.
          SegmentedButton<String>(
            segments: _isNeed
                ? const [
                    ButtonSegment(value: 'barter', label: Text('Barter'), icon: Icon(Icons.swap_horiz)),
                    ButtonSegment(value: 'paid', label: Text('Paid'), icon: Icon(Icons.sell_outlined)),
                  ]
                : const [
                    ButtonSegment(value: 'free', label: Text('Free'), icon: Icon(Icons.card_giftcard)),
                    ButtonSegment(value: 'barter', label: Text('Barter'), icon: Icon(Icons.swap_horiz)),
                    ButtonSegment(value: 'paid', label: Text('Paid'), icon: Icon(Icons.sell_outlined)),
                  ],
            selected: {compensation},
            onSelectionChanged: (value) => _touch(() => compensation = value.first),
          ),
          const SizedBox(height: 8),
          _CompensationNotice(
            type: compensation,
            copy: (_isNeed ? _needCompensationCopy : _compensationCopy)[compensation]!,
          ),
          // NEED-only: how much is needed. A want ad that says "rice" but not
          // "5 kg" leaves the neighbour guessing — and bulk needs are the
          // normal case in a barangay.
          if (_isNeed) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: quantity,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'How much do you need? (optional)',
                helperText: 'e.g. 5 kg, 2 sacks, one bundle',
              ),
            ),
          ],
          // Barter only: the return side. On an offer it is what the owner
          // hopes to receive; on a need it is what the poster can trade —
          // naming it up front is what lets a neighbour offer the right
          // thing instead of guessing.
          if (compensation == 'barter') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: wanted,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: _isNeed
                    ? 'In return, I can offer (optional)'
                    : 'In return, I would like (optional)',
                helperText: _isNeed
                    ? 'e.g. 2 hours of childcare, or a bag of rice'
                    : 'e.g. 5 kg of rice, or an hour of plumbing help',
              ),
            ),
          ],
          if (compensation == 'paid') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _isNeed ? 'I can pay up to (₱)' : 'Price (₱)',
                prefixText: '₱ ',
                helperText: _isNeed
                    ? 'Your budget ceiling — what you are willing to pay for this.'
                    : null,
              ),
              validator: (v) {
                if (compensation != 'paid') return null;
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return 'Enter a price';
                if (parsed <= 0) return 'Price must be greater than zero';
                return null;
              },
            ),
            // "Negotiable" belongs to a seller who may take less than the
            // asking price. A budget ceiling is the poster's own limit, so it
            // is not negotiable against itself.
            if (!_isNeed)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: priceNegotiable,
                onChanged: (value) => _touch(() => priceNegotiable = value),
                title: const Text('Price is negotiable', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Let buyers send a counter-offer in chat.', style: TextStyle(fontSize: 11)),
              ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: _conditions.contains(condition) ? condition : _conditions.first,
            decoration: InputDecoration(labelText: _isNeed ? 'Condition I can accept' : 'Condition'),
            items: _conditions.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => _touch(() => condition = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            initialValue: barangay,
            decoration: const InputDecoration(labelText: 'Trinidad barangay'),
            items: trinidadBarangays.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => _touch(() => barangay = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: purok,
            decoration: const InputDecoration(labelText: 'Purok / Sitio'),
            validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter the purok or sitio';
                if (!isValidPurokSitio(t)) return 'Use a format like "Purok 3" or "Sitio Name"';
                return null;
              },
          ),
          const SizedBox(height: 12),
          // Exact spot (optional). The barangay + purok already place the
          // listing on the community map; a pin narrows it to the gate or the
          // store, which is what a neighbour actually needs to collect.
          _LocationPinCard(
            location: pinLocation,
            onPick: _pickLocation,
            onClear: () => _touch(() => pinLocation = null),
          ),
          const SizedBox(height: 12),
          // Photo gallery: up to six unordered thumbnails plus an add tile. The
          // first photo is the cover, so the row is ordered and removable. A
          // NEED has no item to photograph, so it carries reference pictures
          // of the thing wanted instead.
          _PhotoGallery(
            images: images,
            maxPhotos: _photoCap,
            label: _isNeed ? 'Reference photos' : 'Photos',
            dark: dark,
            onAdd: _photoSheet,
            onRemove: (index) => _touch(() => images.removeAt(index)),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Posting…' : 'Post resource')),
        ]),
      ),
    );
  }
}

/// Read-only banner describing the selected sharing mode. Colour-coded so the
/// three compensation types read as clearly on the form as they do on a card.
class _CompensationNotice extends StatelessWidget {
  final String type;
  final String copy;
  const _CompensationNotice({required this.type, required this.copy});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color accent, IconData icon) = switch (type) {
      'free' => (CblrepColors.compFree, Icons.card_giftcard),
      'paid' => (CblrepColors.compPaid, Icons.sell_outlined),
      _ => (CblrepColors.compBarter, Icons.swap_horiz),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : const Color(0xFFEFE9DA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(copy, style: const TextStyle(fontSize: 11, height: 1.35)),
        ),
      ]),
    );
  }
}

/// Progressive-trust notice for unverified members. It names the cap and their
/// current usage up front, so hitting the limit is not a surprise at submit
/// time, and offers the single action that lifts it.
class _UnverifiedLimitNotice extends StatelessWidget {
  final int used;
  final int limit;
  const _UnverifiedLimitNotice({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final atCap = used >= limit;
    final accent = atCap ? CblrepColors.actionOrange : CblrepColors.brandGreen;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              atCap
                  ? 'You have used all $limit active-listing slots on your account ($used of $limit).'
                  : '$used of $limit active listings used. Unverified members can post up to $limit at a time.',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 2),
            Text(
              'Verify your residency to post without a limit.',
              style: TextStyle(fontSize: 11, color: dark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: accent,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VerificationScreen()),
                  );
                  if (context.mounted) {
                    context.read<ListingsProvider>().loadMine(showSpinner: false);
                  }
                },
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Get verified'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A quiet banner shown when an unfinished draft has been restored, with the one
/// action that makes sense: throw it away and start fresh.
class _DraftRestoredNotice extends StatelessWidget {
  final VoidCallback onDiscard;
  const _DraftRestoredNotice({required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = CblrepColors.brandGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.restore, size: 18, color: accent),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'We saved your unfinished draft. Pick up where you left off.',
            style: TextStyle(fontSize: 12, height: 1.35),
          ),
        ),
        TextButton(
          onPressed: onDiscard,
          style: TextButton.styleFrom(
            foregroundColor: dark ? Colors.white70 : CblrepColors.actionOrange,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Discard'),
        ),
      ]),
    );
  }
}

/// Compact control for pinning a listing's exact spot.
///
/// Empty: a single tappable row that opens the map picker. Once set: it shows
/// the chosen coordinates with a "change" and a "remove" affordance, so a pin
/// is never sticky once dropped by accident.
class _LocationPinCard extends StatelessWidget {
  final LatLng? location;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _LocationPinCard({
    required this.location,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Colors.white60 : Colors.black54;
    final pin = location;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.fieldGreen : const Color(0xFFEFE9DA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(children: [
        Icon(pin == null ? Icons.add_location_alt_outlined : Icons.location_on,
            size: 20, color: CblrepColors.actionOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              pin == null ? 'Pin the exact spot (optional)' : 'Exact location pinned',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              pin == null
                  ? 'Helps a neighbour find the gate or the store.'
                  : '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ]),
        ),
        if (pin == null)
          TextButton(onPressed: onPick, child: const Text('Set'))
        else ...[
          TextButton(onPressed: onPick, child: const Text('Change')),
          IconButton(
            tooltip: 'Remove pin',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: Icon(Icons.close, size: 18, color: muted),
          ),
        ],
      ]),
    );
  }
}

/// A horizontal, ordered photo picker for the Post form.
///
/// Shows each chosen photo as a thumbnail with a remove badge, plus an "add"
/// tile that opens the camera/gallery sheet. The first thumbnail is the cover,
/// so the order matters and is shown as-is. The add tile is hidden at the cap.
class _PhotoGallery extends StatelessWidget {
  final List<File> images;
  final int maxPhotos;
  final String label;
  final bool dark;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  const _PhotoGallery({
    required this.images,
    required this.maxPhotos,
    this.label = 'Photos',
    required this.dark,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final surface = dark ? CblrepColors.fieldGreen : const Color(0xFFEFE9DA);
    final border = dark ? Colors.white12 : Colors.black12;
    final isReference = label == 'Reference photos';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        images.isEmpty
            ? (isReference
                ? 'Add a reference photo (optional) — the kind of thing you want'
                : 'Add item photos (optional)')
            : '$label (${images.length}/$maxPhotos) — first is the cover',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < images.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      images[i],
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 9)),
                      ),
                    ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
            if (images.length < maxPhotos)
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 24),
                      SizedBox(height: 4),
                      Text('Add', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
