import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/person_service.dart';
import '../../models/person_model.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/person/person_financial_balance_banner.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class _PersonPickerState {
  final List<Person> persons;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;

  _PersonPickerState({
    required this.persons,
    required this.isLoading,
    required this.isSearching,
    required this.hasSearched,
  });

  _PersonPickerState copyWith({
    List<Person>? persons,
    bool? isLoading,
    bool? isSearching,
    bool? hasSearched,
  }) {
    return _PersonPickerState(
      persons: persons ?? this.persons,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

class PersonComboboxWidget extends StatefulWidget {
  final int businessId;
  final Person? selectedPerson;
  final ValueChanged<Person?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  final List<String>? personTypes; // فیلتر بر اساس نوع شخص (مثل ['فروشنده', 'بازاریاب'])
  final String? searchHint;
  /// نمایش مانده حساب و بدهکار/بستانکار زیر فیلد (برای فرم‌های مالی)
  final bool showFinancialBalance;

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
    this.showFinancialBalance = false,
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
  
  List<Person> _persons = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;
  final ValueNotifier<_PersonPickerState> _pickerStateNotifier = ValueNotifier<_PersonPickerState>(
    _PersonPickerState(
      persons: [],
      isLoading: false,
      isSearching: false,
      hasSearched: false,
    ),
  );
  final FocusNode _fieldFocus = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final ScrollController _overlayScrollController = ScrollController();
  OverlayEntry? _desktopOverlayEntry;
  int _highlightedIndex = -1;
  double _desktopFieldWidth = 0;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedPerson?.displayName ?? '';
    _fieldFocus.addListener(_onDesktopFocusChanged);
    _loadRecentPersons();
  }

  @override
  void didUpdateWidget(covariant PersonComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPerson?.id != widget.selectedPerson?.id) {
      _searchController.text = widget.selectedPerson?.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _removeDesktopOverlay();
    _fieldFocus.removeListener(_onDesktopFocusChanged);
    _fieldFocus.dispose();
    _overlayScrollController.dispose();
    _searchController.dispose();
    _pickerStateNotifier.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.sizeOf(context).width < 700;

  void _onDesktopFocusChanged() {
    if (!mounted || _isMobile) return;
    if (_fieldFocus.hasFocus) {
      _showDesktopOverlay();
      if (_searchController.text.trim().isEmpty) {
        _loadRecentPersons();
      }
    } else {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted || _fieldFocus.hasFocus) return;
        _removeDesktopOverlay();
      });
    }
  }

  void _showDesktopOverlay() {
    if (!mounted || _isMobile) return;
    if (_desktopOverlayEntry != null) {
      _desktopOverlayEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);
    _desktopOverlayEntry = OverlayEntry(
      builder: (context) => _buildDesktopOverlay(context),
    );
    overlay.insert(_desktopOverlayEntry!);
  }

  void _removeDesktopOverlay() {
    _desktopOverlayEntry?.remove();
    _desktopOverlayEntry = null;
    _highlightedIndex = -1;
  }

  Widget _buildDesktopOverlay(BuildContext context) {
    final width = _desktopFieldWidth > 280 ? _desktopFieldWidth : 280.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _fieldFocus.unfocus();
              _removeDesktopOverlay();
            },
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SizedBox(
                width: width,
                child: ValueListenableBuilder<_PersonPickerState>(
                  valueListenable: _pickerStateNotifier,
                  builder: (context, state, _) => _buildDesktopPersonsList(context, state),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPersonsList(BuildContext context, _PersonPickerState state) {
    final cs = Theme.of(context).colorScheme;
    if (state.isLoading && state.persons.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (!state.isLoading && state.persons.isEmpty) {
      return const SizedBox(height: 90, child: Center(child: Text('شخصی یافت نشد')));
    }
    return Column(
      children: [
        if (state.isSearching) const LinearProgressIndicator(minHeight: 2),
        Flexible(
          child: ListView.builder(
            controller: _overlayScrollController,
            itemCount: state.persons.length,
            itemBuilder: (context, index) {
              final person = state.persons[index];
              final selected = index == _highlightedIndex;
              return Material(
                color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  title: Text(person.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: person.personTypes.isNotEmpty ? Text(person.personTypes.first.persianName) : null,
                  onTap: () => _selectPersonFromOverlay(person),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _selectPersonFromOverlay(Person person) {
    _selectPerson(person);
    _removeDesktopOverlay();
    _fieldFocus.unfocus();
  }

  void _moveHighlight(int delta) {
    final items = _pickerStateNotifier.value.persons;
    if (items.isEmpty) return;
    var idx = _highlightedIndex;
    if (idx < 0 || idx >= items.length) {
      idx = delta > 0 ? 0 : items.length - 1;
    } else {
      idx = (idx + delta).clamp(0, items.length - 1);
    }
    if (idx == _highlightedIndex) return;
    setState(() => _highlightedIndex = idx);
    _desktopOverlayEntry?.markNeedsBuild();
  }

  void _selectHighlighted() {
    final items = _pickerStateNotifier.value.persons;
    if (items.isEmpty) return;
    final idx = (_highlightedIndex >= 0 && _highlightedIndex < items.length) ? _highlightedIndex : 0;
    _selectPersonFromOverlay(items[idx]);
  }

  KeyEventResult _onFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_desktopOverlayEntry == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _selectHighlighted();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeDesktopOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadRecentPersons() async {
    // استفاده از مسیر واحد جست‌وجو با کوئری خالی
    await _performSearch('');
    // مقداردهی اولیه ValueNotifier
    _pickerStateNotifier.value = _PersonPickerState(
      persons: _persons,
      isLoading: _isLoading,
      isSearching: _isSearching,
      hasSearched: _hasSearched,
    );
    _highlightedIndex = _persons.isEmpty ? -1 : 0;
    _desktopOverlayEntry?.markNeedsBuild();
  }

  void _onSearchChanged(String query) {
    print('[PersonCombobox] _onSearchChanged called with query: "$query"');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      print('[PersonCombobox] Debounce timer fired, calling _performSearch with: "${query.trim()}"');
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    final int seq = ++_searchSeq;
    _latestQuery = query;
    print('[PersonCombobox] _performSearch called - seq: $seq, query: "$query", current persons count: ${_persons.length}');

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
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
        isLoading: _isLoading,
        isSearching: _isSearching,
        hasSearched: _hasSearched,
      );
      print('[PersonCombobox] setState called - isLoading: $_isLoading, isSearching: $_isSearching');
    }

    try {
      print('[PersonCombobox] Calling _personService.getPersons - businessId: ${widget.businessId}, search: ${query.isEmpty ? "null" : query}');
      final response = await _personService.getPersons(
        businessId: widget.businessId,
        search: query.isEmpty ? null : query,
        limit: query.isEmpty ? 10 : 20,
        filters: widget.personTypes != null && widget.personTypes!.isNotEmpty
            ? {'person_types': widget.personTypes}
            : null,
      );
      print('[PersonCombobox] Response received from server - type: ${response.runtimeType}');

      // پاسخ کهنه را نادیده بگیر
      print('[PersonCombobox] Checking sequence - seq: $seq, _searchSeq: $_searchSeq, query: "$query", _latestQuery: "$_latestQuery"');
      if (seq != _searchSeq || query != _latestQuery) {
        print('[PersonCombobox] WARNING: Response is stale, ignoring! seq match: ${seq == _searchSeq}, query match: ${query == _latestQuery}');
        return;
      }

      print('[PersonCombobox] Parsing response...');
      final persons = _personService.parsePersonsList(response);
      print('[PersonCombobox] Search completed - seq: $seq, received ${persons.length} persons');
      if (persons.isNotEmpty) {
        print('[PersonCombobox] First person: ${persons.first.displayName}');
      }

      print('[PersonCombobox] Checking mounted state - mounted: $mounted');
      if (mounted) {
        print('[PersonCombobox] Calling setState to update _persons...');
        setState(() {
          _persons = persons;
          if (query.isEmpty) {
            _isLoading = false;
            _hasSearched = false;
          } else {
            _isSearching = false;
          }
        });
        print('[PersonCombobox] setState completed - _persons count: ${_persons.length}, _isLoading: $_isLoading, _isSearching: $_isSearching');
        
        // به‌روزرسانی ValueNotifier
        print('[PersonCombobox] Updating ValueNotifier...');
        _pickerStateNotifier.value = _PersonPickerState(
          persons: persons,
          isLoading: _isLoading,
          isSearching: _isSearching,
          hasSearched: _hasSearched,
        );
        _highlightedIndex = persons.isEmpty ? -1 : 0;
        _desktopOverlayEntry?.markNeedsBuild();
        print('[PersonCombobox] ValueNotifier updated - pickerStateNotifier.value.persons.length: ${_pickerStateNotifier.value.persons.length}');
      } else {
        print('[PersonCombobox] ERROR: Widget is not mounted!');
      }
    } catch (e, stackTrace) {
      print('[PersonCombobox] ERROR in _performSearch: $e');
      print('[PersonCombobox] Stack trace: $stackTrace');
      // پاسخ کهنه را نادیده بگیر
      if (seq != _searchSeq || query != _latestQuery) {
        print('[PersonCombobox] Error response is stale, ignoring');
        return;
      }
      if (mounted) {
        print('[PersonCombobox] Handling error - setting empty list');
        setState(() {
          _persons = [];
          if (query.isEmpty) {
            _isLoading = false;
            _hasSearched = false;
          } else {
            _isSearching = false;
          }
        });
        // به‌روزرسانی ValueNotifier
        _pickerStateNotifier.value = _PersonPickerState(
          persons: [],
          isLoading: _isLoading,
          isSearching: _isSearching,
          hasSearched: _hasSearched,
        );
        _highlightedIndex = -1;
        _desktopOverlayEntry?.markNeedsBuild();
        _showErrorSnackBar(
          'خطا در جست‌وجو: ${ErrorExtractor.forContext(e, context)}',
        );
      } else {
        print('[PersonCombobox] ERROR: Widget is not mounted when handling error!');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    // استفاده از SnackBarHelper تا پیام خطا روی تمام لایه‌ها (دیالوگ/باتم‌شیت) نمایش داده شود
    SnackBarHelper.showError(context, message: message);
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

  Future<void> _addNewPerson(BuildContext bottomSheetContext) async {
    // ذخیره متن جستجو شده
    final searchQuery = _searchController.text.trim();
    
    // بستن bottom sheet قبل از باز کردن dialog
    Navigator.pop(bottomSheetContext);

    final result = await showDialog<Person?>(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
        initialAliasName: searchQuery.isNotEmpty ? searchQuery : null,
      ),
    );
    
    if (result != null && mounted) {
      // اگر Person ایجاد شده را دریافت کردیم، مستقیماً آن را انتخاب کنیم
      _selectPerson(result);
    } else if (result == true && mounted) {
      // Fallback: اگر true برگردانده شد (برای سازگاری با کد قدیمی)
      // Refresh لیست و پیدا کردن شخص جدید
      await _performSearch(_latestQuery);
      
      // پیدا کردن شخص جدید (با بیشترین ID)
      if (_persons.isNotEmpty) {
        final sortedPersons = List<Person>.from(_persons);
        sortedPersons.sort((a, b) {
          final idA = a.id ?? 0;
          final idB = b.id ?? 0;
          return idB.compareTo(idA);
        });
        _selectPerson(sortedPersons.first);
      }
    }
  }

  void _showPersonPicker() {
    print('[PersonCombobox] _showPersonPicker called - _persons count: ${_persons.length}');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        print('[PersonCombobox] BottomSheet builder called - _persons count: ${_persons.length}, _isLoading: $_isLoading, _isSearching: $_isSearching');
        return _PersonPickerBottomSheet(
              pickerStateNotifier: _pickerStateNotifier,
              selectedPerson: widget.selectedPerson,
              onPersonSelected: _selectPerson,
              searchController: _searchController,
              onSearchChanged: (query) {
                print('[PersonCombobox] onSearchChanged callback called with: "$query"');
                _onSearchChanged(query);
              },
              label: widget.label,
              searchHint: widget.searchHint ?? 'جست‌وجو در اشخاص...',
              personTypes: widget.personTypes,
              onAddNew: () => _addNewPerson(context),
            );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = _isMobile;
    
    final displayText = widget.selectedPerson?.displayName ?? widget.hintText;
    final isSelected = widget.selectedPerson != null;
    final bool inlineBalance =
        widget.showFinancialBalance && widget.selectedPerson?.id != null;

    if (isMobile) {
      return InkWell(
        onTap: _showPersonPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surface,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.person_search, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: inlineBalance
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
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
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: PersonFinancialBalanceBanner(selectedPerson: widget.selectedPerson),
                          ),
                        ],
                      )
                    : Text(
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
                    child: Icon(Icons.clear, color: colorScheme.error, size: 18),
                  ),
                )
              else
                Icon(Icons.arrow_drop_down, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ],
          ),
        ),
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if ((_desktopFieldWidth - w).abs() > 0.5) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if ((_desktopFieldWidth - w).abs() > 0.5) {
                setState(() => _desktopFieldWidth = w);
                _desktopOverlayEntry?.markNeedsBuild();
              }
            });
          }
          return Focus(
            onKeyEvent: _onFieldKeyEvent,
            child: TextField(
              controller: _searchController,
              focusNode: _fieldFocus,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearching)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    IconButton(
                      tooltip: 'انتخاب پیشرفته',
                      icon: Icon(Icons.manage_search_rounded, color: colorScheme.primary),
                      onPressed: _showPersonPicker,
                    ),
                  ],
                ),
              ),
              onTap: () {
                _showDesktopOverlay();
                if (_searchController.text.trim().isEmpty) {
                  _loadRecentPersons();
                }
              },
              onChanged: (query) {
                final trimmed = query.trim();
                if (trimmed.isEmpty && widget.selectedPerson != null) {
                  widget.onChanged(null);
                } else if (widget.selectedPerson != null &&
                    trimmed != (widget.selectedPerson?.displayName ?? '').trim()) {
                  widget.onChanged(null);
                }
                _onSearchChanged(query);
                _showDesktopOverlay();
              },
              onSubmitted: (_) => _selectHighlighted(),
            ),
          );
        },
      ),
    );
  }
}

class _PersonPickerBottomSheet extends StatefulWidget {
  final ValueNotifier<_PersonPickerState> pickerStateNotifier;
  final Person? selectedPerson;
  final Function(Person?) onPersonSelected;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final String label;
  final String searchHint;
  final List<String>? personTypes;
  final VoidCallback? onAddNew;

  const _PersonPickerBottomSheet({
    required this.pickerStateNotifier,
    required this.selectedPerson,
    required this.onPersonSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.label,
    required this.searchHint,
    this.personTypes,
    this.onAddNew,
  });

  @override
  State<_PersonPickerBottomSheet> createState() => _PersonPickerBottomSheetState();
}

class _PersonPickerBottomSheetState extends State<_PersonPickerBottomSheet> {
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('[PersonPickerBottomSheet] build called');
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: widget.onSearchChanged,
                ),
              ),
              SizedBox(
                width: 40,
                height: kMinInteractiveDimension,
                child: ValueListenableBuilder<_PersonPickerState>(
                  valueListenable: widget.pickerStateNotifier,
                  builder: (context, pickerState, _) {
                    if (!pickerState.isSearching) {
                      return const SizedBox.shrink();
                    }
                    return const Padding(
                      padding: EdgeInsetsDirectional.only(start: 8, top: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ValueListenableBuilder<_PersonPickerState>(
              valueListenable: widget.pickerStateNotifier,
              builder: (context, pickerState, _) {
                print(
                  '[PersonPickerBottomSheet] list rebuild persons=${pickerState.persons.length} loading=${pickerState.isLoading}',
                );
                return _buildPersonsList(context, pickerState);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonsList(BuildContext context, _PersonPickerState pickerState) {
    print('[PersonPickerBottomSheet] _buildPersonsList called - persons count: ${pickerState.persons.length}, isLoading: ${pickerState.isLoading}, hasSearched: ${pickerState.hasSearched}');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (pickerState.isLoading) {
      print('[PersonPickerBottomSheet] Showing loading indicator');
      return const Center(child: CircularProgressIndicator());
    }

    if (pickerState.persons.isEmpty) {
      print('[PersonPickerBottomSheet] Showing empty state - hasSearched: ${pickerState.hasSearched}');
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
              pickerState.hasSearched 
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

    print('[PersonPickerBottomSheet] Building ListView with ${pickerState.persons.length} items');
    return ListView.builder(
      itemCount: pickerState.persons.length,
      itemBuilder: (context, index) {
        final person = pickerState.persons[index];
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
