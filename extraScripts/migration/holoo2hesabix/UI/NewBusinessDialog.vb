Imports System.Threading

Friend Class NewBusinessDialog
    Inherits Form

    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _session As MigrationSession

    Private ReadOnly _txtName As TextBox
    Private ReadOnly _cmbType As ComboBox
    Private ReadOnly _cmbField As ComboBox
    Private ReadOnly _cmbCurrency As ComboBox
    Private ReadOnly _chkSample As CheckBox
    Private ReadOnly _btnCreate As Button
    Private ReadOnly _btnCancel As Button
    Private ReadOnly _lblStatus As Label
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
        ClientSize = New Size(460, 420)
        Padding = New Padding(24)

        Dim title As New Label() With {
            .Text = "کسب‌وکار مقصد برای ایمپورت",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .AutoSize = True,
            .Location = New Point(24, 20),
            .RightToLeft = RightToLeft.Yes
        }

        Dim lblName As New Label() With {.Text = "نام کسب‌وکار", .AutoSize = True, .Location = New Point(24, 60), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _txtName = New TextBox() With {.Location = New Point(24, 82), .Width = 400, .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleTextBox(_txtName)

        Dim lblType As New Label() With {.Text = "نوع کسب‌وکار", .AutoSize = True, .Location = New Point(24, 120), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _cmbType = New ComboBox() With {
            .Location = New Point(24, 142),
            .Width = 400,
            .DropDownStyle = ComboBoxStyle.DropDownList
        }
        AppTheme.StyleComboBox(_cmbType)
        _cmbType.Items.AddRange({"شرکت", "مغازه", "فروشگاه", "اتحادیه", "باشگاه", "موسسه", "شخصی"})
        _cmbType.SelectedIndex = 0

        Dim lblField As New Label() With {.Text = "زمینه فعالیت", .AutoSize = True, .Location = New Point(24, 180), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _cmbField = New ComboBox() With {
            .Location = New Point(24, 202),
            .Width = 400,
            .DropDownStyle = ComboBoxStyle.DropDownList
        }
        AppTheme.StyleComboBox(_cmbField)
        _cmbField.Items.AddRange({"تولیدی", "بازرگانی", "خدماتی", "سایر"})
        _cmbField.SelectedIndex = 1

        Dim lblCurrency As New Label() With {.Text = "ارز پیش‌فرض", .AutoSize = True, .Location = New Point(24, 240), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _cmbCurrency = New ComboBox() With {
            .Location = New Point(24, 262),
            .Width = 400,
            .DropDownStyle = ComboBoxStyle.DropDownList
        }
        AppTheme.StyleComboBox(_cmbCurrency)

        _chkSample = New CheckBox() With {
            .Text = "درج داده نمونه (برای ایمپورت هلو معمولاً خاموش باشد)",
            .AutoSize = True,
            .Location = New Point(24, 302),
            .Checked = False,
            .ForeColor = AppTheme.TextSecondary,
            .RightToLeft = RightToLeft.Yes
        }

        _lblStatus = New Label() With {
            .AutoSize = True,
            .Location = New Point(24, 336),
            .ForeColor = AppTheme.TextMuted,
            .Text = "",
            .RightToLeft = RightToLeft.Yes
        }

        _btnCreate = New Button() With {.Text = "ایجاد", .Size = New Size(110, 40), .Location = New Point(200, 360), .RightToLeft = RightToLeft.Yes}
        AppTheme.StylePrimaryButton(_btnCreate)
        AddHandler _btnCreate.Click, AddressOf OnCreateClick

        _btnCancel = New Button() With {.Text = "انصراف", .Size = New Size(110, 40), .Location = New Point(314, 360), .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleSecondaryButton(_btnCancel)
        AddHandler _btnCancel.Click, Sub(s, e)
                                         DialogResult = DialogResult.Cancel
                                         Close()
                                     End Sub

        Controls.Add(title)
        Controls.Add(lblName)
        Controls.Add(_txtName)
        Controls.Add(lblType)
        Controls.Add(_cmbType)
        Controls.Add(lblField)
        Controls.Add(_cmbField)
        Controls.Add(lblCurrency)
        Controls.Add(_cmbCurrency)
        Controls.Add(_chkSample)
        Controls.Add(_lblStatus)
        Controls.Add(_btnCreate)
        Controls.Add(_btnCancel)

        AppTheme.ApplyRtlTree(Me, False)
        AddHandler Shown, AddressOf OnShownLoadCurrencies
    End Sub

    Private Async Sub OnShownLoadCurrencies(sender As Object, e As EventArgs)
        _btnCreate.Enabled = False
        _lblStatus.Text = "در حال دریافت ارزها..."
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

            _lblStatus.Text = If(_cmbCurrency.Items.Count = 0, "ارزی یافت نشد.", "")
            _btnCreate.Enabled = _cmbCurrency.Items.Count > 0
        Catch ex As Exception
            _lblStatus.ForeColor = AppTheme.Danger
            _lblStatus.Text = ex.Message
            AsyncUi.ShowError(Me, "خطا در دریافت ارزها", ex)
        End Try
    End Sub

    Private Async Sub OnCreateClick(sender As Object, e As EventArgs)
        Dim name = _txtName.Text.Trim()
        If String.IsNullOrWhiteSpace(name) Then
            MessageBox.Show(Me, "نام کسب‌وکار را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If
        Dim currency = TryCast(_cmbCurrency.SelectedItem, CurrencyInfo)
        If currency Is Nothing Then
            MessageBox.Show(Me, "ارز پیش‌فرض را انتخاب کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If

        _btnCreate.Enabled = False
        _btnCancel.Enabled = False
        _lblStatus.ForeColor = AppTheme.TextMuted
        _lblStatus.Text = "در حال ایجاد کسب‌وکار..."

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
            _lblStatus.ForeColor = AppTheme.Danger
            _lblStatus.Text = ex.Message
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
