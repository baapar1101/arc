Imports System.Threading

Friend Class PreflightPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _preflight As New PreflightService()

    Private ReadOnly _txtReport As TextBox
    Private ReadOnly _reportCard As RoundedCard
    Private ReadOnly _gridCard As RoundedCard
    Private ReadOnly _grid As DataGridView
    Private ReadOnly _chkOverrideCurrency As CheckBox
    Private ReadOnly _chkLockProfile As CheckBox
    Private ReadOnly _btnRefresh As Button
    Private ReadOnly _statusBanner As ContextBanner
    Private _cts As CancellationTokenSource
    Private _busy As Boolean

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        Dim header = PageHeader.Create(
            "بازبینی تطبیقی و قفل نگاشت",
            "ارز، پارتیشن اسناد و جدول نگاشت سرفصل بررسی می‌شوند. برای Full History باید پروفایل نگاشت قفل شود.")

        _btnRefresh = New Button() With {
            .Text = "اجرای بررسی مجدد",
            .Size = New Size(170, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnRefresh"
        }
        AppTheme.StyleSecondaryButton(_btnRefresh)
        AddHandler _btnRefresh.Click, AddressOf OnRefreshClick

        _statusBanner = New ContextBanner() With {.Width = 420, .Name = "statusBanner"}
        _statusBanner.SetStatus("برای شروع، بررسی را اجرا کنید", ContextBanner.BannerTone.Neutral)

        _reportCard = New RoundedCard() With {.Padding = New Padding(12), .Name = "reportCard"}
        _txtReport = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = AppTheme.FontUi,
            .BackColor = AppTheme.BgMuted,
            .ForeColor = AppTheme.TextPrimary,
            .BorderStyle = BorderStyle.None,
            .Dock = DockStyle.Fill,
            .RightToLeft = RightToLeft.Yes,
            .Name = "txtReport"
        }
        _reportCard.Controls.Add(_txtReport)

        _gridCard = New RoundedCard() With {.Padding = New Padding(8), .Name = "gridCard"}
        _grid = New DataGridView() With {
            .Dock = DockStyle.Fill,
            .ReadOnly = False,
            .AllowUserToAddRows = False,
            .AllowUserToDeleteRows = False,
            .AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            .BackgroundColor = AppTheme.BgMuted,
            .BorderStyle = BorderStyle.None,
            .RowHeadersVisible = False,
            .SelectionMode = DataGridViewSelectionMode.CellSelect,
            .Font = AppTheme.FontUi,
            .RightToLeft = RightToLeft.Yes,
            .Name = "gridSarfasl",
            .EditMode = DataGridViewEditMode.EditOnEnter
        }
        _grid.ColumnHeadersDefaultCellStyle.Font = AppTheme.FontUiBold
        AddHandler _grid.CellEndEdit, AddressOf OnGridCellEndEdit
        _gridCard.Controls.Add(_grid)

        _chkOverrideCurrency = New CheckBox() With {
            .Text = "عدم تطابق ارز را می‌پذیرم و ادامه می‌دهم",
            .AutoSize = True,
            .Visible = False,
            .Name = "chkOverride"
        }
        AppTheme.StyleCheckBox(_chkOverrideCurrency)
        _chkOverrideCurrency.Font = AppTheme.FontUiBold
        _chkOverrideCurrency.ForeColor = AppTheme.Warning
        AddHandler _chkOverrideCurrency.CheckedChanged, Sub(s, e)
                                                            If _session.Preflight IsNot Nothing Then
                                                                _session.AllowCurrencyMismatch = _chkOverrideCurrency.Checked
                                                            End If
                                                            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
                                                        End Sub

        _chkLockProfile = New CheckBox() With {
            .Text = "جدول نگاشت سرفصل را بازبینی کردم و پروفایل را قفل می‌کنم",
            .AutoSize = True,
            .Visible = False,
            .Name = "chkLockProfile"
        }
        AppTheme.StyleCheckBox(_chkLockProfile)
        _chkLockProfile.Font = AppTheme.FontUiBold
        _chkLockProfile.ForeColor = AppTheme.AccentDark
        AddHandler _chkLockProfile.CheckedChanged, AddressOf OnLockProfileChanged

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_btnRefresh)
        Controls.Add(_statusBanner)
        Controls.Add(_reportCard)
        Controls.Add(_gridCard)
        Controls.Add(_chkOverrideCurrency)
        Controls.Add(_chkLockProfile)

        AddHandler Resize, AddressOf OnPanelResize
        OnPanelResize(Me, EventArgs.Empty)
        AppTheme.ApplyRtlTree(Me, False)
        OnPanelResize(Me, EventArgs.Empty)
    End Sub

    Private Sub OnPanelResize(sender As Object, e As EventArgs)
        Dim w = ClientSize.Width
        Dim m = AppTheme.PageMargin
        Dim title = Controls("title")
        Dim subtitle = Controls("subtitle")
        If title IsNot Nothing Then AppTheme.PlaceFromRight(title, w, m, 18)
        If subtitle IsNot Nothing Then AppTheme.PlaceFromRight(subtitle, w, m, 52)

        AppTheme.PlaceFromRight(_btnRefresh, w, m, 92)
        _statusBanner.Width = Math.Min(480, Math.Max(220, w - m * 2 - _btnRefresh.Width - 16))
        AppTheme.PlaceFromRight(_statusBanner, w, m + _btnRefresh.Width + 16, 98)

        Dim contentTop = 148
        Dim footerH = 70
        Dim avail = Math.Max(240, ClientSize.Height - contentTop - footerH)
        Dim reportH = Math.Max(120, CInt(avail * 0.42))
        Dim gridH = Math.Max(120, avail - reportH - 12)

        _reportCard.Width = Math.Max(640, w - m * 2)
        _reportCard.Height = reportH
        AppTheme.PlaceFromRight(_reportCard, w, m, contentTop)

        _gridCard.Width = _reportCard.Width
        _gridCard.Height = gridH
        AppTheme.PlaceFromRight(_gridCard, w, m, _reportCard.Bottom + 8)

        Dim y = _gridCard.Bottom + 10
        AppTheme.PlaceFromRight(_chkLockProfile, w, m, y)
        AppTheme.PlaceFromRight(_chkOverrideCurrency, w, m, y + 28)
    End Sub

    Public Async Function RunPreflightAsync() As Task
        If _busy Then Return
        CancelPending()
        _cts = New CancellationTokenSource()
        _busy = True
        _btnRefresh.Enabled = False
        _chkLockProfile.Enabled = False
        _statusBanner.SetStatus("در حال بررسی...", ContextBanner.BannerTone.Info)
        OnPanelResize(Me, EventArgs.Empty)
        Try
            Dim report = Await _preflight.BuildReportAsync(_session, _api, _cts.Token).ConfigureAwait(True)
            _session.Preflight = report
            _session.AllowCurrencyMismatch = False
            _chkOverrideCurrency.Checked = False
            _chkOverrideCurrency.Visible = Not report.CurrencyMatched
            _txtReport.Text = FormatReport(report)
            BindGrid(_session.SarfaslProfile)

            _chkLockProfile.Visible = report.RequiresSarfaslLock
            _chkLockProfile.Enabled = report.RequiresSarfaslLock AndAlso
                (_session.SarfaslProfile Is Nothing OrElse _session.SarfaslProfile.CriticalUnmappedCount = 0)
            RemoveHandler _chkLockProfile.CheckedChanged, AddressOf OnLockProfileChanged
            _chkLockProfile.Checked = _session.SarfaslProfileLocked
            AddHandler _chkLockProfile.CheckedChanged, AddressOf OnLockProfileChanged

            If report.CanProceed AndAlso (Not report.RequiresSarfaslLock OrElse _session.SarfaslProfileLocked) Then
                _statusBanner.SetStatus("بررسی انجام شد — می‌توانید ادامه دهید", ContextBanner.BannerTone.Success)
            ElseIf report.RequiresSarfaslLock AndAlso Not _session.SarfaslProfileLocked Then
                _statusBanner.SetStatus("پروفایل نگاشت را بازبینی و قفل کنید", ContextBanner.BannerTone.Warning)
            Else
                _statusBanner.SetStatus("مغایرت بحرانی وجود دارد", ContextBanner.BannerTone.Danger)
            End If
            OnPanelResize(Me, EventArgs.Empty)
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _statusBanner.SetStatus("بررسی ناموفق", ContextBanner.BannerTone.Danger)
            AsyncUi.ShowError(Me, "خطا در بازبینی", ex)
        Finally
            _busy = False
            _btnRefresh.Enabled = True
        End Try
    End Function

    Private Sub BindGrid(profile As SarfaslProfile)
        _grid.DataSource = Nothing
        _grid.Columns.Clear()
        If profile Is Nothing OrElse profile.Entries Is Nothing Then Return

        Dim table As New DataTable()
        table.Columns.Add("Col", GetType(String))
        table.Columns.Add("Moien", GetType(String))
        table.Columns.Add("Name", GetType(String))
        table.Columns.Add("Lines", GetType(Long))
        table.Columns.Add("Decision", GetType(String))
        table.Columns.Add("Target", GetType(String))
        table.Columns.Add("Override", GetType(String))

        Dim ordered = profile.Entries.
            OrderBy(Function(e) If(e.Decision = "Unmapped", 0, If(e.Decision.StartsWith("Business"), 1, 2))).
            ThenByDescending(Function(e) e.LineCount).
            Take(500)
        For Each e In ordered
            table.Rows.Add(e.Col, e.Moien, e.Name, e.LineCount, e.Decision, e.TargetCode, If(e.OverrideCode, ""))
        Next
        _grid.DataSource = table
        For Each colName In {"Col", "Moien", "Name", "Lines", "Decision", "Target"}
            If _grid.Columns.Contains(colName) Then _grid.Columns(colName).ReadOnly = True
        Next
        If _grid.Columns.Contains("Name") Then _grid.Columns("Name").FillWeight = 160
        If _grid.Columns.Contains("Target") Then _grid.Columns("Target").FillWeight = 100
        If _grid.Columns.Contains("Override") Then
            _grid.Columns("Override").ReadOnly = False
            _grid.Columns("Override").FillWeight = 100
            _grid.Columns("Override").HeaderText = "کد جایگزین"
        End If
    End Sub

    Private Sub OnGridCellEndEdit(sender As Object, e As DataGridViewCellEventArgs)
        If e.RowIndex < 0 OrElse _session.SarfaslProfile Is Nothing Then Return
        If Not String.Equals(_grid.Columns(e.ColumnIndex).Name, "Override", StringComparison.OrdinalIgnoreCase) Then Return
        Dim row = _grid.Rows(e.RowIndex)
        Dim col = Convert.ToString(row.Cells("Col").Value)
        Dim moien = Convert.ToString(row.Cells("Moien").Value)
        Dim overrideCode = Convert.ToString(row.Cells("Override").Value)
        Dim entry = _session.SarfaslProfile.Find(col, moien)
        If entry Is Nothing Then Return
        entry.OverrideCode = If(String.IsNullOrWhiteSpace(overrideCode), Nothing, overrideCode.Trim())
        ' تغییر نگاشت ⇒ قفل قبلی باطل
        If _session.SarfaslProfileLocked Then
            _session.SarfaslProfile.Locked = False
            _session.SarfaslProfile.LockedAt = Nothing
            _session.SarfaslProfileLocked = False
            RemoveHandler _chkLockProfile.CheckedChanged, AddressOf OnLockProfileChanged
            _chkLockProfile.Checked = False
            AddHandler _chkLockProfile.CheckedChanged, AddressOf OnLockProfileChanged
            _statusBanner.SetStatus("نگاشت تغییر کرد — دوباره قفل کنید", ContextBanner.BannerTone.Warning)
        End If
        If _session.SelectedBusiness IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(_session.SelectedDatabase) Then
            Dim store As New SarfaslProfileStore(_session.SelectedBusiness.Id, _session.SelectedDatabase)
            store.Save(_session.SarfaslProfile)
        End If
        RaiseEvent SelectionChanged(Me, EventArgs.Empty)
    End Sub

    Private Sub OnLockProfileChanged(sender As Object, e As EventArgs)
        If _session.SelectedBusiness Is Nothing OrElse String.IsNullOrWhiteSpace(_session.SelectedDatabase) Then Return
        If _session.SarfaslProfile Is Nothing Then Return

        Dim store As New SarfaslProfileStore(_session.SelectedBusiness.Id, _session.SelectedDatabase)
        If _chkLockProfile.Checked Then
            If _session.SarfaslProfile.CriticalUnmappedCount > 0 Then
                _chkLockProfile.Checked = False
                MessageBox.Show(Me, "تا وقتی سرفصل بحرانی بدون نگاشت وجود دارد نمی‌توان پروفایل را قفل کرد.",
                                "قفل نامعتبر", MessageBoxButtons.OK, MessageBoxIcon.Warning,
                                MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
                Return
            End If
            store.LockAndSave(_session.SarfaslProfile)
            _session.SarfaslProfileLocked = True
            _statusBanner.SetStatus("پروفایل نگاشت قفل شد", ContextBanner.BannerTone.Success)
        Else
            _session.SarfaslProfile.Locked = False
            _session.SarfaslProfile.LockedAt = Nothing
            store.Save(_session.SarfaslProfile)
            _session.SarfaslProfileLocked = False
            _statusBanner.SetStatus("قفل پروفایل برداشته شد — برای انتقال دوباره قفل کنید", ContextBanner.BannerTone.Warning)
        End If
        RaiseEvent SelectionChanged(Me, EventArgs.Empty)
    End Sub

    Private Async Sub OnRefreshClick(sender As Object, e As EventArgs)
        Await RunPreflightAsync().ConfigureAwait(True)
    End Sub

    Private Shared Function FormatReport(report As PreflightReport) As String
        Dim sb As New Text.StringBuilder()
        sb.AppendLine("=== خلاصه تطبیق ===")
        sb.AppendLine("شرکت هلو: " & report.HolooCompanyName)
        sb.AppendLine("کسب‌وکار حسابیکس: " & report.HesabixBusinessName)
        sb.AppendLine("ارز پایه هلو: " & report.HolooBaseCurrency)
        sb.AppendLine("ارز حسابیکس: " & report.HesabixCurrencyTitle & " (" & report.HesabixCurrencyCode & ") #" & report.HesabixCurrencyId.ToString())
        sb.AppendLine("تطبیق ارز: " & If(report.CurrencyMatched, "بله", "خیر"))
        sb.AppendLine()
        sb.AppendLine("=== تعداد رکورد منابع ===")
        For Each kv In report.ModuleCounts.OrderBy(Function(x) x.Key)
            sb.AppendLine("• " & MigrationModuleInfo.TitleOf(CType([Enum].Parse(GetType(MigrationModule), kv.Key), MigrationModule)) & ": " & kv.Value.ToString("N0"))
        Next
        sb.AppendLine()
        sb.AppendLine("=== جزئیات ===")
        For Each issue In report.Issues
            Dim mark = If(issue.Severity = "error", "[خطا] ", If(issue.Severity = "warning", "[هشدار] ", "[اطلاعات] "))
            sb.AppendLine(mark & issue.Title)
            sb.AppendLine("   " & issue.Detail)
            sb.AppendLine()
        Next
        Return sb.ToString()
    End Function

    Public ReadOnly Property CanProceed As Boolean
        Get
            If _session.Preflight Is Nothing Then Return False
            Dim baseOk = _session.Preflight.CanProceed OrElse
                (_session.AllowCurrencyMismatch AndAlso Not _session.Preflight.CurrencyMatched)
            If Not baseOk Then Return False
            If _session.Preflight.RequiresSarfaslLock AndAlso Not _session.SarfaslProfileLocked Then Return False
            If _session.SarfaslProfile IsNot Nothing AndAlso _session.SarfaslProfile.CriticalUnmappedCount > 0 Then Return False
            Return True
        End Get
    End Property

    Private Sub CancelPending()
        If _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
            _cts = Nothing
        End If
    End Sub

    Protected Overrides Sub Dispose(disposing As Boolean)
        If disposing Then CancelPending()
        MyBase.Dispose(disposing)
    End Sub
End Class
