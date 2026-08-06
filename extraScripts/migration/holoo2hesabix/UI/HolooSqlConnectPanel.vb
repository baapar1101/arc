Imports System.Threading

Friend Class HolooSqlConnectPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _sql As HolooSqlService

    Private _txtServer As TextBox
    Private _rbWindows As RadioButton
    Private _rbSql As RadioButton
    Private _txtUser As TextBox
    Private _txtPassword As TextBox
    Private _chkTrust As CheckBox
    Private _btnTest As Button
    Private _btnLoadDb As Button
    Private _lstDatabases As ListBox
    Private _txtSummary As TextBox
    Private _lblStatus As Label
    Private _formCard As Panel
    Private _pnlBusy As Panel
    Private _lblBusy As Label
    Private _progress As ProgressBar

    Private _cts As CancellationTokenSource
    Private _busy As Boolean

    Public Sub New(session As MigrationSession, sql As HolooSqlService)
        _session = session
        _sql = sql

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(28, 16, 28, 16)

        Dim title As New Label() With {
            .AutoSize = True,
            .Text = "اتصال به SQL Server هلو",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .Location = New Point(28, 12),
            .RightToLeft = RightToLeft.Yes
        }
        Dim subtitle As New Label() With {
            .AutoSize = True,
            .Text = "اتصال را تست کنید، دیتابیس هلو را انتخاب کنید. در این مرحله هنوز انتقالی انجام نمی‌شود.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .Location = New Point(28, 50),
            .RightToLeft = RightToLeft.Yes
        }

        _formCard = CreateFormCard()
        _formCard.Location = New Point(28, 88)

        Dim lblDb As New Label() With {
            .AutoSize = True,
            .Text = "دیتابیس‌ها",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }

        _lstDatabases = New ListBox() With {
            .IntegralHeight = False,
            .Font = AppTheme.FontUi,
            .RightToLeft = RightToLeft.Yes,
            .BackColor = AppTheme.BgCard,
            .ForeColor = AppTheme.TextPrimary,
            .BorderStyle = BorderStyle.FixedSingle
        }
        AddHandler _lstDatabases.SelectedIndexChanged, AddressOf OnDatabaseSelected

        Dim lblSummary As New Label() With {
            .AutoSize = True,
            .Text = "خلاصه ساختار",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }
        _txtSummary = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = AppTheme.FontStep,
            .BackColor = AppTheme.BgMuted,
            .RightToLeft = RightToLeft.Yes
        }

        _pnlBusy = New Panel() With {
            .Visible = False,
            .BackColor = Color.FromArgb(180, 255, 255, 255),
            .Dock = DockStyle.Fill,
            .RightToLeft = RightToLeft.Yes
        }
        _lblBusy = New Label() With {
            .AutoSize = True,
            .Text = "در حال ارتباط با SQL Server...",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }
        _progress = New ProgressBar() With {
            .Style = ProgressBarStyle.Marquee,
            .MarqueeAnimationSpeed = 30,
            .Size = New Size(220, 8)
        }
        _pnlBusy.Controls.Add(_lblBusy)
        _pnlBusy.Controls.Add(_progress)

        Controls.Add(title)
        Controls.Add(subtitle)
        Controls.Add(_formCard)
        Controls.Add(lblDb)
        Controls.Add(_lstDatabases)
        Controls.Add(lblSummary)
        Controls.Add(_txtSummary)
        Controls.Add(_pnlBusy)
        _pnlBusy.BringToFront()

        lblDb.Name = "lblDb"
        lblSummary.Name = "lblSummary"
        AddHandler Resize, Sub(s, e)
                               LayoutChildren(lblDb, lblSummary)
                           End Sub
        LayoutChildren(lblDb, lblSummary)
        LoadFromSession()
        AppTheme.ApplyRtlTree(Me, False)
    End Sub

    Private Function CreateFormCard() As Panel
        Dim card As New Panel() With {
            .BackColor = AppTheme.BgCard,
            .Height = 210,
            .RightToLeft = RightToLeft.Yes
        }
        AddHandler card.Paint, Sub(s, e)
                                   Dim r = New Rectangle(0, 0, card.Width - 1, card.Height - 1)
                                   AppTheme.DrawRoundedRect(e.Graphics, r, 12, AppTheme.BgCard, AppTheme.Border)
                               End Sub

        Dim lblServer As New Label() With {.Text = "سرور / Instance", .AutoSize = True, .Location = New Point(16, 14), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _txtServer = New TextBox() With {.Location = New Point(16, 36), .Width = 280, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtServer)

        _rbSql = New RadioButton() With {.Text = "احراز هویت SQL Server", .AutoSize = True, .Location = New Point(320, 18), .Checked = True, .RightToLeft = RightToLeft.Yes, .ForeColor = AppTheme.TextPrimary, .Font = AppTheme.FontUi}
        _rbWindows = New RadioButton() With {.Text = "احراز هویت ویندوز", .AutoSize = True, .Location = New Point(320, 44), .RightToLeft = RightToLeft.Yes, .ForeColor = AppTheme.TextPrimary, .Font = AppTheme.FontUi}
        AddHandler _rbSql.CheckedChanged, AddressOf OnAuthModeChanged
        AddHandler _rbWindows.CheckedChanged, AddressOf OnAuthModeChanged

        Dim lblUser As New Label() With {.Text = "نام کاربری", .AutoSize = True, .Location = New Point(16, 72), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _txtUser = New TextBox() With {.Location = New Point(16, 94), .Width = 180, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtUser)

        Dim lblPass As New Label() With {.Text = "رمز عبور", .AutoSize = True, .Location = New Point(210, 72), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _txtPassword = New TextBox() With {.Location = New Point(210, 94), .Width = 180, .UseSystemPasswordChar = True, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtPassword)

        _chkTrust = New CheckBox() With {
            .Text = "اعتماد به گواهی سرور (برای اتصال محلی)",
            .AutoSize = True,
            .Checked = True,
            .Location = New Point(16, 130),
            .RightToLeft = RightToLeft.Yes,
            .ForeColor = AppTheme.TextSecondary,
            .Font = AppTheme.FontStep
        }

        _btnTest = New Button() With {.Text = "تست اتصال", .Size = New Size(120, 36), .Location = New Point(16, 162), .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleSecondaryButton(_btnTest)
        _btnTest.Height = 36
        AddHandler _btnTest.Click, AddressOf OnTestClick

        _btnLoadDb = New Button() With {.Text = "دریافت لیست دیتابیس‌ها", .Size = New Size(200, 36), .Location = New Point(150, 162), .RightToLeft = RightToLeft.Yes}
        AppTheme.StylePrimaryButton(_btnLoadDb)
        _btnLoadDb.Height = 36
        AddHandler _btnLoadDb.Click, AddressOf OnLoadDatabasesClick

        _lblStatus = New Label() With {
            .AutoSize = True,
            .Text = "هنوز اتصال برقرار نشده",
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .Location = New Point(350, 170),
            .RightToLeft = RightToLeft.Yes
        }

        card.Controls.Add(lblServer)
        card.Controls.Add(_txtServer)
        card.Controls.Add(_rbSql)
        card.Controls.Add(_rbWindows)
        card.Controls.Add(lblUser)
        card.Controls.Add(_txtUser)
        card.Controls.Add(lblPass)
        card.Controls.Add(_txtPassword)
        card.Controls.Add(_chkTrust)
        card.Controls.Add(_btnTest)
        card.Controls.Add(_btnLoadDb)
        card.Controls.Add(_lblStatus)

        AddHandler card.Resize, Sub(s, e)
                                    _lblStatus.Left = Math.Min(card.Width - 40, Math.Max(350, _btnLoadDb.Right + 16))
                                End Sub
        Return card
    End Function

    Private Sub LayoutChildren(lblDb As Label, lblSummary As Label)
        If _formCard Is Nothing Then Return
        _formCard.Width = Math.Max(640, ClientSize.Width - 56)

        lblDb.Location = New Point(28, _formCard.Bottom + 14)
        _lstDatabases.Location = New Point(28, lblDb.Bottom + 6)
        _lstDatabases.Size = New Size(Math.Max(260, (ClientSize.Width - 72) \ 2), Math.Max(160, ClientSize.Height - _lstDatabases.Top - 24))

        lblSummary.Location = New Point(_lstDatabases.Right + 16, lblDb.Top)
        _txtSummary.Location = New Point(_lstDatabases.Right + 16, _lstDatabases.Top)
        _txtSummary.Size = New Size(Math.Max(260, ClientSize.Width - _txtSummary.Left - 28), _lstDatabases.Height)

        If _pnlBusy.Visible Then CenterBusy()
    End Sub

    Private Sub CenterBusy()
        _lblBusy.Location = New Point((_pnlBusy.Width - _lblBusy.PreferredWidth) \ 2, (_pnlBusy.Height \ 2) - 24)
        _progress.Location = New Point((_pnlBusy.Width - _progress.Width) \ 2, _lblBusy.Bottom + 12)
    End Sub

    Public Sub LoadFromSession()
        Dim s = _session.SqlSettings
        If s Is Nothing Then
            s = New SqlConnectionSettings()
            _session.SqlSettings = s
        End If
        _txtServer.Text = If(String.IsNullOrWhiteSpace(s.Server), "localhost", s.Server)
        _rbWindows.Checked = s.UseWindowsAuth
        _rbSql.Checked = Not s.UseWindowsAuth
        _txtUser.Text = If(s.UserName, "sa")
        _txtPassword.Text = If(s.Password, "")
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
            _lblStatus.Text = "متصل — دیتابیس‌ها دریافت شد"
            _lblStatus.ForeColor = AppTheme.Success
        Else
            _lblStatus.Text = "هنوز اتصال برقرار نشده"
            _lblStatus.ForeColor = AppTheme.TextMuted
        End If
    End Sub

    Private Sub OnAuthModeChanged(sender As Object, e As EventArgs)
        Dim sqlAuth = _rbSql.Checked
        _txtUser.Enabled = sqlAuth
        _txtPassword.Enabled = sqlAuth
    End Sub

    Private Sub ApplySettingsFromUi()
        If _session.SqlSettings Is Nothing Then _session.SqlSettings = New SqlConnectionSettings()
        Dim s = _session.SqlSettings
        s.Server = _txtServer.Text.Trim()
        s.UseWindowsAuth = _rbWindows.Checked
        s.UserName = _txtUser.Text.Trim()
        s.Password = _txtPassword.Text
        s.TrustServerCertificate = _chkTrust.Checked
        s.Database = If(_session.SelectedDatabase, "")
    End Sub

    Private Sub SetBusy(busy As Boolean, Optional message As String = Nothing)
        _busy = busy
        _pnlBusy.Visible = busy
        _btnTest.Enabled = Not busy
        _btnLoadDb.Enabled = Not busy
        _lstDatabases.Enabled = Not busy
        _txtServer.Enabled = Not busy
        _rbSql.Enabled = Not busy
        _rbWindows.Enabled = Not busy
        _chkTrust.Enabled = Not busy
        OnAuthModeChanged(Nothing, EventArgs.Empty)
        If busy Then
            _lblBusy.Text = If(String.IsNullOrWhiteSpace(message), "در حال ارتباط با SQL Server...", message)
            CenterBusy()
            _pnlBusy.BringToFront()
        End If
    End Sub

    Private Sub CancelPending()
        If _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
            _cts = Nothing
        End If
    End Sub

    Private Async Sub OnTestClick(sender As Object, e As EventArgs)
        If _busy Then Return
        ApplySettingsFromUi()
        If String.IsNullOrWhiteSpace(_session.SqlSettings.Server) Then
            MessageBox.Show(Me, "نام سرور را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim msg = Await AsyncUi.Run(Of String)(Me,
                Function(ct) _sql.TestConnectionAsync(_session.SqlSettings, ct),
                Sub(b) SetBusy(b, "در حال تست اتصال..."),
                _cts.Token).ConfigureAwait(True)
            _lblStatus.Text = msg
            _lblStatus.ForeColor = AppTheme.Success
        Catch ex As Exception
            _lblStatus.Text = "اتصال ناموفق"
            _lblStatus.ForeColor = AppTheme.Danger
            AsyncUi.ShowError(Me, "خطا در تست اتصال", ex)
        End Try
    End Sub

    Private Async Sub OnLoadDatabasesClick(sender As Object, e As EventArgs)
        If _busy Then Return
        ApplySettingsFromUi()
        If String.IsNullOrWhiteSpace(_session.SqlSettings.Server) Then
            MessageBox.Show(Me, "نام سرور را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
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
            _lblStatus.Text = "متصل — " & databases.Count.ToString() & " دیتابیس یافت شد"
            _lblStatus.ForeColor = AppTheme.Success

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
            _lblStatus.Text = "دریافت دیتابیس ناموفق"
            _lblStatus.ForeColor = AppTheme.Danger
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            AsyncUi.ShowError(Me, "خطا در دریافت دیتابیس‌ها", ex)
        End Try
    End Sub

    Private Async Sub OnDatabaseSelected(sender As Object, e As EventArgs)
        If _busy Then Return
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
                _lblStatus.Text = "دیتابیس هلو انتخاب شد: " & info.Name
                _lblStatus.ForeColor = AppTheme.Success
            Else
                _lblStatus.Text = "دیتابیس انتخاب شد (ساختار هلو قطعی نیست): " & info.Name
                _lblStatus.ForeColor = AppTheme.Warning
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
