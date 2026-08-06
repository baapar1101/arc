Imports System.Threading

Friend Class HesabixConnectPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler
    Public Event RequestCreateBusiness As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient

    Private _txtBaseUrl As TextBox
    Private _tabs As TabControl
    Private _txtIdentifier As TextBox
    Private _txtPassword As TextBox
    Private _txtCaptcha As TextBox
    Private _picCaptcha As PictureBox
    Private _btnRefreshCaptcha As Button
    Private _btnLogin As Button
    Private _txtApiKey As TextBox
    Private _btnConnectKey As Button
    Private _btnDisconnect As Button
    Private _lblStatus As Label
    Private _lblUser As Label
    Private _formCard As Panel
    Private _listHeader As Label
    Private ReadOnly _businessHost As FlowLayoutPanel
    Private ReadOnly _btnNewBusiness As Button
    Private ReadOnly _pnlBusy As Panel
    Private ReadOnly _lblBusy As Label
    Private ReadOnly _progress As ProgressBar

    Private _cts As CancellationTokenSource
    Private _busy As Boolean
    Private _currentCaptchaId As String = ""

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(28, 16, 28, 16)

        Dim title As New Label() With {
            .AutoSize = True,
            .Text = "اتصال به حسابیکس",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }
        Dim subtitle As New Label() With {
            .AutoSize = True,
            .Text = "با ایمیل/موبایل وارد شوید یا کلید API را وارد کنید، سپس کسب‌وکار مقصد را انتخاب کنید.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .RightToLeft = RightToLeft.Yes
        }

        _formCard = CreateFormCard()

        _listHeader = New Label() With {
            .AutoSize = True,
            .Text = "کسب‌وکارها",
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }

        _btnNewBusiness = New Button() With {
            .Text = "+ کسب‌وکار جدید",
            .Size = New Size(150, 36),
            .Enabled = False,
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StyleSecondaryButton(_btnNewBusiness)
        AddHandler _btnNewBusiness.Click, Sub(s, e) RaiseEvent RequestCreateBusiness(Me, EventArgs.Empty)

        _businessHost = New FlowLayoutPanel() With {
            .AutoScroll = True,
            .WrapContents = True,
            .FlowDirection = FlowDirection.RightToLeft,
            .RightToLeft = RightToLeft.Yes,
            .BackColor = AppTheme.BgMuted,
            .Padding = New Padding(12)
        }
        AddHandler _businessHost.Paint, Sub(s, e)
                                            Dim r = New Rectangle(0, 0, _businessHost.Width - 1, _businessHost.Height - 1)
                                            AppTheme.DrawRoundedRect(e.Graphics, r, 12, AppTheme.BgMuted, AppTheme.Border)
                                        End Sub

        _pnlBusy = New Panel() With {
            .Visible = False,
            .BackColor = Color.FromArgb(180, 255, 255, 255),
            .Dock = DockStyle.Fill,
            .RightToLeft = RightToLeft.Yes
        }
        _lblBusy = New Label() With {
            .AutoSize = True,
            .Text = "در حال ارتباط با سرور...",
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
        Controls.Add(_listHeader)
        Controls.Add(_btnNewBusiness)
        Controls.Add(_businessHost)
        Controls.Add(_pnlBusy)
        _pnlBusy.BringToFront()

        title.Location = New Point(28, 12)
        subtitle.Location = New Point(28, 50)
        title.Name = "title"
        subtitle.Name = "subtitle"

        AddHandler Resize, AddressOf OnPanelResize
        OnPanelResize(Me, EventArgs.Empty)
        LoadFromSession()
        AppTheme.ApplyRtlTree(Me, False)
    End Sub

    Private Function CreateFormCard() As Panel
        Dim card As New Panel() With {
            .BackColor = AppTheme.BgCard,
            .Height = 310,
            .RightToLeft = RightToLeft.Yes,
            .Padding = New Padding(16)
        }
        AddHandler card.Paint, Sub(s, e)
                                   Dim r = New Rectangle(0, 0, card.Width - 1, card.Height - 1)
                                   AppTheme.DrawRoundedRect(e.Graphics, r, 12, AppTheme.BgCard, AppTheme.Border)
                               End Sub

        Dim lblUrl As New Label() With {
            .Text = "آدرس سرور API",
            .AutoSize = True,
            .Location = New Point(16, 14),
            .ForeColor = AppTheme.TextSecondary,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes
        }
        _txtBaseUrl = New TextBox() With {
            .Location = New Point(16, 36),
            .Width = 520,
            .RightToLeft = RightToLeft.No,
            .TextAlign = HorizontalAlignment.Left,
            .Anchor = AnchorStyles.Top Or AnchorStyles.Left Or AnchorStyles.Right
        }
        AppTheme.StyleTextBox(_txtBaseUrl)

        _lblStatus = New Label() With {
            .AutoSize = True,
            .Location = New Point(16, 66),
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .Text = "هنوز متصل نشده‌اید",
            .RightToLeft = RightToLeft.Yes
        }
        _lblUser = New Label() With {
            .AutoSize = True,
            .Location = New Point(180, 66),
            .ForeColor = AppTheme.AccentDark,
            .Font = AppTheme.FontUiBold,
            .Text = "",
            .RightToLeft = RightToLeft.Yes
        }

        _btnDisconnect = New Button() With {
            .Text = "قطع اتصال",
            .Size = New Size(100, 32),
            .Location = New Point(560, 32),
            .Visible = False,
            .Anchor = AnchorStyles.Top Or AnchorStyles.Right,
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StyleSecondaryButton(_btnDisconnect)
        _btnDisconnect.Height = 32
        AddHandler _btnDisconnect.Click, AddressOf OnDisconnectClick

        _tabs = New TabControl() With {
            .Location = New Point(16, 92),
            .Size = New Size(700, 200),
            .RightToLeft = RightToLeft.Yes,
            .RightToLeftLayout = False,
            .Anchor = AnchorStyles.Top Or AnchorStyles.Left Or AnchorStyles.Right,
            .Font = AppTheme.FontUi
        }

        Dim tabLogin As New TabPage("ورود با حساب کاربری") With {
            .RightToLeft = RightToLeft.Yes,
            .BackColor = AppTheme.BgCard,
            .Padding = New Padding(12),
            .UseVisualStyleBackColor = False
        }
        Dim tabKey As New TabPage("ورود با کلید API") With {
            .RightToLeft = RightToLeft.Yes,
            .BackColor = AppTheme.BgCard,
            .Padding = New Padding(12),
            .UseVisualStyleBackColor = False
        }

        ' --- Login tab ---
        Dim lblId As New Label() With {.Text = "ایمیل یا موبایل", .AutoSize = True, .Location = New Point(12, 12), .ForeColor = AppTheme.TextSecondary, .Font = AppTheme.FontStep, .RightToLeft = RightToLeft.Yes}
        _txtIdentifier = New TextBox() With {.Location = New Point(12, 34), .Width = 260, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtIdentifier)

        Dim lblPass As New Label() With {.Text = "رمز عبور", .AutoSize = True, .Location = New Point(290, 12), .ForeColor = AppTheme.TextSecondary, .Font = AppTheme.FontStep, .RightToLeft = RightToLeft.Yes}
        _txtPassword = New TextBox() With {.Location = New Point(290, 34), .Width = 220, .UseSystemPasswordChar = True, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtPassword)

        Dim lblCap As New Label() With {.Text = "کد تصویر امنیتی", .AutoSize = True, .Location = New Point(12, 72), .ForeColor = AppTheme.TextSecondary, .Font = AppTheme.FontStep, .RightToLeft = RightToLeft.Yes}
        _txtCaptcha = New TextBox() With {.Location = New Point(12, 94), .Width = 120, .RightToLeft = RightToLeft.No, .MaxLength = 8}
        AppTheme.StyleTextBox(_txtCaptcha)

        _picCaptcha = New PictureBox() With {
            .Location = New Point(148, 78),
            .Size = New Size(160, 48),
            .SizeMode = PictureBoxSizeMode.Zoom,
            .BorderStyle = BorderStyle.FixedSingle,
            .BackColor = Color.White
        }
        _btnRefreshCaptcha = New Button() With {
            .Text = "تازه‌سازی تصویر",
            .Size = New Size(130, 36),
            .Location = New Point(320, 84),
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StyleSecondaryButton(_btnRefreshCaptcha)
        _btnRefreshCaptcha.Height = 36
        _btnRefreshCaptcha.Width = 130
        AddHandler _btnRefreshCaptcha.Click, AddressOf OnRefreshCaptchaClick

        _btnLogin = New Button() With {
            .Text = "ورود و دریافت کسب‌وکارها",
            .Size = New Size(200, 40),
            .Location = New Point(460, 82),
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StylePrimaryButton(_btnLogin)
        AddHandler _btnLogin.Click, AddressOf OnLoginClick

        tabLogin.Controls.Add(lblId)
        tabLogin.Controls.Add(_txtIdentifier)
        tabLogin.Controls.Add(lblPass)
        tabLogin.Controls.Add(_txtPassword)
        tabLogin.Controls.Add(lblCap)
        tabLogin.Controls.Add(_txtCaptcha)
        tabLogin.Controls.Add(_picCaptcha)
        tabLogin.Controls.Add(_btnRefreshCaptcha)
        tabLogin.Controls.Add(_btnLogin)

        ' --- API key tab ---
        Dim lblKey As New Label() With {.Text = "کلید API", .AutoSize = True, .Location = New Point(12, 20), .ForeColor = AppTheme.TextSecondary, .RightToLeft = RightToLeft.Yes}
        _txtApiKey = New TextBox() With {.Location = New Point(12, 44), .Width = 420, .UseSystemPasswordChar = True, .RightToLeft = RightToLeft.No}
        AppTheme.StyleTextBox(_txtApiKey)
        _btnConnectKey = New Button() With {.Text = "اتصال با کلید API", .Size = New Size(170, 40), .Location = New Point(450, 40), .RightToLeft = RightToLeft.Yes}
        AppTheme.StylePrimaryButton(_btnConnectKey)
        AddHandler _btnConnectKey.Click, AddressOf OnConnectKeyClick

        Dim hint As New Label() With {
            .AutoSize = True,
            .Text = "کلید را از بخش کلیدهای API در پروفایل حسابیکس کپی کنید.",
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .Location = New Point(12, 96),
            .RightToLeft = RightToLeft.Yes
        }
        tabKey.Controls.Add(lblKey)
        tabKey.Controls.Add(_txtApiKey)
        tabKey.Controls.Add(_btnConnectKey)
        tabKey.Controls.Add(hint)

        _tabs.TabPages.Add(tabLogin)
        _tabs.TabPages.Add(tabKey)

        card.Controls.Add(lblUrl)
        card.Controls.Add(_txtBaseUrl)
        card.Controls.Add(_lblStatus)
        card.Controls.Add(_lblUser)
        card.Controls.Add(_btnDisconnect)
        card.Controls.Add(_tabs)

        AddHandler card.Resize, Sub(s, e)
                                    _txtBaseUrl.Width = Math.Max(280, card.Width - 150)
                                    _btnDisconnect.Left = Math.Max(16, card.Width - _btnDisconnect.Width - 16)
                                    _tabs.Width = Math.Max(400, card.Width - 32)
                                End Sub

        Return card
    End Function

    Private Sub OnPanelResize(sender As Object, e As EventArgs)
        If _formCard Is Nothing Then Return
        _formCard.Location = New Point(28, 88)
        _formCard.Width = Math.Max(640, ClientSize.Width - 56)

        _listHeader.Location = New Point(28, _formCard.Bottom + 16)
        _btnNewBusiness.Location = New Point(Math.Max(28, _formCard.Right - _btnNewBusiness.Width), _formCard.Bottom + 10)

        _businessHost.Location = New Point(28, _listHeader.Bottom + 10)
        _businessHost.Width = Math.Max(640, ClientSize.Width - 56)
        _businessHost.Height = Math.Max(120, ClientSize.Height - _businessHost.Top - 16)

        If _pnlBusy.Visible Then
            CenterBusy()
        End If
    End Sub

    Private Sub CenterBusy()
        _lblBusy.Location = New Point((_pnlBusy.Width - _lblBusy.PreferredWidth) \ 2, (_pnlBusy.Height \ 2) - 24)
        _progress.Location = New Point((_pnlBusy.Width - _progress.Width) \ 2, _lblBusy.Bottom + 12)
    End Sub

    Public Sub LoadFromSession()
        _txtBaseUrl.Text = If(String.IsNullOrWhiteSpace(_session.ApiBaseUrl), MigrationSession.DefaultApiBaseUrl, _session.ApiBaseUrl)
        _txtApiKey.Text = If(_session.ApiKey, "")
        RefreshAuthUi()
        RenderBusinesses()
        If Not _session.IsHesabixConnected Then
            BeginLoadCaptcha()
        End If
    End Sub

    Private Sub SetBusy(busy As Boolean, Optional message As String = Nothing)
        _busy = busy
        _pnlBusy.Visible = busy
        _btnLogin.Enabled = Not busy
        _btnConnectKey.Enabled = Not busy
        _btnRefreshCaptcha.Enabled = Not busy
        _btnDisconnect.Enabled = Not busy
        _btnNewBusiness.Enabled = (Not busy) AndAlso _session.IsHesabixConnected
        _txtBaseUrl.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _txtApiKey.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _txtIdentifier.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _txtPassword.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _txtCaptcha.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _tabs.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        If busy Then
            _lblBusy.Text = If(String.IsNullOrWhiteSpace(message), "در حال ارتباط با سرور...", message)
            CenterBusy()
            _pnlBusy.BringToFront()
        End If
    End Sub

    Private Sub BeginLoadCaptcha()
        Dim ignored = LoadCaptchaAsync()
    End Sub

    Private Async Function LoadCaptchaAsync() As Task
        If _busy OrElse _session.IsHesabixConnected Then Return
        Dim baseUrl = _txtBaseUrl.Text.Trim()
        If String.IsNullOrWhiteSpace(baseUrl) Then Return

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim captcha = Await AsyncUi.Run(Of CaptchaChallenge)(Me,
                Async Function(ct)
                    _api.SetBaseUrl(baseUrl)
                    Return Await _api.GetCaptchaAsync(ct).ConfigureAwait(False)
                End Function,
                Sub(b) SetBusy(b, "در حال دریافت تصویر امنیتی..."),
                _cts.Token).ConfigureAwait(True)

            ApplyCaptcha(captcha)
        Catch ex As Exception
            _lblStatus.Text = "دریافت کپچا ناموفق بود — می‌توانید دوباره تلاش کنید"
            _lblStatus.ForeColor = AppTheme.Warning
        End Try
    End Function

    Private Sub ApplyCaptcha(captcha As CaptchaChallenge)
        _currentCaptchaId = If(captcha.CaptchaId, "")
        _txtCaptcha.Text = ""
        If _picCaptcha.Image IsNot Nothing Then
            _picCaptcha.Image.Dispose()
            _picCaptcha.Image = Nothing
        End If
        Try
            _picCaptcha.Image = captcha.ToImage()
        Catch
            _picCaptcha.Image = Nothing
        End Try
    End Sub

    Private Async Sub OnRefreshCaptchaClick(sender As Object, e As EventArgs)
        Await LoadCaptchaAsync().ConfigureAwait(True)
    End Sub

    Private Async Sub OnLoginClick(sender As Object, e As EventArgs)
        If _busy Then Return
        Dim baseUrl = _txtBaseUrl.Text.Trim()
        Dim identifier = _txtIdentifier.Text.Trim()
        Dim password = _txtPassword.Text
        Dim captchaCode = _txtCaptcha.Text.Trim()

        If String.IsNullOrWhiteSpace(baseUrl) OrElse String.IsNullOrWhiteSpace(identifier) OrElse String.IsNullOrWhiteSpace(password) Then
            MessageBox.Show(Me, "آدرس سرور، ایمیل/موبایل و رمز عبور را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If
        If String.IsNullOrWhiteSpace(_currentCaptchaId) OrElse String.IsNullOrWhiteSpace(captchaCode) Then
            MessageBox.Show(Me, "کد تصویر امنیتی را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Await LoadCaptchaAsync().ConfigureAwait(True)
            Return
        End If

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Await AsyncUi.Run(Me,
                Async Function(ct)
                    _api.SetBaseUrl(baseUrl)
                    Dim login = Await _api.LoginAsync(identifier, password, _currentCaptchaId, captchaCode, ct).ConfigureAwait(False)
                    Dim user = login.User
                    If user Is Nothing OrElse user.Id = 0 Then
                        user = Await _api.GetMeAsync(ct).ConfigureAwait(False)
                    End If
                    Dim businesses = Await _api.ListBusinessesAsync(100, ct).ConfigureAwait(False)
                    _session.ApiBaseUrl = baseUrl
                    _session.ApiKey = login.ApiKey
                    _session.CurrentUser = user
                    _session.Businesses = businesses
                    _session.ResetHesabixSelection()
                End Function,
                Sub(b) SetBusy(b, "در حال ورود و دریافت کسب‌وکارها..."),
                _cts.Token).ConfigureAwait(True)

            RefreshAuthUi()
            RenderBusinesses()
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _session.ClearHesabixAuth()
            _api.ClearApiKey()
            RefreshAuthUi()
            RenderBusinesses()
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            AsyncUi.ShowError(Me, "خطا در ورود", ex)
        End Try

        If Not _session.IsHesabixConnected Then
            Await LoadCaptchaAsync().ConfigureAwait(True)
        End If
    End Sub

    Private Async Sub OnConnectKeyClick(sender As Object, e As EventArgs)
        If _busy Then Return

        Dim baseUrl = _txtBaseUrl.Text.Trim()
        Dim apiKey = _txtApiKey.Text.Trim()
        If String.IsNullOrWhiteSpace(baseUrl) OrElse String.IsNullOrWhiteSpace(apiKey) Then
            MessageBox.Show(Me, "آدرس سرور و کلید API را وارد کنید.", "ورودی ناقص", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            Return
        End If

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Await AsyncUi.Run(Me,
                Async Function(ct)
                    _api.Configure(baseUrl, apiKey)
                    Dim user = Await _api.GetMeAsync(ct).ConfigureAwait(False)
                    Dim businesses = Await _api.ListBusinessesAsync(100, ct).ConfigureAwait(False)
                    _session.ApiBaseUrl = baseUrl
                    _session.ApiKey = apiKey
                    _session.CurrentUser = user
                    _session.Businesses = businesses
                    _session.ResetHesabixSelection()
                End Function,
                Sub(b) SetBusy(b, "در حال احراز هویت و دریافت کسب‌وکارها..."),
                _cts.Token).ConfigureAwait(True)

            RefreshAuthUi()
            RenderBusinesses()
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            _session.ClearHesabixAuth()
            _api.ClearApiKey()
            RefreshAuthUi()
            RenderBusinesses()
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            AsyncUi.ShowError(Me, "خطا در اتصال", ex)
        End Try
    End Sub

    Private Sub OnDisconnectClick(sender As Object, e As EventArgs)
        CancelPending()
        _session.ClearHesabixAuth()
        _api.ClearApiKey()
        _txtApiKey.Text = ""
        _txtPassword.Text = ""
        RefreshAuthUi()
        RenderBusinesses()
        RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        BeginLoadCaptcha()
    End Sub

    Private Sub CancelPending()
        If _cts IsNot Nothing Then
            _cts.Cancel()
            _cts.Dispose()
            _cts = Nothing
        End If
    End Sub

    Private Sub RefreshAuthUi()
        Dim connected = _session.IsHesabixConnected
        _txtBaseUrl.Enabled = Not connected AndAlso Not _busy
        _tabs.Enabled = Not connected AndAlso Not _busy
        _btnDisconnect.Visible = connected
        _btnNewBusiness.Enabled = connected AndAlso Not _busy

        If connected Then
            _lblStatus.Text = "متصل شدید"
            _lblStatus.ForeColor = AppTheme.Success
            _lblUser.Text = _session.CurrentUser.DisplayName
        Else
            _lblStatus.Text = "هنوز متصل نشده‌اید"
            _lblStatus.ForeColor = AppTheme.TextMuted
            _lblUser.Text = ""
        End If
    End Sub

    Private Sub RenderBusinesses()
        _businessHost.SuspendLayout()
        _businessHost.Controls.Clear()

        If Not _session.IsHesabixConnected Then
            AddEmptyBusinessLabel("پس از ورود، لیست کسب‌وکارها اینجا نمایش داده می‌شود.")
            _businessHost.ResumeLayout()
            Return
        End If

        If _session.Businesses Is Nothing OrElse _session.Businesses.Count = 0 Then
            AddEmptyBusinessLabel("کسب‌وکاری یافت نشد. یک کسب‌وکار جدید بسازید.")
            _businessHost.ResumeLayout()
            Return
        End If

        For Each biz In _session.Businesses
            _businessHost.Controls.Add(CreateBusinessCard(biz))
        Next
        _businessHost.ResumeLayout()
    End Sub

    Private Sub AddEmptyBusinessLabel(text As String)
        Dim empty As New Label() With {
            .AutoSize = True,
            .Text = text,
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontUi,
            .Margin = New Padding(8),
            .RightToLeft = RightToLeft.Yes
        }
        _businessHost.Controls.Add(empty)
    End Sub

    Private Function CreateBusinessCard(biz As HesabixBusiness) As Panel
        Dim selected = _session.SelectedBusiness IsNot Nothing AndAlso _session.SelectedBusiness.Id = biz.Id
        Dim card As New Panel() With {
            .Width = 260,
            .Height = 96,
            .Margin = New Padding(8),
            .Cursor = Cursors.Hand,
            .Tag = biz,
            .RightToLeft = RightToLeft.Yes
        }
        Dim fill = If(selected, AppTheme.AccentSoft, AppTheme.BgCard)
        Dim border = If(selected, AppTheme.Accent, AppTheme.Border)

        AddHandler card.Paint, Sub(s, e)
                                   Dim r = New Rectangle(0, 0, card.Width - 1, card.Height - 1)
                                   AppTheme.DrawRoundedRect(e.Graphics, r, 10, fill, border, If(selected, 2.0F, 1.0F))
                               End Sub

        Dim name As New Label() With {
            .AutoSize = False,
            .Text = biz.Name,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .Location = New Point(14, 14),
            .Size = New Size(230, 24),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes
        }
        Dim meta As New Label() With {
            .AutoSize = False,
            .Text = If(String.IsNullOrWhiteSpace(biz.Subtitle), "شناسه " & biz.Id.ToString(), biz.Subtitle),
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextSecondary,
            .Location = New Point(14, 42),
            .Size = New Size(230, 20),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes
        }
        Dim idLbl As New Label() With {
            .AutoSize = True,
            .Text = "#" & biz.Id.ToString(),
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextMuted,
            .Location = New Point(14, 68),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes
        }

        Dim pick =
            Sub(sender As Object, e As EventArgs)
                _session.SelectedBusiness = biz
                RenderBusinesses()
                RaiseEvent SelectionChanged(Me, EventArgs.Empty)
            End Sub
        AddHandler card.Click, pick
        AddHandler name.Click, pick
        AddHandler meta.Click, pick
        AddHandler idLbl.Click, pick

        card.Controls.Add(name)
        card.Controls.Add(meta)
        card.Controls.Add(idLbl)
        Return card
    End Function

    Public Async Function RefreshBusinessListAsync() As Task
        If Not _session.IsHesabixConnected Then Return
        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Await AsyncUi.Run(Me,
                Async Function(ct)
                    _api.Configure(_session.ApiBaseUrl, _session.ApiKey)
                    Dim businesses = Await _api.ListBusinessesAsync(100, ct).ConfigureAwait(False)
                    _session.Businesses = businesses
                End Function,
                Sub(b) SetBusy(b, "در حال به‌روزرسانی لیست کسب‌وکارها..."),
                _cts.Token).ConfigureAwait(True)
            RenderBusinesses()
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        Catch ex As Exception
            AsyncUi.ShowError(Me, "خطا در دریافت لیست", ex)
        End Try
    End Function

    Protected Overrides Sub Dispose(disposing As Boolean)
        If disposing Then
            CancelPending()
            If _picCaptcha IsNot Nothing AndAlso _picCaptcha.Image IsNot Nothing Then
                _picCaptcha.Image.Dispose()
                _picCaptcha.Image = Nothing
            End If
        End If
        MyBase.Dispose(disposing)
    End Sub
End Class
