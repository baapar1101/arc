import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/product_model.dart';
import 'package:hesabix_ui/models/bank_account_model.dart';
import 'package:hesabix_ui/models/cash_register.dart';
import 'package:hesabix_ui/models/petty_cash.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/services/product_service.dart';
import 'package:hesabix_ui/services/bank_account_service.dart';
import 'package:hesabix_ui/services/cash_register_service.dart';
import 'package:hesabix_ui/services/petty_cash_service.dart';
import 'package:hesabix_ui/services/check_service.dart';

/// ویجت دینامیک برای انتخاب تفضیل بر اساس نوع حساب
/// 
/// این ویجت بر اساس نوع حساب انتخاب شده، ویجت انتخاب مناسب را نمایش می‌دهد:
/// - person: انتخاب شخص
/// - product: انتخاب کالا
/// - bank_account: انتخاب حساب بانکی
/// - cash_register: انتخاب صندوق
/// - petty_cash: انتخاب تنخواه
/// - check: انتخاب چک
class DetailSelectorWidget extends StatefulWidget {
  final Account? selectedAccount;
  final int businessId;
  final String? detailType; // person, product, bank_account, etc.
  final int? selectedDetailId;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String label;
  final bool isRequired;

  const DetailSelectorWidget({
    super.key,
    this.selectedAccount,
    required this.businessId,
    this.detailType,
    this.selectedDetailId,
    required this.onChanged,
    this.label = 'تفضیل',
    this.isRequired = false,
  });

  @override
  State<DetailSelectorWidget> createState() => _DetailSelectorWidgetState();
}

class _DetailSelectorWidgetState extends State<DetailSelectorWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSelectedItem();
  }

  @override
  void didUpdateWidget(DetailSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDetailId != oldWidget.selectedDetailId ||
        widget.detailType != oldWidget.detailType) {
      _loadSelectedItem();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// بارگذاری آیتم انتخاب شده
  Future<void> _loadSelectedItem() async {
    if (widget.selectedDetailId == null || widget.detailType == null) {
      setState(() {
        _controller.text = '';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      // بارگذاری بر اساس نوع تفضیل
      switch (widget.detailType) {
        case 'person':
          final service = PersonService();
          final person = await service.getPerson(widget.selectedDetailId!);
          _controller.text = person.aliasName;
          break;
          
        case 'product':
          final service = ProductService();
          final productData = await service.getProduct(
            businessId: widget.businessId,
            productId: widget.selectedDetailId!,
          );
          final product = Product.fromJson(productData);
          _controller.text = product.displayName;
          break;

        case 'bank_account':
          final service = BankAccountService();
          final bankAccount = await service.getById(widget.selectedDetailId!);
          _controller.text = bankAccount.name;
          break;

        case 'cash_register':
          final service = CashRegisterService();
          final cashRegister = await service.getById(widget.selectedDetailId!);
          _controller.text = cashRegister.name;
          break;

        case 'petty_cash':
          final service = PettyCashService();
          final pettyCash = await service.getById(widget.selectedDetailId!);
          _controller.text = pettyCash.name;
          break;

        case 'check':
          final service = CheckService();
          final checkData = await service.getById(widget.selectedDetailId!);
          _controller.text = 'چک شماره ${checkData['check_number'] ?? widget.selectedDetailId}';
          break;

        default:
          _controller.text = 'ID: ${widget.selectedDetailId}';
      }
    } catch (e) {
      _controller.text = '';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // اگر حساب انتخاب نشده یا نیاز به تفضیل ندارد
    if (widget.selectedAccount == null || widget.detailType == null) {
      return TextFormField(
        enabled: false,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'ابتدا حساب را انتخاب کنید',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.lock),
        ),
      );
    }

    return TextFormField(
      controller: _controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: '${widget.label} (${_getDetailTypeLabel()})',
        hintText: 'انتخاب ${_getDetailTypeLabel()}',
        border: const OutlineInputBorder(),
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
      ),
      validator: widget.isRequired
          ? (value) {
              if (value == null || value.isEmpty) {
                return '${_getDetailTypeLabel()} الزامی است';
              }
              return null;
            }
          : null,
      onTap: () => _showSelectionDialog(),
    );
  }

  /// نمایش دیالوگ انتخاب بر اساس نوع تفضیل
  Future<void> _showSelectionDialog() async {
    switch (widget.detailType) {
      case 'person':
        await _showPersonDialog();
        break;
      case 'product':
        await _showProductDialog();
        break;
      case 'bank_account':
        await _showBankAccountDialog();
        break;
      case 'cash_register':
        await _showCashRegisterDialog();
        break;
      case 'petty_cash':
        await _showPettyCashDialog();
        break;
      case 'check':
        await _showCheckDialog();
        break;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('انتخاب ${_getDetailTypeLabel()} هنوز پیاده‌سازی نشده است'),
            ),
          );
        }
    }
  }

  /// دیالوگ انتخاب شخص
  Future<void> _showPersonDialog() async {
    final service = PersonService();
    
    try {
      setState(() => _isLoading = true);
      final response = await service.getPersons(
        businessId: widget.businessId,
        page: 1,
        limit: 100,
      );
      
      if (!mounted) return;
      
      final personsData = response['items'] as List<dynamic>;
      final persons = personsData
          .map((json) => Person.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final selected = await showDialog<Person>(
        context: context,
        builder: (context) => _PersonSelectionDialog(persons: persons),
      );

      if (selected != null) {
        setState(() {
          _controller.text = selected.aliasName;
        });
        
        widget.onChanged({
          'person_id': selected.id,
          'person_name': selected.aliasName,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری اشخاص: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دیالوگ انتخاب کالا
  Future<void> _showProductDialog() async {
    final service = ProductService();
    
    try {
      setState(() => _isLoading = true);
      final productsData = await service.searchProducts(
        businessId: widget.businessId,
        limit: 100,
      );
      
      if (!mounted) return;
      
      final products = productsData
          .map((json) => Product.fromJson(json))
          .toList();
      
      final selected = await showDialog<Product>(
        context: context,
        builder: (context) => _ProductSelectionDialog(products: products),
      );

      if (selected != null) {
        setState(() {
          _controller.text = selected.displayName;
        });
        
        widget.onChanged({
          'product_id': selected.id,
          'product_name': selected.name,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری کالاها: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دیالوگ انتخاب حساب بانکی
  Future<void> _showBankAccountDialog() async {
    final service = BankAccountService();
    
    try {
      setState(() => _isLoading = true);
      final response = await service.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      
      if (!mounted) return;
      
      // دسترسی به data.items
      final dataMap = response['data'] as Map<String, dynamic>?;
      final accountsData = (dataMap?['items'] ?? []) as List<dynamic>;
      final accounts = accountsData
          .map((json) => BankAccount.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final selected = await showDialog<BankAccount>(
        context: context,
        builder: (context) => _BankAccountSelectionDialog(accounts: accounts),
      );

      if (selected != null) {
        setState(() {
          _controller.text = selected.name;
        });
        
        widget.onChanged({
          'bank_account_id': selected.id,
          'bank_account_name': selected.name,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری حساب‌های بانکی: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دیالوگ انتخاب صندوق
  Future<void> _showCashRegisterDialog() async {
    final service = CashRegisterService();
    
    try {
      setState(() => _isLoading = true);
      final response = await service.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      
      if (!mounted) return;
      
      // دسترسی به data.items
      final dataMap = response['data'] as Map<String, dynamic>?;
      final registersData = (dataMap?['items'] ?? []) as List<dynamic>;
      final registers = registersData
          .map((json) => CashRegister.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final selected = await showDialog<CashRegister>(
        context: context,
        builder: (context) => _CashRegisterSelectionDialog(registers: registers),
      );

      if (selected != null) {
        setState(() {
          _controller.text = selected.name;
        });
        
        widget.onChanged({
          'cash_register_id': selected.id,
          'cash_register_name': selected.name,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری صندوق‌ها: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دیالوگ انتخاب تنخواه
  Future<void> _showPettyCashDialog() async {
    final service = PettyCashService();
    
    try {
      setState(() => _isLoading = true);
      final response = await service.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      
      if (!mounted) return;
      
      // دسترسی به data.items
      final dataMap = response['data'] as Map<String, dynamic>?;
      final cashesData = (dataMap?['items'] ?? []) as List<dynamic>;
      final cashes = cashesData
          .map((json) => PettyCash.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final selected = await showDialog<PettyCash>(
        context: context,
        builder: (context) => _PettyCashSelectionDialog(cashes: cashes),
      );

      if (selected != null) {
        setState(() {
          _controller.text = selected.name;
        });
        
        widget.onChanged({
          'petty_cash_id': selected.id,
          'petty_cash_name': selected.name,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری تنخواه‌ها: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دیالوگ انتخاب چک
  Future<void> _showCheckDialog() async {
    final service = CheckService();
    
    try {
      setState(() => _isLoading = true);
      final response = await service.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      
      if (!mounted) return;
      
      // دسترسی به data.items
      final dataMap = response['data'] as Map<String, dynamic>?;
      final checksData = (dataMap?['items'] ?? []) as List<dynamic>;
      final checks = checksData
          .map((json) => Map<String, dynamic>.from(json as Map))
          .toList();
      
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _CheckSelectionDialog(checks: checks),
      );

      if (selected != null) {
        setState(() {
          _controller.text = 'چک شماره ${selected['check_number'] ?? selected['id']}';
        });
        
        widget.onChanged({
          'check_id': selected['id'],
          'check_number': selected['check_number'],
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری چک‌ها: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// دریافت برچسب فارسی نوع تفضیل
  String _getDetailTypeLabel() {
    switch (widget.detailType) {
      case 'person':
        return 'شخص';
      case 'product':
        return 'کالا';
      case 'bank_account':
        return 'حساب بانکی';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواه';
      case 'check':
        return 'چک';
      default:
        return 'تفصیل';
    }
  }
}


/// دیالوگ انتخاب شخص
class _PersonSelectionDialog extends StatefulWidget {
  final List<Person> persons;

  const _PersonSelectionDialog({required this.persons});

  @override
  State<_PersonSelectionDialog> createState() => _PersonSelectionDialogState();
}

class _PersonSelectionDialogState extends State<_PersonSelectionDialog> {
  List<Person> _filteredPersons = [];

  @override
  void initState() {
    super.initState();
    _filteredPersons = widget.persons;
  }

  void _filterPersons(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPersons = widget.persons;
      } else {
        _filteredPersons = widget.persons
            .where((person) =>
                person.aliasName.toLowerCase().contains(query.toLowerCase()) ||
                (person.code?.toString().toLowerCase().contains(query.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب شخص',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterPersons,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredPersons.length,
                itemBuilder: (context, index) {
                  final person = _filteredPersons[index];
                  return ListTile(
                    title: Text(person.aliasName),
                    subtitle: Text('کد: ${person.code ?? "-"}'),
                    onTap: () => Navigator.pop(context, person),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب کالا
class _ProductSelectionDialog extends StatefulWidget {
  final List<Product> products;

  const _ProductSelectionDialog({required this.products});

  @override
  State<_ProductSelectionDialog> createState() => _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = widget.products;
      } else {
        _filteredProducts = widget.products
            .where((product) =>
                product.name.toLowerCase().contains(query.toLowerCase()) ||
                (product.code?.toLowerCase().contains(query.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب کالا',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterProducts,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text('کد: ${product.code ?? "-"}'),
                    onTap: () => Navigator.pop(context, product),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب حساب بانکی
class _BankAccountSelectionDialog extends StatefulWidget {
  final List<BankAccount> accounts;

  const _BankAccountSelectionDialog({required this.accounts});

  @override
  State<_BankAccountSelectionDialog> createState() => _BankAccountSelectionDialogState();
}

class _BankAccountSelectionDialogState extends State<_BankAccountSelectionDialog> {
  List<BankAccount> _filteredAccounts = [];

  @override
  void initState() {
    super.initState();
    _filteredAccounts = widget.accounts;
  }

  void _filterAccounts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredAccounts = widget.accounts;
      } else {
        _filteredAccounts = widget.accounts
            .where((acc) =>
                acc.name.toLowerCase().contains(query.toLowerCase()) ||
                (acc.accountNumber?.toLowerCase().contains(query.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب حساب بانکی',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterAccounts,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredAccounts.length,
                itemBuilder: (context, index) {
                  final account = _filteredAccounts[index];
                  return ListTile(
                    title: Text(account.name),
                    subtitle: Text('شماره حساب: ${account.accountNumber ?? "-"}'),
                    onTap: () => Navigator.pop(context, account),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب صندوق
class _CashRegisterSelectionDialog extends StatefulWidget {
  final List<CashRegister> registers;

  const _CashRegisterSelectionDialog({required this.registers});

  @override
  State<_CashRegisterSelectionDialog> createState() => _CashRegisterSelectionDialogState();
}

class _CashRegisterSelectionDialogState extends State<_CashRegisterSelectionDialog> {
  List<CashRegister> _filteredRegisters = [];

  @override
  void initState() {
    super.initState();
    _filteredRegisters = widget.registers;
  }

  void _filterRegisters(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredRegisters = widget.registers;
      } else {
        _filteredRegisters = widget.registers
            .where((reg) =>
                reg.name.toLowerCase().contains(query.toLowerCase()) ||
                (reg.code?.toLowerCase().contains(query.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب صندوق',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterRegisters,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredRegisters.length,
                itemBuilder: (context, index) {
                  final register = _filteredRegisters[index];
                  return ListTile(
                    title: Text(register.name),
                    subtitle: Text('کد: ${register.code ?? "-"}'),
                    onTap: () => Navigator.pop(context, register),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب تنخواه
class _PettyCashSelectionDialog extends StatefulWidget {
  final List<PettyCash> cashes;

  const _PettyCashSelectionDialog({required this.cashes});

  @override
  State<_PettyCashSelectionDialog> createState() => _PettyCashSelectionDialogState();
}

class _PettyCashSelectionDialogState extends State<_PettyCashSelectionDialog> {
  List<PettyCash> _filteredCashes = [];

  @override
  void initState() {
    super.initState();
    _filteredCashes = widget.cashes;
  }

  void _filterCashes(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCashes = widget.cashes;
      } else {
        _filteredCashes = widget.cashes
            .where((cash) =>
                cash.name.toLowerCase().contains(query.toLowerCase()) ||
                (cash.code?.toLowerCase().contains(query.toLowerCase()) ?? false))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب تنخواه',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterCashes,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredCashes.length,
                itemBuilder: (context, index) {
                  final cash = _filteredCashes[index];
                  return ListTile(
                    title: Text(cash.name),
                    subtitle: Text('کد: ${cash.code ?? "-"}'),
                    onTap: () => Navigator.pop(context, cash),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب چک
class _CheckSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> checks;

  const _CheckSelectionDialog({required this.checks});

  @override
  State<_CheckSelectionDialog> createState() => _CheckSelectionDialogState();
}

class _CheckSelectionDialogState extends State<_CheckSelectionDialog> {
  List<Map<String, dynamic>> _filteredChecks = [];

  @override
  void initState() {
    super.initState();
    _filteredChecks = widget.checks;
  }

  void _filterChecks(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChecks = widget.checks;
      } else {
        _filteredChecks = widget.checks
            .where((check) {
              final checkNumber = check['check_number']?.toString() ?? '';
              return checkNumber.toLowerCase().contains(query.toLowerCase());
            })
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'انتخاب چک',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'جستجو بر اساس شماره چک',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterChecks,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredChecks.length,
                itemBuilder: (context, index) {
                  final check = _filteredChecks[index];
                  return ListTile(
                    title: Text('چک شماره ${check['check_number'] ?? check['id']}'),
                    subtitle: Text('مبلغ: ${check['amount'] ?? "-"}'),
                    onTap: () => Navigator.pop(context, check),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
  }
}
