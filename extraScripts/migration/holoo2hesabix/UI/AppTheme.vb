Imports System.Drawing.Drawing2D

Friend NotInheritable Class AppTheme
    Private Sub New()
    End Sub

    Public Const LtrInputTag As String = "ltr-input"
    Public Const FieldHeight As Integer = 40
    Public Const FieldBlockHeight As Integer = 62
    Public Const PageMargin As Integer = 32
    Public Const SectionGap As Integer = 20
    Public Const CardRadius As Integer = 14

    Public Shared ReadOnly BgApp As Color = Color.FromArgb(238, 242, 247)
    Public Shared ReadOnly BgSidebar As Color = Color.FromArgb(15, 23, 42)
    Public Shared ReadOnly BgSidebarElevated As Color = Color.FromArgb(30, 41, 59)
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
    Public Shared ReadOnly FontTitle As Font = New Font("Tahoma", 17.0F, FontStyle.Bold)
    Public Shared ReadOnly FontSubtitle As Font = New Font("Tahoma", 9.75F, FontStyle.Regular)
    Public Shared ReadOnly FontHero As Font = New Font("Tahoma", 24.0F, FontStyle.Bold)
    Public Shared ReadOnly FontStep As Font = New Font("Tahoma", 8.5F, FontStyle.Regular)
    Public Shared ReadOnly FontFieldLabel As Font = New Font("Tahoma", 8.5F, FontStyle.Regular)
    Public Shared ReadOnly FontMono As Font = New Font("Consolas", 9.5F, FontStyle.Regular)

    Public Shared Function CreateRoundedPath(bounds As Rectangle, radius As Integer) As GraphicsPath
        Dim path As New GraphicsPath()
        If bounds.Width <= 0 OrElse bounds.Height <= 0 Then
            path.AddRectangle(New Rectangle(bounds.X, bounds.Y, Math.Max(1, bounds.Width), Math.Max(1, bounds.Height)))
            Return path
        End If
        Dim r = Math.Max(1, Math.Min(radius, Math.Min(bounds.Width, bounds.Height) \ 2))
        Dim d = r * 2
        If bounds.Width < d OrElse bounds.Height < d Then
            path.AddRectangle(bounds)
            Return path
        End If
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90)
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90)
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90)
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90)
        path.CloseFigure()
        Return path
    End Function

    Public Shared Sub DrawRoundedRect(g As Graphics, bounds As Rectangle, radius As Integer, fill As Color, Optional borderColor As Color? = Nothing, Optional borderWidth As Single = 1.0F)
        If g Is Nothing OrElse bounds.Width <= 0 OrElse bounds.Height <= 0 Then Return
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

    Public Shared Sub PaintCardBackground(ctrl As Control, e As PaintEventArgs, Optional radius As Integer = 14)
        Dim r As New Rectangle(0, 0, ctrl.Width - 1, ctrl.Height - 1)
        DrawRoundedRect(e.Graphics, r, radius, BgCard, Border, 1.0F)
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
        btn.RightToLeft = RightToLeft.Yes
        btn.Padding = New Padding(14, 6, 14, 6)
        btn.Height = FieldHeight
    End Sub

    Public Shared Sub StyleSecondaryButton(btn As Button)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderColor = Border
        btn.FlatAppearance.BorderSize = 1
        btn.FlatAppearance.MouseOverBackColor = AccentSoft
        btn.FlatAppearance.MouseDownBackColor = Color.FromArgb(153, 246, 228)
        btn.UseVisualStyleBackColor = False
        btn.BackColor = Color.White
        btn.ForeColor = AccentDark
        btn.Font = FontUiBold
        btn.Cursor = Cursors.Hand
        btn.TextAlign = ContentAlignment.MiddleCenter
        btn.RightToLeft = RightToLeft.Yes
        btn.Padding = New Padding(12, 5, 12, 5)
        btn.Height = FieldHeight
    End Sub

    Public Shared Sub StyleGhostButton(btn As Button)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderSize = 0
        btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(40, 255, 255, 255)
        btn.UseVisualStyleBackColor = False
        btn.BackColor = Color.Transparent
        btn.ForeColor = TextMuted
        btn.Font = FontUi
        btn.Cursor = Cursors.Hand
        btn.TextAlign = ContentAlignment.MiddleCenter
        btn.RightToLeft = RightToLeft.Yes
        btn.Height = 32
    End Sub

    Public Shared Sub StyleDangerGhostButton(btn As Button)
        StyleGhostButton(btn)
        btn.ForeColor = Danger
        btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(254, 226, 226)
    End Sub

    Public Shared Sub StyleTextBox(tb As TextBox)
        tb.BorderStyle = BorderStyle.None
        tb.Font = FontUi
        tb.BackColor = BgCard
        tb.ForeColor = TextPrimary
    End Sub

    Public Shared Sub StyleRtlTextBox(tb As TextBox)
        StyleTextBox(tb)
        tb.RightToLeft = RightToLeft.Yes
        tb.TextAlign = HorizontalAlignment.Right
        If TypeOf tb.Tag Is String AndAlso String.Equals(CStr(tb.Tag), LtrInputTag, StringComparison.Ordinal) Then
            tb.Tag = Nothing
        End If
    End Sub

    Public Shared Sub StyleLtrTextBox(tb As TextBox)
        StyleTextBox(tb)
        tb.RightToLeft = RightToLeft.No
        tb.TextAlign = HorizontalAlignment.Left
        tb.Tag = LtrInputTag
        tb.Font = FontMono
    End Sub

    Public Shared Sub StyleComboBox(cmb As ComboBox)
        cmb.FlatStyle = FlatStyle.Flat
        cmb.Font = FontUi
        cmb.BackColor = BgCard
        cmb.ForeColor = TextPrimary
        cmb.RightToLeft = RightToLeft.Yes
        cmb.Height = FieldHeight
    End Sub

    Public Shared Sub StyleLabel(lbl As Label, Optional secondary As Boolean = False)
        lbl.Font = FontUi
        lbl.ForeColor = If(secondary, TextSecondary, TextPrimary)
        lbl.BackColor = Color.Transparent
        lbl.RightToLeft = RightToLeft.Yes
        If Not lbl.AutoSize Then
            lbl.TextAlign = ContentAlignment.MiddleRight
        End If
    End Sub

    Public Shared Sub StyleCheckBox(chk As CheckBox)
        chk.RightToLeft = RightToLeft.Yes
        chk.Font = FontUi
        chk.CheckAlign = ContentAlignment.MiddleLeft
        chk.TextAlign = ContentAlignment.MiddleLeft
        chk.FlatStyle = FlatStyle.Standard
        chk.ForeColor = TextPrimary
        chk.BackColor = Color.Transparent
    End Sub

    Public Shared Sub StyleRadioButton(rb As RadioButton)
        rb.RightToLeft = RightToLeft.Yes
        rb.Font = FontUi
        rb.CheckAlign = ContentAlignment.MiddleLeft
        rb.TextAlign = ContentAlignment.MiddleLeft
        rb.FlatStyle = FlatStyle.Standard
        rb.ForeColor = TextPrimary
        rb.BackColor = Color.Transparent
    End Sub

    Public Shared Function IsLtrInput(ctrl As Control) As Boolean
        If ctrl Is Nothing OrElse ctrl.Tag Is Nothing Then Return False
        Return TypeOf ctrl.Tag Is String AndAlso String.Equals(CStr(ctrl.Tag), LtrInputTag, StringComparison.Ordinal)
    End Function

    Public Shared Function RtlLeft(containerWidth As Integer, marginFromRight As Integer, controlWidth As Integer) As Integer
        Return Math.Max(0, containerWidth - marginFromRight - controlWidth)
    End Function

    Public Shared Function PreferredWidth(ctrl As Control) As Integer
        If ctrl Is Nothing Then Return 0
        If ctrl.AutoSize Then Return Math.Max(ctrl.Width, ctrl.PreferredSize.Width)
        Return ctrl.Width
    End Function

    Public Shared Sub PlaceFromRight(ctrl As Control, containerWidth As Integer, marginFromRight As Integer, y As Integer, Optional fixedWidth As Integer = -1)
        If fixedWidth > 0 Then ctrl.Width = fixedWidth
        Dim w = PreferredWidth(ctrl)
        ctrl.Location = New Point(RtlLeft(containerWidth, marginFromRight, w), y)
    End Sub

    Public Shared ReadOnly Property MsgRtl As MessageBoxOptions
        Get
            Return MessageBoxOptions.RtlReading Or MessageBoxOptions.RightAlign
        End Get
    End Property

    Public Shared Sub ApplyRtlTree(root As Control, Optional mirrorLayout As Boolean = False)
        If root Is Nothing Then Return
        ApplyRtlRecursive(root, mirrorLayout, isRoot:=True)
    End Sub

    Private Shared Sub ApplyRtlRecursive(ctrl As Control, mirrorLayout As Boolean, isRoot As Boolean)
        If TypeOf ctrl Is ModernTextField OrElse TypeOf ctrl Is SegmentedControl OrElse
           TypeOf ctrl Is ContextBanner OrElse TypeOf ctrl Is BusyOverlay OrElse
           TypeOf ctrl Is ModernProgressBar OrElse TypeOf ctrl Is EmptyStateView OrElse
           TypeOf ctrl Is RoundedCard Then
            For Each child As Control In ctrl.Controls
                ApplyRtlRecursive(child, False, False)
            Next
            Return
        End If

        Dim keepLtr = IsLtrInput(ctrl)
        If Not keepLtr Then
            ctrl.RightToLeft = RightToLeft.Yes
        End If

        If isRoot Then
            Dim form = TryCast(ctrl, Form)
            If form IsNot Nothing Then
                form.RightToLeftLayout = mirrorLayout
            End If
        End If

        Dim tabs = TryCast(ctrl, TabControl)
        If tabs IsNot Nothing Then
            tabs.RightToLeftLayout = False
        End If

        If Not keepLtr Then
            Dim btn = TryCast(ctrl, Button)
            If btn IsNot Nothing Then btn.TextAlign = ContentAlignment.MiddleCenter

            Dim lbl = TryCast(ctrl, Label)
            If lbl IsNot Nothing AndAlso Not lbl.AutoSize Then
                lbl.TextAlign = ContentAlignment.MiddleRight
            End If

            Dim chk = TryCast(ctrl, CheckBox)
            If chk IsNot Nothing Then
                chk.CheckAlign = ContentAlignment.MiddleLeft
                chk.TextAlign = ContentAlignment.MiddleLeft
            End If

            Dim rb = TryCast(ctrl, RadioButton)
            If rb IsNot Nothing Then
                rb.CheckAlign = ContentAlignment.MiddleLeft
                rb.TextAlign = ContentAlignment.MiddleLeft
            End If

            Dim tb = TryCast(ctrl, TextBox)
            If tb IsNot Nothing AndAlso tb.RightToLeft = RightToLeft.Yes AndAlso Not tb.Multiline Then
                tb.TextAlign = HorizontalAlignment.Right
            End If
        Else
            Dim tbLtr = TryCast(ctrl, TextBox)
            If tbLtr IsNot Nothing Then
                tbLtr.RightToLeft = RightToLeft.No
                tbLtr.TextAlign = HorizontalAlignment.Left
            End If
        End If

        For Each child As Control In ctrl.Controls
            ApplyRtlRecursive(child, False, False)
        Next
    End Sub
End Class
