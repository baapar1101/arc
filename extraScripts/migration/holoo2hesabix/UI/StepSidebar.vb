Imports System.Drawing.Drawing2D
Imports System.Drawing.Text

Friend Class StepInfo
    Public Property WizardStepValue As WizardStep
    Public Property Title As String
    Public Property Hint As String

    Public Sub New(wizardStepValue As WizardStep, title As String, hint As String)
        Me.WizardStepValue = wizardStepValue
        Me.Title = title
        Me.Hint = hint
    End Sub
End Class

Friend Class StepSidebar
    Inherits Panel

    Private _current As WizardStep = WizardStep.Welcome
    Private ReadOnly _steps As StepInfo()

    Public Sub New()
        _steps = {
            New StepInfo(WizardStep.Welcome, "خوش‌آمد", "معرفی ابزار"),
            New StepInfo(WizardStep.HesabixConnect, "حسابیکس", "API و کسب‌وکار"),
            New StepInfo(WizardStep.HolooSql, "هلو", "اتصال SQL Server"),
            New StepInfo(WizardStep.SelectModules, "انتخاب بخش‌ها", "اشخاص، کالا، فاکتور..."),
            New StepInfo(WizardStep.Review, "بازبینی", "تأیید نهایی"),
            New StepInfo(WizardStep.Transfer, "انتقال", "اجرا و گزارش")
        }

        SetStyle(ControlStyles.AllPaintingInWmPaint Or ControlStyles.OptimizedDoubleBuffer Or ControlStyles.UserPaint Or ControlStyles.ResizeRedraw, True)
        Width = 236
        Dock = DockStyle.Left
        BackColor = AppTheme.BgSidebar
        Padding = New Padding(18, 28, 18, 28)
        Cursor = Cursors.Default
        RightToLeft = RightToLeft.Yes
    End Sub

    Public Property CurrentStep As WizardStep
        Get
            Return _current
        End Get
        Set(value As WizardStep)
            _current = value
            Invalidate()
        End Set
    End Property

    Protected Overrides Sub OnPaint(e As PaintEventArgs)
        MyBase.OnPaint(e)
        Dim g = e.Graphics
        g.SmoothingMode = SmoothingMode.AntiAlias
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit
        g.Clear(AppTheme.BgSidebar)

        ' نوار اکسنت لبه داخلی (سمت محتوا)
        Using accentPen As New Pen(AppTheme.Accent, 3.0F)
            g.DrawLine(accentPen, 0, 0, 0, Height)
        End Using

        Using brandFont As New Font("Tahoma", 12.0F, FontStyle.Bold)
            Dim brand = "حسابیکس"
            Dim brandSize = g.MeasureString(brand, brandFont)
            Using brush As New SolidBrush(Color.White)
                g.DrawString(brand, brandFont, brush, Width - 20 - brandSize.Width, 22)
            End Using
        End Using
        Dim subTitle = "مهاجرت از هلو"
        Dim subSize = g.MeasureString(subTitle, AppTheme.FontStep)
        Using brush As New SolidBrush(Color.FromArgb(148, 163, 184))
            g.DrawString(subTitle, AppTheme.FontStep, brush, Width - 20 - subSize.Width, 46)
        End Using

        Dim y = 88
        Dim persianNums = {"۱", "۲", "۳", "۴", "۵", "۶"}
        For i = 0 To _steps.Length - 1
            Dim item = _steps(i)
            Dim active = item.WizardStepValue = _current
            Dim done = CInt(item.WizardStepValue) < CInt(_current)
            Dim upcoming = CInt(item.WizardStepValue) > CInt(_current)

            If active Then
                Dim highlight As New Rectangle(10, y - 6, Width - 20, 52)
                AppTheme.DrawRoundedRect(g, highlight, 10, AppTheme.BgSidebarElevated, Nothing)
                Using mark As New SolidBrush(AppTheme.Accent)
                    g.FillRectangle(mark, New Rectangle(Width - 6, y + 4, 3, 32))
                End Using
            End If

            Dim circleRect As New Rectangle(Width - 48, y, 28, 28)
            Dim fill = If(active, AppTheme.Accent, If(done, AppTheme.AccentDark, Color.FromArgb(51, 65, 85)))
            Using brush As New SolidBrush(fill)
                g.FillEllipse(brush, circleRect)
            End Using
            If active Then
                Using pen As New Pen(Color.FromArgb(90, 45, 212, 191), 3.0F)
                    g.DrawEllipse(pen, circleRect.X - 2, circleRect.Y - 2, circleRect.Width + 4, circleRect.Height + 4)
                End Using
            End If

            Dim num = If(done, "✓", persianNums(i))
            Dim numSize = g.MeasureString(num, AppTheme.FontUiBold)
            Using brush As New SolidBrush(AppTheme.TextOnAccent)
                g.DrawString(num, AppTheme.FontUiBold, brush,
                             circleRect.X + (circleRect.Width - numSize.Width) / 2.0F,
                             circleRect.Y + (circleRect.Height - numSize.Height) / 2.0F)
            End Using

            Dim titleColor = If(upcoming AndAlso Not active, Color.FromArgb(148, 163, 184), AppTheme.TextOnDark)
            Dim titleFont = If(active, AppTheme.FontUiBold, AppTheme.FontUi)
            Dim titleSize = g.MeasureString(item.Title, titleFont)
            Using brush As New SolidBrush(titleColor)
                g.DrawString(item.Title, titleFont, brush, circleRect.X - 12 - titleSize.Width, y + 1)
            End Using

            Dim hintSize = g.MeasureString(item.Hint, AppTheme.FontStep)
            Using brush As New SolidBrush(Color.FromArgb(148, 163, 184))
                g.DrawString(item.Hint, AppTheme.FontStep, brush, circleRect.X - 12 - hintSize.Width, y + 20)
            End Using

            If i < _steps.Length - 1 Then
                Using pen As New Pen(If(done, AppTheme.AccentDark, Color.FromArgb(51, 65, 85)), 2)
                    Dim cx = circleRect.X + circleRect.Width \ 2
                    g.DrawLine(pen, cx, y + 34, cx, y + 54)
                End Using
            End If

            y += 62
        Next

        Dim foot = "Holoo2Hesabix"
        Dim fs = g.MeasureString(foot, AppTheme.FontStep)
        Using brush As New SolidBrush(Color.FromArgb(100, 148, 163, 184))
            g.DrawString(foot, AppTheme.FontStep, brush, Width - 20 - fs.Width, Height - 36)
        End Using
    End Sub
End Class
