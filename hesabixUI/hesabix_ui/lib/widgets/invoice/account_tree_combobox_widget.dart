import 'package:flutter/material.dart';
import '../../models/account_model.dart';
import '../../models/account_tree_node.dart';
import '../../services/account_service.dart';

/// ویجت انتخاب حساب با ساختار درختی
/// فقط حساب‌هایی که فرزند ندارند (leaf nodes) قابل انتخاب هستند
class AccountTreeComboboxWidget extends StatefulWidget {
  final int businessId;
  final Account? selectedAccount;
  final ValueChanged<Account?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  /// 'expense' یا 'income' برای فیلتر کردن درخت حساب‌ها
  final String? documentTypeFilter;

  const AccountTreeComboboxWidget({
    super.key,
    required this.businessId,
    this.selectedAccount,
    required this.onChanged,
    this.label = 'حساب',
    this.hintText = 'انتخاب حساب',
    this.isRequired = false,
    this.documentTypeFilter,
  });

  @override
  State<AccountTreeComboboxWidget> createState() => _AccountTreeComboboxWidgetState();
}

class _AccountTreeComboboxWidgetState extends State<AccountTreeComboboxWidget> {
  final AccountService _accountService = AccountService();
  final TextEditingController _searchController = TextEditingController();
  
  List<AccountTreeNode> _accountTree = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedAccount?.displayName ?? '';
    _loadAccountsTree();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountsTree() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _accountService.getAccountsTree(businessId: widget.businessId);
      final items = (response['items'] as List<dynamic>?)
          ?.map((item) => AccountTreeNode.fromJson(item as Map<String, dynamic>))
          .toList() ?? [];
      
      setState(() {
        _accountTree = items;
      });
    } catch (e) {
      setState(() {
        _accountTree = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
            : const Icon(Icons.account_tree),
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
      onTap: () => _showAccountTreeDialog(),
    );
  }

  void _showAccountTreeDialog() {
    showDialog(
      context: context,
      builder: (context) => _AccountTreeDialog(
        accountTree: _accountTree,
        selectedAccount: widget.selectedAccount,
        documentTypeFilter: widget.documentTypeFilter,
        onAccountSelected: (account) {
          widget.onChanged(account);
          _searchController.text = account?.displayName ?? '';
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// دیالوگ انتخاب حساب با ساختار درختی
class _AccountTreeDialog extends StatefulWidget {
  final List<AccountTreeNode> accountTree;
  final Account? selectedAccount;
  final ValueChanged<Account?> onAccountSelected;
  final String? documentTypeFilter;

  const _AccountTreeDialog({
    required this.accountTree,
    this.selectedAccount,
    required this.onAccountSelected,
    this.documentTypeFilter,
  });

  @override
  State<_AccountTreeDialog> createState() => _AccountTreeDialogState();
}

class _AccountTreeDialogState extends State<_AccountTreeDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expandedNodes = {};

  @override
  void initState() {
    super.initState();
    // باز کردن خودکار مسیر به حساب انتخاب شده
    if (widget.selectedAccount != null) {
      _expandToNode(widget.accountTree, widget.selectedAccount!.id!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// باز کردن مسیر تا یک نود خاص
  bool _expandToNode(List<AccountTreeNode> nodes, int targetId) {
    for (final node in nodes) {
      if (node.id == targetId) {
        return true;
      }
      if (node.children.isNotEmpty) {
        if (_expandToNode(node.children, targetId)) {
          setState(() {
            _expandedNodes.add(node.id);
          });
          return true;
        }
      }
    }
    return false;
  }

  /// فیلتر کردن درخت بر اساس جستجو
  List<AccountTreeNode> _filterTree(List<AccountTreeNode> nodes) {
    // ابتدا بر اساس نوع سند (expense/income) هرس می‌کنیم
    final prunedByType = _pruneByDocumentType(nodes, widget.documentTypeFilter);
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      return prunedByType;
    }

    final List<AccountTreeNode> filtered = [];
    final query = q;

    for (final node in prunedByType) {
      final matchesSearch = node.name.toLowerCase().contains(query) ||
          node.code.toLowerCase().contains(query);
      
      final filteredChildren = _filterTree(node.children);
      
      if (matchesSearch || filteredChildren.isNotEmpty) {
        filtered.add(AccountTreeNode(
          id: node.id,
          code: node.code,
          name: node.name,
          accountType: node.accountType,
          parentId: node.parentId,
          children: filteredChildren,
        ));
        
        // باز کردن خودکار نودهای دارای نتیجه جستجو
        if (filteredChildren.isNotEmpty) {
          _expandedNodes.add(node.id);
        }
      }
    }

    return filtered;
  }

  List<AccountTreeNode> _pruneByDocumentType(List<AccountTreeNode> nodes, String? docType) {
    if (docType != 'expense' && docType != 'income') return nodes;
    final List<AccountTreeNode> result = [];
    for (final node in nodes) {
      // ابتدا فرزندان را هرس کن
      final prunedChildren = _pruneByDocumentType(node.children, docType);
      final isLeaf = prunedChildren.isEmpty && node.children.isEmpty || (node.children.isEmpty);
      bool leafAllowed = true;
      if (isLeaf) {
        leafAllowed = _isLeafAllowedForDocType(node, docType!);
      }
      // نگه‌داشتن نود اگر خودش (به عنوان برگ) مجاز است یا فرزند مجاز دارد
      if ((isLeaf && leafAllowed) || (!isLeaf && prunedChildren.isNotEmpty)) {
        result.add(AccountTreeNode(
          id: node.id,
          code: node.code,
          name: node.name,
          accountType: node.accountType,
          parentId: node.parentId,
          level: node.level,
          children: prunedChildren,
        ));
      }
    }
    return result;
  }

  bool _isLeafAllowedForDocType(AccountTreeNode node, String docType) {
    final t = (node.accountType ?? '').toLowerCase();
    if (docType == 'expense') {
      // اولویت با accountType، سپس الگوی کد 7xxxx
      if (t.contains('expense')) return true;
      return node.code.startsWith('7');
    } else {
      if (t.contains('income') || t.contains('revenue')) return true;
      return node.code.startsWith('6');
    }
  }

  void _toggleExpanded(int nodeId) {
    setState(() {
      if (_expandedNodes.contains(nodeId)) {
        _expandedNodes.remove(nodeId);
      } else {
        _expandedNodes.add(nodeId);
      }
    });
  }

  void _expandAll(List<AccountTreeNode> nodes) {
    setState(() {
      for (final node in nodes) {
        if (node.children.isNotEmpty) {
          _expandedNodes.add(node.id);
          _expandAll(node.children);
        }
      }
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedNodes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
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
                  Icon(
                    Icons.account_tree,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'انتخاب حساب (درختی)',
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
            
            // فیلد جستجو و دکمه‌های باز/بسته کردن
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'جستجو',
                      hintText: 'نام یا کد حساب...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _expandAll(_filterTree(widget.accountTree)),
                        icon: const Icon(Icons.unfold_more, size: 18),
                        label: const Text('باز کردن همه'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _collapseAll,
                        icon: const Icon(Icons.unfold_less, size: 18),
                        label: const Text('بستن همه'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // درخت حساب‌ها — فقط این بخش با تایپ دوباره ساخته می‌شود؛ فوکوس روی جستجو حفظ می‌شود.
            Expanded(
              child: ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) {
                  final filteredTree = _filterTree(widget.accountTree);
                  final queryEmpty = _searchController.text.trim().isEmpty;
                  if (filteredTree.isEmpty) {
                    return Center(
                      child: Text(
                        queryEmpty ? 'هیچ حسابی یافت نشد' : 'نتیجه‌ای یافت نشد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(8),
                    children: _buildTreeNodes(filteredTree, 0),
                  );
                },
              ),
            ),
            
            const Divider(height: 1),
            
            // دکمه‌های پایین
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'فقط حساب‌های انتهایی قابل انتخاب هستند',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          widget.onAccountSelected(null);
                        },
                        child: const Text('پاک کردن'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTreeNodes(List<AccountTreeNode> nodes, int level) {
    final List<Widget> widgets = [];
    
    for (final node in nodes) {
      final isExpanded = _expandedNodes.contains(node.id);
      final hasChildren = node.children.isNotEmpty;
      final isSelected = widget.selectedAccount?.id == node.id;
      final isSelectable = node.isSelectable;
      
      widgets.add(
        _TreeNodeWidget(
          node: node,
          level: level,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          isSelected: isSelected,
          isSelectable: isSelectable,
          onTap: isSelectable
              ? () => widget.onAccountSelected(node.toAccount())
              : null,
          onToggleExpand: hasChildren ? () => _toggleExpanded(node.id) : null,
        ),
      );
      
      if (isExpanded && hasChildren) {
        widgets.addAll(_buildTreeNodes(node.children, level + 1));
      }
    }
    
    return widgets;
  }
}

/// ویجت نمایش یک نود در درخت
class _TreeNodeWidget extends StatelessWidget {
  final AccountTreeNode node;
  final int level;
  final bool isExpanded;
  final bool hasChildren;
  final bool isSelected;
  final bool isSelectable;
  final VoidCallback? onTap;
  final VoidCallback? onToggleExpand;

  const _TreeNodeWidget({
    required this.node,
    required this.level,
    required this.isExpanded,
    required this.hasChildren,
    required this.isSelected,
    required this.isSelectable,
    this.onTap,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = level * 24.0;
    
    return InkWell(
      onTap: isSelectable ? onTap : onToggleExpand,
      child: Container(
        padding: EdgeInsets.only(
          right: indent + 8,
          left: 8,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          border: Border(
            right: isSelected
                ? BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  )
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // آیکون باز/بسته کردن
            SizedBox(
              width: 24,
              child: hasChildren
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 20,
                      onPressed: onToggleExpand,
                      icon: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_left,
                        color: theme.colorScheme.onSurface,
                      ),
                    )
                  : null,
            ),
            
            const SizedBox(width: 8),
            
            // آیکون حساب
            Icon(
              hasChildren ? Icons.folder : Icons.receipt_long,
              size: 20,
              color: isSelectable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            
            const SizedBox(width: 12),
            
            // اطلاعات حساب
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: hasChildren ? FontWeight.bold : FontWeight.normal,
                      color: isSelectable
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'کد: ${node.code}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            
            // نشانگر انتخاب یا غیرفعال بودن
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 20,
              )
            else if (!isSelectable)
              Icon(
                Icons.lock_outline,
                color: theme.colorScheme.onSurfaceVariant,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
