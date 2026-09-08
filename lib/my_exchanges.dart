import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class ExchangeItem {
  final String id;
  final String title;
  final String btn1Text;
  final String btn2Text;

  ExchangeItem({
    required this.id,
    required this.title,
    required this.btn1Text,
    required this.btn2Text,
  });
}

class CompletedItem {
  final String title;
  final String rateLabel;

  CompletedItem({
    required this.title,
    required this.rateLabel,
  });
}

class MyExchangesPage extends StatefulWidget {
  const MyExchangesPage({super.key});

  @override
  State<MyExchangesPage> createState() => _MyExchangesPageState();
}

class _MyExchangesPageState extends State<MyExchangesPage> {
  int _selectedTabIndex = 0; // 0: ACTIVE, 1: PENDING, 2: COMPLETED

  // Pending items state list
  final List<ExchangeItem> _pendingItems = [
    ExchangeItem(
      id: '1',
      title: 'BORROW REQUEST: VINTAGE CAMERA',
      btn1Text: 'Approved',
      btn2Text: 'Declined',
    ),
    ExchangeItem(
      id: '2',
      title: 'BARTER OFFER: 1 DOZEN EGGS',
      btn1Text: 'Accept Offer',
      btn2Text: 'Chat',
    ),
  ];

  // Completed items state list
  final List<CompletedItem> _completedItems = [
    CompletedItem(title: 'Heavy duty Power Drill', rateLabel: 'Rate Lender'),
    CompletedItem(title: 'Fresh Veggie Basket', rateLabel: 'Rate Partner'),
  ];

  void _handleApprove(ExchangeItem item) {
    setState(() {
      _pendingItems.removeWhere((element) => element.id == item.id);
      _completedItems.add(
        CompletedItem(title: item.title, rateLabel: 'Rate Partner'),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} has been accepted! Moved to Completed.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleDecline(ExchangeItem item) {
    setState(() {
      _pendingItems.removeWhere((element) => element.id == item.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} was declined.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openPostResourceModal() async {
    final newResource = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const PostResourceDialog(),
    );

    if (newResource != null) {
      globalResourceProvider.addResource(
        newResource['title']!,
        newResource['postedBy']!,
        newResource['brgy']!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D4D36),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D4D36),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'MY EXCHANGES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTabButton('ACTIVE', 0),
                  _buildTabButton('PENDING', 1),
                  _buildTabButton('COMPLETED', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildTabContent(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE58824),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _openPostResourceModal,
                  child: const Text(
                    '+ POST A RESOURCE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFFE58824) : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildActiveTab();
      case 1:
        return _buildPendingTab();
      case 2:
        return _buildCompletedTab();
      default:
        return _buildActiveTab();
    }
  }

  Widget _buildActiveTab() {
    return ListView(
      children: [
        const Text(
          'ONGOING - BORROWING',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          width: 50,
          height: 50,
          alignment: Alignment.centerLeft,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0xFFCCCCCC),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'PENDING CONFIRMATION',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          width: 50,
          height: 50,
          alignment: Alignment.centerLeft,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0xFFCCCCCC),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingTab() {
    if (_pendingItems.isEmpty) {
      return const Center(
        child: Text(
          'No pending requests',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      itemCount: _pendingItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _pendingItems[index];
        return _buildPendingCardItem(item);
      },
    );
  }

  Widget _buildCompletedTab() {
    if (_completedItems.isEmpty) {
      return const Center(
        child: Text(
          'No completed exchanges yet',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      itemCount: _completedItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _completedItems[index];
        return _buildCompletedCardItem(item.title, item.rateLabel);
      },
    );
  }

  Widget _buildPendingCardItem(ExchangeItem item) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFCCCCCC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: const Color(0xFF6E2800),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Colors.black),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE58824),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: () => _handleApprove(item),
                          child: Text(
                            item.btn1Text,
                            style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE58824),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: () {
                            if (item.btn2Text == 'Declined') {
                              _handleDecline(item);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Opening chat...')),
                              );
                            }
                          },
                          child: Text(
                            item.btn2Text,
                            style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedCardItem(String title, String rateLabel) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFCCCCCC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFF6E2800),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(Icons.check_circle, color: Colors.white, size: 14),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.black54),
                        Icon(Icons.star, size: 12, color: Colors.black54),
                        Icon(Icons.star, size: 12, color: Colors.black54),
                        Icon(Icons.star_border, size: 12, color: Colors.black54),
                        Icon(Icons.star_border, size: 12, color: Colors.black54),
                      ],
                    ),
                    Text(
                      rateLabel,
                      style: const TextStyle(fontSize: 8, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}