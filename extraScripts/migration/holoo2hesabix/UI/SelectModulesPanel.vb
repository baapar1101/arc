Imports System.Threading

Friend Class SelectModulesPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _reader As New HolooBaseDataReader()
    Private ReadOnly _host As RoundedCard
    Private ReadOnly _chkList As New List(Of Tuple(Of CheckBox, ModuleOption, Panel))
    Private ReadOnly _lblHint As Label
    Private _busy As Boolean

    Public Sub New(session As MigrationSession)
        _session = session
        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill

        Dim header = PageHeader.Create(
            "انتخاب بخش‌های انتقال",
            "اطلاعات پایه و اسناد (Full History). برای تاریخچه کامل، ماژول‌های سند را هم انتخاب کنید.")

        _host = New RoundedCard() With {
            .AutoScroll = True,
            .Padding = New Padding(8),
            .Name = "host"
        }
        AddHandler _host.Resize, Sub(s, e) LayoutChecks()

        _lblHint = New Label() With {
            .AutoSize = True,
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes,
            .Text = "با انتخاب فاکتور/اسناد، انتقال سال‌به‌سال (Full History) فعال می‌شود و مانده افتتاحیه اشخاص/کالا جداگانه ارسال نمی‌شود.",
            .Name = "lblHint"
        }

        Controls.Add(header.Item1)
        Controls.Add(header.Item2)
        Controls.Add(_host)
        Controls.Add(_lblHint)

        AddHandler Resize, AddressOf OnPanelResize
        BuildChecks()
        OnPanelResize(Me, EventArgs.Empty)
        AppTheme.ApplyRtlTree(Me, False)
        OnPanelResize(Me, EventArgs.Empty)
    End Sub

    Private Sub OnPanelResize(sender As Object, e As EventArgs)
        Dim w = ClientSize.Width
        Dim m = AppTheme.PageMargin
        Dim title = Controls("title")
        Dim subtitle = Controls("subtitle")
        If title IsNot Nothing Then AppTheme.PlaceFromRight(title, w, m, 18)
        If subtitle IsNot Nothing Then AppTheme.PlaceFromRight(subtitle, w, m, 52)

        _host.Width = Math.Max(640, w - m * 2)
        _host.Height = Math.Max(280, ClientSize.Height - 160)
        AppTheme.PlaceFromRight(_host, w, m, 92)
        LayoutChecks()
        AppTheme.PlaceFromRight(_lblHint, w, m, _host.Bottom + 14)
    End Sub

    Private Sub BuildChecks()
        _host.Controls.Clear()
        _chkList.Clear()
        If _session.SelectedModules Is Nothing OrElse _session.SelectedModules.Count = 0 Then
            _session.SelectedModules = MigrationModuleInfo.GetAllModules()
        Else
            Dim existing = New HashSet(Of MigrationModule)(_session.SelectedModules.Select(Function(x) x.ModuleKey))
            For Each opt In MigrationModuleInfo.GetAllModules()
                If Not existing.Contains(opt.ModuleKey) Then
                    _session.SelectedModules.Add(opt)
                End If
            Next
        End If

        For Each opt In _session.SelectedModules.OrderBy(Function(x) x.SortOrder)
            Dim row As New Panel() With {
                .Height = 48,
                .BackColor = Color.Transparent,
                .RightToLeft = RightToLeft.Yes,
                .Name = "row_" & opt.ModuleKey.ToString()
            }
            AddHandler row.Paint, Sub(s, e)
                                      Dim r As New Rectangle(0, 0, row.Width - 1, row.Height - 1)
                                      AppTheme.DrawRoundedRect(e.Graphics, r, 10, AppTheme.BgMuted, AppTheme.Border, 1.0F)
                                  End Sub

            Dim chk As New CheckBox() With {
                .Text = opt.Title & "  (" & opt.HolooSource & ")",
                .Checked = opt.Selected AndAlso opt.Enabled,
                .Enabled = opt.Enabled,
                .AutoSize = True,
                .Tag = opt,
                .Name = "chk_" & opt.ModuleKey.ToString()
            }
            AppTheme.StyleCheckBox(chk)
            chk.Font = AppTheme.FontUiBold
            AddHandler chk.CheckedChanged, Sub(s, e)
                                               opt.Selected = chk.Checked
                                               RaiseEvent SelectionChanged(Me, EventArgs.Empty)
                                           End Sub

            Dim countText = If(opt.SourceCount >= 0, opt.SourceCount.ToString("N0") & " رکورد", "در حال شمارش...")
            Dim countChip As New Panel() With {
                .Size = New Size(110, 26),
                .Tag = countText,
                .RightToLeft = RightToLeft.Yes,
                .BackColor = Color.Transparent,
                .Name = "cnt_" & opt.ModuleKey.ToString()
            }
            AddHandler countChip.Paint, Sub(s, e)
                                            Dim chip = DirectCast(s, Panel)
                                            Dim g = e.Graphics
                                            g.SmoothingMode = Drawing2D.SmoothingMode.AntiAlias
                                            Dim r As New Rectangle(0, 0, chip.Width - 1, chip.Height - 1)
                                            AppTheme.DrawRoundedRect(g, r, 8, Color.FromArgb(241, 245, 249), AppTheme.Border, 1.0F)
                                            Using brush As New SolidBrush(AppTheme.TextMuted)
                                                Dim sf As New StringFormat() With {
                                                    .Alignment = StringAlignment.Center,
                                                    .LineAlignment = StringAlignment.Center,
                                                    .FormatFlags = StringFormatFlags.DirectionRightToLeft
                                                }
                                                g.DrawString(CStr(chip.Tag), AppTheme.FontStep, brush, New RectangleF(0, 0, chip.Width, chip.Height), sf)
                                            End Using
                                        End Sub

            row.Controls.Add(chk)
            row.Controls.Add(countChip)
            _host.Controls.Add(row)
            _chkList.Add(Tuple.Create(chk, opt, countChip))
        Next

        Dim later As New Label() With {
            .AutoSize = True,
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontUi,
            .Text = "نکته: اسناد Type=5 و Type=0 لینک‌شده به چک از مسیر «چک‌ها» منتقل می‌شوند (جلوگیری از GL دوبل).",
            .RightToLeft = RightToLeft.Yes,
            .Name = "laterNote"
        }
        _host.Controls.Add(later)
        LayoutChecks()
    End Sub

    Private Sub LayoutChecks()
        If _host Is Nothing OrElse _host.Width < 80 Then Return
        Dim w = _host.ClientSize.Width
        Const m As Integer = 18
        Dim y = 16
        Dim rowW = Math.Max(200, w - m * 2)

        For Each item In _chkList
            Dim chk = item.Item1
            Dim countChip = item.Item3
            Dim row = TryCast(chk.Parent, Panel)
            If row Is Nothing Then Continue For

            row.SetBounds(m, y, rowW, 48)
            AppTheme.PlaceFromRight(chk, rowW, 14, 12)
            countChip.Location = New Point(14, 11)
            y += 56
        Next

        Dim later = _host.Controls("laterNote")
        If later IsNot Nothing Then
            AppTheme.PlaceFromRight(later, w, m, y + 8)
        End If
    End Sub

    Public Async Function RefreshCountsAsync() As Task
        If _busy OrElse Not _session.CanProceedFromHolooSql Then Return
        _busy = True
        Try
            For Each item In _chkList
                Dim opt = item.Item2
                Dim countChip = item.Item3
                Dim count = Await Task.Run(Function() _reader.CountModule(_session.SqlSettings, opt.ModuleKey)).ConfigureAwait(True)
                opt.SourceCount = count
                countChip.Tag = count.ToString("N0") & " رکورد"
                countChip.Invalidate()
            Next
            LayoutChecks()
        Finally
            _busy = False
            RaiseEvent SelectionChanged(Me, EventArgs.Empty)
        End Try
    End Function

    Public Function GetSelectedModules() As List(Of MigrationModule)
        Return _session.SelectedModules.Where(Function(x) x.Selected AndAlso x.Enabled).
            OrderBy(Function(x) x.SortOrder).
            Select(Function(x) x.ModuleKey).ToList()
    End Function

    Public ReadOnly Property HasSelection As Boolean
        Get
            Return GetSelectedModules().Count > 0
        End Get
    End Property
End Class
