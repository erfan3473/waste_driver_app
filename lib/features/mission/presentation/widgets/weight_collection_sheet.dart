// lib/features/mission/presentation/widgets/weight_collection_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../orders/presentation/driver_orders_screen.dart';

class WeightCollectionSheet extends ConsumerStatefulWidget {
  final int orderId;
  const WeightCollectionSheet({super.key, required this.orderId});

  @override
  ConsumerState<WeightCollectionSheet> createState() =>
      _WeightCollectionSheetState();
}

class _WeightCollectionSheetState extends ConsumerState<WeightCollectionSheet> {
  List<dynamic> _categories = [];
  final Map<int, TextEditingController> _controllers = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('categories/');
      setState(() {
        _categories = res.data;
        for (var cat in _categories) {
          _controllers[cat['id']] = TextEditingController();
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submitCompletion() async {
    // اصلاح خط خطا: تعریف صریح نوع لیست برای ممانعت از خطای سینتکس
    final List itemsPayload = [];

    for (var cat in _categories) {
      final id = cat['id'] as int;
      final text = _controllers[id]?.text.trim() ?? '';
      final amount = double.tryParse(text);
      if (amount != null && amount > 0) {
        itemsPayload.add({'category_id': id, 'actual_amount': amount});
      }
    }

    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حداقل وزن یکی از اقلام تحویلی را وارد کنید.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(
        'driver/requests/${widget.orderId}/complete/',
        data: {'items': itemsPayload},
      );

      final total = res.data['total_citizen_amount'] ?? 0;

      if (mounted) {
        Navigator.of(context).pop(); // بستن باتم‌شیت
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('تسویه نهایی با موفقیت انجام شد'),
            content: Text(
              'مبلغ $total تومان به کیف پول شهروند و دستمزد راننده واریز گردید.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const DriverOrdersScreen(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('بازگشت به لیست سفارش‌ها'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تسویه سفارش: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ثبت وزن‌های قطعی باسکول',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'وزن دقیق تفکیک‌شده را به کیلوگرم وارد فرمایید:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  ..._categories.map((cat) {
                    final id = cat['id'] as int;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${cat['title']} (${cat['price_per_unit']} ت)',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _controllers[id],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                hintText: 'وزن (${cat['unit']})',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isSubmitting ? null : _submitCompletion,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'ثبت قطعی و صدور فاکتور تسویه',
                              style: TextStyle(fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
