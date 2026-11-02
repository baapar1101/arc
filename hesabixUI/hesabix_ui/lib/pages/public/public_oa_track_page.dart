import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../services/office_automation_service.dart';
import '../../utils/error_extractor.dart';
import '../../widgets/office_automation/oa_ui.dart';

class PublicOaTrackPage extends StatefulWidget {
  final String? token;

  const PublicOaTrackPage({super.key, this.token});

  @override
  State<PublicOaTrackPage> createState() => _PublicOaTrackPageState();
}

class _PublicOaTrackPageState extends State<PublicOaTrackPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _token = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    final token = widget.token?.trim() ?? '';
    if (token.isNotEmpty) {
      _token.text = token;
      _track(token);
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _track(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final data = await _svc.publicTrack(token: trimmed);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.oaPublicTrack)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(t.oaPublicTrackHint, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _token,
                decoration: InputDecoration(
                  labelText: t.oaTrackingToken,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _track(_token.text),
                  ),
                ),
                onSubmitted: _track,
              ),
              const SizedBox(height: 24),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                  ),
                ),
              if (_data != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.oaPublicTrackResult, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        _row(t.oaRegistry, '${_data!['number'] ?? '—'}'),
                        _row(t.oaLetterKind, oaKindLabel(t, '${_data!['letter_kind'] ?? ''}')),
                        _row(t.oaStatus, oaStatusLabel(t, '${_data!['status'] ?? ''}')),
                        _row(t.oaConfidential, oaConfidentialityLabel(t, '${_data!['confidentiality'] ?? ''}')),
                        if (_data!['subject'] != null) _row(t.oaSubject, '${_data!['subject']}'),
                        if (_data!['letter_date'] != null)
                          _row(
                            t.oaLetterDate,
                            HesabixDateUtils.formatForDisplay(
                              HesabixDateUtils.parseApiDate(_data!['letter_date'], rawValue: _data!['letter_date_raw']),
                              ApiClient.getCalendarController()?.isJalali ?? true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
