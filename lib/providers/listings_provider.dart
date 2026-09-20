import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class ListingsProvider extends ChangeNotifier {
  final ApiService api;
  List<ListingModel> listings = const [];
  bool loading = false;
  String? error;

  ListingsProvider(this.api);

  Future<void> load({String? query, String? barangay}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      listings = (await api.listings(query: query, barangay: barangay))
          .map((item) => ListingModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on ApiException catch (exception) {
      error = exception.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
