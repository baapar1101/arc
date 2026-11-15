Imports System.IO
Imports System.Text

''' <summary>ثبت دو وظیفه روزانه ویندوز برای اجرای --auto-sync.</summary>
Friend NotInheritable Class WindowsTaskSync
    Public Const TaskName1 As String = "Holoo2Hesabix Sync Morning"
    Public Const TaskName2 As String = "Holoo2Hesabix Sync Evening"

    Private Sub New()
    End Sub

    Public Shared Function LauncherPath() As String
        Dim dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix")
        Directory.CreateDirectory(dir)
        Return Path.Combine(dir, "run-auto-sync.cmd")
    End Function

    Public Shared Sub WriteLauncher(exePath As String)
        Dim cmd = "@echo off" & Environment.NewLine &
                  "cd /d """ & Path.GetDirectoryName(exePath) & """" & Environment.NewLine &
                  """" & exePath & """ --auto-sync" & Environment.NewLine
        File.WriteAllText(LauncherPath(), cmd, Encoding.GetEncoding(1256))
    End Sub

    Public Shared Function Register(exePath As String, times As IList(Of TimeSpan)) As String
        If String.IsNullOrWhiteSpace(exePath) OrElse Not File.Exists(exePath) Then
            Return "فایل برنامه پیدا نشد: " & exePath
        End If
        WriteLauncher(exePath)
        Unregister()
        Dim t1 = If(times Is Nothing OrElse times.Count = 0, New TimeSpan(9, 0, 0), times(0))
        Dim t2 = If(times Is Nothing OrElse times.Count < 2, New TimeSpan(17, 0, 0), times(1))
        Dim err1 = CreateTask(TaskName1, t1)
        If err1 IsNot Nothing Then Return err1
        If t1 <> t2 Then
            Dim err2 = CreateTask(TaskName2, t2)
            If err2 IsNot Nothing Then Return err2
        End If
        Return Nothing
    End Function

    Public Shared Sub Unregister()
        DeleteTask(TaskName1)
        DeleteTask(TaskName2)
    End Sub

    Private Shared Function CreateTask(name As String, at As TimeSpan) As String
        Dim st = at.Hours.ToString("00") & ":" & at.Minutes.ToString("00")
        Dim args = "/Create /TN """ & name & """ /TR """ & LauncherPath() & """ /SC DAILY /ST " & st & " /F /RL LIMITED"
        Dim output As String = Nothing
        Dim code = RunSchtasks(args, output)
        If code <> 0 Then Return "ثبت وظیفه «" & name & "» ناموفق بود: " & If(output, code.ToString())
        Return Nothing
    End Function

    Private Shared Sub DeleteTask(name As String)
        Dim output As String = Nothing
        RunSchtasks("/Delete /TN """ & name & """ /F", output)
    End Sub

    Private Shared Function RunSchtasks(arguments As String, ByRef output As String) As Integer
        Try
            Dim psi As New ProcessStartInfo() With {
                .FileName = "schtasks.exe",
                .Arguments = arguments,
                .UseShellExecute = False,
                .RedirectStandardOutput = True,
                .RedirectStandardError = True,
                .CreateNoWindow = True
            }
            Using p = Process.Start(psi)
                output = (p.StandardOutput.ReadToEnd() & " " & p.StandardError.ReadToEnd()).Trim()
                p.WaitForExit(20000)
                Return p.ExitCode
            End Using
        Catch ex As Exception
            output = ex.Message
            Return 1
        End Try
    End Function
End Class
