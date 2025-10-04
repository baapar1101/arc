import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../models/petty_cash.dart';
import '../../services/petty_cash_service.dart';
import 'currency_picker_widget.dart';

class PettyCashFormDialog extends StatefulWidget {
	final int businessId;
	final PettyCash? pettyCash; // null برای افزودن، مقدار برای ویرایش
	final VoidCallback? onSuccess;

	const PettyCashFormDialog({
		super.key,
		required this.businessId,
		this.pettyCash,
		this.onSuccess,
	});

	@override
	State<PettyCashFormDialog> createState() => _PettyCashFormDialogState();
}

class _PettyCashFormDialogState extends State<PettyCashFormDialog> {
	final _formKey = GlobalKey<FormState>();
	final _service = PettyCashService();
	bool _isLoading = false;

	final _codeController = TextEditingController();
	bool _autoGenerateCode = true;

	final _nameController = TextEditingController();
	final _descriptionController = TextEditingController();

	bool _isActive = true;
	bool _isDefault = false;
	int? _currencyId;

	@override
	void initState() {
		super.initState();
		_initializeForm();
	}

	void _initializeForm() {
		if (widget.pettyCash != null) {
			final p = widget.pettyCash!;
			if (p.code != null) {
				_codeController.text = p.code!;
				_autoGenerateCode = false;
			}
			_nameController.text = p.name;
			_descriptionController.text = p.description ?? '';
			_isActive = p.isActive;
			_isDefault = p.isDefault;
			_currencyId = p.currencyId;
		}
	}

	@override
	void dispose() {
		_codeController.dispose();
		_nameController.dispose();
		_descriptionController.dispose();
		super.dispose();
	}

	Future<void> _save() async {
		if (!_formKey.currentState!.validate()) return;

		if (_currencyId == null) {
			final t = AppLocalizations.of(context);
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text(t.currency), backgroundColor: Colors.red),
			);
			return;
		}

		setState(() { _isLoading = true; });
		try {
			final payload = <String, dynamic>{
				'name': _nameController.text.trim(),
				'code': _autoGenerateCode ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
				'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
				'is_active': _isActive,
				'is_default': _isDefault,
				'currency_id': _currencyId,
			};

			if (widget.pettyCash == null) {
				await _service.create(businessId: widget.businessId, payload: payload);
			} else {
				await _service.update(id: widget.pettyCash!.id!, payload: payload);
			}

			if (mounted) {
				Navigator.of(context).pop(true); // Return true to indicate success
				widget.onSuccess?.call();
				final t = AppLocalizations.of(context);
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(
						content: Text(widget.pettyCash == null
							? (t.localeName == 'fa' ? 'تنخواه گردان با موفقیت ایجاد شد' : 'Petty cash created successfully')
							: (t.localeName == 'fa' ? 'تنخواه گردان با موفقیت به‌روزرسانی شد' : 'Petty cash updated successfully')
						),
						backgroundColor: Colors.green,
					),
				);
			}
		} catch (e) {
			if (mounted) {
				final t = AppLocalizations.of(context);
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(content: Text('${t.error}: $e'), backgroundColor: Colors.red),
				);
			}
		} finally {
			if (mounted) {
				setState(() { _isLoading = false; });
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		final t = AppLocalizations.of(context);
		final isEditing = widget.pettyCash != null;

		return Dialog(
			child: Container(
				width: MediaQuery.of(context).size.width * 0.9,
				height: MediaQuery.of(context).size.height * 0.9,
				padding: const EdgeInsets.all(24),
				child: Column(
					children: [
						Row(
							children: [
								Icon(isEditing ? Icons.edit : Icons.add, color: Theme.of(context).primaryColor),
								const SizedBox(width: 8),
								Text(
									isEditing ? (t.localeName == 'fa' ? 'ویرایش تنخواه گردان' : 'Edit Petty Cash') : (t.localeName == 'fa' ? 'افزودن تنخواه گردان' : 'Add Petty Cash'),
									style: Theme.of(context).textTheme.headlineSmall,
								),
								const Spacer(),
								IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
							],
						),
						const Divider(),
						const SizedBox(height: 16),
						Expanded(
							child: DefaultTabController(
								length: 2,
								child: Form(
									key: _formKey,
									child: Column(
										children: [
											TabBar(isScrollable: true, tabs: [
												Tab(text: t.title),
												Tab(text: t.settings),
											]),
											const SizedBox(height: 12),
											Expanded(
												child: TabBarView(
													children: [
														SingleChildScrollView(
															child: Padding(
																padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
																child: _buildBasicInfo(t),
															),
														),
														SingleChildScrollView(
															child: Padding(
																padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
																child: _buildSettings(t),
															),
														),
													],
												),
											),
										],
									),
								),
							),
						),
						const Divider(),
						const SizedBox(height: 16),
						Row(
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								TextButton(onPressed: _isLoading ? null : () => Navigator.of(context).pop(), child: Text(t.cancel)),
								const SizedBox(width: 8),
								ElevatedButton(
									onPressed: _isLoading ? null : _save,
									child: _isLoading
										? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
										: Text(isEditing ? t.update : t.add),
								),
							],
						),
					],
				),
			),
		);
	}

	Widget _buildSectionHeader(String title) {
		return Text(
			title,
			style: Theme.of(context).textTheme.titleMedium?.copyWith(
				fontWeight: FontWeight.bold,
				color: Theme.of(context).primaryColor,
			),
		);
	}

	Widget _buildBasicInfo(AppLocalizations t) {
		return Column(
			children: [
				_buildSectionHeader(t.title),
				const SizedBox(height: 16),
				TextFormField(
					controller: _nameController,
					decoration: InputDecoration(labelText: t.title, hintText: t.title),
					validator: (value) {
						if (value == null || value.trim().isEmpty) {
							return t.title;
						}
						return null;
					},
				),
				const SizedBox(height: 16),
				Row(
					children: [
						Expanded(
							child: TextFormField(
								controller: _codeController,
								readOnly: _autoGenerateCode,
								decoration: InputDecoration(
									labelText: t.code,
									hintText: t.uniqueCodeNumeric,
									suffixIcon: Container(
										margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
										padding: const EdgeInsets.all(2),
										decoration: BoxDecoration(
											borderRadius: BorderRadius.circular(8),
											color: Theme.of(context).colorScheme.surfaceContainerHighest,
										),
										child: ToggleButtons(
											isSelected: [_autoGenerateCode, !_autoGenerateCode],
											borderRadius: BorderRadius.circular(6),
											constraints: const BoxConstraints(minHeight: 32, minWidth: 64),
											onPressed: (index) {
												setState(() { _autoGenerateCode = (index == 0); });
											},
											children: [
												Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t.automatic)),
												Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t.manual)),
											],
										),
									),
								),
								keyboardType: TextInputType.text,
								validator: (value) {
									if (!_autoGenerateCode) {
										if (value == null || value.trim().isEmpty) {
											return t.personCodeRequired;
										}
										if (value.trim().length < 3) {
											return t.passwordMinLength; // fallback
										}
										if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
											return t.codeMustBeNumeric;
										}
									}
									return null;
								},
							),
						),
					],
				),
				const SizedBox(height: 16),
				CurrencyPickerWidget(
					businessId: widget.businessId,
					selectedCurrencyId: _currencyId,
					onChanged: (value) { setState(() { _currencyId = value; }); },
					label: t.currency,
					hintText: t.currency,
				),
				const SizedBox(height: 16),
				TextFormField(
					controller: _descriptionController,
					decoration: InputDecoration(labelText: t.description, hintText: t.description),
					maxLines: 3,
				),
			],
		);
	}

	Widget _buildSettings(AppLocalizations t) {
		return Column(
			children: [
				_buildSectionHeader(t.settings),
				const SizedBox(height: 16),
				SwitchListTile(
					title: Text(t.active),
					subtitle: Text(t.active),
					value: _isActive,
					onChanged: (value) { setState(() { _isActive = value; }); },
				),
				const SizedBox(height: 8),
				SwitchListTile(
					title: Text(t.isDefault),
					subtitle: Text(t.defaultConfiguration),
					value: _isDefault,
					onChanged: (value) { setState(() { _isDefault = value; }); },
				),
			],
		);
	}
}
																				