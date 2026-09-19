Imports System.Drawing.Drawing2D

Friend Class WelcomePanel
    Inherits UserControl

    Public Event StartRequested As EventHandler

    Private ReadOnly _btnStart As Button
    Private ReadOnly _card As RoundedCard

    Public Sub New()
        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        _card = New RoundedCard() With {.ShowShadow = True}

        Dim brand As New Label() With {
            .AutoSize = True,
            .Text = "Holoo2Hesabix",
            .Font = AppTheme.FontHero,
            .ForeColor = AppTheme.AccentDark,
            .RightToLeft = RightToLeft.Yes,
            .Name = "brand",
            .BackColor = Color.Transparent
        }

        Dim title As New Label() With {
            .AutoSize = True,
            .Text = "انتقال اطلاعات از هلو به حسابیکس",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Name = "title",
            .BackColor = Color.Transparent
        }

        Dim subtitle As New Label() With {
            .AutoSize = False,
            .Text = "داده‌های کسب‌وکار را از SQL Server هلو می‌خوانیم و از طریق API به حسابیکس منتقل می‌کنیم — مرحله‌به‌مرحله، قابل ازسرگیری و قابل کنترل.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .Size = New Size(620, 52),
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.TopRight,
            .Name = "subtitle",
            .BackColor = Color.Transparent
        }

        Dim features = CreateFeatureList()
        features.Name = "features"

        _btnStart = New Button() With {
            .Text = "شروع مهاجرت",
            .Size = New Size(200, 46),
            .RightToLeft = RightToLeft.Yes,
            .Name = "btnStart"
        }
        AppTheme.StylePrimaryButton(_btnStart)
        _btnStart.Height = 46
        AddHandler _btnStart.Click, Sub(s, e) RaiseEvent StartRequested(Me, EventArgs.Empty)

        Dim tip As New Label() With {
            .AutoSize = True,
            .Text = "می‌توانید با ایمیل/موبایل وارد شوید یا از کلید API استفاده کنید.",
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextMuted,
            .RightToLeft = RightToLeft.Yes,
            .Name = "tip",
            .BackColor = Color.Transparent
        }

        _card.Controls.Add(brand)
        _card.Controls.Add(title)
        _card.Controls.Add(subtitle)
        _card.Controls.Add(features)
        _card.Controls.Add(_btnStart)
        _card.Controls.Add(tip)
        Controls.Add(_card)

        AddHandler Resize, Sub(s, e) LayoutCard()
        AddHandler _card.Resize, Sub(s, e) LayoutCardContent()
        LayoutCard()
        AppTheme.ApplyRtlTree(Me, False)
        LayoutCardContent()
    End Sub

    Private Function CreateFeatureList() As Panel
        Dim host As New Panel() With {.BackColor = Color.Transparent, .RightToLeft = RightToLeft.Yes, .Size = New Size(620, 180)}
        Dim numbers = {"۱", "۲", "۳", "۴"}
        Dim texts = {
            "اتصال امن به حسابیکس و انتخاب یا ایجاد کسب‌وکار مقصد",
            "اتصال به SQL Server هلو و مشاهده خلاصه داده‌ها",
            "انتخاب بخش‌ها: اشخاص، کالا، خدمات، فاکتور، انبار و ...",
            "انتقال مرحله‌ای با گزارش پیشرفت و ادامه بعد از خطا"
        }
        Dim y = 0
        For i = 0 To numbers.Length - 1
            Dim row = CreateFeatureRow(numbers(i), texts(i))
            row.Location = New Point(0, y)
            row.Width = 620
            host.Controls.Add(row)
            y += 42
        Next
        Return host
    End Function

    Private Function CreateFeatureRow(number As String, text As String) As Panel
        Dim row As New Panel() With {.Height = 38, .BackColor = Color.Transparent, .RightToLeft = RightToLeft.Yes}
        Dim badge As New Panel() With {
            .Size = New Size(30, 30),
            .BackColor = Color.Transparent,
            .RightToLeft = RightToLeft.Yes,
            .Name = "badge",
            .Tag = number
        }
        AddHandler badge.Paint, Sub(s, e)
                                    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias
                                    Using brush As New SolidBrush(AppTheme.AccentSoft)
                                        e.Graphics.FillEllipse(brush, 0, 0, badge.Width - 1, badge.Height - 1)
                                    End Using
                                    Dim sf As New StringFormat() With {.Alignment = StringAlignment.Center, .LineAlignment = StringAlignment.Center}
                                    Using br As New SolidBrush(AppTheme.AccentDark)
                                        e.Graphics.DrawString(CStr(badge.Tag), AppTheme.FontUiBold, br, New RectangleF(0, 0, badge.Width, badge.Height), sf)
                                    End Using
                                End Sub

        Dim lbl As New Label() With {
            .AutoSize = False,
            .Text = text,
            .Font = AppTheme.FontUi,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight,
            .Name = "featureText",
            .BackColor = Color.Transparent
        }
        row.Controls.Add(badge)
        row.Controls.Add(lbl)
        AddHandler row.Resize, Sub(s, e)
                                   badge.Location = New Point(Math.Max(0, row.Width - badge.Width), 4)
                                   lbl.Location = New Point(0, 4)
                                   lbl.Size = New Size(Math.Max(40, row.Width - badge.Width - 14), 30)
                               End Sub
        Return row
    End Function

    Private Sub LayoutCard()
        If _card Is Nothing Then Return
        Dim maxW = Math.Min(780, Math.Max(520, ClientSize.Width - 96))
        Dim maxH = Math.Min(580, Math.Max(460, ClientSize.Height - 72))
        _card.Size = New Size(maxW, maxH)
        _card.Location = New Point((ClientSize.Width - _card.Width) \ 2, (ClientSize.Height - _card.Height) \ 2)
        LayoutCardContent()
    End Sub

    Private Sub LayoutCardContent()
        If _card Is Nothing OrElse _card.Width < 100 Then Return
        Dim w = _card.ClientSize.Width
        Const m As Integer = 48
        Dim contentW = Math.Max(280, w - m * 2)

        Dim brand = _card.Controls("brand")
        Dim title = _card.Controls("title")
        Dim subtitle = TryCast(_card.Controls("subtitle"), Label)
        Dim features = _card.Controls("features")
        Dim tip = _card.Controls("tip")

        If brand IsNot Nothing Then AppTheme.PlaceFromRight(brand, w, m, 44)
        If title IsNot Nothing Then AppTheme.PlaceFromRight(title, w, m, 96)
        If subtitle IsNot Nothing Then
            subtitle.Width = contentW
            AppTheme.PlaceFromRight(subtitle, w, m, 148)
        End If
        If features IsNot Nothing Then
            features.Width = contentW
            AppTheme.PlaceFromRight(features, w, m, 220)
            For Each row As Control In features.Controls
                row.Width = contentW
            Next
        End If
        If _btnStart IsNot Nothing Then AppTheme.PlaceFromRight(_btnStart, w, m, 430)
        If tip IsNot Nothing Then AppTheme.PlaceFromRight(tip, w, m, 490)
    End Sub
End Class
