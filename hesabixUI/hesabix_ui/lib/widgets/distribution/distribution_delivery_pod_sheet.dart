import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/distribution_location_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_field_helpers.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_signature_pad.dart';

Future<void> showDistributionDeliveryPodSheet({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  required Map<String, dynamic> stop,
  bool requireSignature = false,
  bool requirePhoto = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DeliveryPodSheet(
      businessId: businessId,
      service: service,
      stop: stop,
      requireSignature: requireSignature,
      requirePhoto: requirePhoto,
    ),
  );
}

class _DeliveryPodSheet extends StatefulWidget {
  const _DeliveryPodSheet({
    required this.businessId,
    required this.service,
    required this.stop,
    required this.requireSignature,
    required this.requirePhoto,
  });

  final int businessId;
  final DistributionService service;
  final Map<String, dynamic> stop;
  final bool requireSignature;
  final bool requirePhoto;

  @override
  State<_DeliveryPodSheet> createState() => _DeliveryPodSheetState();
}

class _DeliveryPodSheetState extends State<_DeliveryPodSheet> {
  String _status = 'delivered';
  final _nameCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  String? _signaturePng;
  int? _photoFileId;
  String _failCode = 'closed';
  var _saving = false;
  late final List<_QtyLine> _lines;

  @override
  void initState() {
    super.initState();
    final raw = widget.stop['order_lines'];
    final list = raw is List ? raw : const [];
    _lines = list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final ordered = double.tryParse('${m['quantity'] ?? m['qty'] ?? 0}') ?? 0;
      return _QtyLine(
        productId: int.tryParse('${m['product_id']}') ?? 0,
        name: '${m['product_name'] ?? m['name'] ?? m['product_id']}',
        ordered: ordered,
        delivered: ordered,
      );
    }).where((e) => e.productId > 0).toList();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (pick == null || pick.files.isEmpty || pick.files.first.bytes == null) return;
    final f = pick.files.first;
    try {
      final uploaded = await BusinessStorageService(ApiClient()).uploadFile(
        businessId: widget.businessId,
        fileBytes: f.bytes!,
        filename: f.name,
        moduleContext: 'distribution',
        contextId: '${widget.stop['id']}',
      );
      if (mounted) setState(() => _photoFileId = uploaded['id'] as int?);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final sid = int.tryParse('${widget.stop['id']}');
    if (sid == null) return;
    if (_status != 'failed') {
      if (_nameCtl.text.trim().length < 2) {
        SnackBarHelper.showError(context, message: t.distributionPodSignerRequired);
        return;
      }
      if (widget.requireSignature && (_signaturePng == null || _signaturePng!.length < 40)) {
        SnackBarHelper.showError(context, message: t.distributionPodSignatureRequired);
        return;
      }
      if (widget.requirePhoto && _photoFileId == null) {
        SnackBarHelper.showError(context, message: t.distributionPodPhotoRequired);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final loc = await readDistributionVisitLocation();
      final status = _status == 'delivered' && _lines.any((l) => l.delivered + 1e-9 < l.ordered)
          ? 'partial'
          : _status;
      await widget.service.completeDeliveryStop(
        businessId: widget.businessId,
        stopId: sid,
        payload: {
          'status': status,
          if (status != 'failed') ...{
            'pod_confirmed': true,
            'pod_signer_name': _nameCtl.text.trim(),
            if (_noteCtl.text.trim().isNotEmpty) 'pod_note': _noteCtl.text.trim(),
            if (_photoFileId != null) 'pod_photo_file_id': _photoFileId,
            'delivered_lines': _lines
                .map((l) => {'product_id': l.productId, 'quantity': l.delivered})
                .toList(),
            if (loc.latitude != null) 'latitude': loc.latitude,
            if (loc.longitude != null) 'longitude': loc.longitude,
          } else
            'failure_reason': _failCode,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.distributionDeliveryPodTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.stop['person_name']?.toString() ?? '#${widget.stop['person_id']}'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'delivered', label: Text(t.distributionMarkDelivered), icon: const Icon(Icons.check)),
                ButtonSegment(value: 'partial', label: Text(t.distributionPartialDelivery), icon: const Icon(Icons.tune)),
                ButtonSegment(value: 'failed', label: Text(t.distributionDeliveryFailed), icon: const Icon(Icons.close)),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (_status != 'failed' && _lines.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t.distributionDeliveryLines, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._lines.map(
                (ln) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(ln.name, style: theme.textTheme.titleSmall),
                        Text('${t.distributionOrderedQty}: ${ln.ordered}'),
                        Slider(
                          min: 0,
                          max: ln.ordered <= 0 ? 1 : ln.ordered,
                          divisions: ln.ordered <= 0 ? 1 : (ln.ordered.round().clamp(1, 50)),
                          value: ln.delivered.clamp(0, ln.ordered <= 0 ? 1 : ln.ordered),
                          label: '${ln.delivered}',
                          onChanged: _status == 'failed'
                              ? null
                              : (v) => setState(() => ln.delivered = double.parse(v.toStringAsFixed(2))),
                        ),
                        Text('${t.distributionDeliveryQty}: ${ln.delivered}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_status == 'failed') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: distributionFailCodes
                    .map(
                      (c) => ChoiceChip(
                        label: Text(distributionFailReasonLabel(t, c)),
                        selected: _failCode == c,
                        onSelected: (_) => setState(() => _failCode = c),
                      ),
                    )
                    .toList(),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtl,
                decoration: InputDecoration(
                  labelText: t.distributionPodSignerName,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtl,
                maxLines: 2,
                decoration: InputDecoration(labelText: t.distributionPodNote, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DistributionSignaturePad(onChanged: (v) => _signaturePng = v),
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: Icon(_photoFileId != null ? Icons.check_circle_outline : Icons.photo_camera_outlined),
                label: Text(t.distributionPodPhoto),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_status == 'failed' ? t.distributionMarkFailed : t.distributionMarkDelivered),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyLine {
  _QtyLine({
    required this.productId,
    required this.name,
    required this.ordered,
    required this.delivered,
  });
  final int productId;
  final String name;
  final double ordered;
  double delivered;
}
