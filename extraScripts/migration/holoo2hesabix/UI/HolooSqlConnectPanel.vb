Imports System.Threading

Friend Class HolooSqlConnectPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _sql As HolooSqlService

    Private _fldServer As ModernTextField
    Private _rbWindows As RadioButton
    Private _rbSql As RadioButton
    Private _fldUser As ModernTextField
    Private _fldPassword As ModernTextField
    Private _chkTrust As CheckBox
    Private _btnTest As Button
    Private _btnLoadDb As Button
    Private _lstDatabases As ListBox
    Private _txtSummary As TextBox
    Private _statusBanner As ContextBanner
    Private _formCard As RoundedCard
    Private _dbCard As RoundedCard
    Private _summaryCard As RoundedCard
    Private ReadOnly _busy As BusyOverlay

    Private _cts As CancellationTokenSource
    Private _isBusy As Boolean

    Public Sub New(session As MigrationSession, sql As HolooSqlService)
        _session = session
        _sql = sql

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        Dim header = PageHeader.Create(
            "اتصال به SQL Server هلو",
            "اتصال را تست کنید، دیتابیس هلو را انتخاب کنید. در این مرحله هنوز انتقالی انجام نمی‌شود.")

        _formCard = CreateFormCard()

        Dim lblDb As New Label() With {
            .AutoSize = True,
            .Text = "دیتابیس‌ها",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Name = "lblDb"
        }

        _dbCard = New RoundedCard() With {.Padding = New Padding(10), .Name = "dbCard"}
        _lstDatabases = New ListBox() With {
            .IntegralHeight = False,
            .Font = AppTheme.FontUi,
            .RightToLeft = RightToLeft.Yes,
            .BackColor = AppTheme.BgCard,
            .ForeColor = AppTheme.TextPrimary,
            .BorderStyle = BorderStyle.None,
            .Dock = DockStyle.Fill
        }
        AddHandler _lstDatabases.SelectedIndexChanged, AddressOf OnDatabaseSelected
        _dbCard.Controls.Add(_lstDatabases)

        Dim lblSummary As New Label() With {
            .AutoSize = True,
            .Text = "خلاصه ساختار",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Name = "lblSummary"
        }

        _summaryCard = New RoundedCard() With {.Padding = New Padding(12), .Name = "summaryCard"}
        _txtSummary = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = AppTheme.FontStep,
            .BackColor = AppTheme.BgMuted,
            .ForeColor = AppTheme.TextPrimary,
            .BorderStyle = BorderStyle.None,
            .Dock = DockStyle.Fill,
            .RightToLeft = RightToLeft.Yes
        }
        _summaryCard.Controls.Add(_txtSummary)

        _busy = New BusyOverlay()

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_formCard)
        Controls.Add(lblDb)
        Controls.Add(_dbCard)
        Controls.Add(lblSummary)
        Controls.Add(_summaryCard)
        Controls.Add(_busy)

        AddHandler Resize, AddressOf OnPanelResize
        OnPanelResize(Me, EventArgs.Empty)
        LoadFromSession()
        AppTheme.ApplyRtlTree(Me, False)
        OnPanelResize(Me, EventArgs.Empty)
    End Sub

    Private Function CreateFormCard() As RoundedCard
        Dim card As New RoundedCard() With {.Height = 268, .Padding = New Padding(22)}

        _fldServer = New ModernTextField() With {
            .FieldLabel = "سرور / Instance",
            .IsLtr = True,
            .Width = 280,
            .Name = "fldServer"
        }

        _rbSql = New RadioButton() With {
            .Text = "احراز هویت SQL Server",
            .AutoSize = True,
            .Checked = True,
            .Name = "rbSql"
        }
        AppTheme.StyleRadioButton(_rbSql)

        _rbWindows = New RadioButton() With {
            .Text = "احراز هویت ویندوز",
            .AutoSize = True,
            .Name = "rbWindows"
        }
        AppTheme.StyleRadioButton(_rbWindows)
        AddHandler _rbSql.CheckedChanged, AddressOf OnAuthModeChanged
        AddHandler _rbWindows.CheckedChanged, AddressOf OnAuthModeChanged

        _fldUser = New ModernTextField() With {
            .FieldLabel = "نام کاربری",
            .IsLtr = True,
            .Width = 200,
            .Name = "fldUser"
        }
        _fldPassword = New ModernTextField() With {
            .FieldLabel = "رمز عبور",
            .IsLtr = True,
            .UseSystemPasswordChar = True,
            .Width = 200,
            .Name = "fldPassword"
        }

        _chkTrust = New CheckBox() With {
            .Text = "اعتماد به گواهی سرور (برای اتصال محلی)",
            .AutoSize = True,
            .Checked = True,
            .Name = "chkTrust"
        }
        AppTheme.StyleCheckBox(_chkTrust)
        _chkTrust.Font = AppTheme.FontStep
        _chkTrust.ForeColor = AppTheme.TextSecondary

        _btnTest = New Button() With {
            .Text = "تست اتصال",
            .Size = New Size(120, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnTest"
        }
        AppTheme.StyleSecondaryButton(_btnTest)
        AddHandler _btnTest.Click, AddressOf OnTestClick

        _btnLoadDb = New Button() With {
            .Text = "دریافت لیست دیتابیس‌ها",
            .Size = New Size(200, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnLoadDb"
        }
        AppTheme.StylePrimaryButton(_btnLoadDb)
        AddHandler _btnLoadDb.Click, AddressOf OnLoadDatabasesClick

        _statusBanner = New ContextBanner() With {.Width = 420, .Name = "statusBanner"}
        _statusBanner.SetStatus("هنوز اتصال برقرار نشده", ContextBanner.BannerTone.Neutral)

        card.Controls.Add(_fldServer)
        card.Controls.Add(_rbSql)
        card.Controls.Add(_rbWindows)
        card.Controls.Add(_fldUser)
        card.Controls.Add(_fldPassword)
        card.Controls.Add(_chkTrust)
        card.Controls.Add(_btnLoadDb)
        card.Controls.Add(_btnTest)
        card.Controls.Add(_statusBanner)

        AddHandler card.Resize, AddressOf LayoutFormCard
        Return card
    End Function

    Private Sub LayoutFormCard(sender As Object, e As EventArgs)
        If _formCard Is Nothing OrElse _fldServer Is Nothing Then Return
        Dim w = _formCard.ClientSize.Width
        Const m As Integer = 22
        Const gap As Integer = 16

        AppTheme.PlaceFromRight(_fldServer, w, m, 16)

        Dim serverRight = m + _fldServer.Width + gap
        AppTheme.PlaceFromRight(_rbSql, w, serverRight, 28)
        AppTheme.PlaceFromRight(_rbWindows, w, serverRight, 54)

        AppTheme.PlaceFromRight(_fldUser, w, m, 90)
        Dim userRight = m + _fldUser.Width + gap
        AppTheme.PlaceFromRight(_fldPassword, w, userRight, 90)

        AppTheme.PlaceFromRight(_chkTrust, w, m, 162)

        AppTheme.PlaceFromRight(_btnLoadDb, w, m, 198)
        AppTheme.PlaceFromRight(_btnTest, w, m + _btnLoadDb.Width + 12, 198)

        Dim bannerRight = m + _btnLoadDb.Width + 12 + _btnTest.Width + 16
        _statusBanner.Width = Math.Max(180, w - bannerRight - m)
        AppTheme.PlaceFromRight(_statusBanner, w, bannerRight, 202)
    End Sub

    Private Sub OnPanelResize(sender As Object, e As EventArgs)
        If _formCard Is Nothing Then Return
        Dim w = ClientSize.Width
        Dim m = AppTheme.PageMargin
        Dim title = Controls("title")
        Dim subtitle = Controls("subtitle")
        Dim lblDb = Controls("lblDb")
        Dim lblSummary = Controls("lblSummary")

        If title IsNot Nothing Then AppTheme.PlaceFromRight(title, w, m, 18)
        If subtitle IsNot Nothing Then AppTheme.PlaceFromRight(subtitle, w, m, 52)

        _formCard.Width = Math.Max(640, w - m * 2)
        AppTheme.PlaceFromRight(_formCard, w, m, 92)
        LayoutFormCard(_formCard, EventArgs.Empty)

        If lblDb IsNot Nothing Then AppTheme.PlaceFromRight(lblDb, w, m, _formCard.Bottom + 18)

        Dim colW = Math.Max(260, (w - m * 2 - 16) \ 2)
        Dim listTop = If(lblDb IsNot Nothing, lblDb.Bottom + 8, _formCard.Bottom + 40)
        Dim listH = Math.Max(160, ClientSize.Height - listTop - 16)

        _dbCard.Size = New Size(colW, listH)
        AppTheme.PlaceFromRight(_dbCard, w, m, listTop)

        If lblSummary IsNot Nothing Then
            AppTheme.PlaceFromRight(lblSummary, w, m + colW + 16, If(lblDb IsNot Nothing, lblDb.Top, _formCard.Bottom + 18))
        End If
        _summaryCard.Size = New Size(colW, listH)
        AppTheme.PlaceFromRight(_summaryCard, w, m + colW + 16, listTop)
    End Sub

    Public Sub LoadFromSession()
        Dim s = _session.SqlSettings
        If s Is Nothing Then
            s = New SqlConnectionSettings()
            _session.SqlSettings = s
        End If
        _fldServer.Text = If(String.IsNullOrWhiteSpace(s.Server), "localhost", s.Server)
        _rbWindows.Checked = s.UseWindowsAuth
        _rbSql.Checked = Not s.UseWindowsAuth
        _fldUser.Text = If(s.UserName, "sa")
        _fldPassword.Text = If(s.Password, "")
        _chkTrust.Checked = s.TrustServerCertificate
        OnAuthModeChanged(Nothing, EventArgs.Empty)

        _lstDatabases.Items.Clear()
        If _session.AvailableDatabases IsNot Nothing Then
            For Each db In _session.AvailableDatabases
                _lstDatabases.Items.Add(db)
            Next
            If Not String.IsNullOrWhiteSpace(_session.SelectedDatabase) Then
                For i = 0 To _lstDatabases.Items.Count - 1
                    Dim item = TryCast(_lstDatabases.Items(i), HolooDatabaseInfo)
                    If item IsNot Nothing AndAlso String.Equals(item.Name, _session.SelectedDatabase, StringComparison.OrdinalIgnoreCase) Then
                        _lstDatabases.SelectedIndex = i
                        Exit For
                    End If
                Next
            End If
        End If

        If _session.HolooProbe IsNot Nothing Then
            _txtSummary.Text = _session.HolooProbe.SummaryText
        Else
            _txtSummary.Text = "پس از انتخاب دیتابیس، خلاصه جداول هلو اینجا نمایش داده می‌شود."
        End If

        If _session.IsSqlConnected Then
            _statusBanner.SetStatus("متصل — دیتابیس‌ها دریافت شد", ContextBanner.BannerTone.Success)
        Else
            _statusBanner.SetStatus("هنوز اتصال برقرار نشده", ContextBanner.BannerTone.Neutral)
        End If
    End Sub

    Private Sub OnAuthModeChanged(sender As Object, e As EventArgs)
        Dim sqlAuth = _rbSql.Checked
        _fldUser.Enabled = sqlAuth AndAlso Not _isBusy
        _fldPassword.Enabled = sqlAuth AndAlso Not _isBusy
    End Sub

    Private Sub ApplySettingsFromUi()
        If _session.SqlSettings Is Nothing Then _session.SqlSettings = New SqlConnectionSettings()
        Dim s = _session.SqlSettings
        s.Server = _fldServer.Text.Trim()
        s.UseWindowsAuth = _rbWindows.Checked
        s.UserName = _fldUser.Text.Trim()
        s.Password = _fldPassword.Text
        s.TrustServerCertificate = _chkTrust.Checked
        s.Database = If(_session.SelectedDatabase, "")
    End Sub

    Private Sub SetBusy(busy As Boolean, Optional message As String = Nothing)
        _isBusy = busy
        If busy Then
            _busy.ShowBusy(message)
        Else
            _busy.HideBusy()
        End If
        _btnTest.Enabled = Not busy
        _btnLoadDb.Enabled = Not busy
        _lstDatabases.Enabled = Not busy
        _fldServer.Enabled = Not busy
        _rbSql.Enabled = Not busy
        _rbWindows.Enabled = Not busy
        _chkTrust.Enabled = Not busy
        OnAuthModeChanged(Nothing, EventArgs.Empty)
    End Sub

    Private Sub CancelPending()
        If _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
            _cts = Nothing
        End If
    End Sub

    Private Async Sub OnTestClick(sender As Object, e As EventArgs)
        If _isBusy Then Return
        ApplySettingsFromUi()
        If String.IsNullOrWhiteSpace(_session.SqlSettings.Server) Then
            MessageBox.Show(Me, "نام سرور را وارد کنید.", "ورودی ناقص",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim msg = Await AsyncUi.Run(Of String)(Me,
                Function(ct) _sql.TestConnectionAsync(_session.SqlSettings, ct),
                Sub(b) SetBusy(b, "در حال تست اتصال..."),
                _cts.Token).ConfigureAwait(True)
            _statusBanner.SetStatus(msg, ContextBanner.BannerTone.Success)
        Catch ex As Exception
            _statusBanner.SetStatus("اتصال ناموفق", ContextBanner.BannerTone.Danger)
            AsyncUi.ShowError(Me, "خطا در تست اتصال", ex)
        End Try
    End Sub

    Private Async Sub OnLoadDatabasesClick(sender As Object, e As EventArgs)
        If _isBusy Then Return
        ApplySettingsFromUi()
        If String.IsNullOrWhiteSpace(_session.SqlSettings.Server) Then
            MessageBox.Show(Me, "نام سرور را وارد کنید.", "ورودی ناقص",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim databases = Await AsyncUi.Run(Of List(Of HolooDatabaseInfo))(Me,
                Function(ct) _sql.ListDatabasesAsync(_session.SqlSettings, ct),
                Sub(b) SetBusy(b, "در حال دریافت و بررسی دیتابیس‌ها..."),
                _cts.Token).ConfigureAwait(True)

            _session.AvailableDatabases = databases
            _session.IsSqlConnected = True
            _session.SelectedDatabase = Nothing
            _session.HolooProbe = Nothing
            _session.SqlSettings.Database = ""

            _lstDatabases.Items.Clear()
            For Each db In databases
                _lstDatabases.Items.Add(db)
            Next

            _txtSummary.Text = "دیتابیس مورد نظر (ترجیحاً با علامت ★ هلو) را انتخاب کنید."
            _statusBanner.SetStatus("متصل — " & databases.Count.ToString() & " دیتابیس یافت شد", ContextBanner.BannerTone.Success)

            Dim holooFirst = databases.FirstOrDefault(Function(x) x.LooksLikeHoloo)
            If holooFirst IsNot Nothing Then
                _lstDatabases.SelectedItem = holooFirst
            End If

            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _session.IsSqlConnected = False
            _session.AvailableDatabases = Nothing
            _session.SelectedDatabase = Nothing
            _session.HolooProbe = Nothing
            _lstDatabases.Items.Clear()
            _statusBanner.SetStatus("دریافت دیتابیس ناموفق", ContextBanner.BannerTone.Danger)
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            AsyncUi.ShowError(Me, "خطا در دریافت دیتابیس‌ها", ex)
        End Try
    End Sub

    Private Async Sub OnDatabaseSelected(sender As Object, e As EventArgs)
        If _isBusy Then Return
        Dim info = TryCast(_lstDatabases.SelectedItem, HolooDatabaseInfo)
        If info Is Nothing Then
            _session.SelectedDatabase = Nothing
            _session.HolooProbe = Nothing
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            Return
        End If

        ApplySettingsFromUi()
        _session.SelectedDatabase = info.Name
        _session.SqlSettings.Database = info.Name

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim probe = Await AsyncUi.Run(Of HolooProbeResult)(Me,
                Function(ct) _sql.ProbeDatabaseAsync(_session.SqlSettings, info.Name, ct),
                Sub(b) SetBusy(b, "در حال بررسی ساختار دیتابیس «" & info.Name & "»..."),
                _cts.Token).ConfigureAwait(True)

            _session.HolooProbe = probe
            _txtSummary.Text = probe.SummaryText
            If probe.LooksLikeHoloo Then
                _statusBanner.SetStatus("دیتابیس هلو انتخاب شد: " & info.Name, ContextBanner.BannerTone.Success)
            Else
                _statusBanner.SetStatus("دیتابیس انتخاب شد (ساختار هلو قطعی نیست): " & info.Name, ContextBanner.BannerTone.Warning)
            End If
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _session.HolooProbe = Nothing
            _txtSummary.Text = "بررسی ساختار ناموفق بود."
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            AsyncUi.ShowError(Me, "خطا در بررسی دیتابیس", ex)
        End Try
    End Sub

    Protected Overrides Sub Dispose(disposing As Boolean)
        If disposing Then CancelPending()
        MyBase.Dispose(disposing)
    End Sub
End Class
