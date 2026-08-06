Friend Module Program

    <STAThread()>
    Friend Sub Main()
        Application.EnableVisualStyles()
        Application.SetCompatibleTextRenderingDefault(False)
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException)
        AddHandler Application.ThreadException, AddressOf OnUiThreadException
        AddHandler AppDomain.CurrentDomain.UnhandledException, AddressOf OnDomainException
        Application.Run(New MainForm())
    End Sub

    Private Sub OnUiThreadException(sender As Object, e As Threading.ThreadExceptionEventArgs)
        MessageBox.Show(e.Exception.Message, "خطای برنامه", MessageBoxButtons.OK, MessageBoxIcon.Error)
    End Sub

    Private Sub OnDomainException(sender As Object, e As UnhandledExceptionEventArgs)
        Dim ex = TryCast(e.ExceptionObject, Exception)
        If ex IsNot Nothing Then
            MessageBox.Show(ex.Message, "خطای بحرانی", MessageBoxButtons.OK, MessageBoxIcon.Error)
        End If
    End Sub

End Module
