Imports System.Threading

Friend Class SelectModulesPanel
    Inherits UserControl

    Public Event SelectionChanged As EventHandler

    Private ReadOnly _session As MigrationSession
    Private ReadOnly _reader As New HolooBaseDataReader()
    Private ReadOnly _host As Panel
    Private ReadOnly _chkList As New List(Of Tuple(Of CheckBox, ModuleOption))
    Private ReadOnly _lblHint As Label
    Private _busy As Boolean

    Public Sub New(session As MigrationSession)
        _session = session
        DoubleBuffered = True
        BackColor = AppTheme.BgApp
        RightToLeft = RightToLeft.Yes
        Dock = DockStyle.Fill
        Padding = New Padding(28, 16, 28, 16)

        Dim title As New Label() With {
            .Text = "انتخاب بخش‌های انتقال",
            .Font = AppTheme.FontTitle,
            .ForeColor = AppTheme.TextPrimary,
            .AutoSize = True,
            .Location = New Point(28, 12),
            .RightToLeft = RightToLeft.Yes
        }
        Dim subtitle As New Label() With {
            .Text = "اطلاعات پایه و اسناد (Full History). برای تاریخچه کامل، ماژول‌های سند را هم انتخاب کنید.",
            .Font = AppTheme.FontSubtitle,
            .ForeColor = AppTheme.TextSecondary,
            .AutoSize = True,
            .Location = New Point(28, 52),
            .RightToLeft = RightToLeft.Yes
        }

        _host = New Panel() With {
            .Location = New Point(28, 100),
            .AutoScroll = True,
            .BackColor = AppTheme.BgCard,
            .RightToLeft = RightToLeft.Yes
        }
        AddHandler _host.Paint, Sub(s, e)
                                    Dim r = New Rectangle(0, 0, _host.Width - 1, _host.Height - 1)
                                    AppTheme.DrawRoundedRect(e.Graphics, r, 12, AppTheme.BgCard, AppTheme.Border)
                                End Sub

        _lblHint = New Label() With {
            .AutoSize = True,
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontStep,
            .RightToLeft = RightToLeft.Yes,
            .Text = "با انتخاب فاکتور/اسناد، انتقال سال‌به‌سال (Full History) فعال می‌شود و مانده افتتاحیه اشخاص/کالا جداگانه ارسال نمی‌شود."
        }

        Controls.Add(title)
        Controls.Add(subtitle)
        Controls.Add(_host)
        Controls.Add(_lblHint)

        AddHandler Resize, Sub(s, e)
                               _host.Width = Math.Max(640, ClientSize.Width - 56)
                               _host.Height = Math.Max(280, ClientSize.Height - 160)
                               _lblHint.Location = New Point(28, _host.Bottom + 12)
                           End Sub
        OnResize(EventArgs.Empty)
        BuildChecks()
        AppTheme.ApplyRtlTree(Me, False)
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

        Dim y = 16
        For Each opt In _session.SelectedModules.OrderBy(Function(x) x.SortOrder)
            Dim chk As New CheckBox() With {
                .Text = opt.Title & "  (" & opt.HolooSource & ")",
                .Checked = opt.Selected AndAlso opt.Enabled,
                .Enabled = opt.Enabled,
                .AutoSize = True,
                .Location = New Point(20, y),
                .Font = AppTheme.FontUiBold,
                .ForeColor = AppTheme.TextPrimary,
                .RightToLeft = RightToLeft.Yes,
                .Tag = opt
            }
            AddHandler chk.CheckedChanged, Sub(s, e)
                                               opt.Selected = chk.Checked
                                               RaiseEvent SelectionChanged(Me, EventArgs.Empty)
                                           End Sub
            Dim countLbl As New Label() With {
                .AutoSize = True,
                .Location = New Point(420, y + 2),
                .ForeColor = AppTheme.TextSecondary,
                .Font = AppTheme.FontStep,
                .Text = If(opt.SourceCount >= 0, opt.SourceCount.ToString("N0") & " رکورد", "در حال شمارش..."),
                .Tag = opt.ModuleKey,
                .RightToLeft = RightToLeft.Yes
            }
            _host.Controls.Add(chk)
            _host.Controls.Add(countLbl)
            _chkList.Add(Tuple.Create(chk, opt))
            y += 36
        Next

        Dim later As New Label() With {
            .AutoSize = True,
            .Location = New Point(20, y + 12),
            .ForeColor = AppTheme.TextMuted,
            .Font = AppTheme.FontUi,
            .Text = "نکته: اسناد Type=5 و Type=0 لینک‌شده به چک از مسیر «چک‌ها» منتقل می‌شوند (جلوگیری از GL دوبل).",
            .RightToLeft = RightToLeft.Yes
        }
        _host.Controls.Add(later)
    End Sub

    Public Async Function RefreshCountsAsync() As Task
        If _busy OrElse Not _session.CanProceedFromHolooSql Then Return
        _busy = True
        Try
            For Each item In _chkList
                Dim opt = item.Item2
                Dim count = Await Task.Run(Function() _reader.CountModule(_session.SqlSettings, opt.ModuleKey)).ConfigureAwait(True)
                opt.SourceCount = count
                For Each ctrl As Control In _host.Controls
                    Dim lbl = TryCast(ctrl, Label)
                    If lbl IsNot Nothing AndAlso lbl.Tag IsNot Nothing AndAlso lbl.Tag.Equals(opt.ModuleKey) Then
                        lbl.Text = count.ToString("N0") & " رکورد"
                    End If
                Next
            Next
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
