import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';

/// Reusable resource card — grey body on deep forest, orange exchange pill,
/// network photo when available, responsive via parent grid constraints.
class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback? onTap;
  final VoidCallback? onManage;

  const ListingCard({super.key, required this.listing, this.onTap, this.onManage});

  bool get isNeed => listing.type == 'request';

  /// Centered watermark shown while a listing has no usable photo.
  Widget _placeholder(bool need) => Center(
        child: Icon(
          need ? Icons.help_outline : Icons.volunteer_activism,
          size: 44,
          color: Colors.white24,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 120,
              child: Stack(fit: StackFit.expand, children: [
                // Branded gradient placeholder instead of a flat grey block
                // while a listing has no uploaded photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B6B48), Color(0xFF1B382B)],
                    ),
                  ),
                ),
                if (listing.imageUrl != null)
                  Image.network(
                    listing.imageUrl!,
                    fit: BoxFit.cover,
                    // Decode at card resolution instead of full camera size —
                    // a big scroll-smoothness win on 2-core devices.
                    cacheWidth: 480,
                    errorBuilder: (_, _, _) => _placeholder(isNeed),
                  )
                else
                  _placeholder(isNeed),
                Positioned(
                  top: 8, left: 8,
                  child: _ModePill(label: isNeed ? 'NEED' : 'OFFER', need: isNeed),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(listing.exchangeType.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54), overflow: TextOverflow.ellipsis),
                  ),
                  if (onManage != null)
                    InkWell(onTap: onManage, child: const Icon(Icons.more_vert, size: 16, color: Colors.black54)),
                ]),
                const SizedBox(height: 4),
                Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                const SizedBox(height: 2),
                Text('${listing.category} · ${listing.condition}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                const SizedBox(height: 2),
                Text('${listing.location} · ${listing.owner}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool need;
  const _ModePill({required this.label, required this.need});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: need ? CblrepColors.brandGreen : CblrepColors.actionOrange, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}
