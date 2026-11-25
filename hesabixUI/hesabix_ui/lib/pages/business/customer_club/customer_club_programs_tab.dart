import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth_store.dart';
import '../../../models/person_model.dart';
import '../../../services/customer_club_service.dart';
import '../../../services/product_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';

/// Reward catalogue, one-shot campaigns, and member communication preferences.
class CustomerClubProgramsTab extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CustomerClubProgramsTab({super.key, required this.businessId, required this.authStore});

  @override
  State<CustomerClubProgramsTab> createState() => _CustomerClubProgramsTabState();
}

class _CustomerClubProgramsTabState extends State<CustomerClubProgramsTab> {
  final CustomerClubService _service = CustomerClubService();
  final TextEditingController _referrerCodeCtl = TextEditingController();
  String _ownReferralCode = '';
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _vouchers = [];
  Person? _person;
  bool _smsConsent = false;
  bool _emailConsent = false;
  bool _loading = true;
  bool _saving = false;
  bool _canManage = false;
  bool _canRedeem = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String s(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _canManage = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'manage');
    _canRedeem = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'redeem');
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.listRewards(businessId: widget.businessId),
        _service.listCampaigns(businessId: widget.businessId),
        _service.listVouchers(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _rewards = values[0] as List<Map<String, dynamic>>;
        _campaigns = values[1] as List<Map<String, dynamic>>;
        _vouchers = values[2] as List<Map<String, dynamic>>;
      });
      final personId = _person?.id;
      if (personId != null) await _loadMember(personId);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMember(int personId) async {
    try {
      final profile = await _service.getMemberProfile(businessId: widget.businessId, personId: personId);
      final vouchers = await _service.listVouchers(businessId: widget.businessId, personId: personId);
      if (!mounted) return;
      setState(() {
        _smsConsent = profile['sms_consent'] == true;
        _emailConsent = profile['email_consent'] == true;
        _ownReferralCode = (profile['referral_code'] ?? '').toString();
        _vouchers = vouchers;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _smsConsent = false;
        _emailConsent = false;
      });
    }
  }

  Future<void> _saveConsent() async {
    final person = _person;
    final personId = person?.id;
    if (personId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final member = await _service.updateMemberConsent(
        businessId: widget.businessId,
        personId: personId,
        payload: {'sms_consent': _smsConsent, 'email_consent': _emailConsent, if (_referrerCodeCtl.text.trim().isNotEmpty) 'referral_code': _referrerCodeCtl.text.trim()},
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: s('تنظیم رضایت ارتباطی ذخیره شد', 'Communication preferences saved'));
      final code = member['referral_code']?.toString();
      if (code?.isNotEmpty == true) _showInfo(s('کد معرفی', 'Referral code'), code!);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _redeemSelectedReward() async {
    final person = _person;
    final personId = person?.id;
    if (personId == null || _rewards.isEmpty) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s('انتخاب پاداش', 'Choose a reward')),
        children: [
          for (final reward in _rewards.where((e) => e['active'] == true))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reward),
              child: Text('${reward['name']} · ${reward['points_cost']} ${s('امتیاز', 'points')}'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final voucher = await _service.redeemReward(
        businessId: widget.businessId,
        personId: personId,
        rewardId: int.parse('${selected['id']}'),
      );
      if (!mounted) return;
      await _load();
      _showInfo(s('کد پاداش صادر شد', 'Reward issued'), '${voucher['code']}');
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createReward() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final cost = TextEditingController(text: '100');
    final value = TextEditingController(text: '10000');
    final days = TextEditingController(text: '30');
    List<Map<String, dynamic>> products = [];
    try {
      products = await ProductService().searchProducts(businessId: widget.businessId, limit: 100);
    } catch (_) {}
    String type = 'discount_amount';
    int? productId;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(s('جایزهٔ جدید', 'New reward')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s('نام جایزه', 'Reward name'))),
              TextField(controller: description, decoration: InputDecoration(labelText: s('توضیحات', 'Description'))),
              DropdownButtonFormField<String>(
                value: type,
                decoration: InputDecoration(labelText: s('نوع پاداش', 'Reward type')),
                items: [
                  DropdownMenuItem(value: 'discount_amount', child: Text(s('تخفیف مبلغی', 'Fixed discount'))),
                  DropdownMenuItem(value: 'discount_percent', child: Text(s('تخفیف درصدی', 'Percentage discount'))),
                  DropdownMenuItem(value: 'wallet_credit', child: Text(s('اعتبار هدیه', 'Gift credit'))),
                  DropdownMenuItem(value: 'free_product', child: Text(s('محصول رایگان', 'Free product'))),
                ],
                onChanged: (v) => setDialogState(() {
                  type = v ?? type;
                  if (type == 'free_product' && productId == null && products.isNotEmpty) {
                    productId = int.tryParse('${products.first['id']}');
                  }
                }),
              ),
              if (type == 'free_product') DropdownButtonFormField<int>(
                value: productId,
                decoration: InputDecoration(labelText: s('کالای مشمول', 'Eligible product')),
                items: products.map((product) => DropdownMenuItem<int>(
                  value: int.tryParse('${product['id']}'),
                  child: Text('${product['name'] ?? product['title'] ?? product['id']}'),
                )).where((item) => item.value != null).toList(),
                onChanged: (v) => setDialogState(() => productId = v),
              ),
              TextField(controller: cost, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('هزینه به امتیاز', 'Points cost'))),
              TextField(controller: value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('ارزش/درصد پاداش', 'Reward value / percent'))),
              TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('اعتبار کد (روز)', 'Voucher validity (days)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s('لغو', 'Cancel'))),
            FilledButton(onPressed: () {
              if (type == 'free_product' && productId == null) {
                SnackBarHelper.showError(context, message: s('ابتدا کالا را انتخاب کنید.', 'Select a product first.'));
                return;
              }
              Navigator.pop(dialogContext, {
              'name': name.text.trim(), 'description': description.text.trim(), 'reward_type': type,
              'points_cost': num.tryParse(cost.text) ?? 0, 'value': num.tryParse(value.text) ?? 0,
              if (type == 'free_product' && productId != null) 'product_id': productId,
              'valid_days': int.tryParse(days.text), 'active': true,
            });
            }, child: Text(s('ذخیره', 'Save'))),
          ],
        ),
      ),
    );
    name.dispose(); description.dispose(); cost.dispose(); value.dispose(); days.dispose();
    if (result == null) return;
    try {
      await _service.saveReward(businessId: widget.businessId, payload: result);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createCampaign() async {
    final name = TextEditingController();
    final rfm = TextEditingController();
    final minBalance = TextEditingController();
    final minRecency = TextEditingController();
    final maxRecency = TextEditingController();
    final minPurchase = TextEditingController();
    final amount = TextEditingController(text: '50');
    final message = TextEditingController(text: s('{name} عزیز، پاداش باشگاه شما آماده است: {voucher_code}', 'Hi {name}, your loyalty reward is ready: {voucher_code}'));
    String rewardType = 'points';
    String trigger = 'manual';
    String channel = 'none';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(s('کمپین وفاداری', 'Loyalty campaign')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s('نام کمپین', 'Campaign name'))),
              DropdownButtonFormField<String>(
                value: trigger,
                decoration: InputDecoration(labelText: s('زمان اجرای کمپین', 'Campaign trigger')),
                items: [
                  DropdownMenuItem(value: 'manual', child: Text(s('اجرای دستی', 'Manual run'))),
                  DropdownMenuItem(value: 'purchase', child: Text(s('پس از خرید واجد شرایط', 'Qualifying purchase'))),
                  DropdownMenuItem(value: 'inactivity', child: Text(s('کمپین خودکار بازگشت', 'Automated win-back'))),
                ],
                onChanged: (v) => setDialogState(() => trigger = v ?? trigger),
              ),
              TextField(controller: rfm, decoration: InputDecoration(labelText: s('بخش RFM (اختیاری)', 'RFM segment (optional)'))),
              TextField(controller: minBalance, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('حداقل مانده امتیاز', 'Minimum points balance'))),
              if (trigger == 'inactivity') TextField(controller: minRecency, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s('حداقل روز از آخرین خرید', 'Minimum days since last purchase'))),
              TextField(controller: maxRecency, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('حداکثر روز از خرید', 'Maximum days since purchase'))),
              if (trigger == 'purchase') TextField(controller: minPurchase, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s('حداقل مبلغ این خرید', 'Minimum purchase amount'))),
              DropdownButtonFormField<String>(
                value: rewardType,
                decoration: InputDecoration(labelText: s('پاداش کمپین', 'Campaign reward')),
                items: [
                  DropdownMenuItem(value: 'points', child: Text(s('امتیاز', 'Points'))),
                  DropdownMenuItem(value: 'discount_amount', child: Text(s('کد تخفیف مبلغی', 'Fixed-discount voucher'))),
                  DropdownMenuItem(value: 'discount_percent', child: Text(s('کد تخفیف درصدی', 'Percentage voucher'))),
                ],
                onChanged: (v) => setDialogState(() => rewardType = v ?? rewardType),
              ),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('مقدار پاداش', 'Reward amount'))),
              DropdownButtonFormField<String>(
                value: channel,
                decoration: InputDecoration(labelText: s('کانال پیام', 'Message channel')),
                items: [
                  DropdownMenuItem(value: 'none', child: Text(s('فقط اعطای پاداش', 'Reward only'))),
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                ],
                onChanged: (v) => setDialogState(() => channel = v ?? channel),
              ),
              if (channel != 'none') ...[
                TextField(controller: message, maxLines: 3, decoration: InputDecoration(labelText: s('متن پیام', 'Message template'))),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(channel == 'sms'
                    ? s('ارسال فقط برای مشتریانی انجام می‌شود که رضایت پیامکی ثبت کرده‌اند.', 'Messages are sent only to customers with recorded SMS consent.')
                    : s('ارسال فقط برای مشتریانی انجام می‌شود که رضایت ایمیلی و نشانی ایمیل ثبت‌شده دارند.', 'Messages are sent only to customers with email consent and a saved email address.'), style: Theme.of(context).textTheme.bodySmall)),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(s('متغیرها: {name}، {points}، {voucher_code}', 'Variables: {name}, {points}, {voucher_code}'), style: Theme.of(context).textTheme.bodySmall)),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final filters = <String, dynamic>{
                      if (rfm.text.trim().isNotEmpty) 'rfm_segment': rfm.text.trim(),
                      if (minBalance.text.trim().isNotEmpty) 'min_balance_points': num.tryParse(minBalance.text),
                      if (maxRecency.text.trim().isNotEmpty) 'max_recency_days': int.tryParse(maxRecency.text),
                      if (minRecency.text.trim().isNotEmpty) 'min_recency_days': int.tryParse(minRecency.text),
                      if (channel == 'sms') 'sms_consent': true,
                      if (channel == 'email') 'email_consent': true,
                    }..removeWhere((key, value) => value == null);
                    final preview = await _service.previewSegment(businessId: widget.businessId, filters: filters);
                    if (dialogContext.mounted) showDialog<void>(context: dialogContext, builder: (ctx) => AlertDialog(
                      title: Text(s('پیش‌نمایش مخاطبان', 'Audience preview')),
                      content: Text('${s('تعداد مشمولان', 'Eligible members')}: ${preview['total'] ?? 0}'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s('بستن', 'Close')))],
                    ));
                  } catch (e) {
                    if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                },
                icon: const Icon(Icons.groups_outlined), label: Text(s('پیش‌نمایش مخاطبان', 'Preview audience')),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyAudienceCsv(<String, dynamic>{
                  if (rfm.text.trim().isNotEmpty) 'rfm_segment': rfm.text.trim(),
                  if (minBalance.text.trim().isNotEmpty) 'min_balance_points': num.tryParse(minBalance.text),
                  if (maxRecency.text.trim().isNotEmpty) 'max_recency_days': int.tryParse(maxRecency.text),
                  if (minRecency.text.trim().isNotEmpty) 'min_recency_days': int.tryParse(minRecency.text),
                  if (channel == 'sms') 'sms_consent': true,
                  if (channel == 'email') 'email_consent': true,
                }..removeWhere((key, value) => value == null)),
                icon: const Icon(Icons.content_copy_outlined), label: Text(s('کپی خروجی CSV', 'Copy CSV export')),
              ),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s('لغو', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {
              'name': name.text.trim(), 'trigger_type': trigger, 'min_purchase_amount': num.tryParse(minPurchase.text), 'segment': <String, dynamic>{
                if (rfm.text.trim().isNotEmpty) 'rfm_segment': rfm.text.trim(),
                if (minBalance.text.trim().isNotEmpty) 'min_balance_points': num.tryParse(minBalance.text),
                if (maxRecency.text.trim().isNotEmpty) 'max_recency_days': int.tryParse(maxRecency.text),
                if (minRecency.text.trim().isNotEmpty) 'min_recency_days': int.tryParse(minRecency.text),
                if (channel == 'sms') 'sms_consent': true,
                if (channel == 'email') 'email_consent': true,
              }..removeWhere((key, value) => value == null),
              'reward_type': rewardType, 'reward_value': num.tryParse(amount.text) ?? 0,
              'channel': channel, 'message_template': message.text.trim(), 'status': 'active',
              'starts_at': DateTime.now().toUtc().toIso8601String(),
            }), child: Text(s('فعال و ذخیره', 'Save active'))),
          ],
        ),
      ),
    );
    name.dispose(); rfm.dispose(); minBalance.dispose(); minRecency.dispose(); maxRecency.dispose(); minPurchase.dispose(); amount.dispose(); message.dispose();
    if (result == null) return;
    try {
      await _service.saveCampaign(businessId: widget.businessId, payload: result);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _copyAudienceCsv(Map<String, dynamic> filters) async {
    try {
      final data = await _service.exportSegment(businessId: widget.businessId, filters: filters);
      final items = data['items'] is List ? (data['items'] as List).whereType<Map>().toList() : <Map>[];
      final rows = <String>['person_id,name,mobile,balance_points,segment,recency_days,frequency_count'];
      String csv(String value) => '"${value.replaceAll('"', '""')}"';
      for (final item in items) {
        rows.add([
          '${item['person_id'] ?? ''}', csv('${item['name'] ?? ''}'), csv('${item['mobile'] ?? ''}'),
          '${item['balance_points'] ?? 0}', csv('${item['segment'] ?? ''}'),
          '${item['recency_days'] ?? ''}', '${item['frequency_count'] ?? ''}',
        ].join(','));
      }
      await Clipboard.setData(ClipboardData(text: rows.join('\n')));
      if (!mounted) return;
      final suffix = data['truncated'] == true ? s(' (خروجی محدود شده است)', ' (export is truncated)') : '';
      SnackBarHelper.showSuccess(context, message: '${s('مخاطبان', 'Audience')}: ${data['total'] ?? items.length}$suffix');
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _runCampaign(Map<String, dynamic> campaign) async {
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(s('اجرای کمپین', 'Run campaign')),
      content: Text(s('پاداش برای مخاطبان واجد شرایط صادر می‌شود. اگر پیامک فعال باشد، برای افراد دارای رضایت ارسال خواهد شد.',
          'Rewards will be issued to eligible members. SMS will be sent only to members who consented.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('لغو', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('اجرا', 'Run')))],
    ));
    if (approved != true) return;
    try {
      final result = await _service.runCampaign(businessId: widget.businessId, campaignId: int.parse('${campaign['id']}'));
      if (!mounted) return;
      await _load();
      _showInfo(s('نتیجهٔ اجرا', 'Run results'),
          '${s('مخاطب', 'Audience')}: ${result['audience_size']} · ${s('پاداش', 'Rewards')}: ${result['rewards_issued']} · SMS: ${result['messages_sent']} · ${s('خطا', 'Errors')}: ${result['errors']}');
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _showInfo(String title, String body) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: SelectableText(body),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s('بستن', 'Close')))]));
  }

  @override
  void dispose() {
    _referrerCodeCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.card_giftcard_outlined), const SizedBox(width: 8), Expanded(child: Text(s('کاتالوگ پاداش‌ها', 'Reward catalogue'), style: theme.textTheme.titleMedium)),
            if (_canManage) IconButton(onPressed: _createReward, icon: const Icon(Icons.add_circle_outline))]),
          if (_rewards.isEmpty) Text(s('هنوز پاداشی تعریف نشده است.', 'No rewards have been defined yet.')),
          for (final reward in _rewards) ListTile(dense: true, contentPadding: EdgeInsets.zero,
            leading: Icon(reward['active'] == true ? Icons.redeem_outlined : Icons.block_outlined),
            title: Text('${reward['name'] ?? ''}'),
            subtitle: Text('${reward['points_cost'] ?? 0} ${s('امتیاز', 'points')} · ${reward['reward_type']} · ${reward['value'] ?? 0}'),
            trailing: Text(reward['active'] == true ? s('فعال', 'Active') : s('غیرفعال', 'Inactive'))),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.campaign_outlined), const SizedBox(width: 8), Expanded(child: Text(s('کمپین‌ها', 'Campaigns'), style: theme.textTheme.titleMedium)),
            if (_canManage) IconButton(onPressed: _createCampaign, icon: const Icon(Icons.add_circle_outline))]),
          if (_campaigns.isEmpty) Text(s('کمپینی ثبت نشده است.', 'No campaigns yet.')),
          for (final campaign in _campaigns) Card(color: theme.colorScheme.surfaceContainerLow, child: ListTile(
            title: Text('${campaign['name'] ?? ''}'),
            subtitle: Text('${campaign['status']} · ${campaign['reward_type']} ${campaign['reward_value']} · ${campaign['channel']}'),
            trailing: _canManage &&
                (campaign['status'] == 'active' || (campaign['status'] == 'completed' && {'sms', 'email'}.contains(campaign['channel'])))
                ? IconButton(tooltip: s('اجرا', 'Run'), onPressed: () => _runCampaign(campaign), icon: const Icon(Icons.play_arrow_rounded))
                : null,
          )),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s('پروفایل باشگاه مشتری', 'Customer club profile'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          PersonComboboxWidget(businessId: widget.businessId, selectedPerson: _person,
            label: s('مشتری', 'Customer'), hintText: s('انتخاب مشتری', 'Select customer'),
            onChanged: (person) {
              _referrerCodeCtl.clear();
              setState(() => _person = person);
              final personId = person?.id;
              if (personId != null) _loadMember(personId);
            }),
          if (_person != null) ...[
            if (_ownReferralCode.isNotEmpty) SelectableText('${s('کد معرفی مشتری', 'Customer referral code')}: $_ownReferralCode'),
            TextField(controller: _referrerCodeCtl,
              decoration: InputDecoration(labelText: s('کد معرف این مشتری', 'Referrer code for this customer'), helperText: s('برای معرفی‌کننده و مشتری جدید، پس از اولین خرید امتیاز ثبت می‌شود.', 'Both inviter and referred customer earn points after the first sale.')),
              readOnly: !_canManage),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(s('رضایت دریافت پیامک', 'SMS consent')), value: _smsConsent,
              onChanged: _canManage ? (v) => setState(() => _smsConsent = v ?? false) : null),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(s('رضایت دریافت ایمیل', 'Email consent')), value: _emailConsent,
              onChanged: _canManage ? (v) => setState(() => _emailConsent = v ?? false) : null),
            Wrap(spacing: 8, children: [
              if (_canManage) OutlinedButton.icon(onPressed: _saving ? null : _saveConsent, icon: const Icon(Icons.save_outlined), label: Text(s('ذخیره رضایت', 'Save consent'))),
              if (_canRedeem) FilledButton.tonalIcon(onPressed: _rewards.isEmpty ? null : _redeemSelectedReward,
                icon: const Icon(Icons.redeem), label: Text(s('صدور پاداش', 'Issue reward'))),
            ]),
          ],
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s('کدهای پاداش', 'Reward vouchers'), style: theme.textTheme.titleMedium),
          if (_vouchers.isEmpty) Text(s('کدی صادر نشده است.', 'No vouchers issued.')),
          for (final voucher in _vouchers.take(50)) ListTile(dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.confirmation_number_outlined), title: SelectableText('${voucher['code']}'),
            subtitle: Text('${voucher['status']} · ${voucher['reward_type']} · ${voucher['value']}')),
        ]))),
      ]),
    );
  }
}
