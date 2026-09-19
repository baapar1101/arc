Imports System.Threading

Friend Class PreflightPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _preflight As New PreflightService()

    Private ReadOnly _txtReport As TextBox
    Private ReadOnly _reportCard As RoundedCard
    Private ReadOnly _chkOverrideCurrency As CheckBox
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
            "بازبینی تطبیقی قبل از انتقال",
            "ارز پایه، نام شرکت و تعداد رکوردها بررسی می‌شوند. در صورت مغایرت ارز، انتقال متوقف می‌شود مگر تأیید دستی بدهید.")

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

        _reportCard = New RoundedCard() With {.Padding = New Padding(16), .Name = "reportCard"}
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

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_btnRefresh)
        Controls.Add(_statusBanner)
        Controls.Add(_reportCard)
        Controls.Add(_chkOverrideCurrency)

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

        _reportCard.Width = Math.Max(640, w - m * 2)
        _reportCard.Height = Math.Max(220, ClientSize.Height - 230)
        AppTheme.PlaceFromRight(_reportCard, w, m, 148)
        AppTheme.PlaceFromRight(_chkOverrideCurrency, w, m, _reportCard.Bottom + 14)
    End Sub

    Public Async Function RunPreflightAsync() As Task
        If _busy Then Return
        CancelPending()
        _cts = New CancellationTokenSource()
        _busy = True
        _btnRefresh.Enabled = False
        _statusBanner.SetStatus("در حال بررسی...", ContextBanner.BannerTone.Info)
        OnPanelResize(Me, EventArgs.Empty)
        Try
            Dim report = Await _preflight.BuildReportAsync(_session, _api, _cts.Token).ConfigureAwait(True)
            _session.Preflight = report
            _session.AllowCurrencyMismatch = False
            _chkOverrideCurrency.Checked = False
            _chkOverrideCurrency.Visible = Not report.CurrencyMatched
            _txtReport.Text = FormatReport(report)
            If report.CanProceed Then
                _statusBanner.SetStatus("بررسی انجام شد — می‌توانید ادامه دهید", ContextBanner.BannerTone.Success)
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
            If _session.Preflight.CanProceed Then Return True
            Return _session.AllowCurrencyMismatch AndAlso Not _session.Preflight.CurrencyMatched
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
