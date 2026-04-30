import 'package:flutter/material.dart';
import '../../models/account_model.dart';
import '../../services/account_service.dart';

class AccountComboboxWidget extends StatefulWidget {
  final int businessId;
  final Account? selectedAccount;
  final ValueChanged<Account?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;

  const AccountComboboxWidget({
    super.key,
    required this.businessId,
    this.selectedAccount,
    required this.onChanged,
    this.label = 'حساب',
    this.hintText = 'انتخاب حساب',
    this.isRequired = false,
  });

  @override
  State<AccountComboboxWidget> createState() => _AccountComboboxWidgetState();
}

class _AccountComboboxWidgetState extends State<AccountComboboxWidget> {
  final AccountService _accountService = AccountService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Account> _accounts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedAccount?.displayName ?? '';
    _loadAccounts();
  }

  @override
  void didUpdateWidget(AccountComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAccount?.id != widget.selectedAccount?.id) {
      _searchController.text = widget.selectedAccount?.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _accountService.getAccounts(businessId: widget.businessId);
      final items = (response['items'] as List<dynamic>?)
          ?.map((item) => Account.fromJson(item as Map<String, dynamic>))
          .toList() ?? [];
      
      if (mounted) {
        setState(() {
          _accounts = items;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accounts = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        suffixIcon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
      readOnly: true,
      validator: widget.isRequired
          ? (value) {
              if (value == null || value.isEmpty) {
                return '${widget.label} الزامی است';
              }
              return null;
            }
          : null,
      onTap: () => _showAccountSelectionDialog(),
    );
  }

  void _showAccountSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => _AccountSelectionDialog(
        accounts: _accounts,
        selectedAccount: widget.selectedAccount,
        onAccountSelected: (account) {
          widget.onChanged(account);
          _searchController.text = account?.name ?? '';
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _AccountSelectionDialog extends StatefulWidget {
  final List<Account> accounts;
  final Account? selectedAccount;
  final ValueChanged<Account?> onAccountSelected;

  const _AccountSelectionDialog({
    required this.accounts,
    this.selectedAccount,
    required this.onAccountSelected,
  });

  @override
  State<_AccountSelectionDialog> createState() => _AccountSelectionDialogState();
}

class _AccountSelectionDialogState extends State<_AccountSelectionDialog> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Account> _computedFiltered() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.accounts;
    }
    return widget.accounts
        .where(
          (account) =>
              account.name.toLowerCase().contains(query) ||
              account.code.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          children: [
            // هدر دیالوگ
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'انتخاب حساب',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            
            // فیلد جستجو
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'جستجو',
                  hintText: 'نام یا کد حساب...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),

            // لیست حساب‌ها
            Expanded(
              child: ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) {
                  final filtered = _computedFiltered();
                  final queryEmpty = _searchController.text.trim().isEmpty;
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        queryEmpty ? 'هیچ حسابی یافت نشد' : 'نتیجه‌ای یافت نشد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final account = filtered[index];
                      final isSelected = widget.selectedAccount?.id == account.id;

                      return ListTile(
                        title: Text(account.name),
                        subtitle: Text('کد: ${account.code}'),
                        selected: isSelected,
                        onTap: () {
                          widget.onAccountSelected(account);
                        },
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            
            // دکمه‌های پایین
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      widget.onAccountSelected(null);
                      Navigator.pop(context);
                    },
                    child: const Text('پاک کردن انتخاب'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
