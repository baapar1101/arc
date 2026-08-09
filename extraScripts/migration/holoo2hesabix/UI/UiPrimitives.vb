Imports System.ComponentModel
Imports System.Drawing.Drawing2D
Imports System.Drawing.Text

''' <summary>کارت سفید با گوشه گرد و سایه نرم.</summary>
Friend Class RoundedCard
    Inherits Panel

    Private _radius As Integer = 14
    Private _showShadow As Boolean = True

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        BackColor = Color.Transparent
        RightToLeft = RightToLeft.Yes
        Padding = New Padding(20)
    End Sub

    <DefaultValue(14)>
    Public Property CornerRadius As Integer
        Get
            Return _radius
        End Get
        Set(value As Integer)
            _radius = value
            Invalidate()
        End Set
    End Property

    <DefaultValue(True)>
    Public Property ShowShadow As Boolean
        Get
            Return _showShadow
        End Get
        Set(value As Boolean)
            _showShadow = value
            Invalidate()
        End Set
    End Property

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        If Width < 8 OrElse Height < 8 Then Return
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        Dim pad = If(_showShadow, 3, 0)
        Dim rw = Width - pad * 2 - 1
        Dim rh = Height - pad * 2 - 1
        If rw < 4 OrElse rh < 4 Then Return
        Dim rect As New Rectangle(pad, pad, rw, rh)
        If _showShadow Then
            Using shadowPath = AppTheme.CreateRoundedPath(New Rectangle(rect.X + 1, rect.Y + 2, rect.Width, rect.Height), _radius)
                Using brush As New SolidBrush(Color.FromArgb(28, 15, 23, 42))
                    g.FillPath(brush, shadowPath)
                End Using
            End Using
        End If
        AppTheme.DrawRoundedRect(g, rect, _radius, AppTheme.BgCard, AppTheme.Border, 1.0F)
    End Sub
End Class

''' <summary>فیلد متن مدرن: لیبل + اینپوت با فوکوس اکسنت.</summary>
Friend Class ModernTextField
    Inherits Panel

    Private ReadOnly _lbl As Label
    Private ReadOnly _box As Panel
    Private ReadOnly _inner As TextBox
    Private _focused As Boolean
    Private _error As Boolean
    Private _isLtr As Boolean

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        RightToLeft = RightToLeft.Yes
        BackColor = Color.Transparent

        _lbl = New Label() With {
            .AutoSize = False,
            .Height = 18,
            .Font = AppTheme.FontFieldLabel,
            .ForeColor = AppTheme.TextSecondary,
            .BackColor = Color.Transparent,
            .RightToLeft = RightToLeft.Yes,
            .TextAlign = ContentAlignment.MiddleRight
        }

        _box = New Panel() With {
            .Height = AppTheme.FieldHeight,
            .BackColor = Color.Transparent
        }
        SetStyleDeep(_box)

        _inner = New TextBox() With {
            .BorderStyle = BorderStyle.None,
            .Font = AppTheme.FontUi,
            .BackColor = AppTheme.BgCard,
            .ForeColor = AppTheme.TextPrimary,
            .Location = New Point(12, 10),
            .Height = 20
        }

        AddHandler _box.Paint, AddressOf OnBoxPaint
        AddHandler _inner.GotFocus, Sub(s, e)
                                        _focused = True
                                        _box.Invalidate()
                                    End Sub
        AddHandler _inner.LostFocus, Sub(s, e)
                                         _focused = False
                                         _box.Invalidate()
                                     End Sub
        AddHandler _inner.TextChanged, Sub(s, e) RaiseEvent TextChanged(Me, e)
        AddHandler _box.Click, Sub(s, e) _inner.Focus()
        AddHandler _box.Resize, AddressOf LayoutInner

        Controls.Add(_lbl)
        Controls.Add(_box)
        _box.Controls.Add(_inner)

        ' Height را بعد از ساخت فرزندان تنظیم کن تا OnResize روی null نیفتد
        Height = AppTheme.FieldBlockHeight
        LayoutParts()
    End Sub

    Public Shadows Event TextChanged As EventHandler

    Public Property FieldLabel As String
        Get
            Return _lbl.Text
        End Get
        Set(value As String)
            _lbl.Text = value
        End Set
    End Property

    Public Property IsLtr As Boolean
        Get
            Return _isLtr
        End Get
        Set(value As Boolean)
            _isLtr = value
            If value Then
                AppTheme.StyleLtrTextBox(_inner)
                _inner.BorderStyle = BorderStyle.None
                _inner.Font = AppTheme.FontMono
            Else
                AppTheme.StyleRtlTextBox(_inner)
                _inner.BorderStyle = BorderStyle.None
                _inner.Font = AppTheme.FontUi
            End If
            LayoutInner(_box, EventArgs.Empty)
        End Set
    End Property

    Public Shadows Property [Text] As String
        Get
            Return _inner.Text
        End Get
        Set(value As String)
            _inner.Text = value
        End Set
    End Property

    Public Property UseSystemPasswordChar As Boolean
        Get
            Return _inner.UseSystemPasswordChar
        End Get
        Set(value As Boolean)
            _inner.UseSystemPasswordChar = value
        End Set
    End Property

    Public Property MaxLength As Integer
        Get
            Return _inner.MaxLength
        End Get
        Set(value As Integer)
            _inner.MaxLength = value
        End Set
    End Property

    Public Property HasError As Boolean
        Get
            Return _error
        End Get
        Set(value As Boolean)
            _error = value
            _box.Invalidate()
        End Set
    End Property

    Public ReadOnly Property InnerTextBox As TextBox
        Get
            Return _inner
        End Get
    End Property

    Public Shadows Property Enabled As Boolean
        Get
            Return MyBase.Enabled
        End Get
        Set(value As Boolean)
            MyBase.Enabled = value
            _inner.Enabled = value
            _lbl.ForeColor = If(value, AppTheme.TextSecondary, AppTheme.TextMuted)
            _box.Invalidate()
        End Set
    End Property

    Protected Overrides Sub OnResize(e As EventArgs)
        MyBase.OnResize(e)
        LayoutParts()
    End Sub

    Private Sub LayoutParts()
        If _lbl Is Nothing OrElse _box Is Nothing OrElse _inner Is Nothing Then Return
        _lbl.SetBounds(0, 0, Width, 18)
        _box.SetBounds(0, 22, Width, AppTheme.FieldHeight)
        LayoutInner(_box, EventArgs.Empty)
    End Sub

    Private Sub LayoutInner(sender As Object, e As EventArgs)
        If _inner Is Nothing OrElse _box Is Nothing Then Return
        Dim padX = 12
        _inner.Width = Math.Max(20, _box.Width - padX * 2)
        _inner.Left = padX
        _inner.Top = Math.Max(8, (_box.Height - _inner.Font.Height) \ 2)
    End Sub

    Private Sub OnBoxPaint(sender As Object, e As PaintEventArgs)
        If _box Is Nothing OrElse _box.Width < 4 OrElse _box.Height < 4 Then Return
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        Dim r As New Rectangle(0, 0, _box.Width - 1, _box.Height - 1)
        Dim fill = If(MyBase.Enabled, AppTheme.BgCard, AppTheme.BgMuted)
        Dim border = AppTheme.Border
        Dim bw = 1.2F
        If _error Then
            border = AppTheme.Danger
            bw = 1.6F
        ElseIf _focused Then
            border = AppTheme.Accent
            bw = 1.8F
        End If
        AppTheme.DrawRoundedRect(g, r, 10, fill, border, bw)
        If _focused AndAlso Not _error Then
            Dim glow As New Rectangle(Math.Max(0, r.X), Math.Max(0, r.Y), r.Width, r.Height)
            Using path = AppTheme.CreateRoundedPath(glow, 10)
                Using pen As New Pen(Color.FromArgb(55, AppTheme.Accent.R, AppTheme.Accent.G, AppTheme.Accent.B), 2.0F)
                    g.DrawPath(pen, path)
                End Using
            End Using
        End If
    End Sub

    Private Shared Sub SetStyleDeep(ctrl As Control)
        Dim t = GetType(Control)
        Dim mi = t.GetMethod("SetStyle", Reflection.BindingFlags.Instance Or Reflection.BindingFlags.NonPublic)
        If mi IsNot Nothing Then
            mi.Invoke(ctrl, {ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True})
        End If
    End Sub
End Class

''' <summary>سگمنت مدرن به‌جای TabControl کلاسیک.</summary>
Friend Class SegmentedControl
    Inherits Panel

    Private _items As String() = {}
    Private _selected As Integer = 0
    Private _hover As Integer = -1

    Public Event SelectedIndexChanged As EventHandler

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw Or ControlStyles.Selectable, True)
        Height = 40
        RightToLeft = RightToLeft.Yes
        Cursor = Cursors.Hand
        BackColor = Color.Transparent
    End Sub

    Public Sub SetItems(ParamArray items As String())
        _items = If(items, {})
        If _selected >= _items.Length Then _selected = 0
        Invalidate()
    End Sub

    Public Property SelectedIndex As Integer
        Get
            Return _selected
        End Get
        Set(value As Integer)
            If value < 0 OrElse value >= _items.Length OrElse value = _selected Then Return
            _selected = value
            Invalidate()
            RaiseEvent SelectedIndexChanged(Me, EventArgs.Empty)
        End Set
    End Property

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        If Width < 12 OrElse Height < 12 Then Return
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit
        Dim outer As New Rectangle(0, 0, Width - 1, Height - 1)
        AppTheme.DrawRoundedRect(g, outer, 10, AppTheme.BgMuted, AppTheme.Border, 1.0F)
        If _items Is Nothing OrElse _items.Length = 0 Then Return

        Dim n = _items.Length
        Dim gap = 4
        Dim inner = New Rectangle(4, 4, Math.Max(1, Width - 8), Math.Max(1, Height - 8))
        Dim segW = Math.Max(1, inner.Width \ n)

        For i = 0 To n - 1
            Dim visualIndex = n - 1 - i
            Dim x = inner.X + visualIndex * segW
            Dim segWidth = Math.Max(1, segW - gap)
            Dim seg As New Rectangle(x + If(visualIndex = 0, 0, gap \ 2), inner.Y, segWidth, inner.Height)

            If i = _selected Then
                AppTheme.DrawRoundedRect(g, seg, 8, AppTheme.BgCard, AppTheme.Accent, 1.2F)
            ElseIf i = _hover Then
                AppTheme.DrawRoundedRect(g, seg, 8, Color.FromArgb(230, 236, 242), Nothing)
            End If

            Dim sf As New StringFormat() With {
                .Alignment = StringAlignment.Center,
                .LineAlignment = StringAlignment.Center,
                .FormatFlags = StringFormatFlags.DirectionRightToLeft
            }
            Dim textColor = If(i = _selected, AppTheme.AccentDark, AppTheme.TextSecondary)
            Dim textFont = If(i = _selected, AppTheme.FontUiBold, AppTheme.FontUi)
            Using brush As New SolidBrush(textColor)
                g.DrawString(_items(i), textFont, brush, New RectangleF(seg.X, seg.Y, seg.Width, seg.Height), sf)
            End Using
        Next
    End Sub

    Protected Overrides Sub OnMouseMove(e As MouseEventArgs)
        MyBase.OnMouseMove(e)
        Dim idx = HitTest(e.Location)
        If idx <> _hover Then
            _hover = idx
            Invalidate()
        End If
    End Sub

    Protected Overrides Sub OnMouseLeave(e As EventArgs)
        MyBase.OnMouseLeave(e)
        _hover = -1
        Invalidate()
    End Sub

    Protected Overrides Sub OnMouseClick(e As MouseEventArgs)
        MyBase.OnMouseClick(e)
        Dim idx = HitTest(e.Location)
        If idx >= 0 Then SelectedIndex = idx
    End Sub

    Private Function HitTest(pt As Point) As Integer
        If _items.Length = 0 Then Return -1
        Dim n = _items.Length
        Dim inner = New Rectangle(4, 4, Width - 8, Height - 8)
        If Not inner.Contains(pt) Then Return -1
        Dim segW = Math.Max(1, inner.Width \ n)
        Dim visual = Math.Min(n - 1, Math.Max(0, (pt.X - inner.X) \ segW))
        Return n - 1 - visual
    End Function
End Class

''' <summary>بنر وضعیت اتصال / خلاصه ویزارد.</summary>
Friend Class ContextBanner
    Inherits Panel

    Private _text As String = ""
    Private _tone As BannerTone = BannerTone.Neutral

    Public Enum BannerTone
        Neutral
        Success
        Warning
        Danger
        Info
    End Enum

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        Height = 36
        RightToLeft = RightToLeft.Yes
        BackColor = Color.Transparent
    End Sub

    Public Sub SetStatus(text As String, Optional tone As BannerTone = BannerTone.Neutral)
        _text = If(text, "")
        _tone = tone
        Visible = Not String.IsNullOrWhiteSpace(_text)
        Invalidate()
    End Sub

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        If String.IsNullOrWhiteSpace(_text) Then Return
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit
        Dim fill As Color
        Dim border As Color
        Dim fg As Color
        Select Case _tone
            Case BannerTone.Success
                fill = Color.FromArgb(220, 252, 231) : border = Color.FromArgb(134, 239, 172) : fg = AppTheme.Success
            Case BannerTone.Warning
                fill = Color.FromArgb(255, 247, 237) : border = Color.FromArgb(253, 186, 116) : fg = AppTheme.Warning
            Case BannerTone.Danger
                fill = Color.FromArgb(254, 226, 226) : border = Color.FromArgb(252, 165, 165) : fg = AppTheme.Danger
            Case BannerTone.Info
                fill = AppTheme.AccentSoft : border = Color.FromArgb(94, 234, 212) : fg = AppTheme.AccentDark
            Case Else
                fill = AppTheme.BgMuted : border = AppTheme.Border : fg = AppTheme.TextSecondary
        End Select
        Dim r As New Rectangle(0, 0, Width - 1, Height - 1)
        AppTheme.DrawRoundedRect(g, r, 10, fill, border, 1.0F)
        Using brush As New SolidBrush(fg)
            Dim sf As New StringFormat() With {.Alignment = StringAlignment.Far, .LineAlignment = StringAlignment.Center, .FormatFlags = StringFormatFlags.DirectionRightToLeft}
            g.DrawString(_text, AppTheme.FontStep, brush, New RectangleF(12, 0, Width - 24, Height), sf)
        End Using
    End Sub
End Class

''' <summary>حالت خالی با پیام و دکمه اختیاری.</summary>
Friend Class EmptyStateView
    Inherits Panel

    Private ReadOnly _title As Label
    Private ReadOnly _body As Label
    Private ReadOnly _action As Button

    Public Event ActionClick As EventHandler

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        RightToLeft = RightToLeft.Yes
        BackColor = Color.Transparent

        _title = New Label() With {
            .AutoSize = False,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .TextAlign = ContentAlignment.MiddleCenter,
            .RightToLeft = RightToLeft.Yes,
            .Height = 24
        }
        _body = New Label() With {
            .AutoSize = False,
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextMuted,
            .TextAlign = ContentAlignment.TopCenter,
            .RightToLeft = RightToLeft.Yes,
            .Height = 40
        }
        _action = New Button() With {
            .Size = New Size(160, 36),
            .Visible = False,
            .RightToLeft = RightToLeft.Yes
        }
        AppTheme.StyleSecondaryButton(_action)
        AddHandler _action.Click, Sub(s, e) RaiseEvent ActionClick(Me, EventArgs.Empty)

        Controls.Add(_title)
        Controls.Add(_body)
        Controls.Add(_action)
        AddHandler Resize, Sub(s, e) LayoutParts()
    End Sub

    Public Sub Configure(title As String, body As String, Optional actionText As String = Nothing)
        _title.Text = title
        _body.Text = body
        If String.IsNullOrWhiteSpace(actionText) Then
            _action.Visible = False
        Else
            _action.Text = actionText
            _action.Visible = True
        End If
        LayoutParts()
    End Sub

    Private Sub LayoutParts()
        Dim w = Math.Min(420, Math.Max(200, Width - 40))
        Dim x = (Width - w) \ 2
        Dim y = Math.Max(24, (Height \ 2) - 50)
        _title.SetBounds(x, y, w, 24)
        _body.SetBounds(x, y + 28, w, 44)
        _action.Location = New Point((Width - _action.Width) \ 2, y + 84)
    End Sub

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        Dim cx = Width \ 2
        Dim cy = Math.Max(36, (Height \ 2) - 78)
        Using brush As New SolidBrush(AppTheme.AccentSoft)
            g.FillEllipse(brush, cx - 22, cy - 22, 44, 44)
        End Using
        Using pen As New Pen(AppTheme.Accent, 2.0F)
            g.DrawEllipse(pen, cx - 14, cy - 10, 28, 20)
            g.DrawLine(pen, cx - 6, cy, cx + 6, cy)
        End Using
    End Sub
End Class

''' <summary>اوریلی مشغول بودن داخل کارت شناور.</summary>
Friend Class BusyOverlay
    Inherits Panel

    Private ReadOnly _card As Panel
    Private ReadOnly _lbl As Label
    Private ReadOnly _bar As ProgressBar

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        Dock = DockStyle.Fill
        Visible = False
        BackColor = Color.FromArgb(120, 241, 245, 249)
        RightToLeft = RightToLeft.Yes

        _card = New Panel() With {.Size = New Size(280, 96), .BackColor = Color.Transparent}
        AddHandler _card.Paint, Sub(s, e)
                                    Dim r As New Rectangle(0, 0, _card.Width - 1, _card.Height - 1)
                                    AppTheme.DrawRoundedRect(e.Graphics, r, 14, AppTheme.BgCard, AppTheme.Border, 1.0F)
                                End Sub
        _lbl = New Label() With {
            .AutoSize = False,
            .TextAlign = ContentAlignment.MiddleCenter,
            .Font = AppTheme.FontUiBold,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Size = New Size(240, 28),
            .Location = New Point(20, 18)
        }
        _bar = New ProgressBar() With {
            .Style = ProgressBarStyle.Marquee,
            .MarqueeAnimationSpeed = 28,
            .Size = New Size(200, 6),
            .Location = New Point(40, 58)
        }
        _card.Controls.Add(_lbl)
        _card.Controls.Add(_bar)
        Controls.Add(_card)
        AddHandler Resize, Sub(s, e) CenterCard()
    End Sub

    Public Sub ShowBusy(Optional message As String = Nothing)
        _lbl.Text = If(String.IsNullOrWhiteSpace(message), "لطفاً صبر کنید...", message)
        Visible = True
        BringToFront()
        CenterCard()
    End Sub

    Public Sub HideBusy()
        Visible = False
    End Sub

    Private Sub CenterCard()
        _card.Location = New Point(Math.Max(0, (Width - _card.Width) \ 2), Math.Max(0, (Height - _card.Height) \ 2))
    End Sub
End Class

''' <summary>نوار پیشرفت سفارشی با درصد.</summary>
Friend Class ModernProgressBar
    Inherits Panel

    Private _value As Integer
    Private _maximum As Integer = 100
    Private _caption As String = ""

    Public Sub New()
        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        Height = 28
        RightToLeft = RightToLeft.Yes
        BackColor = Color.Transparent
    End Sub

    Public Property Value As Integer
        Get
            Return _value
        End Get
        Set(value As Integer)
            _value = Math.Max(0, Math.Min(value, _maximum))
            Invalidate()
        End Set
    End Property

    Public Property Maximum As Integer
        Get
            Return _maximum
        End Get
        Set(value As Integer)
            _maximum = Math.Max(1, value)
            If _value > _maximum Then _value = _maximum
            Invalidate()
        End Set
    End Property

    Public Property Caption As String
        Get
            Return _caption
        End Get
        Set(value As String)
            _caption = If(value, "")
            Invalidate()
        End Set
    End Property

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit
        Dim track As New Rectangle(0, 10, Width - 1, 8)
        AppTheme.DrawRoundedRect(g, track, 4, AppTheme.BgMuted, AppTheme.Border, 1.0F)
        Dim pct = If(_maximum <= 0, 0.0, _value / CDbl(_maximum))
        Dim fillW = Math.Max(0, CInt(Math.Floor((Width - 2) * pct)))
        If fillW > 0 Then
            ' پر شدن از راست در UI فارسی
            Dim fill As New Rectangle(Width - 1 - fillW, 10, fillW, 8)
            AppTheme.DrawRoundedRect(g, fill, 4, AppTheme.Accent, Nothing)
        End If
        If Not String.IsNullOrWhiteSpace(_caption) Then
            Using brush As New SolidBrush(AppTheme.TextMuted)
                Dim sf As New StringFormat() With {.Alignment = StringAlignment.Far, .LineAlignment = StringAlignment.Near, .FormatFlags = StringFormatFlags.DirectionRightToLeft}
                g.DrawString(_caption, AppTheme.FontStep, brush, New RectangleF(0, 0, Width, 12), sf)
            End Using
        End If
    End Sub
End Class

''' <summary>هدر صفحه: عنوان + زیرعنوان با فاصله استاندارد.</summary>
Friend NotInheritable Class PageHeader
    Private Sub New()
    End Sub

    Public Shared Function Create(titleText As String, subtitleText As String) As Tuple(Of Label, Label)
        Dim title As New Label() With {
            .AutoSize = True,
            .Text = titleText,
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .RightToLeft = RightToLeft.Yes,
            .Name = "title"
        }
        Dim subtitle As New Label() With {
            .AutoSize = True,
            .Text = subtitleText,
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .RightToLeft = RightToLeft.Yes,
            .Name = "subtitle"
        }
        Return Tuple.Create(title, subtitle)
    End Function
End Class
