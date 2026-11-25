Imports System.Threading

Friend Class TransferPanel
    Inherits UserControl

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _baseTransfer As New BaseDataTransferService()
    Private ReadOnly _docTransfer As New DocumentTransferService()
    Private ReadOnly _liveSync As New LiveSyncService()
    Private ReadOnly _syncStore As New SyncProfileStore()

    Private ReadOnly _progress As ModernProgressBar
    Private ReadOnly _lblModule As Label
    Private ReadOnly _txtLog As TextBox
    Private ReadOnly _logCard As Panel
    Private ReadOnly _btnStart As Button
    Private ReadOnly _btnCancel As Button
    Private ReadOnly _chkReset As CheckBox
    Private ReadOnly _chkAutoSync As CheckBox
    Private ReadOnly _dtTime1 As DateTimePicker
    Private ReadOnly _dtTime2 As DateTimePicker
    Private ReadOnly _btnSyncNow As Button
    Private ReadOnly _lblSyncStatus As Label
    Private ReadOnly _checkpointBanner As ContextBanner
    Private _cts As CancellationTokenSource
    Private _running As Boolean

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        Dim header = PageHeader.Create(
            "انتقال اطلاعات",
            "پایه + اسناد سال‌به‌سال. همگام‌سازی خودکار روزی دو بار ایجاد، ویرایش و حذف را اعمال می‌کند.")

        _chkReset = New CheckBox() With {
            .Text = "شروع از صفر (پاک کردن checkpoint)",
            .AutoSize = True,
            .Name = "chkReset"
        }
        AppTheme.StyleCheckBox(_chkReset)
        _chkReset.ForeColor = AppTheme.TextSecondary

        _btnStart = New Button() With {
            .Text = "شروع / ادامه انتقال",
            .Size = New Size(180, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnStart"
        }
        AppTheme.StylePrimaryButton(_btnStart)
        AddHandler _btnStart.Click, AddressOf OnStartClick

        _btnCancel = New Button() With {
            .Text = "توقف",
            .Size = New Size(100, AppTheme.FieldHeight),
            .Enabled = False,
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnCancel"
        }
        AppTheme.StyleSecondaryButton(_btnCancel)
        AddHandler _btnCancel.Click, AddressOf OnCancelClick

        _chkAutoSync = New CheckBox() With {
            .Text = "همگام‌سازی خودکار روزی ۲ بار (ایجاد / ویرایش / حذف)",
            .AutoSize = True,
            .Name = "chkAutoSync"
        }
        AppTheme.StyleCheckBox(_chkAutoSync)
        _chkAutoSync.ForeColor = AppTheme.TextSecondary
        AddHandler _chkAutoSync.CheckedChanged, AddressOf OnAutoSyncChecked

        _dtTime1 = New DateTimePicker() With {
            .Format = DateTimePickerFormat.Custom,
            .CustomFormat = "HH:mm",
            .ShowUpDown = True,
            .Width = 78,
            .Height = AppTheme.FieldHeight - 6,
            .Value = Date.Today.AddHours(9),
            .RightToLeft = RightToLeft.No,
            .Name = "dtTime1"
        }
        _dtTime2 = New DateTimePicker() With {
            .Format = DateTimePickerFormat.Custom,
            .CustomFormat = "HH:mm",
            .ShowUpDown = True,
            .Width = 78,
            .Height = AppTheme.FieldHeight - 6,
            .Value = Date.Today.AddHours(17),
            .RightToLeft = RightToLeft.No,
            .Name = "dtTime2"
        }
        AddHandler _dtTime1.ValueChanged, AddressOf OnScheduleTimeChanged
        AddHandler _dtTime2.ValueChanged, AddressOf OnScheduleTimeChanged

        _btnSyncNow = New Button() With {
            .Text = "همگام کن الان",
            .Size = New Size(140, AppTheme.FieldHeight),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnSyncNow"
        }
        AppTheme.StyleSecondaryButton(_btnSyncNow)
        AddHandler _btnSyncNow.Click, AddressOf OnSyncNowClick

        _lblSyncStatus = New Label() With {
            .AutoSize = True,
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextMuted,
            .RightToLeft = RightToLeft.Yes,
            .Text = "",
            .Name = "lblSyncStatus"
        }

        _lblModule = New Label() With {
            .AutoSize = True,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Text = "آماده",
            .Name = "lblModule"
        }

        _progress = New ModernProgressBar() With {
            .Height = 28,
            .Maximum = 100,
            .Value = 0,
            .Caption = "",
            .Name = "progress"
        }

        _logCard = New Panel() With {
            .BackColor = Color.Transparent,
            .RightToLeft = RightToLeft.Yes,
            .Padding = New Padding(14),
            .Name = "logCard"
        }
        AddHandler _logCard.Paint, Sub(s, e)
                                       Dim r As New Rectangle(0, 0, _logCard.Width - 1, _logCard.Height - 1)
                                       AppTheme.DrawRoundedRect(e.Graphics, r, 14, Color.FromArgb(15, 23, 42), Color.FromArgb(30, 41, 59), 1.0F)
                                   End Sub

        _txtLog = New TextBox() With {
            .Multiline = True,
            .ReadOnly = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = AppTheme.FontStep,
            .BackColor = Color.FromArgb(15, 23, 42),
            .ForeColor = Color.FromArgb(226, 232, 240),
            .BorderStyle = BorderStyle.None,
            .Dock = DockStyle.Fill,
            .RightToLeft = RightToLeft.Yes,
            .Name = "txtLog"
        }
        _logCard.Controls.Add(_txtLog)

        _checkpointBanner = New ContextBanner() With {.Width = 520, .Name = "checkpointBanner"}
        _checkpointBanner.SetStatus("", ContextBanner.BannerTone.Neutral)

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_chkReset)
        Controls.Add(_btnStart)
        Controls.Add(_btnCancel)
        Controls.Add(_chkAutoSync)
        Controls.Add(_dtTime1)
        Controls.Add(_dtTime2)
        Controls.Add(_btnSyncNow)
        Controls.Add(_lblSyncStatus)
        Controls.Add(_lblModule)
        Controls.Add(_progress)
        Controls.Add(_logCard)
        Controls.Add(_checkpointBanner)

        AddHandler _baseTransfer.ProgressChanged, AddressOf OnTransferProgress
        AddHandler _docTransfer.ProgressChanged, AddressOf OnTransferProgress
        AddHandler _liveSync.ProgressChanged, AddressOf OnTransferProgress
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

        AppTheme.PlaceFromRight(_chkReset, w, m, 92)
        AppTheme.PlaceFromRight(_btnStart, w, m, 128)
        AppTheme.PlaceFromRight(_btnCancel, w, m + _btnStart.Width + 12, 128)

        AppTheme.PlaceFromRight(_chkAutoSync, w, m, 172)
        AppTheme.PlaceFromRight(_dtTime1, w, m, 204)
        AppTheme.PlaceFromRight(_dtTime2, w, m + _dtTime1.Width + 10, 204)
        AppTheme.PlaceFromRight(_btnSyncNow, w, m + _dtTime1.Width + _dtTime2.Width + 28, 200)
        AppTheme.PlaceFromRight(_lblSyncStatus, w, m, 242)

        AppTheme.PlaceFromRight(_lblModule, w, m, 268)
        _progress.Width = Math.Max(640, w - m * 2)
        AppTheme.PlaceFromRight(_progress, w, m, 296)

        _logCard.Width = _progress.Width
        _logCard.Height = Math.Max(150, ClientSize.Height - 400)
        AppTheme.PlaceFromRight(_logCard, w, m, 334)

        _checkpointBanner.Width = Math.Max(400, w - m * 2)
        AppTheme.PlaceFromRight(_checkpointBanner, w, m, _logCard.Bottom + 10)
    End Sub

    Public Sub Prepare()
        Dim store As New CheckpointStore(_session.SelectedBusiness.Id, _session.SelectedDatabase)
        _checkpointBanner.SetStatus("مسیر checkpoint: " & store.FilePath, ContextBanner.BannerTone.Neutral)
        LoadAutoSyncUi()
        OnPanelResize(Me, EventArgs.Empty)
        If Not _running Then
            AppendLog("آماده برای شروع، ادامه، یا همگام‌سازی اسناد جدید/ویرایش/حذف.")
        End If
    End Sub

    Private Async Sub OnStartClick(sender As Object, e As EventArgs)
        If _running Then Return
        If _session.SelectedBusiness Is Nothing OrElse Not _session.CanProceedFromHolooSql Then
            MessageBox.Show(Me, "ابتدا حسابیکس و دیتابیس هلو را کامل کنید.", "شروع ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If
        Dim modules = If(_session.SelectedModules, MigrationModuleInfo.GetAllModules()).
            Where(Function(x) x.Selected AndAlso x.Enabled).
            Select(Function(x) x.ModuleKey).ToList()
        If modules.Count = 0 Then
            MessageBox.Show(Me, "هیچ بخشی انتخاب نشده است.", "شروع ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If
        Dim currencyId = If(_session.Preflight IsNot Nothing, _session.Preflight.HesabixCurrencyId, 0)
        If currencyId <= 0 Then
            MessageBox.Show(Me, "شناسه ارز کسب‌وکار مشخص نیست. ابتدا بازبینی تطبیقی را اجرا کنید.", "شروع ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If

        Dim hasDocs = modules.Any(Function(m) MigrationModuleInfo.IsDocumentModule(m))
        Dim skipOb = hasDocs
        If hasDocs AndAlso Not _session.SarfaslProfileLocked Then
            MessageBox.Show(Me, "برای انتقال اسناد باید در مرحله بازبینی، پروفایل نگاشت سرفصل را قفل کنید.", "شروع ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If
        If hasDocs AndAlso _session.SarfaslProfile IsNot Nothing AndAlso _session.SarfaslProfile.CriticalUnmappedCount > 0 Then
            MessageBox.Show(Me, "سرفصل بحرانی بدون نگاشت باقی است؛ انتقال اسناد متوقف است.", "شروع ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If

        _running = True
        _btnStart.Enabled = False
        _btnSyncNow.Enabled = False
        _btnCancel.Enabled = True
        _chkReset.Enabled = False
        CancelPending()
        _cts = New CancellationTokenSource()
        AppendLog("=== شروع انتقال ===")
        If skipOb Then AppendLog("حالت Full History: مانده افتتاحیه اشخاص/کالا جداگانه ارسال نمی‌شود.")

        Try
            Dim path = Await _baseTransfer.RunAsync(
                _session, _api, modules, currencyId, _chkReset.Checked, skipOb, _cts.Token,
                ignoreCompleted:=True).ConfigureAwait(True)
            AppendLog("پایان اطلاعات پایه. Checkpoint: " & path)

            If hasDocs Then
                AppendLog("=== شروع انتقال اسناد (سال‌به‌سال) ===")
                path = Await _docTransfer.RunAsync(
                    _session, _api, modules, currencyId, False, _cts.Token, applyMutations:=True).ConfigureAwait(True)
                AppendLog("پایان اسناد. Checkpoint: " & path)
            End If

            If _chkAutoSync.Checked Then PersistAutoSync(True)

            _lblModule.Text = "پایان یافت"
            _lblModule.ForeColor = AppTheme.Success
            _progress.Caption = "پایان یافت"
            MessageBox.Show(Me, "انتقال به پایان رسید (موارد خطادار در لاگ و checkpoint ثبت شده‌اند).", "انتقال",
                            MessageBoxButtons.OK, MessageBoxIcon.Information, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
        Catch ex As OperationCanceledException
            AppendLog("انتقال توسط کاربر متوقف شد. اجرای بعدی از checkpoint ادامه می‌دهد.")
            _lblModule.Text = "متوقف شد"
            _lblModule.ForeColor = AppTheme.Warning
            _progress.Caption = "متوقف شد"
        Catch ex As Exception
            AppendLog("خطای کلی: " & ex.Message)
            _lblModule.Text = "خطا"
            _lblModule.ForeColor = AppTheme.Danger
            _progress.Caption = "خطا"
            AsyncUi.ShowError(Me, "خطا در انتقال", ex)
        Finally
            _running = False
            _btnStart.Enabled = True
            _btnCancel.Enabled = False
            _chkReset.Enabled = True
            _btnSyncNow.Enabled = True
        End Try
    End Sub

    Private Async Sub OnSyncNowClick(sender As Object, e As EventArgs)
        If _running Then Return
        If _session.SelectedBusiness Is Nothing OrElse Not _session.CanProceedFromHolooSql Then
            MessageBox.Show(Me, "ابتدا حسابیکس و دیتابیس هلو را کامل کنید.", "همگام‌سازی ممکن نیست",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            Return
        End If
        _running = True
        _btnStart.Enabled = False
        _btnSyncNow.Enabled = False
        _btnCancel.Enabled = True
        CancelPending()
        _cts = New CancellationTokenSource()
        AppendLog("=== همگام‌سازی زنده (ایجاد / ویرایش / حذف) ===")
        Try
            Dim result = Await _liveSync.RunAsync(_session, _api, _cts.Token).ConfigureAwait(True)
            AppendLog(If(result.Ok, "OK: ", "FAIL: ") & result.Message)
            PersistLastSync(result.Ok, result.Message)
            _lblModule.Text = If(result.Ok, "همگام شد", "خطای همگام‌سازی")
            _lblModule.ForeColor = If(result.Ok, AppTheme.Success, AppTheme.Danger)
            If Not result.Ok Then
                MessageBox.Show(Me, result.Message, "همگام‌سازی", MessageBoxButtons.OK, MessageBoxIcon.Warning,
                                MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
            End If
        Catch ex As OperationCanceledException
            AppendLog("همگام‌سازی متوقف شد.")
        Catch ex As Exception
            AppendLog("خطای همگام‌سازی: " & ex.Message)
            AsyncUi.ShowError(Me, "خطا در همگام‌سازی", ex)
        Finally
            _running = False
            _btnStart.Enabled = True
            _btnSyncNow.Enabled = True
            _btnCancel.Enabled = False
        End Try
    End Sub

    Private Sub OnAutoSyncChecked(sender As Object, e As EventArgs)
        If _running Then Return
        PersistAutoSync(_chkAutoSync.Checked)
    End Sub

    Private Sub OnScheduleTimeChanged(sender As Object, e As EventArgs)
        If _running Then Return
        If _chkAutoSync.Checked Then PersistAutoSync(True)
    End Sub

    Private Sub LoadAutoSyncUi()
        Dim profile = _syncStore.Load()
        RemoveHandler _chkAutoSync.CheckedChanged, AddressOf OnAutoSyncChecked
        RemoveHandler _dtTime1.ValueChanged, AddressOf OnScheduleTimeChanged
        RemoveHandler _dtTime2.ValueChanged, AddressOf OnScheduleTimeChanged
        If profile IsNot Nothing Then
            _chkAutoSync.Checked = profile.Enabled
            ApplyTime(profile.Time1, _dtTime1, 9)
            ApplyTime(profile.Time2, _dtTime2, 17)
            If Not String.IsNullOrWhiteSpace(profile.LastSyncAt) Then
                _lblSyncStatus.Text = "آخرین همگام‌سازی: " & profile.LastSyncAt &
                    If(profile.LastSyncOk, " — موفق", " — ناموفق") &
                    If(String.IsNullOrWhiteSpace(profile.LastSyncMessage), "", " (" & profile.LastSyncMessage & ")")
            Else
                _lblSyncStatus.Text = If(profile.Enabled, "همگام‌سازی خودکار روشن است. برنامه لازم نیست باز بماند.", "")
            End If
        Else
            _chkAutoSync.Checked = False
            _lblSyncStatus.Text = ""
        End If
        AddHandler _chkAutoSync.CheckedChanged, AddressOf OnAutoSyncChecked
        AddHandler _dtTime1.ValueChanged, AddressOf OnScheduleTimeChanged
        AddHandler _dtTime2.ValueChanged, AddressOf OnScheduleTimeChanged
    End Sub

    Private Shared Sub ApplyTime(raw As String, picker As DateTimePicker, hour As Integer)
        Dim t As TimeSpan
        If TimeSpan.TryParse(raw, t) Then
            picker.Value = Date.Today.Add(New TimeSpan(t.Hours, t.Minutes, 0))
        Else
            picker.Value = Date.Today.AddHours(hour)
        End If
    End Sub

    Private Sub PersistAutoSync(enabled As Boolean)
        Try
            Dim t1 = _dtTime1.Value.ToString("HH:mm")
            Dim t2 = _dtTime2.Value.ToString("HH:mm")
            Dim profile = _syncStore.CaptureFrom(_session, enabled, t1, t2)
            _syncStore.Save(profile)
            If enabled Then
                Dim err = WindowsTaskSync.Register(Application.ExecutablePath, SyncProfileStore.ParseTimes(profile))
                If err IsNot Nothing Then
                    AppendLog("ثبت زمان‌بندی ویندوز: " & err)
                    _lblSyncStatus.Text = err
                    MessageBox.Show(Me, err & Environment.NewLine & "می‌توانید با دکمه «همگام کن الان» یا باز نگه داشتن برنامه همگام کنید.",
                                    "زمان‌بندی", MessageBoxButtons.OK, MessageBoxIcon.Warning,
                                    MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
                Else
                    _lblSyncStatus.Text = "خودکار فعال شد: هر روز ساعت " & t1 & " و " & t2
                    AppendLog("وظیفه زمان‌بندی ویندوز ثبت شد: " & t1 & " و " & t2)
                End If
            Else
                WindowsTaskSync.Unregister()
                _lblSyncStatus.Text = "همگام‌سازی خودکار خاموش است."
            End If
        Catch ex As Exception
            AppendLog("خطا در ذخیره همگام‌سازی: " & ex.Message)
        End Try
    End Sub

    Private Sub PersistLastSync(ok As Boolean, message As String)
        Dim profile = _syncStore.Load()
        If profile Is Nothing Then
            profile = _syncStore.CaptureFrom(_session, _chkAutoSync.Checked,
                                             _dtTime1.Value.ToString("HH:mm"), _dtTime2.Value.ToString("HH:mm"))
        End If
        profile.LastSyncAt = DateTime.Now.ToString("s")
        profile.LastSyncOk = ok
        profile.LastSyncMessage = message
        _syncStore.Save(profile)
        LoadAutoSyncUi()
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
            _progress.Caption = e.Current.ToString("N0") & " / " & e.Total.ToString("N0")
        Else
            _progress.Caption = e.ModuleTitle
        End If
        AppendLog("[" & e.ModuleTitle & "] " & e.Message)
        OnPanelResize(Me, EventArgs.Empty)
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
