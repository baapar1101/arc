Imports System.Drawing.Drawing2D

Friend NotInheritable Class AppTheme
    Private Sub New()
    End Sub

    Public Shared ReadOnly BgApp As Color = Color.FromArgb(241, 245, 249)
    Public Shared ReadOnly BgSidebar As Color = Color.FromArgb(15, 23, 42)
    Public Shared ReadOnly BgCard As Color = Color.White
    Public Shared ReadOnly BgMuted As Color = Color.FromArgb(248, 250, 252)
    Public Shared ReadOnly Accent As Color = Color.FromArgb(13, 148, 136)
    Public Shared ReadOnly AccentDark As Color = Color.FromArgb(15, 118, 110)
    Public Shared ReadOnly AccentSoft As Color = Color.FromArgb(204, 251, 241)
    Public Shared ReadOnly TextPrimary As Color = Color.FromArgb(15, 23, 42)
    Public Shared ReadOnly TextSecondary As Color = Color.FromArgb(71, 85, 105)
    Public Shared ReadOnly TextMuted As Color = Color.FromArgb(100, 116, 139)
    Public Shared ReadOnly TextOnDark As Color = Color.FromArgb(226, 232, 240)
    Public Shared ReadOnly TextOnAccent As Color = Color.White
    Public Shared ReadOnly Border As Color = Color.FromArgb(203, 213, 225)
    Public Shared ReadOnly BorderFocus As Color = Color.FromArgb(45, 212, 191)
    Public Shared ReadOnly Danger As Color = Color.FromArgb(220, 38, 38)
    Public Shared ReadOnly Success As Color = Color.FromArgb(22, 163, 74)
    Public Shared ReadOnly Warning As Color = Color.FromArgb(217, 119, 6)

    Public Shared ReadOnly FontUi As Font = New Font("Tahoma", 9.5F, FontStyle.Regular)
    Public Shared ReadOnly FontUiBold As Font = New Font("Tahoma", 9.5F, FontStyle.Bold)
    Public Shared ReadOnly FontTitle As Font = New Font("Tahoma", 16.0F, FontStyle.Bold)
    Public Shared ReadOnly FontSubtitle As Font = New Font("Tahoma", 10.0F, FontStyle.Regular)
    Public Shared ReadOnly FontHero As Font = New Font("Tahoma", 22.0F, FontStyle.Bold)
    Public Shared ReadOnly FontStep As Font = New Font("Tahoma", 8.5F, FontStyle.Regular)

    Public Shared Function CreateRoundedPath(bounds As Rectangle, radius As Integer) As GraphicsPath
        Dim path As New GraphicsPath()
        Dim d = radius * 2
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90)
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90)
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90)
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90)
        path.CloseFigure()
        Return path
    End Function

    Public Shared Sub DrawRoundedRect(g As Graphics, bounds As Rectangle, radius As Integer, fill As Color, Optional borderColor As Color? = Nothing, Optional borderWidth As Single = 1.0F)
        g.SmoothingMode = SmoothingMode.AntiAlias
        Using path = CreateRoundedPath(bounds, radius)
            Using brush As New SolidBrush(fill)
                g.FillPath(brush, path)
            End Using
            If borderColor.HasValue Then
                Using pen As New Pen(borderColor.Value, borderWidth)
                    g.DrawPath(pen, path)
                End Using
            End If
        End Using
    End Sub

    Public Shared Sub StylePrimaryButton(btn As Button)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderSize = 0
        btn.FlatAppearance.MouseOverBackColor = AccentDark
        btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(17, 94, 89)
        btn.UseVisualStyleBackColor = False
        btn.BackColor = Accent
        btn.ForeColor = TextOnAccent
        btn.Font = FontUiBold
        btn.Cursor = Cursors.Hand
        btn.TextAlign = ContentAlignment.MiddleCenter
        btn.Padding = New Padding(10, 4, 10, 4)
        If btn.Height < 36 Then btn.Height = 40
    End Sub

    Public Shared Sub StyleSecondaryButton(btn As Button)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderColor = Accent
        btn.FlatAppearance.BorderSize = 1
        btn.FlatAppearance.MouseOverBackColor = AccentSoft
        btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(153, 246, 228)
        btn.UseVisualStyleBackColor = False
        btn.BackColor = Color.White
        btn.ForeColor = AccentDark
        btn.Font = FontUiBold
        btn.Cursor = Cursors.Hand
        btn.TextAlign = ContentAlignment.MiddleCenter
        btn.Padding = New Padding(8, 4, 8, 4)
        If btn.Height < 32 Then btn.Height = 36
    End Sub

    Public Shared Sub StyleGhostButton(btn As Button)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderSize = 0
        btn.UseVisualStyleBackColor = False
        btn.BackColor = Color.Transparent
        btn.ForeColor = TextOnDark
        btn.Font = FontUi
        btn.Cursor = Cursors.Hand
        btn.TextAlign = ContentAlignment.MiddleCenter
    End Sub

    Public Shared Sub StyleTextBox(tb As TextBox)
        tb.BorderStyle = BorderStyle.FixedSingle
        tb.Font = FontUi
        tb.BackColor = BgCard
        tb.ForeColor = TextPrimary
    End Sub

    Public Shared Sub StyleComboBox(cmb As ComboBox)
        cmb.FlatStyle = FlatStyle.Flat
        cmb.Font = FontUi
        cmb.BackColor = BgCard
        cmb.ForeColor = TextPrimary
        cmb.RightToLeft = RightToLeft.Yes
    End Sub

    Public Shared Sub StyleLabel(lbl As Label, Optional secondary As Boolean = False)
        lbl.Font = FontUi
        lbl.ForeColor = If(secondary, TextSecondary, TextPrimary)
        lbl.BackColor = Color.Transparent
        lbl.RightToLeft = RightToLeft.Yes
    End Sub

    ''' <summary>
    ''' راست‌چین کردن درخت کنترل‌ها بدون فعال کردن RightToLeftLayout
    ''' (Layout آینه‌ای مختصات مطلق را به هم می‌ریزد).
    ''' </summary>
    Public Shared Sub ApplyRtlTree(root As Control, Optional mirrorLayout As Boolean = False)
        If root Is Nothing Then Return
        root.RightToLeft = RightToLeft.Yes
        Dim form = TryCast(root, Form)
        If form IsNot Nothing Then
            form.RightToLeftLayout = mirrorLayout
        End If
        Dim tabs = TryCast(root, TabControl)
        If tabs IsNot Nothing Then
            ' فقط متن تب RTL؛ مختصات داخلی آینه نشود
            tabs.RightToLeftLayout = False
        End If
        For Each child As Control In root.Controls
            ApplyRtlTree(child, False)
            Dim btn = TryCast(child, Button)
            If btn IsNot Nothing Then
                btn.TextAlign = ContentAlignment.MiddleCenter
            End If
            Dim lbl = TryCast(child, Label)
            If lbl IsNot Nothing AndAlso Not lbl.AutoSize Then
                lbl.TextAlign = ContentAlignment.TopRight
            End If
        Next
    End Sub
End Class
