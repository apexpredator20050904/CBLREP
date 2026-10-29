import 'package:flutter/material.dart';

/// Shared vocabulary for the Post form.
///
/// The backend mirrors these keys in App\Support\QuantityUnits and
/// App\Models\Resource::URGENCIES. Keep the three lists in step: the API
/// rejects a unit or urgency it does not recognise.

class ListingUnit {
  final String key;
  final String singular;
  final String plural;

  const ListingUnit(this.key, this.singular, this.plural);
}

const listingUnits = <ListingUnit>[
  ListingUnit('piece', 'pc', 'pcs'),
  ListingUnit('kg', 'kg', 'kg'),
  ListingUnit('gram', 'g', 'g'),
  ListingUnit('sack', 'sack', 'sacks'),
  ListingUnit('bundle', 'bundle', 'bundles'),
  ListingUnit('hour', 'hour', 'hours'),
  ListingUnit('liter', 'L', 'L'),
  ListingUnit('pack', 'pack', 'packs'),
  ListingUnit('tray', 'tray', 'trays'),
  ListingUnit('dozen', 'dozen', 'dozen'),
];

/// The label for one unit, pluralised when the amount is not exactly one.
String listingUnitLabel(String key, num value) {
  for (final unit in listingUnits) {
    if (unit.key == key) {
      return value == 1 ? unit.singular : unit.plural;
    }
  }
  return key;
}

/// Trim trailing zeros so 5.00 reads as "5" and 2.50 as "2.5".
String formatQuantityNumber(num value) {
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Compose the display string the API also stores in the legacy column.
String formatListingQuantity(num value, String unit) {
  return '${formatQuantityNumber(value)} ${listingUnitLabel(unit, value)}';
}

class ListingUrgency {
  final String key;
  final String label;
  final IconData icon;

  const ListingUrgency(this.key, this.label, this.icon);
}

const listingUrgencies = <ListingUrgency>[
  ListingUrgency('urgent', 'Urgent / Today', Icons.bolt),
  ListingUrgency('this_week', 'This Week', Icons.event_outlined),
  ListingUrgency('flexible', 'Flexible', Icons.eco_outlined),
];

String listingUrgencyLabel(String? key) {
  for (final urgency in listingUrgencies) {
    if (urgency.key == key) return urgency.label;
  }
  return key ?? '';
}

/// Direction-specific wording for the Post form.
///
/// An OFFER and a NEED share the same controls but mean different things by
/// them, so every label/helper lives here instead of in scattered ternaries.
class ListingFormCopy {
  final String titleLabel;
  final String titleHint;
  final String titleHelper;
  final String descriptionLabel;
  final String descriptionHint;
  final String descriptionHelper;
  final String quantityLabel;
  final String quantityHelper;
  final String priceLabel;
  final String priceHelper;
  final String wantedLabel;
  final String wantedHelper;
  final String conditionLabel;
  final String directionBanner;

  const ListingFormCopy({
    required this.titleLabel,
    required this.titleHint,
    required this.titleHelper,
    required this.descriptionLabel,
    required this.descriptionHint,
    required this.descriptionHelper,
    required this.quantityLabel,
    required this.quantityHelper,
    required this.priceLabel,
    required this.priceHelper,
    required this.wantedLabel,
    required this.wantedHelper,
    required this.conditionLabel,
    required this.directionBanner,
  });

  static const offer = ListingFormCopy(
    titleLabel: 'What are you offering?',
    titleHint: 'e.g. 5 kg of rice, a working drill, 2 hours of tutoring',
    titleHelper: 'Name the item or skill clearly — neighbours search by it.',
    descriptionLabel: 'Describe what you are sharing',
    descriptionHint:
        'e.g. Works well, minor scratches, pickup at the Poblacion market on Saturday.',
    descriptionHelper:
        'Condition, what is included, and pickup notes — where and when.',
    quantityLabel: 'How much are you sharing?',
    quantityHelper: 'Optional — e.g. 5 kg, 2 sacks, 3 pieces.',
    priceLabel: 'Price (₱)',
    priceHelper:
        'Leave negotiable on if you will consider a counter-offer.',
    wantedLabel: 'In return, I would like (optional)',
    wantedHelper: 'e.g. 5 kg of rice, or an hour of plumbing help.',
    conditionLabel: 'Condition',
    directionBanner: 'Posting an OFFER — you have this to share.',
  );

  static const need = ListingFormCopy(
    titleLabel: 'What do you need?',
    titleHint: 'e.g. 5 kg of rice for the weekend',
    titleHelper: 'Name the thing you need, not "looking for".',
    descriptionLabel: 'Why do you need it, and by when?',
    descriptionHint:
        'e.g. I am cooking for a barangay feeding on Sunday and need rice.',
    descriptionHelper:
        'A sentence of context helps neighbours decide if they can help.',
    quantityLabel: 'How much do you need?',
    quantityHelper: 'e.g. 5 kg, 2 sacks, 3 hours.',
    priceLabel: 'I can pay up to (₱)',
    priceHelper:
        'Your budget ceiling — what you are willing to pay for this.',
    wantedLabel: 'In return, I can offer (optional)',
    wantedHelper: 'e.g. 2 hours of childcare, or a bag of rice.',
    conditionLabel: 'Condition I can accept',
    directionBanner: 'Posting a NEED — you are looking for this.',
  );

  static ListingFormCopy of(String type) => type == 'request' ? need : offer;
}
