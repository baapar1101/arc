import 'package:flutter/material.dart';

import '../../services/sepidar_import_service.dart';

class SepidarImportSettingsPage extends StatefulWidget {
  final int businessId;
  const SepidarImportSettingsPage({super.key, required this.businessId});
  @override State<SepidarImportSettingsPage> createState() => _State();
}

class _State extends State<SepidarImportSettingsPage> {
  final _service = SepidarImportService();
  final _host = TextEditingController(), _port = TextEditingController(text: '1433');
  final _database = TextEditingController(), _username = TextEditingController(), _password = TextEditingController();
  final _interval = TextEditingController(text: '15'), _batch = TextEditingController(text: '500');
  final _schemas = TextEditingController(), _tables = TextEditingController();
  bool _enabled = false, _busy = false, _hidePassword = true, _nativeEnabled = false;
  Map<String, dynamic>? _nativeSummary;
  String? _nativeError;
  String? _status;
  List<Map<String, dynamic>> _runs = const [];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in [_host,_port,_database,_username,_password,_interval,_batch,_schemas,_tables]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final s = await _service.settings(widget.businessId);
      _host.text = '${s['host'] ?? ''}'; _port.text = '${s['port'] ?? 1433}'; _database.text = '${s['database_name'] ?? ''}';
      _username.text = '${s['username'] ?? ''}'; _interval.text = '${s['sync_interval_minutes'] ?? 15}'; _batch.text = '${s['batch_size'] ?? 500}';
      _schemas.text = (s['included_schemas'] as List? ?? const []).join(', '); _tables.text = (s['included_tables'] as List? ?? const []).join(', ');
      _enabled = s['enabled'] == true; _runs = await _service.runs(widget.businessId);
      _nativeEnabled = s['native_enabled'] == true;
      _nativeSummary = s['native_summary'] is Map ? Map<String,dynamic>.from(s['native_summary'] as Map) : null;
      _nativeError = s['native_last_error'] as String?;
    } catch (e) { _status = 'خطا در دریافت تنظیمات: $e'; }
    if (mounted) setState(() => _busy = false);
  }

  List<String> _csv(String text) => text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  Future<void> _save() async {
    setState(() { _busy = true; _status = null; });
    try {
      await _service.save(widget.businessId, {'host':_host.text.trim(),'port':int.tryParse(_port.text)??1433,'database_name':_database.text.trim(),
        'username':_username.text.trim(),if(_password.text.isNotEmpty)'password':_password.text,'enabled':_enabled,
        'native_enabled':_nativeEnabled,
        'sync_interval_minutes':int.tryParse(_interval.text)??15,'batch_size':int.tryParse(_batch.text)??500,
        'included_schemas':_csv(_schemas.text),'included_tables':_csv(_tables.text)});
      _password.clear(); _status = 'تنظیمات با رمزنگاری امن ذخیره شد.';
    } catch(e) { _status = 'ذخیره ناموفق: $e'; }
    if(mounted) setState(()=>_busy=false);
  }
  Future<void> _action(bool sync) async {
    setState(() { _busy=true; _status=null; });
    try { final r = sync ? await _service.sync(widget.businessId) : await _service.test(widget.businessId);
      _status = sync ? 'همگام‌سازی انجام شد: ${r['rows_seen']} رکورد از ${r['tables']} جدول' : 'اتصال موفق: ${r['tables']} جدول، حدود ${r['estimated_rows']} رکورد';
      _runs = await _service.runs(widget.businessId);
      final s = await _service.settings(widget.businessId);
      _nativeSummary = s['native_summary'] is Map ? Map<String,dynamic>.from(s['native_summary'] as Map) : null;
      _nativeError = s['native_last_error'] as String?;
    } catch(e) { _status='عملیات ناموفق: $e'; }
    if(mounted) setState(()=>_busy=false);
  }
  Widget _field(TextEditingController c,String label,{bool secret=false}) => TextField(controller:c,obscureText:secret&&_hidePassword,
    decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),suffixIcon:secret?IconButton(onPressed:()=>setState(()=>_hidePassword=!_hidePassword),icon:Icon(_hidePassword?Icons.visibility:Icons.visibility_off)):null));

  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('ورود لایو اطلاعات از سپیدار')),
    body:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('اتصال فقط‌خواندنی و همگام‌سازی تکرارپذیر SQL Server سپیدار',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),const Text('رمز عبور رمزنگاری می‌شود. برای ورود تمام جدول‌ها، فیلترهای schema و table را خالی بگذارید.'),
      const SizedBox(height:20),Wrap(spacing:12,runSpacing:12,children:[SizedBox(width:360,child:_field(_host,'سرور')),SizedBox(width:160,child:_field(_port,'پورت')),
        SizedBox(width:360,child:_field(_database,'نام دیتابیس')),SizedBox(width:260,child:_field(_username,'نام کاربری')),SizedBox(width:300,child:_field(_password,'رمز عبور (برای عدم تغییر خالی)',secret:true)),
        SizedBox(width:180,child:_field(_interval,'فاصله همگام‌سازی (دقیقه)')),SizedBox(width:180,child:_field(_batch,'اندازه batch')),
        SizedBox(width:520,child:_field(_schemas,'Schemaها با کاما (اختیاری)')),SizedBox(width:520,child:_field(_tables,'Schema.Table با کاما (اختیاری)'))]),
      SwitchListTile(value:_enabled,onChanged:_busy?null:(v)=>setState(()=>_enabled=v),title:const Text('همگام‌سازی لایو فعال باشد')),
      SwitchListTile(value:_nativeEnabled,onChanged:_busy?null:(v)=>setState(()=>_nativeEnabled=v),title:const Text('تبدیل خودکار به اطلاعات قابل استفاده حسابیکس'),
        subtitle:const Text('اشخاص، کالاها، سال‌های مالی، حساب‌ها، فاکتورها و اسناد؛ هر بار پس از دریافت اطلاعات سپیدار به‌روز می‌شوند.')),
      const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('اسناد مالی واردشده از سپیدار مدیریت می‌شوند. ویرایش مالی آن‌ها را در سپیدار انجام دهید. صدور فاکتور جدید در حسابیکس مستقل است.')),
      if(_nativeSummary!=null) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('آخرین تبدیل موفق: ${_nativeSummary!['completed_at'] ?? ''}'),
        Text('دیتابیس: ${_nativeSummary!['database'] ?? ''}'),
        const SizedBox(height:8),
        for(final entry in ((_nativeSummary!['entities'] as Map?) ?? {}).entries)
          Text('${_entityLabel(entry.key.toString())}: ${_entityCount(entry.value)}'),
      ]))),
      if(_nativeError!=null) Text('خطای تبدیل: $_nativeError',style:TextStyle(color:Theme.of(context).colorScheme.error)),
      Wrap(spacing:12,children:[FilledButton.icon(onPressed:_busy?null:_save,icon:const Icon(Icons.save),label:const Text('ذخیره تنظیمات')),
        OutlinedButton.icon(onPressed:_busy?null:()=>_action(false),icon:const Icon(Icons.cable),label:const Text('تست اتصال')),
        FilledButton.tonalIcon(onPressed:_busy?null:()=>_action(true),icon:const Icon(Icons.sync),label:const Text('همگام‌سازی الآن'))]),
      if(_busy) const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator()),if(_status!=null) Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(_status!)),
      const Divider(height:40),const Text('آخرین اجراها',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
      ..._runs.map((r)=>ListTile(leading:Icon(r['status']=='success'?Icons.check_circle:Icons.error,color:r['status']=='success'?Colors.green:Colors.red),
        title:Text('${r['status']} — ${r['rows_seen']} رکورد'),subtitle:Text('${r['tables_completed']}/${r['tables_total']} جدول • ${r['started_at'] ?? ''}${r['error']!=null?'\n${r['error']}':''}'))),
    ]));

  String _entityLabel(String key) => const {'GNR.Party':'اشخاص','INV.Item':'کالاها','ACC.Voucher':'اسناد حسابداری',
    'SLS.Invoice':'فروش','SLS.ReturnedInvoice':'برگشت فروش','INV.InventoryPurchaseInvoice':'خرید','SLS.Quotation':'پیش‌فاکتور',
    'FMK.FiscalYear':'سال مالی','ACC.Account':'حساب‌ها','INV.Stock':'انبارها'}[key] ?? key;
  String _entityCount(dynamic value) {
    final m = value is Map ? value : const {};
    final total = (m['created'] as num? ?? 0) + (m['updated'] as num? ?? 0) + (m['unchanged'] as num? ?? 0);
    return '$total مورد؛ ${m['created'] ?? 0} جدید، ${m['updated'] ?? 0} به‌روزشده';
  }
}
