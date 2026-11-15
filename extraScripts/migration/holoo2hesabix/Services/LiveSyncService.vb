Imports System.IO
Imports System.Threading

Friend Class LiveSyncResult
    Public Property Ok As Boolean
    Public Property Message As String
    Public Property CheckpointPath As String
End Class

''' <summary>
''' یک پاس همگام‌سازی زنده: اطلاعات پایه جدید + ایجاد/ویرایش/حذف اسناد.
''' </summary>
Friend Class LiveSyncService
    Private ReadOnly _baseTransfer As New BaseDataTransferService()
    Private ReadOnly _docTransfer As New DocumentTransferService()

    Public Event ProgressChanged As EventHandler(Of TransferProgressEventArgs)

    Public Sub New()
        AddHandler _baseTransfer.ProgressChanged, Sub(s, e) RaiseEvent ProgressChanged(Me, e)
        AddHandler _docTransfer.ProgressChanged, Sub(s, e) RaiseEvent ProgressChanged(Me, e)
    End Sub

    Public Async Function RunAsync(
        session As MigrationSession,
        api As HesabixApiClient,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of LiveSyncResult)
        Dim result As New LiveSyncResult()
        If session Is Nothing OrElse session.SelectedBusiness Is Nothing Then
            result.Message = "کسب‌وکار مقصد مشخص نیست."
            Return result
        End If
        If Not session.CanProceedFromHolooSql Then
            result.Message = "اتصال SQL هلو کامل نیست."
            Return result
        End If

        Using mutex As New Mutex(False, "Holoo2Hesabix-LiveSync")
            Dim owned = False
            Try
                owned = mutex.WaitOne(0)
                If Not owned Then
                    result.Ok = True
                    result.Message = "همگام‌سازی دیگری در حال اجراست — این نوبت رد شد."
                    Return result
                End If

                Dim modules = If(session.SelectedModules, MigrationModuleInfo.GetAllModules()).
                    Where(Function(x) x.Selected AndAlso x.Enabled).
                    Select(Function(x) x.ModuleKey).ToList()
                If modules.Count = 0 Then
                    result.Message = "هیچ بخشی برای همگام‌سازی انتخاب نشده است."
                    Return result
                End If

                Dim hasDocs = modules.Any(Function(m) MigrationModuleInfo.IsDocumentModule(m))
                If hasDocs AndAlso Not session.SarfaslProfileLocked Then
                    result.Message = "پروفایل نگاشت سرفصل قفل نیست؛ همگام‌سازی اسناد متوقف شد."
                    Return result
                End If
                If hasDocs AndAlso session.SarfaslProfile IsNot Nothing AndAlso session.SarfaslProfile.CriticalUnmappedCount > 0 Then
                    result.Message = "سرفصل بحرانی بدون نگاشت باقی است."
                    Return result
                End If

                RaiseProgress("بازبینی", 0, 0, "کشف سال‌های مالی و ارز...")
                Dim preflight = Await New PreflightService().BuildReportAsync(session, api, ct).ConfigureAwait(False)
                session.Preflight = preflight
                session.AllowCurrencyMismatch = True
                Dim currencyId = preflight.HesabixCurrencyId
                If currencyId <= 0 Then
                    result.Message = "شناسه ارز کسب‌وکار مشخص نیست."
                    Return result
                End If
                If hasDocs AndAlso (preflight.FiscalYears Is Nothing OrElse preflight.FiscalYears.Count = 0) Then
                    result.Message = "سال مالی در هلو پیدا نشد."
                    Return result
                End If

                Dim path = Await _baseTransfer.RunAsync(
                    session, api, modules, currencyId,
                    resetCheckpoint:=False,
                    skipOpeningBalances:=hasDocs,
                    ct:=ct,
                    ignoreCompleted:=True).ConfigureAwait(False)

                If hasDocs Then
                    path = Await _docTransfer.RunAsync(
                        session, api, modules, currencyId,
                        resetCheckpoint:=False,
                        ct:=ct,
                        applyMutations:=True).ConfigureAwait(False)
                End If

                result.Ok = True
                result.CheckpointPath = path
                result.Message = "همگام‌سازی تمام شد."
                Return result
            Finally
                If owned Then
                    Try
                        mutex.ReleaseMutex()
                    Catch
                    End Try
                End If
            End Try
        End Using
    End Function

    Private Sub RaiseProgress(title As String, current As Integer, total As Integer, message As String)
        RaiseEvent ProgressChanged(Me, New TransferProgressEventArgs With {
            .ModuleTitle = title,
            .Current = current,
            .Total = total,
            .Message = message
        })
    End Sub
End Class

Friend NotInheritable Class AutoSyncRunner
    Private Sub New()
    End Sub

    Public Shared Function Run(Optional args As String() = Nothing) As Integer
        Dim logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix", "logs")
        Directory.CreateDirectory(logDir)
        Dim logPath = Path.Combine(logDir, "sync-" & DateTime.Now.ToString("yyyyMMdd") & ".log")
        Dim log As Action(Of String) =
            Sub(msg)
                Dim line = DateTime.Now.ToString("s") & " " & msg
                Try
                    File.AppendAllText(logPath, line & Environment.NewLine, System.Text.Encoding.UTF8)
                Catch
                End Try
            End Sub

        Dim store As New SyncProfileStore()
        Dim profile = store.Load()
        If profile Is Nothing Then
            log("ERROR: sync profile missing")
            Return 2
        End If

        Dim session As New MigrationSession()
        Dim restoreErr = store.TryRestoreSession(profile, session)
        If restoreErr IsNot Nothing Then
            log("ERROR: " & restoreErr)
            SaveLast(store, profile, False, restoreErr)
            Return 2
        End If

        log("start business=" & session.SelectedBusiness.Id.ToString() & " db=" & session.SelectedDatabase)
        Dim api As New HesabixApiClient()
        Try
            Dim result = New LiveSyncService().RunAsync(session, api).GetAwaiter().GetResult()
            log(If(result.Ok, "OK ", "FAIL ") & result.Message)
            SaveLast(store, profile, result.Ok, result.Message)
            Return If(result.Ok, 0, 1)
        Catch ex As Exception
            log("FATAL: " & ex.ToString())
            SaveLast(store, profile, False, ex.Message)
            Return 1
        Finally
            api.Dispose()
        End Try
    End Function

    Private Shared Sub SaveLast(store As SyncProfileStore, profile As SyncProfile, ok As Boolean, message As String)
        profile.LastSyncAt = DateTime.Now.ToString("s")
        profile.LastSyncOk = ok
        profile.LastSyncMessage = message
        store.Save(profile)
    End Sub
End Class
