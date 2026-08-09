Imports System.Threading

Friend Class TransferPanel
    Inherits UserControl

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _baseTransfer As New BaseDataTransferService()
    Private ReadOnly _docTransfer As New DocumentTransferService()

    Private ReadOnly _progress As ProgressBar
    Private ReadOnly _lblModule As Label
    Private ReadOnly _txtLog As TextBox
    Private ReadOnly _btnStart As Button
    Private ReadOnly _btnCancel As Button
    Private ReadOnly _chkReset As CheckBox
    Private ReadOnly _lblCheckpoint As Label
    Private _cts As CancellationTokenSource
    Private _running As Boolean

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(28, 16, 28, 16)

        Dim title As New Label() With {
            .Text = "انتقال اطلاعات",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .AutoSize = True,
            .Location = New Point(28, 12),
            .RightToLeft = RightToLeft.Yes
        }
        Dim subtitle As New Label() With {
            .Text = "پایه + اسناد سال‌به‌سال. در صورت قطع، از checkpoint ادامه می‌یابد.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .AutoSize = True,
            .Location = New Point(28, 52),
            .RightToLeft = RightToLeft.Yes
        }

        _chkReset = New CheckBox() With {
            .Text = "شروع از صفر (پاک کردن checkpoint)",
            .AutoSize = True,
            .Location = New Point(28, 90),
            .RightToLeft = RightToLeft.Yes,
            .ForeColor = AppTheme.TextSecondary
        }

        _btnStart = New Button() With {.Text = "شروع / ادامه انتقال", .Size = New Size(180, 40), .Location = New Point(28, 120), .RightToLeft = RightToLeft.Yes}
        AppTheme.StylePrimaryButton(_btnStart)
        AddHandler _btnStart.Click, AddressOf OnStartClick

        _btnCancel = New Button() With {.Text = "توقف", .Size = New Size(100, 40), .Location = New Point(220, 120), .Enabled = False, .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleSecondaryButton(_btnCancel)
        AddHandler _btnCancel.Click, AddressOf OnCancelClick

        _lblModule = New Label() With {
            .AutoSize = True,
            .Location = New Point(28, 175),
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Text = "آماده"
        }
        _progress = New ProgressBar() With {
            .Location = New Point(28, 205),
            .Height = 18,
            .Minimum = 0,
            .Maximum = 100
        }

        _txtLog = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Location = New Point(28, 240),
            .Font = AppTheme.FontStep,
            .BackColor = Color.FromArgb(15, 23, 42),
            .ForeColor = Color.FromArgb(226, 232, 240),
            .RightToLeft = RightToLeft.Yes
        }

        _lblCheckpoint = New Label() With {
            .AutoSize = True,
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes,
            .Text = ""
        }

        Controls.Add(title)
        Controls.Add(subtitle)
        Controls.Add(_chkReset)
        Controls.Add(_btnStart)
        Controls.Add(_btnCancel)
        Controls.Add(_lblModule)
        Controls.Add(_progress)
        Controls.Add(_txtLog)
        Controls.Add(_lblCheckpoint)

        AddHandler _baseTransfer.ProgressChanged, AddressOf OnTransferProgress
        AddHandler _docTransfer.ProgressChanged, AddressOf OnTransferProgress
        AddHandler Resize, Sub(s, e)
                               _progress.Width = Math.Max(640, ClientSize.Width - 56)
                               _txtLog.Width = _progress.Width
                               _txtLog.Height = Math.Max(180, ClientSize.Height - 320)
                               _lblCheckpoint.Location = New Point(28, _txtLog.Bottom + 8)
                           End Sub
        OnResize(EventArgs.Empty)
        AppTheme.ApplyRtlTree(Me, False)
    End Sub

    Public Sub Prepare()
        Dim store As New CheckpointStore(_session.SelectedBusiness.Id, _session.SelectedDatabase)
        _lblCheckpoint.Text = "مسیر checkpoint: " & store.FilePath
        If Not _running Then
            AppendLog("آماده برای شروع یا ادامه انتقال.")
        End If
    End Sub

    Private Async Sub OnStartClick(sender As Object, e As EventArgs)
        If _running Then Return
        If _session.SelectedBusiness Is Nothing OrElse Not _session.CanProceedFromHolooSql Then
            MessageBox.Show(Me, "ابتدا حسابیکس و دیتابیس هلو را کامل کنید.", "شروع ممکن نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If
        Dim modules = If(_session.SelectedModules, MigrationModuleInfo.GetAllModules()).
            Where(Function(x) x.Selected AndAlso x.Enabled).
            Select(Function(x) x.ModuleKey).ToList()
        If modules.Count = 0 Then
            MessageBox.Show(Me, "هیچ بخشی انتخاب نشده است.", "شروع ممکن نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If
        Dim currencyId = If(_session.Preflight IsNot Nothing, _session.Preflight.HesabixCurrencyId, 0)
        If currencyId <= 0 Then
            MessageBox.Show(Me, "شناسه ارز کسب‌وکار مشخص نیست. ابتدا بازبینی تطبیقی را اجرا کنید.", "شروع ممکن نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If

        Dim hasDocs = modules.Any(Function(m) MigrationModuleInfo.IsDocumentModule(m))
        Dim skipOb = hasDocs

        _running = True
        _btnStart.Enabled = False
        _btnCancel.Enabled = True
        _chkReset.Enabled = False
        CancelPending()
        _cts = New CancellationTokenSource()
        AppendLog("=== شروع انتقال ===")
        If skipOb Then AppendLog("حالت Full History: مانده افتتاحیه اشخاص/کالا جداگانه ارسال نمی‌شود.")

        Try
            Dim path = Await _baseTransfer.RunAsync(
                _session, _api, modules, currencyId, _chkReset.Checked, skipOb, _cts.Token).ConfigureAwait(True)
            AppendLog("پایان اطلاعات پایه. Checkpoint: " & path)

            If hasDocs Then
                AppendLog("=== شروع انتقال اسناد (سال‌به‌سال) ===")
                path = Await _docTransfer.RunAsync(
                    _session, _api, modules, currencyId, False, _cts.Token).ConfigureAwait(True)
                AppendLog("پایان اسناد. Checkpoint: " & path)
            End If

            _lblModule.Text = "پایان یافت"
            _lblModule.ForeColor = AppTheme.Success
            MessageBox.Show(Me, "انتقال به پایان رسید (موارد خطادار در لاگ و checkpoint ثبت شده‌اند).", "انتقال", MessageBoxButtons.OK, MessageBoxIcon.Information)
        Catch ex As OperationCanceledException
            AppendLog("انتقال توسط کاربر متوقف شد. اجرای بعدی از checkpoint ادامه می‌دهد.")
            _lblModule.Text = "متوقف شد"
            _lblModule.ForeColor = AppTheme.Warning
        Catch ex As Exception
            AppendLog("خطای کلی: " & ex.Message)
            _lblModule.Text = "خطا"
            _lblModule.ForeColor = AppTheme.Danger
            AsyncUi.ShowError(Me, "خطا در انتقال", ex)
        Finally
            _running = False
            _btnStart.Enabled = True
            _btnCancel.Enabled = False
            _chkReset.Enabled = True
        End Try
    End Sub

    Private Sub OnCancelClick(sender As Object, e As EventArgs)
        If _cts IsNot Nothing Then _cts.Cancel()
    End Sub

    Private Sub OnTransferProgress(sender As Object, e As TransferProgressEventArgs)
        If InvokeRequired Then
            BeginInvoke(New Action(Of Object, TransferProgressEventArgs)(AddressOf OnTransferProgress), sender, e)
            Return
        End If
        _lblModule.Text = e.ModuleTitle
        _lblModule.ForeColor = If(e.IsError, AppTheme.Danger, AppTheme.TextPrimary)
        If e.Total > 0 Then
            _progress.Maximum = Math.Max(e.Total, 1)
            _progress.Value = Math.Min(e.Current, _progress.Maximum)
        End If
        AppendLog("[" & e.ModuleTitle & "] " & e.Message)
    End Sub

    Private Sub AppendLog(text As String)
        If _txtLog.TextLength > 0 Then _txtLog.AppendText(Environment.NewLine)
        _txtLog.AppendText(DateTime.Now.ToString("HH:mm:ss") & "  " & text)
    End Sub

    Private Sub CancelPending()
        If _cts IsNot Nothing Then
            _cts.Dispose()
            _cts = Nothing
        End If
    End Sub
End Class
