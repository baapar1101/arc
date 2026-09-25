Imports System.Threading

Friend Class NewBusinessDialog
    Inherits Form

    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _session As MigrationSession

    Private ReadOnly _fldName As ModernTextField
    Private ReadOnly _cmbType As ComboBox
    Private ReadOnly _cmbField As ComboBox
    Private ReadOnly _cmbCurrency As ComboBox
    Private ReadOnly _chkSample As CheckBox
    Private ReadOnly _btnCreate As Button
    Private ReadOnly _btnCancel As Button
    Private ReadOnly _statusBanner As ContextBanner
    Private _cts As CancellationTokenSource

    Public Property CreatedBusiness As HesabixBusiness

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        Text = "ایجاد کسب‌وکار جدید"
        StartPosition = FormStartPosition.CenterParent
        FormBorderStyle = FormBorderStyle.FixedDialog
        MaximizeBox = False
        MinimizeBox = False
        ShowInTaskbar = False
        RightToLeft = RightToLeft.Yes
        RightToLeftLayout = False
        BackColor = AppTheme.BgApp
        Font = AppTheme.FontUi
        ClientSize = New Size(480, 460)
        Padding = New Padding(24)

        Dim title As New Label() With {
            .Text = "کسب‌وکار مقصد برای ایمپورت",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .AutoSize = True,
            .RightToLeft = RightToLeft.Yes,
            .Name = "title"
        }

        _fldName = New ModernTextField() With {
            .FieldLabel = "نام کسب‌وکار",
            .IsLtr = False,
            .Width = 420,
            .Name = "fldName"
        }

        Dim lblType As New Label() With {
            .Text = "نوع کسب‌وکار",
            .AutoSize = True,
            .ForeColor = AppTheme.TextSecondary,
            .Font = AppTheme.FontFieldLabel,
            .RightToLeft = RightToLeft.Yes,
            .Name = "lblType"
        }
        _cmbType = New ComboBox() With {
            .Width = 420,
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Name = "cmbType"
        }
        AppTheme.StyleComboBox(_cmbType)
        _cmbType.Items.AddRange({"شرکت", "مغازه", "فروشگاه", "اتحادیه", "باشگاه", "موسسه", "شخصی"})
        _cmbType.SelectedIndex = 0

        Dim lblField As New Label() With {
            .Text = "زمینه فعالیت",
            .AutoSize = True,
            .ForeColor = AppTheme.TextSecondary,
            .Font = AppTheme.FontFieldLabel,
            .RightToLeft = RightToLeft.Yes,
            .Name = "lblField"
        }
        _cmbField = New ComboBox() With {
            .Width = 420,
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Name = "cmbField"
        }
        AppTheme.StyleComboBox(_cmbField)
        _cmbField.Items.AddRange({"تولیدی", "بازرگانی", "خدماتی", "سایر"})
        _cmbField.SelectedIndex = 1

        Dim lblCurrency As New Label() With {
            .Text = "ارز پیش‌فرض",
            .AutoSize = True,
            .ForeColor = AppTheme.TextSecondary,
            .Font = AppTheme.FontFieldLabel,
            .RightToLeft = RightToLeft.Yes,
            .Name = "lblCurrency"
        }
        _cmbCurrency = New ComboBox() With {
            .Width = 420,
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Name = "cmbCurrency"
        }
        AppTheme.StyleComboBox(_cmbCurrency)

        _chkSample = New CheckBox() With {
            .Text = "درج داده نمونه (برای ایمپورت هلو معمولاً خاموش باشد)",
            .AutoSize = True,
            .Checked = False,
            .Name = "chkSample"
        }
        AppTheme.StyleCheckBox(_chkSample)
        _chkSample.ForeColor = AppTheme.TextSecondary

        _statusBanner = New ContextBanner() With {.Width = 420, .Name = "statusBanner"}
        _statusBanner.SetStatus("", ContextBanner.BannerTone.Neutral)

        _btnCreate = New Button() With {
            .Text = "ایجاد",
            .Size = New Size(110, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnCreate"
        }
        AppTheme.StylePrimaryButton(_btnCreate)
        AddHandler _btnCreate.Click, AddressOf OnCreateClick

        _btnCancel = New Button() With {
            .Text = "انصراف",
            .Size = New Size(110, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnCancel"
        }
        AppTheme.StyleSecondaryButton(_btnCancel)
        AddHandler _btnCancel.Click, Sub(s, e)
                                         DialogResult = DialogResult.Cancel
                                         Close()
                                     End Sub

        Controls.Add(title)
        Controls.Add(_fldName)
        Controls.Add(lblType)
        Controls.Add(_cmbType)
        Controls.Add(lblField)
        Controls.Add(_cmbField)
        Controls.Add(lblCurrency)
        Controls.Add(_cmbCurrency)
        Controls.Add(_chkSample)
        Controls.Add(_statusBanner)
        Controls.Add(_btnCreate)
        Controls.Add(_btnCancel)

        LayoutDialog()
        AppTheme.ApplyRtlTree(Me, False)
        LayoutDialog()
        AddHandler Shown, AddressOf OnShownLoadCurrencies
    End Sub

    Private Sub LayoutDialog()
        Dim w = ClientSize.Width
        Const m As Integer = 28
        Const fieldW As Integer = 420

        AppTheme.PlaceFromRight(Controls("title"), w, m, 20)

        _fldName.Width = fieldW
        AppTheme.PlaceFromRight(_fldName, w, m, 52)

        AppTheme.PlaceFromRight(Controls("lblType"), w, m, 126)
        _cmbType.Width = fieldW
        AppTheme.PlaceFromRight(_cmbType, w, m, 146)

        AppTheme.PlaceFromRight(Controls("lblField"), w, m, 196)
        _cmbField.Width = fieldW
        AppTheme.PlaceFromRight(_cmbField, w, m, 216)

        AppTheme.PlaceFromRight(Controls("lblCurrency"), w, m, 266)
        _cmbCurrency.Width = fieldW
        AppTheme.PlaceFromRight(_cmbCurrency, w, m, 286)

        AppTheme.PlaceFromRight(_chkSample, w, m, 338)

        _statusBanner.Width = fieldW
        AppTheme.PlaceFromRight(_statusBanner, w, m, 372)

        AppTheme.PlaceFromRight(_btnCreate, w, m, 416)
        AppTheme.PlaceFromRight(_btnCancel, w, m + _btnCreate.Width + 12, 416)
    End Sub

    Private Async Sub OnShownLoadCurrencies(sender As Object, e As EventArgs)
        _btnCreate.Enabled = False
        _statusBanner.SetStatus("در حال دریافت ارزها...", ContextBanner.BannerTone.Info)
        _cts = New CancellationTokenSource()
        Try
            Dim currencies = Await Task.Run(Async Function()
                                                _api.Configure(_session.ApiBaseUrl, _session.ApiKey)
                                                Return Await _api.ListCurrenciesAsync(_cts.Token).ConfigureAwait(False)
                                            End Function).ConfigureAwait(True)

            _cmbCurrency.Items.Clear()
            For Each c In currencies
                _cmbCurrency.Items.Add(c)
            Next

            Dim irr = currencies.FirstOrDefault(Function(x) String.Equals(x.Code, "IRR", StringComparison.OrdinalIgnoreCase) OrElse
                                                             (x.Title IsNot Nothing AndAlso x.Title.Contains("ریال")))
            If irr IsNot Nothing Then
                _cmbCurrency.SelectedItem = irr
            ElseIf _cmbCurrency.Items.Count > 0 Then
                _cmbCurrency.SelectedIndex = 0
            End If

            If _cmbCurrency.Items.Count = 0 Then
                _statusBanner.SetStatus("ارزی یافت نشد.", ContextBanner.BannerTone.Warning)
            Else
                _statusBanner.SetStatus("", ContextBanner.BannerTone.Neutral)
            End If
            _btnCreate.Enabled = _cmbCurrency.Items.Count > 0
            LayoutDialog()
        Catch ex As Exception
            _statusBanner.SetStatus(ex.Message, ContextBanner.BannerTone.Danger)
            AsyncUi.ShowError(Me, "خطا در دریافت ارزها", ex)
        End Try
    End Sub

    Private Async Sub OnCreateClick(sender As Object, e As EventArgs)
        Dim name = _fldName.Text.Trim()
        If String.IsNullOrWhiteSpace(name) Then
            _fldName.HasError = True
            MessageBox.Show(Me, "نام کسب‌وکار را وارد کنید.", "ورودی ناقص",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If
        _fldName.HasError = False
        Dim currency = TryCast(_cmbCurrency.SelectedItem, CurrencyInfo)
        If currency Is Nothing Then
            MessageBox.Show(Me, "ارز پیش‌فرض را انتخاب کنید.", "ورودی ناقص",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If

        _btnCreate.Enabled = False
        _btnCancel.Enabled = False
        _statusBanner.SetStatus("در حال ایجاد کسب‌وکار...", ContextBanner.BannerTone.Info)

        If _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
        End If
        _cts = New CancellationTokenSource()

        Try
            Dim req As New NewBusinessRequest With {
                .Name = name,
                .BusinessType = CStr(_cmbType.SelectedItem),
                .BusinessField = CStr(_cmbField.SelectedItem),
                .DefaultCurrencyId = currency.Id,
                .IncludeSampleData = _chkSample.Checked
            }

            CreatedBusiness = Await Task.Run(Async Function()
                                                 _api.Configure(_session.ApiBaseUrl, _session.ApiKey)
                                                 Return Await _api.CreateBusinessAsync(req, _cts.Token).ConfigureAwait(False)
                                             End Function).ConfigureAwait(True)

            DialogResult = DialogResult.OK
            Close()
        Catch ex As Exception
            _statusBanner.SetStatus(ex.Message, ContextBanner.BannerTone.Danger)
            _btnCreate.Enabled = True
            _btnCancel.Enabled = True
            AsyncUi.ShowError(Me, "خطا در ایجاد کسب‌وکار", ex)
        End Try
    End Sub

    Protected Overrides Sub Dispose(disposing As Boolean)
        If disposing AndAlso _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
            _cts = Nothing
        End If
        MyBase.Dispose(disposing)
    End Sub
End Class
