Imports System.Drawing.Drawing2D

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

        DoubleBuffered = True
        Width = 220
        ' با RightToLeftLayout فرم، Dock.Left در سمت راست دیده می‌شود
        Dock = DockStyle.Left
        BackColor = AppTheme.BgSidebar
        Padding = New Padding(16, 24, 16, 24)
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
        g.Clear(AppTheme.BgSidebar)
        g.TextRenderingHint = Drawing.Text.TextRenderingHint.ClearTypeGridFit

        Using brandFont As New Font("Tahoma", 11.0F, FontStyle.Bold)
            Using brush As New SolidBrush(AppTheme.AccentSoft)
                Dim brand = "Holoo → Hesabix"
                Dim brandSize = g.MeasureString(brand, brandFont)
                g.DrawString(brand, brandFont, brush, Width - 16 - brandSize.Width, 20)
            End Using
        End Using

        Dim y = 70
        For i = 0 To _steps.Length - 1
            Dim item = _steps(i)
            Dim active = item.WizardStepValue = _current
            Dim done = CInt(item.WizardStepValue) < CInt(_current)
            Dim upcoming = CInt(item.WizardStepValue) > CInt(_current)

            Dim circleRect As New Rectangle(Width - 46, y, 28, 28)
            Dim fill = If(active, AppTheme.Accent, If(done, AppTheme.AccentDark, Color.FromArgb(51, 65, 85)))
            Using brush As New SolidBrush(fill)
                g.FillEllipse(brush, circleRect)
            End Using

            Dim num = If(done, "✓", (i + 1).ToString())
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
                g.DrawString(item.Title, titleFont, brush, circleRect.X - 12 - titleSize.Width, y + 2)
            End Using

            Dim hintSize = g.MeasureString(item.Hint, AppTheme.FontStep)
            Using brush As New SolidBrush(Color.FromArgb(148, 163, 184))
                g.DrawString(item.Hint, AppTheme.FontStep, brush, circleRect.X - 12 - hintSize.Width, y + 20)
            End Using

            If i < _steps.Length - 1 Then
                Using pen As New Pen(Color.FromArgb(51, 65, 85), 2)
                    Dim cx = circleRect.X + circleRect.Width \ 2
                    g.DrawLine(pen, cx, y + 34, cx, y + 52)
                End Using
            End If

            y += 58
        Next
    End Sub
End Class
