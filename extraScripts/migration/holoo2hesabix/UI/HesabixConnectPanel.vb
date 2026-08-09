Imports System.Threading

Friend Class HesabixConnectPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler
    Public Event RequestCreateBusiness As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _api As HesabixApiClient

    Private _fldBaseUrl As ModernTextField
    Private _segments As SegmentedControl
    Private _pnlLogin As Panel
    Private _pnlApiKey As Panel
    Private _fldIdentifier As ModernTextField
    Private _fldPassword As ModernTextField
    Private _fldCaptcha As ModernTextField
    Private _picCaptcha As PictureBox
    Private _btnRefreshCaptcha As Button
    Private _btnLogin As Button
    Private _fldApiKey As ModernTextField
    Private _btnConnectKey As Button
    Private _btnDisconnect As Button
    Private _statusBanner As ContextBanner
    Private _formCard As RoundedCard
    Private _listHeader As Label
    Private ReadOnly _businessHost As Panel
    Private ReadOnly _btnNewBusiness As Button
    Private ReadOnly _busy As BusyOverlay
    Private ReadOnly _empty As EmptyStateView

    Private _cts As CancellationTokenSource
    Private _isBusy As Boolean
    Private _currentCaptchaId As String = ""

    Public Sub New(session As MigrationSession, api As HesabixApiClient)
        _session = session
        _api = api

        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        Dim header = PageHeader.Create(
            "اتصال به حسابیکس",
            "وارد شوید، سپس کسب‌وکار مقصد را برای مهاجرت انتخاب کنید.")

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
            .Size = New Size(150, AppTheme.FieldHeight),
            .Enabled = False,
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StyleSecondaryButton(_btnNewBusiness)
        AddHandler _btnNewBusiness.Click, Sub(s, e) RaiseEvent RequestCreateBusiness(Me, EventArgs.Empty)

        _businessHost = New Panel() With {
            .AutoScroll = True,
            .BackColor = Color.Transparent,
            .RightToLeft = RightToLeft.Yes
        }
        AddHandler _businessHost.Paint, Sub(s, e)
                                            Dim r As New Rectangle(0, 0, _businessHost.Width - 1, _businessHost.Height - 1)
                                            AppTheme.DrawRoundedRect(e.Graphics, r, 14, AppTheme.BgMuted, AppTheme.Border)
                                        End Sub

        _empty = New EmptyStateView() With {.Dock = DockStyle.Fill}
        AddHandler _empty.ActionClick, Sub(s, e) RaiseEvent RequestCreateBusiness(Me, EventArgs.Empty)
        _businessHost.Controls.Add(_empty)

        _busy = New BusyOverlay()

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_formCard)
        Controls.Add(_listHeader)
        Controls.Add(_btnNewBusiness)
        Controls.Add(_businessHost)
        Controls.Add(_busy)

        AddHandler Resize, AddressOf OnPanelResize
        OnPanelResize(Me, EventArgs.Empty)
        LoadFromSession()
        AppTheme.ApplyRtlTree(Me, False)
        OnPanelResize(Me, EventArgs.Empty)
    End Sub

    Private Function CreateFormCard() As RoundedCard
        Dim card As New RoundedCard() With {.Height = 348, .Padding = New Padding(22)}

        _fldBaseUrl = New ModernTextField() With {
            .FieldLabel = "آدرس سرور API",
            .IsLtr = True,
            .Width = 520,
            .Name = "fldBaseUrl"
        }

        _statusBanner = New ContextBanner() With {.Width = 420, .Name = "statusBanner"}
        _statusBanner.SetStatus("هنوز متصل نشده‌اید", ContextBanner.BannerTone.Neutral)

        _btnDisconnect = New Button() With {
            .Text = "قطع اتصال",
            .Size = New Size(110, 32),
            .Visible = False,
            .Name = "btnDisconnect"
        }
        AppTheme.StyleDangerGhostButton(_btnDisconnect)
        AddHandler _btnDisconnect.Click, AddressOf OnDisconnectClick

        _segments = New SegmentedControl() With {.Width = 360, .Name = "segments"}
        _segments.SetItems("ورود با حساب", "کلید API")
        AddHandler _segments.SelectedIndexChanged, AddressOf OnSegmentChanged

        _pnlLogin = BuildLoginPane()
        _pnlApiKey = BuildApiKeyPane()
        _pnlApiKey.Visible = False

        card.Controls.Add(_fldBaseUrl)
        card.Controls.Add(_statusBanner)
        card.Controls.Add(_btnDisconnect)
        card.Controls.Add(_segments)
        card.Controls.Add(_pnlLogin)
        card.Controls.Add(_pnlApiKey)
        AddHandler card.Resize, AddressOf LayoutFormCard
        Return card
    End Function

    Private Function BuildLoginPane() As Panel
        Dim pane As New Panel() With {.BackColor = Color.Transparent, .RightToLeft = RightToLeft.Yes, .Height = 168}

        _fldIdentifier = New ModernTextField() With {.FieldLabel = "ایمیل یا موبایل", .IsLtr = True, .Width = 260}
        _fldPassword = New ModernTextField() With {.FieldLabel = "رمز عبور", .IsLtr = True, .UseSystemPasswordChar = True, .Width = 220}
        _fldCaptcha = New ModernTextField() With {.FieldLabel = "کد تصویر امنیتی", .IsLtr = True, .Width = 130, .MaxLength = 8}

        _picCaptcha = New PictureBox() With {
            .Size = New Size(150, 44),
            .SizeMode = PictureBoxSizeMode.Zoom,
            .BackColor = Color.White,
            .BorderStyle = BorderStyle.FixedSingle
        }
        _btnRefreshCaptcha = New Button() With {.Text = "تازه‌سازی", .Size = New Size(100, 36)}
        AppTheme.StyleSecondaryButton(_btnRefreshCaptcha)
        _btnRefreshCaptcha.Height = 36
        AddHandler _btnRefreshCaptcha.Click, AddressOf OnRefreshCaptchaClick

        _btnLogin = New Button() With {.Text = "ورود", .Size = New Size(120, AppTheme.FieldHeight)}
        AppTheme.StylePrimaryButton(_btnLogin)
        AddHandler _btnLogin.Click, AddressOf OnLoginClick

        pane.Controls.Add(_fldIdentifier)
        pane.Controls.Add(_fldPassword)
        pane.Controls.Add(_fldCaptcha)
        pane.Controls.Add(_picCaptcha)
        pane.Controls.Add(_btnRefreshCaptcha)
        pane.Controls.Add(_btnLogin)
        AddHandler pane.Resize, AddressOf LayoutLoginPane
        Return pane
    End Function

    Private Function BuildApiKeyPane() As Panel
        Dim pane As New Panel() With {.BackColor = Color.Transparent, .RightToLeft = RightToLeft.Yes, .Height = 168}
        _fldApiKey = New ModernTextField() With {.FieldLabel = "کلید API", .IsLtr = True, .UseSystemPasswordChar = True, .Width = 420}
        _btnConnectKey = New Button() With {.Text = "اتصال", .Size = New Size(120, AppTheme.FieldHeight)}
        AppTheme.StylePrimaryButton(_btnConnectKey)
        AddHandler _btnConnectKey.Click, AddressOf OnConnectKeyClick

        Dim hint As New Label() With {
            .AutoSize = True,
            .Text = "کلید را از بخش کلیدهای API در پروفایل حسابیکس کپی کنید.",
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes,
            .Name = "hintApiKey"
        }
        pane.Controls.Add(_fldApiKey)
        pane.Controls.Add(_btnConnectKey)
        pane.Controls.Add(hint)
        AddHandler pane.Resize, AddressOf LayoutApiKeyPane
        Return pane
    End Function

    Private Sub OnSegmentChanged(sender As Object, e As EventArgs)
        _pnlLogin.Visible = (_segments.SelectedIndex = 0)
        _pnlApiKey.Visible = (_segments.SelectedIndex = 1)
        LayoutFormCard(_formCard, EventArgs.Empty)
    End Sub

    Private Sub LayoutFormCard(sender As Object, e As EventArgs)
        If _formCard Is Nothing OrElse _fldBaseUrl Is Nothing Then Return
        Dim w = _formCard.ClientSize.Width
        Const m As Integer = 22

        Dim urlW = Math.Max(280, w - m * 2 - If(_btnDisconnect.Visible, 130, 0))
        _fldBaseUrl.Width = urlW
        AppTheme.PlaceFromRight(_fldBaseUrl, w, m, 18)
        If _btnDisconnect.Visible Then
            _btnDisconnect.Location = New Point(m, 40)
        End If

        _statusBanner.Width = Math.Min(480, w - m * 2)
        AppTheme.PlaceFromRight(_statusBanner, w, m, 88)

        _segments.Width = Math.Min(360, w - m * 2)
        AppTheme.PlaceFromRight(_segments, w, m, 132)

        Dim paneTop = 184
        _pnlLogin.SetBounds(m, paneTop, Math.Max(200, w - m * 2), 168)
        _pnlApiKey.SetBounds(m, paneTop, Math.Max(200, w - m * 2), 168)
        LayoutLoginPane(_pnlLogin, EventArgs.Empty)
        LayoutApiKeyPane(_pnlApiKey, EventArgs.Empty)
    End Sub

    Private Sub LayoutLoginPane(sender As Object, e As EventArgs)
        If _pnlLogin Is Nothing OrElse _fldIdentifier Is Nothing Then Return
        Dim w = _pnlLogin.ClientSize.Width
        Const gap As Integer = 14

        AppTheme.PlaceFromRight(_fldIdentifier, w, 0, 0)
        AppTheme.PlaceFromRight(_fldPassword, w, _fldIdentifier.Width + gap, 0)

        AppTheme.PlaceFromRight(_fldCaptcha, w, 0, 72)
        Dim capRight = _fldCaptcha.Width + gap
        _picCaptcha.Location = New Point(AppTheme.RtlLeft(w, capRight, _picCaptcha.Width), 88)
        Dim picRight = capRight + _picCaptcha.Width + gap
        AppTheme.PlaceFromRight(_btnRefreshCaptcha, w, picRight, 92)
        AppTheme.PlaceFromRight(_btnLogin, w, picRight + _btnRefreshCaptcha.Width + gap, 88)
    End Sub

    Private Sub LayoutApiKeyPane(sender As Object, e As EventArgs)
        If _pnlApiKey Is Nothing OrElse _fldApiKey Is Nothing Then Return
        Dim w = _pnlApiKey.ClientSize.Width
        Dim keyW = Math.Max(200, w - _btnConnectKey.Width - 14)
        _fldApiKey.Width = keyW
        AppTheme.PlaceFromRight(_fldApiKey, w, 0, 0)
        AppTheme.PlaceFromRight(_btnConnectKey, w, keyW + 14, 22)
        Dim hint = _pnlApiKey.Controls("hintApiKey")
        If hint IsNot Nothing Then AppTheme.PlaceFromRight(hint, w, 0, 78)
    End Sub

    Private Sub OnPanelResize(sender As Object, e As EventArgs)
        If _formCard Is Nothing Then Return
        Dim w = ClientSize.Width
        Dim m = AppTheme.PageMargin
        Dim title = Controls("title")
        Dim subtitle = Controls("subtitle")
        If title IsNot Nothing Then AppTheme.PlaceFromRight(title, w, m, 18)
        If subtitle IsNot Nothing Then AppTheme.PlaceFromRight(subtitle, w, m, 52)

        _formCard.Width = Math.Max(640, w - m * 2)
        AppTheme.PlaceFromRight(_formCard, w, m, 92)
        LayoutFormCard(_formCard, EventArgs.Empty)

        AppTheme.PlaceFromRight(_listHeader, w, m, _formCard.Bottom + 18)
        _btnNewBusiness.Location = New Point(m, _formCard.Bottom + 12)

        _businessHost.Width = Math.Max(640, w - m * 2)
        AppTheme.PlaceFromRight(_businessHost, w, m, _listHeader.Bottom + 10)
        _businessHost.Height = Math.Max(120, ClientSize.Height - _businessHost.Top - 16)
        LayoutBusinessCards()
    End Sub

    Public Sub LoadFromSession()
        _fldBaseUrl.Text = If(String.IsNullOrWhiteSpace(_session.ApiBaseUrl), MigrationSession.DefaultApiBaseUrl, _session.ApiBaseUrl)
        _fldApiKey.Text = If(_session.ApiKey, "")
        RefreshAuthUi()
        RenderBusinesses()
        If Not _session.IsHesabixConnected Then
            BeginLoadCaptcha()
        End If
    End Sub

    Private Sub SetBusy(busy As Boolean, Optional message As String = Nothing)
        _isBusy = busy
        If busy Then
            _busy.ShowBusy(message)
        Else
            _busy.HideBusy()
        End If
        _btnLogin.Enabled = Not busy
        _btnConnectKey.Enabled = Not busy
        _btnRefreshCaptcha.Enabled = Not busy
        _btnDisconnect.Enabled = Not busy
        _btnNewBusiness.Enabled = (Not busy) AndAlso _session.IsHesabixConnected
        _fldBaseUrl.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _fldApiKey.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _fldIdentifier.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _fldPassword.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _fldCaptcha.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
        _segments.Enabled = Not busy AndAlso Not _session.IsHesabixConnected
    End Sub

    Private Sub BeginLoadCaptcha()
        Dim ignored = LoadCaptchaAsync()
    End Sub

    Private Async Function LoadCaptchaAsync() As Task
        If _isBusy OrElse _session.IsHesabixConnected Then Return
        Dim baseUrl = _fldBaseUrl.Text.Trim()
        If String.IsNullOrWhiteSpace(baseUrl) Then Return

        CancelPending()
        _cts = New CancellationTokenSource()
        Try
            Dim captcha = Await AsyncUi.Run(Of CaptchaChallenge)(Me,
                Async Function(ct)
                    _api.SetBaseUrl(baseUrl)
                    Return Await _api.GetCaptchaAsync(ct).ConfigureAwait(False)
                End Function,
                Sub(b) SetBusy(b, "دریافت تصویر امنیتی..."),
                _cts.Token).ConfigureAwait(True)
            ApplyCaptcha(captcha)
        Catch ex As Exception
            _statusBanner.SetStatus("دریافت کپچا ناموفق بود — دوباره تلاش کنید", ContextBanner.BannerTone.Warning)
        End Try
    End Function

    Private Sub ApplyCaptcha(captcha As CaptchaChallenge)
        _currentCaptchaId = If(captcha.CaptchaId, "")
        _fldCaptcha.Text = ""
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
        If _isBusy Then Return
        ClearFieldErrors()
        Dim baseUrl = _fldBaseUrl.Text.Trim()
        Dim identifier = _fldIdentifier.Text.Trim()
        Dim password = _fldPassword.Text
        Dim captchaCode = _fldCaptcha.Text.Trim()

        Dim ok = True
        If String.IsNullOrWhiteSpace(baseUrl) Then _fldBaseUrl.HasError = True : ok = False
        If String.IsNullOrWhiteSpace(identifier) Then _fldIdentifier.HasError = True : ok = False
        If String.IsNullOrWhiteSpace(password) Then _fldPassword.HasError = True : ok = False
        If String.IsNullOrWhiteSpace(captchaCode) OrElse String.IsNullOrWhiteSpace(_currentCaptchaId) Then
            _fldCaptcha.HasError = True
            ok = False
        End If
        If Not ok Then
            _statusBanner.SetStatus("لطفاً فیلدهای مشخص‌شده را کامل کنید", ContextBanner.BannerTone.Warning)
            If String.IsNullOrWhiteSpace(_currentCaptchaId) Then Await LoadCaptchaAsync().ConfigureAwait(True)
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
                Sub(b) SetBusy(b, "در حال ورود..."),
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
            _statusBanner.SetStatus(ex.Message, ContextBanner.BannerTone.Danger)
            AsyncUi.ShowError(Me, "خطا در ورود", ex)
        End Try

        If Not _session.IsHesabixConnected Then
            Await LoadCaptchaAsync().ConfigureAwait(True)
        End If
    End Sub

    Private Async Sub OnConnectKeyClick(sender As Object, e As EventArgs)
        If _isBusy Then Return
        ClearFieldErrors()
        Dim baseUrl = _fldBaseUrl.Text.Trim()
        Dim apiKey = _fldApiKey.Text.Trim()
        Dim ok = True
        If String.IsNullOrWhiteSpace(baseUrl) Then _fldBaseUrl.HasError = True : ok = False
        If String.IsNullOrWhiteSpace(apiKey) Then _fldApiKey.HasError = True : ok = False
        If Not ok Then
            _statusBanner.SetStatus("آدرس سرور و کلید API را وارد کنید", ContextBanner.BannerTone.Warning)
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
                Sub(b) SetBusy(b, "در حال احراز هویت..."),
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
            _statusBanner.SetStatus(ex.Message, ContextBanner.BannerTone.Danger)
            AsyncUi.ShowError(Me, "خطا در اتصال", ex)
        End Try
    End Sub

    Private Sub OnDisconnectClick(sender As Object, e As EventArgs)
        CancelPending()
        _session.ClearHesabixAuth()
        _api.ClearApiKey()
        _fldApiKey.Text = ""
        _fldPassword.Text = ""
        RefreshAuthUi()
        RenderBusinesses()
        RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        BeginLoadCaptcha()
    End Sub

    Private Sub ClearFieldErrors()
        _fldBaseUrl.HasError = False
        _fldIdentifier.HasError = False
        _fldPassword.HasError = False
        _fldCaptcha.HasError = False
        _fldApiKey.HasError = False
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
        _fldBaseUrl.Enabled = Not connected AndAlso Not _isBusy
        _segments.Enabled = Not connected AndAlso Not _isBusy
        _btnDisconnect.Visible = connected
        _btnNewBusiness.Enabled = connected AndAlso Not _isBusy
        _pnlLogin.Enabled = Not connected
        _pnlApiKey.Enabled = Not connected

        If connected Then
            _statusBanner.SetStatus("متصل شدید — " & _session.CurrentUser.DisplayName, ContextBanner.BannerTone.Success)
        Else
            _statusBanner.SetStatus("هنوز متصل نشده‌اید", ContextBanner.BannerTone.Neutral)
        End If
        LayoutFormCard(_formCard, EventArgs.Empty)
    End Sub

    Private Sub RenderBusinesses()
        For i = _businessHost.Controls.Count - 1 To 0 Step -1
            Dim c = _businessHost.Controls(i)
            If Not Object.ReferenceEquals(c, _empty) Then
                _businessHost.Controls.RemoveAt(i)
                c.Dispose()
            End If
        Next

        If Not _session.IsHesabixConnected Then
            _empty.Configure("پس از ورود", "لیست کسب‌وکارها اینجا نمایش داده می‌شود.")
            _empty.Visible = True
            _empty.BringToFront()
            Return
        End If

        If _session.Businesses Is Nothing OrElse _session.Businesses.Count = 0 Then
            _empty.Configure("کسب‌وکاری یافت نشد", "یک کسب‌وکار جدید بسازید تا مهاجرت را شروع کنید.", "+ ایجاد کسب‌وکار")
            _empty.Visible = True
            _empty.BringToFront()
            Return
        End If

        _empty.Visible = False
        For Each biz In _session.Businesses
            _businessHost.Controls.Add(CreateBusinessCard(biz))
        Next
        LayoutBusinessCards()
    End Sub

    Private Sub LayoutBusinessCards()
        Const pad As Integer = 14
        Const gap As Integer = 12
        Dim cardW = 250
        Dim cardH = 104
        Dim x = _businessHost.ClientSize.Width - pad - cardW
        Dim y = pad
        Dim rowH = 0
        For Each ctrl As Control In _businessHost.Controls
            If Object.ReferenceEquals(ctrl, _empty) Then Continue For
            If x < pad Then
                x = _businessHost.ClientSize.Width - pad - cardW
                y += rowH + gap
                rowH = 0
            End If
            ctrl.SetBounds(x, y, cardW, cardH)
            x -= cardW + gap
            rowH = Math.Max(rowH, cardH)
        Next
    End Sub

    Private Function CreateBusinessCard(biz As HesabixBusiness) As Panel
        Dim selected = _session.SelectedBusiness IsNot Nothing AndAlso _session.SelectedBusiness.Id = biz.Id
        Dim card As New Panel() With {
            .Size = New Size(250, 104),
            .Cursor = Cursors.Hand,
            .Tag = biz,
            .RightToLeft = RightToLeft.Yes,
            .BackColor = Color.Transparent
        }
        Dim fill = If(selected, AppTheme.AccentSoft, AppTheme.BgCard)
        Dim border = If(selected, AppTheme.Accent, AppTheme.Border)
        Dim bw = If(selected, 2.0F, 1.0F)

        AddHandler card.Paint, Sub(s, e)
                                   Dim g = e.Graphics
                                   g.SmoothingMode = Drawing2D.SmoothingMode.AntiAlias
                                   Dim r As New Rectangle(0, 0, card.Width - 1, card.Height - 1)
                                   AppTheme.DrawRoundedRect(g, r, 12, fill, border, bw)
                                   If selected Then
                                       Using brush As New SolidBrush(AppTheme.Accent)
                                           g.FillRectangle(brush, New Rectangle(card.Width - 4, 18, 3, 68))
                                       End Using
                                   End If
                               End Sub

        Dim name As New Label() With {
            .AutoSize = False,
            .Text = biz.Name,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .Location = New Point(14, 16),
            .Size = New Size(220, 24),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight,
            .BackColor = Color.Transparent
        }
        Dim meta As New Label() With {
            .AutoSize = False,
            .Text = If(String.IsNullOrWhiteSpace(biz.Subtitle), "شناسه " & biz.Id.ToString(), biz.Subtitle),
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextSecondary,
            .Location = New Point(14, 44),
            .Size = New Size(220, 20),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight,
            .BackColor = Color.Transparent
        }
        Dim idLbl As New Label() With {
            .AutoSize = False,
            .Text = If(selected, "انتخاب‌شده  ·  #" & biz.Id.ToString(), "#" & biz.Id.ToString()),
            .Font = AppTheme.FontStep,
            .ForeColor = If(selected, AppTheme.AccentDark, AppTheme.TextMuted),
            .Location = New Point(14, 70),
            .Size = New Size(220, 18),
            .Cursor = Cursors.Hand,
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight,
            .BackColor = Color.Transparent
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
                Sub(b) SetBusy(b, "به‌روزرسانی لیست کسب‌وکارها..."),
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
