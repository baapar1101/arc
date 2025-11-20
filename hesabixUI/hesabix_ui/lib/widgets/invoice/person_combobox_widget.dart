import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/person_service.dart';
import '../../models/person_model.dart';
import '../../widgets/person/person_form_dialog.dart';

class PersonComboboxWidget extends StatefulWidget {
  final int businessId;
  final Person? selectedPerson;
  final ValueChanged<Person?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  final List<String>? personTypes; // فیلتر بر اساس نوع شخص (مثل ['فروشنده', 'بازاریاب'])
  final String? searchHint;

  const PersonComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedPerson,
    this.label = 'شخص',
    this.hintText = 'جست‌وجو و انتخاب شخص',
    this.isRequired = false,
    this.personTypes,
    this.searchHint,
  });

  @override
  State<PersonComboboxWidget> createState() => _PersonComboboxWidgetState();
}

class _PersonComboboxWidgetState extends State<PersonComboboxWidget> {
  final PersonService _personService = PersonService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  int _searchSeq = 0; // برای جلوگیری از نمایش نتایج قدیمی
  String _latestQuery = '';
  void Function(void Function())? _setModalState;
  
  List<Person> _persons = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedPerson?.displayName ?? '';
    _loadRecentPersons();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentPersons() async {
    // استفاده از مسیر واحد جست‌وجو با کوئری خالی
    await _performSearch('');
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    final int seq = ++_searchSeq;
    _latestQuery = query;

    // حالت لودینگ بسته به خالی بودن کوئری
    if (mounted) {
      setState(() {
        if (query.isEmpty) {
          _isLoading = true;
          _hasSearched = false;
        } else {
          _isSearching = true;
          _hasSearched = true;
        }
      });
    }

    try {
      // Debug: نمایش پارامترهای جست‌وجو

      final response = await _personService.getPersons(
        businessId: widget.businessId,
        search: query.isEmpty ? null : query,
        limit: query.isEmpty ? 10 : 20,
        filters: widget.personTypes != null && widget.personTypes!.isNotEmpty
            ? {'person_types': widget.personTypes}
            : null,
      );

      // پاسخ کهنه را نادیده بگیر
      if (seq != _searchSeq || query != _latestQuery) {
        return;
      }

      final persons = _personService.parsePersonsList(response);

      if (mounted) {
        setState(() {
          _persons = persons;
          if (query.isEmpty) {
            _isLoading = false;
            _hasSearched = false;
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
          _persons = [];
          if (query.isEmpty) {
            _isLoading = false;
            _hasSearched = false;
          } else {
            _isSearching = false;
          }
        });
        _showErrorSnackBar('خطا در جست‌وجو: $e');
        _setModalState?.call(() {});
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _selectPerson(Person? person) {
    if (person == null) {
      _searchController.clear();
      widget.onChanged(null);
      return;
    }
    
    _searchController.text = person.displayName;
    widget.onChanged(person);
  }

  Future<void> _addNewPerson() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
      ),
    );
    
    if (result == true && mounted) {
      // Refresh لیست
      await _performSearch(_latestQuery);
      
      // پیدا کردن آخرین آیتم اضافه شده (احتمالاً آخرین آیتم در لیست)
      if (_persons.isNotEmpty) {
        final lastPerson = _persons.last;
        _selectPerson(lastPerson);
      }
    }
  }

  void _showPersonPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _setModalState = setModalState;
          return _PersonPickerBottomSheet(
            persons: _persons,
            selectedPerson: widget.selectedPerson,
            onPersonSelected: _selectPerson,
            searchController: _searchController,
            onSearchChanged: (query) {
              _onSearchChanged(query);
              setModalState(() {});
            },
            isLoading: _isLoading,
            isSearching: _isSearching,
            hasSearched: _hasSearched,
            label: widget.label,
            searchHint: widget.searchHint ?? 'جست‌وجو در اشخاص...',
            personTypes: widget.personTypes,
            onAddNew: _addNewPerson,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final displayText = widget.selectedPerson?.displayName ?? widget.hintText;
    final isSelected = widget.selectedPerson != null;

    return InkWell(
      onTap: _showPersonPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
          color: colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_search,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color: isSelected 
                      ? colorScheme.onSurface 
                      : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (widget.selectedPerson != null)
              GestureDetector(
                onTap: () => _selectPerson(null),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.clear,
                    color: colorScheme.error,
                    size: 18,
                  ),
                ),
              )
            else
              Icon(
                Icons.arrow_drop_down,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonPickerBottomSheet extends StatefulWidget {
  final List<Person> persons;
  final Person? selectedPerson;
  final Function(Person?) onPersonSelected;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;
  final String label;
  final String searchHint;
  final List<String>? personTypes;
  final VoidCallback? onAddNew;

  const _PersonPickerBottomSheet({
    required this.persons,
    required this.selectedPerson,
    required this.onPersonSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.isLoading,
    required this.isSearching,
    required this.hasSearched,
    required this.label,
    required this.searchHint,
    this.personTypes,
    this.onAddNew,
  });

  @override
  State<_PersonPickerBottomSheet> createState() => _PersonPickerBottomSheetState();
}

class _PersonPickerBottomSheetState extends State<_PersonPickerBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // هدر
          Row(
            children: [
              Text(
                widget.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (widget.onAddNew != null)
                IconButton(
                  onPressed: widget.onAddNew,
                  icon: const Icon(Icons.add),
                  tooltip: 'افزودن شخص جدید',
                  color: theme.colorScheme.primary,
                ),
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
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: widget.isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 16),
          
          // لیست اشخاص
          Expanded(
            child: _buildPersonsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonsList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.persons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.hasSearched 
                  ? 'شخصی با این مشخصات یافت نشد'
                  : 'هیچ شخصی ثبت نشده است',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (widget.personTypes != null && widget.personTypes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'فیلتر: ${widget.personTypes!.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.persons.length,
      itemBuilder: (context, index) {
        final person = widget.persons[index];
        final isSelected = widget.selectedPerson?.id == person.id;
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(person.displayName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (person.personTypes.isNotEmpty)
                Text(
                  person.personTypes.first.persianName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              if (person.phone != null)
                Text(
                  'تلفن: ${person.phone}',
                  style: theme.textTheme.bodySmall,
                ),
              if (person.email != null)
                Text(
                  'ایمیل: ${person.email}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          trailing: isSelected
              ? Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                )
              : null,
          onTap: () {
            widget.onPersonSelected(person);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}
