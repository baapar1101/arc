import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../utils/snackbar_helper.dart';

class SellerPickerWidget extends StatefulWidget {
  final Person? selectedSeller;
  final Function(Person?) onSellerChanged;
  final int businessId;
  final AuthStore authStore;
  final bool isRequired;
  final String label;
  final String hintText;

  const SellerPickerWidget({
    super.key,
    this.selectedSeller,
    required this.onSellerChanged,
    required this.businessId,
    required this.authStore,
    this.isRequired = false,
    this.label = 'فروشنده/بازاریاب',
    this.hintText = 'جست‌وجو و انتخاب فروشنده یا بازاریاب',
  });

  @override
  State<SellerPickerWidget> createState() => _SellerPickerWidgetState();
}

class _SellerPickerWidgetState extends State<SellerPickerWidget> {
  final PersonService _personService = PersonService();
  final TextEditingController _searchController = TextEditingController();
  List<Person> _sellers = [];
  bool _isLoading = false;
  bool _isSearching = false;
  int _searchSeq = 0; // برای جلوگیری از نمایش نتایج قدیمی
  String _latestQuery = '';
  void Function(void Function())? _setModalState;

  @override
  void initState() {
    super.initState();
    _loadSellers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSellers() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _personService.getPersons(
        businessId: widget.businessId,
        filters: {
          // یکسان‌سازی با API: استفاده از person_types (لیستی از مقادیر)
          'person_types': ['فروشنده', 'بازاریاب'],
        },
        limit: 100, // دریافت همه فروشندگان/بازاریاب‌ها
      );

      final sellers = _personService.parsePersonsList(response);
      
      if (mounted) {
        setState(() {
          _sellers = sellers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دریافت لیست فروشندگان: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _searchSellers(String query) async {
    final int seq = ++_searchSeq;
    _latestQuery = query;

    if (!mounted) return;

    setState(() {
      if (query.isEmpty) {
        _isLoading = true; // برای نمایش لودینگ مرکزی هنگام پاک‌کردن کوئری
      } else {
        _isSearching = true; // برای نمایش اسپینر کوچک کنار فیلد جست‌وجو
      }
    });
    _setModalState?.call(() {});

    try {
      final response = await _personService.getPersons(
        businessId: widget.businessId,
        search: query.isEmpty ? null : query,
        filters: {
          'person_types': ['فروشنده', 'بازاریاب'],
        },
        limit: query.isEmpty ? 100 : 50,
      );

      // پاسخ کهنه را نادیده بگیر
      if (seq != _searchSeq || query != _latestQuery) {
        return;
      }

      final sellers = _personService.parsePersonsList(response);
      
      if (mounted) {
        setState(() {
          _sellers = sellers;
          if (query.isEmpty) {
            _isLoading = false;
          } else {
            _isSearching = false;
          }
        });
        _setModalState?.call(() {});
      }
    } catch (e) {
      // پاسخ کهنه را نادیده بگیر
      if (seq != _searchSeq || query != _latestQuery) {
        return;
      }
      if (mounted) {
        setState(() {
          if (query.isEmpty) {
            _isLoading = false;
          } else {
            _isSearching = false;
          }
        });
        _setModalState?.call(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در جست‌وجو: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showSellerPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _setModalState = setModalState;
          return _SellerPickerBottomSheet(
            sellers: _sellers,
            selectedSeller: widget.selectedSeller,
            onSellerSelected: (seller) {
              widget.onSellerChanged(seller);
              Navigator.pop(context);
            },
            searchController: _searchController,
            onSearchChanged: _searchSellers,
            isLoading: _isLoading || _isSearching,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showSellerPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_search,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: widget.selectedSeller != null
                  ? Text(
                      widget.selectedSeller!.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    )
                  : Text(
                      widget.hintText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
            ),
            if (widget.selectedSeller != null)
              GestureDetector(
                onTap: () {
                  widget.onSellerChanged(null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.error,
                    size: 18,
                  ),
                ),
              )
            else
              Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}

class _SellerPickerBottomSheet extends StatefulWidget {
  final List<Person> sellers;
  final Person? selectedSeller;
  final Function(Person) onSellerSelected;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final bool isLoading;

  const _SellerPickerBottomSheet({
    required this.sellers,
    required this.selectedSeller,
    required this.onSellerSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.isLoading,
  });

  @override
  State<_SellerPickerBottomSheet> createState() => _SellerPickerBottomSheetState();
}

class _SellerPickerBottomSheetState extends State<_SellerPickerBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // هدر
          Row(
            children: [
              Text(
                'انتخاب فروشنده/بازاریاب',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // فیلد جست‌وجو
          TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: 'جست‌وجو در فروشندگان و بازاریاب‌ها...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 16),
          
          // لیست فروشندگان
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.sellers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'فروشنده یا بازاریابی یافت نشد',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.sellers.length,
                        itemBuilder: (context, index) {
                          final seller = widget.sellers[index];
                          final isSelected = widget.selectedSeller?.id == seller.id;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(seller.displayName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(seller.personTypes.isNotEmpty 
                                    ? seller.personTypes.first.persianName
                                    : 'نامشخص'),
                                if (seller.commissionSalePercent != null)
                                  Text(
                                    'کارمزد فروش: ${seller.commissionSalePercent!.toStringAsFixed(1)}%',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    color: Theme.of(context).colorScheme.primary,
                                  )
                                : null,
                            onTap: () => widget.onSellerSelected(seller),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
