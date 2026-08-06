Imports System.Threading

Friend Class PreflightPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _preflight As New PreflightService()

    Private ReadOnly _txtReport As TextBox
    Private ReadOnly _chkOverrideCurrency As CheckBox
    Private ReadOnly _btnRefresh As Button
    Private ReadOnly _lblStatus As Label
    Private _cts As CancellationTokenSource
    Private _busy As Boolean

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(28, 16, 28, 16)

        Dim title As New Label() With {
            .Text = "بازبینی تطبیقی قبل از انتقال",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .AutoSize = True,
            .Location = New Point(28, 12),
            .RightToLeft = RightToLeft.Yes
        }
        Dim subtitle As New Label() With {
            .Text = "ارز پایه، نام شرکت و تعداد رکوردها بررسی می‌شوند. در صورت مغایرت ارز، انتقال متوقف می‌شود مگر تأیید دستی بدهید.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .AutoSize = True,
            .Location = New Point(28, 52),
            .RightToLeft = RightToLeft.Yes
        }

        _btnRefresh = New Button() With {.Text = "اجرای بررسی مجدد", .Size = New Size(160, 36), .Location = New Point(28, 90), .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleSecondaryButton(_btnRefresh)
        AddHandler _btnRefresh.Click, AddressOf OnRefreshClick

        _lblStatus = New Label() With {
            .AutoSize = True,
            .Location = New Point(200, 98),
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes,
            .Text = ""
        }

        _txtReport = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Location = New Point(28, 140),
            .Font = AppTheme.FontUi,
            .BackColor = AppTheme.BgMuted,
            .RightToLeft = RightToLeft.Yes
        }

        _chkOverrideCurrency = New CheckBox() With {
            .Text = "عدم تطابق ارز را می‌پذیرم و ادامه می‌دهم",
            .AutoSize = True,
            .Visible = False,
            .RightToLeft = RightToLeft.Yes,
            .ForeColor = AppTheme.Warning,
            .Font = AppTheme.FontUiBold
        }
        AddHandler _chkOverrideCurrency.CheckedChanged, Sub(s, e)
                                                            If _session.Preflight IsNot Nothing Then
                                                                _session.AllowCurrencyMismatch = _chkOverrideCurrency.Checked
                                                            End If
                                                            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
                                                        End Sub

        Controls.Add(title)
        Controls.Add(subtitle)
        Controls.Add(_btnRefresh)
        Controls.Add(_lblStatus)
        Controls.Add(_txtReport)
        Controls.Add(_chkOverrideCurrency)

        AddHandler Resize, Sub(s, e)
                               _txtReport.Width = Math.Max(640, ClientSize.Width - 56)
                               _txtReport.Height = Math.Max(220, ClientSize.Height - 230)
                               _chkOverrideCurrency.Location = New Point(28, _txtReport.Bottom + 12)
                           End Sub
        OnResize(EventArgs.Empty)
        AppTheme.ApplyRtlTree(Me, False)
    End Sub

    Public Async Function RunPreflightAsync() As Task
        If _busy Then Return
        CancelPending()
        _cts = New CancellationTokenSource()
        _busy = True
        _btnRefresh.Enabled = False
        _lblStatus.Text = "در حال بررسی..."
        _lblStatus.ForeColor = AppTheme.TextMuted
        Try
            Dim report = Await _preflight.BuildReportAsync(_session, _api, _cts.Token).ConfigureAwait(True)
            _session.Preflight = report
            _session.AllowCurrencyMismatch = False
            _chkOverrideCurrency.Checked = False
            _chkOverrideCurrency.Visible = Not report.CurrencyMatched
            _txtReport.Text = FormatReport(report)
            If report.CanProceed Then
                _lblStatus.Text = "بررسی انجام شد — می‌توانید ادامه دهید"
                _lblStatus.ForeColor = AppTheme.Success
            Else
                _lblStatus.Text = "مغایرت بحرانی وجود دارد"
                _lblStatus.ForeColor = AppTheme.Danger
            End If
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _lblStatus.Text = "بررسی ناموفق"
            _lblStatus.ForeColor = AppTheme.Danger
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
