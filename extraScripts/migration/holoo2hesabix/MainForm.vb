Public Class MainForm
    Private ReadOnly _session As New MigrationSession()
    Private ReadOnly _api As New HesabixApiClient()
    Private ReadOnly _sql As New HolooSqlService()

    Private _sidebar As StepSidebar
    Private _contentHost As Panel
    Private _footer As Panel
    Private _btnBack As Button
    Private _btnNext As Button
    Private _lblFooterHint As Label

    Private _welcomePanel As WelcomePanel
    Private _hesabixPanel As HesabixConnectPanel
    Private _holooSqlPanel As HolooSqlConnectPanel
    Private _modulesPanel As SelectModulesPanel
    Private _preflightPanel As PreflightPanel
    Private _transferPanel As TransferPanel
    Private _currentStep As WizardStep = WizardStep.Welcome

    Private Sub MainForm_Load(sender As Object, e As EventArgs) Handles Me.Load
        ApplyWindowIcon()
        BuildUi()
        ShowStep(WizardStep.Welcome)
    End Sub

    Private Sub ApplyWindowIcon()
        Try
            Dim exeIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath)
            If exeIcon IsNot Nothing Then
                Me.Icon = exeIcon
                Return
            End If
        Catch
        End Try
        Try
            Dim iconPath = IO.Path.Combine(Application.StartupPath, "icon.ico")
            If IO.File.Exists(iconPath) Then
                Me.Icon = New Icon(iconPath)
            End If
        Catch
        End Try
    End Sub

    Private Sub BuildUi()
        SuspendLayout()
        RightToLeft = RightToLeft.Yes
        RightToLeftLayout = True
        BackColor = AppTheme.BgApp
        Font = AppTheme.FontUi
        DoubleBuffered = True

        _sidebar = New StepSidebar()
        _contentHost = New Panel() With {.Dock = DockStyle.Fill, .BackColor = AppTheme.BgApp, .RightToLeft = RightToLeft.Yes}
        _footer = New Panel() With {.Dock = DockStyle.Bottom, .Height = 72, .BackColor = AppTheme.BgCard, .RightToLeft = RightToLeft.Yes}
        AddHandler _footer.Paint, Sub(s, e)
                                      Using pen As New Pen(AppTheme.Border)
                                          e.Graphics.DrawLine(pen, 0, 0, _footer.Width, 0)
                                      End Using
                                  End Sub

        _lblFooterHint = New Label() With {.AutoSize = True, .ForeColor = AppTheme.TextMuted, .Font = AppTheme.FontStep, .RightToLeft = RightToLeft.Yes}
        _btnBack = New Button() With {.Text = "بازگشت", .Size = New Size(110, 40), .RightToLeft = RightToLeft.Yes}
        AppTheme.StyleSecondaryButton(_btnBack)
        AddHandler _btnBack.Click, AddressOf OnBackClick
        _btnNext = New Button() With {.Text = "ادامه", .Size = New Size(130, 40), .RightToLeft = RightToLeft.Yes}
        AppTheme.StylePrimaryButton(_btnNext)
        AddHandler _btnNext.Click, AddressOf OnNextClick

        _footer.Controls.Add(_lblFooterHint)
        _footer.Controls.Add(_btnBack)
        _footer.Controls.Add(_btnNext)
        AddHandler _footer.Resize, AddressOf LayoutFooterButtons

        _welcomePanel = New WelcomePanel() With {.Visible = False}
        AddHandler _welcomePanel.StartRequested, Sub(s, ev) ShowStep(WizardStep.HesabixConnect)

        _hesabixPanel = New HesabixConnectPanel(_session, _api) With {.Visible = False}
        AddHandler _hesabixPanel.SelectionChanged, Sub(s, ev) UpdateFooterState()
        AddHandler _hesabixPanel.RequestCreateBusiness, AddressOf OnCreateBusiness

        _holooSqlPanel = New HolooSqlConnectPanel(_session, _sql) With {.Visible = False}
        AddHandler _holooSqlPanel.SelectionChanged, Sub(s, ev) UpdateFooterState()

        _modulesPanel = New SelectModulesPanel(_session) With {.Visible = False}
        AddHandler _modulesPanel.SelectionChanged, Sub(s, ev) UpdateFooterState()

        _preflightPanel = New PreflightPanel(_session, _api) With {.Visible = False}
        AddHandler _preflightPanel.SelectionChanged, Sub(s, ev) UpdateFooterState()

        _transferPanel = New TransferPanel(_session, _api) With {.Visible = False}

        _contentHost.Controls.Add(_welcomePanel)
        _contentHost.Controls.Add(_hesabixPanel)
        _contentHost.Controls.Add(_holooSqlPanel)
        _contentHost.Controls.Add(_modulesPanel)
        _contentHost.Controls.Add(_preflightPanel)
        _contentHost.Controls.Add(_transferPanel)

        Controls.Add(_contentHost)
        Controls.Add(_footer)
        Controls.Add(_sidebar)

        LayoutFooterButtons(_footer, EventArgs.Empty)
        ResumeLayout()
        AppTheme.ApplyRtlTree(_contentHost, False)
        AppTheme.ApplyRtlTree(_footer, False)
    End Sub

    Private Sub LayoutFooterButtons(sender As Object, e As EventArgs)
        _btnNext.Location = New Point(24, 16)
        _btnBack.Location = New Point(_btnNext.Right + 10, 16)
        _lblFooterHint.Location = New Point(Math.Max(24, _footer.Width - _lblFooterHint.PreferredWidth - 24), 28)
    End Sub

    Private Async Sub ShowStep(target As WizardStep)
        _currentStep = target
        _sidebar.CurrentStep = target

        _welcomePanel.Visible = (target = WizardStep.Welcome)
        _hesabixPanel.Visible = (target = WizardStep.HesabixConnect)
        _holooSqlPanel.Visible = (target = WizardStep.HolooSql)
        _modulesPanel.Visible = (target = WizardStep.SelectModules)
        _preflightPanel.Visible = (target = WizardStep.Review)
        _transferPanel.Visible = (target = WizardStep.Transfer)

        Select Case target
            Case WizardStep.Welcome
                _welcomePanel.BringToFront() : _welcomePanel.Dock = DockStyle.Fill
            Case WizardStep.HesabixConnect
                _hesabixPanel.BringToFront() : _hesabixPanel.Dock = DockStyle.Fill : _hesabixPanel.LoadFromSession()
            Case WizardStep.HolooSql
                _holooSqlPanel.BringToFront() : _holooSqlPanel.Dock = DockStyle.Fill : _holooSqlPanel.LoadFromSession()
            Case WizardStep.SelectModules
                _modulesPanel.BringToFront() : _modulesPanel.Dock = DockStyle.Fill
                Await _modulesPanel.RefreshCountsAsync().ConfigureAwait(True)
            Case WizardStep.Review
                _preflightPanel.BringToFront() : _preflightPanel.Dock = DockStyle.Fill
                If _session.Preflight Is Nothing Then
                    Await _preflightPanel.RunPreflightAsync().ConfigureAwait(True)
                End If
            Case WizardStep.Transfer
                _transferPanel.BringToFront() : _transferPanel.Dock = DockStyle.Fill : _transferPanel.Prepare()
        End Select

        UpdateFooterState()
    End Sub

    Private Sub UpdateFooterState()
        Select Case _currentStep
            Case WizardStep.Welcome
                _btnBack.Visible = False : _btnNext.Visible = True : _btnNext.Enabled = True : _btnNext.Text = "شروع"
                _lblFooterHint.Text = "مرحله ۰ — معرفی"
            Case WizardStep.HesabixConnect
                _btnBack.Visible = True : _btnNext.Visible = True : _btnNext.Enabled = _session.CanProceedFromHesabix : _btnNext.Text = "ادامه"
                If Not _session.IsHesabixConnected Then
                    _lblFooterHint.Text = "با حساب کاربری یا کلید API وارد شوید"
                ElseIf _session.SelectedBusiness Is Nothing Then
                    _lblFooterHint.Text = "یک کسب‌وکار را انتخاب کنید"
                Else
                    _lblFooterHint.Text = "کسب‌وکار: " & _session.SelectedBusiness.Name
                End If
            Case WizardStep.HolooSql
                _btnBack.Visible = True : _btnNext.Visible = True : _btnNext.Enabled = _session.CanProceedFromHolooSql : _btnNext.Text = "ادامه"
                If String.IsNullOrWhiteSpace(_session.SelectedDatabase) Then
                    _lblFooterHint.Text = "دیتابیس هلو را انتخاب کنید"
                Else
                    _lblFooterHint.Text = "دیتابیس: " & _session.SelectedDatabase
                End If
            Case WizardStep.SelectModules
                _btnBack.Visible = True : _btnNext.Visible = True : _btnNext.Enabled = _modulesPanel.HasSelection : _btnNext.Text = "ادامه به بازبینی"
                _lblFooterHint.Text = "بخش‌های اطلاعات پایه را انتخاب کنید"
            Case WizardStep.Review
                _btnBack.Visible = True : _btnNext.Visible = True : _btnNext.Enabled = _preflightPanel.CanProceed : _btnNext.Text = "شروع انتقال پایه"
                _lblFooterHint.Text = If(_preflightPanel.CanProceed, "بازبینی تأیید شد", "ابتدا بررسی تطبیقی را کامل کنید")
            Case WizardStep.Transfer
                _btnBack.Visible = True : _btnNext.Visible = False
                _lblFooterHint.Text = "انتقال اطلاعات پایه — قابل ازسرگیری"
            Case Else
                _btnBack.Visible = True : _btnNext.Enabled = False
                _lblFooterHint.Text = "این مرحله هنوز پیاده‌سازی نشده است"
        End Select
        LayoutFooterButtons(_footer, EventArgs.Empty)
    End Sub

    Private Sub OnBackClick(sender As Object, e As EventArgs)
        Select Case _currentStep
            Case WizardStep.HesabixConnect : ShowStep(WizardStep.Welcome)
            Case WizardStep.HolooSql : ShowStep(WizardStep.HesabixConnect)
            Case WizardStep.SelectModules : ShowStep(WizardStep.HolooSql)
            Case WizardStep.Review : ShowStep(WizardStep.SelectModules)
            Case WizardStep.Transfer : ShowStep(WizardStep.Review)
        End Select
    End Sub

    Private Sub OnNextClick(sender As Object, e As EventArgs)
        Select Case _currentStep
            Case WizardStep.Welcome
                ShowStep(WizardStep.HesabixConnect)
            Case WizardStep.HesabixConnect
                If Not _session.CanProceedFromHesabix Then Return
                ShowStep(WizardStep.HolooSql)
            Case WizardStep.HolooSql
                If Not _session.CanProceedFromHolooSql Then Return
                ShowStep(WizardStep.SelectModules)
            Case WizardStep.SelectModules
                If Not _modulesPanel.HasSelection Then Return
                _session.Preflight = Nothing
                ShowStep(WizardStep.Review)
            Case WizardStep.Review
                If Not _preflightPanel.CanProceed Then
                    MessageBox.Show(Me, "بازبینی تطبیقی کامل نیست یا مغایرت ارز تأیید نشده است.", "ادامه ممکن نیست", MessageBoxButtons.OK, MessageBoxIcon.Warning)
                    Return
                End If
                ShowStep(WizardStep.Transfer)
        End Select
    End Sub

    Private Async Sub OnCreateBusiness(sender As Object, e As EventArgs)
        Using dlg As New NewBusinessDialog(_session, _api)
            If dlg.ShowDialog(Me) = DialogResult.OK AndAlso dlg.CreatedBusiness IsNot Nothing Then
                _session.SelectedBusiness = dlg.CreatedBusiness
                Await _hesabixPanel.RefreshBusinessListAsync().ConfigureAwait(True)
                Dim match = _session.Businesses.FirstOrDefault(Function(b) b.Id = dlg.CreatedBusiness.Id)
                If match IsNot Nothing Then
                    _session.SelectedBusiness = match
                Else
                    _session.Businesses.Insert(0, dlg.CreatedBusiness)
                    _session.SelectedBusiness = dlg.CreatedBusiness
                End If
                _hesabixPanel.LoadFromSession()
                UpdateFooterState()
            End If
        End Using
    End Sub

    Protected Overrides Sub OnFormClosed(e As FormClosedEventArgs)
        _api.Dispose()
        MyBase.OnFormClosed(e)
    End Sub
End Class
