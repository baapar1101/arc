Imports System.Globalization
Imports System.Net
Imports System.Threading

Friend Module Program

    <STAThread()>
    Friend Sub Main()
        Try
            ServicePointManager.DefaultConnectionLimit = 32
            ServicePointManager.Expect100Continue = False
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12
        Catch
        End Try

        ' UI فارسی؛ اما تقویم اجرایی باید میلادی بماند.
        ' اگر Calendar=Persian باشد، Date.ToString("yyyy-MM-dd") جلالی می‌سازد و API آن را میلادی می‌خواند.
        Dim fa = CultureInfo.GetCultureInfo("fa-IR")
        Dim faGregorian = DirectCast(fa.Clone(), CultureInfo)
        faGregorian.DateTimeFormat.Calendar = New GregorianCalendar()
        CultureInfo.DefaultThreadCurrentCulture = faGregorian
        CultureInfo.DefaultThreadCurrentUICulture = fa
        Thread.CurrentThread.CurrentCulture = faGregorian
        Thread.CurrentThread.CurrentUICulture = fa

        Dim args = Environment.GetCommandLineArgs().Skip(1).ToArray()
        If args.Any(Function(a) String.Equals(a, "--e2e-opening", StringComparison.OrdinalIgnoreCase)) Then
            Dim code = E2eOpeningRunner.Run(args)
            Environment.Exit(code)
            Return
        End If

        Application.EnableVisualStyles()
        Application.SetCompatibleTextRenderingDefault(False)
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException)
        AddHandler Application.ThreadException, AddressOf OnUiThreadException
        AddHandler AppDomain.CurrentDomain.UnhandledException, AddressOf OnDomainException
        Application.Run(New MainForm())
    End Sub

    Private Sub OnUiThreadException(sender As Object, e As ThreadExceptionEventArgs)
        Try
            IO.File.AppendAllText(IO.Path.Combine(IO.Path.GetTempPath(), "holoo2hesabix-crash.txt"),
                                  DateTime.Now.ToString("s") & Environment.NewLine & e.Exception.ToString() & Environment.NewLine & Environment.NewLine)
        Catch
        End Try
        MessageBox.Show(e.Exception.Message & Environment.NewLine & Environment.NewLine & e.Exception.StackTrace,
                        "خطای برنامه", MessageBoxButtons.OK, MessageBoxIcon.Error,
                        MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
    End Sub

    Private Sub OnDomainException(sender As Object, e As UnhandledExceptionEventArgs)
        Dim ex = TryCast(e.ExceptionObject, Exception)
        If ex IsNot Nothing Then
            Dim detail = ex.GetType().FullName & Environment.NewLine &
                         ex.Message & Environment.NewLine & Environment.NewLine &
                         ex.StackTrace
            MessageBox.Show(detail, "خطای بحرانی", MessageBoxButtons.OK, MessageBoxIcon.Error,
                            MessageBoxDefaultButton.Button1, AppTheme.MsgRtl)
        End If
    End Sub

End Module
