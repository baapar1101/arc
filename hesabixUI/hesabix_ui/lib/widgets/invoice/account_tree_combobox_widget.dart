import 'package:flutter/material.dart';
import '../../models/account_tree_node.dart';
import '../../services/account_service.dart';

class AccountTreeComboboxWidget extends StatefulWidget {
  final int businessId;
  final AccountTreeNode? selectedAccount;
  final ValueChanged<AccountTreeNode?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;

  const AccountTreeComboboxWidget({
    super.key,
    required this.businessId,
    this.selectedAccount,
    required this.onChanged,
    this.label = 'حساب',
    this.hintText = 'انتخاب حساب',
    this.isRequired = false,
  });

  @override
  State<AccountTreeComboboxWidget> createState() => _AccountTreeComboboxWidgetState();
}

class _AccountTreeComboboxWidgetState extends State<AccountTreeComboboxWidget> {
  final AccountService _accountService = AccountService();
  List<AccountTreeNode> _accounts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _accountService.getAccountsTree(businessId: widget.businessId);
      final items = (response['items'] as List<dynamic>?)
          ?.map((item) => AccountTreeNode.fromJson(item as Map<String, dynamic>))
          .toList() ?? [];
      
      setState(() {
        _accounts = items;
      });
    } catch (e) {
      print('خطا در لود کردن حساب‌ها: $e');
      setState(() {
        _accounts = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // لیبل
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.isRequired)
                  Text(
                    ' *',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        
        // فیلد انتخاب
        InkWell(
          onTap: _isLoading ? null : _showAccountDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.selectedAccount?.toString() ?? widget.hintText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: widget.selectedAccount != null
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.arrow_drop_down,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AccountSelectionDialog(
        accounts: _accounts,
        selectedAccount: widget.selectedAccount,
        onAccountSelected: (account) {
          widget.onChanged(account);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class AccountSelectionDialog extends StatefulWidget {
  final List<AccountTreeNode> accounts;
  final AccountTreeNode? selectedAccount;
  final ValueChanged<AccountTreeNode?> onAccountSelected;

  const AccountSelectionDialog({
    super.key,
    required this.accounts,
    this.selectedAccount,
    required this.onAccountSelected,
  });

  @override
  State<AccountSelectionDialog> createState() => _AccountSelectionDialogState();
}

class _AccountSelectionDialogState extends State<AccountSelectionDialog> {
  String _searchQuery = '';
  List<AccountTreeNode> _filteredAccounts = [];
  final Set<int> _expandedNodes = <int>{};

  @override
  void initState() {
    super.initState();
    _filteredAccounts = widget.accounts;
    // همه گره‌های سطح اول را به صورت پیش‌فرض باز کن
    _expandedNodes.addAll(widget.accounts.map((account) => account.id));
  }

  void _filterAccounts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredAccounts = widget.accounts;
      } else {
        _filteredAccounts = widget.accounts
            .expand((account) => account.searchAccounts(query))
            .where((account) => !account.hasChildren) // فقط حساب‌های بدون فرزند
            .toList();
      }
    });
  }

  void _expandAll() {
    setState(() {
      _expandedNodes.clear();
      // همه گره‌هایی که فرزند دارند را باز کن
      for (final account in widget.accounts) {
        _addAllExpandableNodes(account);
      }
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedNodes.clear();
    });
  }

  void _addAllExpandableNodes(AccountTreeNode account) {
    if (account.hasChildren) {
      _expandedNodes.add(account.id);
      for (final child in account.children) {
        _addAllExpandableNodes(child);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        margin: const EdgeInsets.all(16),
        child: Column(
          children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: theme.colorScheme.onPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'انتخاب حساب',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
            
            // جستجو و دکمه‌های کنترل
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'جستجو در حساب‌ها...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _filterAccounts,
                  ),
                  if (_searchQuery.isEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _expandAll,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('همه را باز کن'),
                        ),
                        TextButton.icon(
                          onPressed: _collapseAll,
                          icon: const Icon(Icons.expand_less),
                          label: const Text('همه را ببند'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            // لیست حساب‌ها
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: _searchQuery.isEmpty
                    ? _buildTreeView()
                    : _buildSearchResults(),
              ),
            ),
            
            // دکمه‌ها
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  if (widget.selectedAccount != null)
                    TextButton(
                      onPressed: () {
                        widget.onAccountSelected(null);
                        Navigator.pop(context);
                      },
                      child: const Text('حذف انتخاب'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeView() {
    return ListView.builder(
      itemCount: widget.accounts.length,
      itemBuilder: (context, index) {
        return _buildAccountNode(widget.accounts[index], 0);
      },
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredAccounts.length,
      itemBuilder: (context, index) {
        final account = _filteredAccounts[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor: account.id == widget.selectedAccount?.id
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            leading: Icon(
              Icons.account_balance_wallet,
              color: account.id == widget.selectedAccount?.id
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(account.name),
            subtitle: Text('کد: ${account.code}'),
            trailing: account.id == widget.selectedAccount?.id
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: () => widget.onAccountSelected(account),
          ),
        );
      },
    );
  }

  Widget _buildAccountNode(AccountTreeNode account, int level) {
    final theme = Theme.of(context);
    final isSelected = account.id == widget.selectedAccount?.id;
    final canSelect = !account.hasChildren;
    final isExpanded = _expandedNodes.contains(account.id);
    
    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16 + (level * 24),
              vertical: 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor: isSelected 
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            leading: account.hasChildren
                ? IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedNodes.remove(account.id);
                        } else {
                          _expandedNodes.add(account.id);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  )
                : Icon(
                    Icons.account_balance_wallet,
                    color: canSelect
                        ? (isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)
                        : theme.colorScheme.outline,
                  ),
            title: Text(
              account.name,
              style: TextStyle(
                color: canSelect
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
                fontWeight: account.hasChildren ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              'کد: ${account.code}',
              style: TextStyle(
                color: canSelect
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.outline,
              ),
            ),
            trailing: isSelected
                ? Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                  )
                : null,
            onTap: canSelect ? () => widget.onAccountSelected(account) : null,
          ),
        ),
        // نمایش فرزندان فقط اگر گره باز باشد
        if (account.hasChildren && isExpanded)
          ...account.children.map((child) => _buildAccountNode(child, level + 1)),
        // خط جداکننده بین حساب‌های مختلف (فقط برای سطح اول)
        if (level == 0 && account != widget.accounts.last)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
      ],
    );
  }
}
