Friend Class WelcomePanel
    Inherits UserControl

    Public Event StartRequested As EventHandler

    Private ReadOnly _btnStart As Button
    Private ReadOnly _card As Panel

    Public Sub New()
        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(48, 36, 48, 36)

        _card = New Panel() With {
            .BackColor = AppTheme.BgCard,
            .RightToLeft = RightToLeft.Yes
        }
        AddHandler _card.Paint, AddressOf OnCardPaint

        Dim brand As New Label() With {
            .AutoSize = True,
            .Text = "Holoo2Hesabix",
            .Font = AppTheme.FontHero,
            .ForeColor = AppTheme.AccentDark,
            .RightToLeft = RightToLeft.Yes
        }

        Dim title As New Label() With {
            .AutoSize = True,
            .Text = "انتقال اطلاعات از هلو به حسابیکس",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes
        }

        Dim subtitle As New Label() With {
            .AutoSize = False,
            .Text = "این ابزار داده‌های کسب‌وکار را از دیتابیس SQL Server برنامه هلو می‌خواند و از طریق API به حسابیکس منتقل می‌کند. در هر مرحله می‌توانید بخش‌های مورد نظر را انتخاب کنید.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .Size = New Size(640, 60),
            .RightToLeft = RightToLeft.Yes
        }

        Dim features = CreateFeatureList()
        features.Size = New Size(640, 160)

        _btnStart = New Button() With {
            .Text = "شروع انتقال",
            .Size = New Size(180, 44),
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StylePrimaryButton(_btnStart)
        AddHandler _btnStart.Click, Sub(s, e) RaiseEvent StartRequested(Me, EventArgs.Empty)

        Dim tip As New Label() With {
            .AutoSize = True,
            .Text = "می‌توانید با ایمیل/موبایل وارد شوید یا از کلید API استفاده کنید.",
            .Font = AppTheme.FontStep,
            .ForeColor = AppTheme.TextMuted,
            .RightToLeft = RightToLeft.Yes
        }

        brand.Location = New Point(48, 48)
        title.Location = New Point(48, 100)
        subtitle.Location = New Point(48, 150)
        features.Location = New Point(48, 230)
        _btnStart.Location = New Point(48, 420)
        tip.Location = New Point(48, 480)

        _card.Controls.Add(brand)
        _card.Controls.Add(title)
        _card.Controls.Add(subtitle)
        _card.Controls.Add(features)
        _card.Controls.Add(_btnStart)
        _card.Controls.Add(tip)
        Controls.Add(_card)

        AddHandler Resize, Sub(s, e) LayoutCard()
        LayoutCard()
        AppTheme.ApplyRtlTree(Me, False)
    End Sub

    Private Function CreateFeatureList() As Panel
        Dim host As New Panel() With {.BackColor = Color.Transparent, .RightToLeft = RightToLeft.Yes}
        Dim numbers = {"۱", "۲", "۳", "۴"}
        Dim texts = {
            "اتصال امن به حسابیکس با ورود کاربری یا کلید API و انتخاب/ایجاد کسب‌وکار",
            "اتصال به SQL Server هلو و مشاهده خلاصه داده‌ها",
            "انتخاب بخش‌ها: اشخاص، کالا، خدمات، فاکتور، انبار و ...",
            "انتقال مرحله‌ای با گزارش پیشرفت و امکان ادامه بعد از خطا"
        }
        Dim y = 0
        For i = 0 To numbers.Length - 1
            Dim row = CreateFeatureRow(numbers(i), texts(i))
            row.Location = New Point(0, y)
            row.Width = 640
            host.Controls.Add(row)
            y += 38
        Next
        Return host
    End Function

    Private Function CreateFeatureRow(number As String, text As String) As Panel
        Dim row As New Panel() With {
            .Height = 34,
            .BackColor = Color.Transparent,
            .RightToLeft = RightToLeft.Yes
        }
        Dim badge As New Label() With {
            .Text = number,
            .Size = New Size(28, 28),
            .TextAlign = ContentAlignment.MiddleCenter,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.AccentDark,
            .BackColor = AppTheme.AccentSoft,
            .Location = New Point(0, 2),
            .RightToLeft = RightToLeft.Yes
        }
        Dim lbl As New Label() With {
            .AutoSize = False,
            .Text = text,
            .Font = AppTheme.FontUi,
            .ForeColor = AppTheme.TextPrimary,
            .Location = New Point(40, 4),
            .Size = New Size(580, 24),
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight
        }
        row.Controls.Add(badge)
        row.Controls.Add(lbl)
        Return row
    End Function

    Private Sub LayoutCard()
        If _card Is Nothing Then Return
        Dim maxW = Math.Min(760, Math.Max(480, ClientSize.Width - 96))
        Dim maxH = Math.Min(560, Math.Max(420, ClientSize.Height - 72))
        _card.Size = New Size(maxW, maxH)
        _card.Location = New Point((ClientSize.Width - _card.Width) \ 2, (ClientSize.Height - _card.Height) \ 2)
    End Sub

    Private Sub OnCardPaint(sender As Object, e As PaintEventArgs)
        Dim rect = New Rectangle(0, 0, _card.Width - 1, _card.Height - 1)
        AppTheme.DrawRoundedRect(e.Graphics, rect, 16, AppTheme.BgCard, AppTheme.Border)
    End Sub
End Class
