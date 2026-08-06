Imports System.Threading

''' <summary>
''' کمک‌کننده برای اجرای کار پس‌زمینه بدون قفل شدن UI و مدیریت Cancellation.
''' </summary>
Friend Class AsyncUi
    Private Sub New()
    End Sub

    Public Shared Async Function Run(Of T)(
        owner As Control,
        work As Func(Of CancellationToken, Task(Of T)),
        Optional onBusy As Action(Of Boolean) = Nothing,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of T)
        If onBusy IsNot Nothing Then
            SafeInvoke(owner, Sub() onBusy(True))
        End If
        Try
            Return Await work(ct).ConfigureAwait(True)
        Finally
            If onBusy IsNot Nothing Then
                SafeInvoke(owner, Sub() onBusy(False))
            End If
        End Try
    End Function

    Public Shared Async Function Run(
        owner As Control,
        work As Func(Of CancellationToken, Task),
        Optional onBusy As Action(Of Boolean) = Nothing,
        Optional ct As CancellationToken = Nothing
    ) As Task
        If onBusy IsNot Nothing Then
            SafeInvoke(owner, Sub() onBusy(True))
        End If
        Try
            Await work(ct).ConfigureAwait(True)
        Finally
            If onBusy IsNot Nothing Then
                SafeInvoke(owner, Sub() onBusy(False))
            End If
        End Try
    End Function

    Public Shared Sub SafeInvoke(owner As Control, action As Action)
        If owner Is Nothing OrElse owner.IsDisposed Then Return
        If owner.InvokeRequired Then
            Try
                owner.BeginInvoke(action)
            Catch
            End Try
        Else
            action()
        End If
    End Sub

    Public Shared Sub ShowError(owner As IWin32Window, title As String, ex As Exception)
        Dim message As String
        If TypeOf ex Is OperationCanceledException Then
            message = "عملیات لغو شد."
        Else
            message = ex.Message
        End If
        MessageBox.Show(owner, message, title, MessageBoxButtons.OK, MessageBoxIcon.Error)
    End Sub
End Class
