Imports System.Data.SqlClient
Imports System.Threading

Friend Class HolooSqlService
    ' جداول کلیدی هلو برای تشخیص دیتابیس
    Private Shared ReadOnly KeyTables As String() = {
        "CUSTOMER", "ARTICLE", "FACTURE", "FACTART", "SARFASL", "SANAD", "TYPE_ANB", "NEWBANK", "Cash"
    }

    ' برچسب فارسی برای نمایش خلاصه
    Private Shared ReadOnly CountLabels As Dictionary(Of String, String) =
        New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
            {"CUSTOMER", "اشخاص / مشتریان (CUSTOMER)"},
            {"ARTICLE", "کالا و خدمات (ARTICLE)"},
            {"FACTURE", "فاکتورها (FACTURE)"},
            {"FACTART", "ردیف فاکتور (FACTART)"},
            {"SANAD", "اسناد حسابداری (SANAD)"},
            {"SARFASL", "سرفصل‌ها (SARFASL)"},
            {"NEWBANK", "بانک‌ها (NEWBANK)"},
            {"Cash", "صندوق‌ها (Cash)"},
            {"Check", "چک‌ها (Check)"},
            {"TYPE_ANB", "انبارها (TYPE_ANB)"},
            {"UNIT", "واحدها (UNIT)"}
        }

    Public Async Function TestConnectionAsync(settings As SqlConnectionSettings, Optional ct As CancellationToken = Nothing) As Task(Of String)
        Return Await Task.Run(
            Function()
                ct.ThrowIfCancellationRequested()
                Using conn = OpenConnection(settings, "master")
                    Using cmd As New SqlCommand("SELECT @@VERSION;", conn)
                        cmd.CommandTimeout = settings.ConnectionTimeoutSeconds
                        Dim version = Convert.ToString(cmd.ExecuteScalar())
                        If String.IsNullOrWhiteSpace(version) Then Return "اتصال موفق بود."
                        Dim firstLine = version.Split({ControlChars.Cr, ControlChars.Lf}, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
                        Return "اتصال موفق — " & If(firstLine, version)
                    End Using
                End Using
            End Function, ct).ConfigureAwait(False)
    End Function

    Public Async Function ListDatabasesAsync(settings As SqlConnectionSettings, Optional ct As CancellationToken = Nothing) As Task(Of List(Of HolooDatabaseInfo))
        Return Await Task.Run(
            Function()
                ct.ThrowIfCancellationRequested()
                Dim list As New List(Of HolooDatabaseInfo)
                Using conn = OpenConnection(settings, "master")
                    Dim sql =
                        "SELECT d.name " &
                        "FROM sys.databases d " &
                        "WHERE d.database_id > 4 AND d.state = 0 " &
                        "ORDER BY d.name;"
                    Using cmd As New SqlCommand(sql, conn)
                        cmd.CommandTimeout = settings.ConnectionTimeoutSeconds
                        Using reader = cmd.ExecuteReader()
                            While reader.Read()
                                ct.ThrowIfCancellationRequested()
                                list.Add(New HolooDatabaseInfo With {
                                    .Name = reader.GetString(0),
                                    .LooksLikeHoloo = False,
                                    .HolooScore = 0
                                })
                            End While
                        End Using
                    End Using

                    For Each db In list
                        ct.ThrowIfCancellationRequested()
                        Try
                            Dim score = ScoreHolooDatabase(conn, db.Name, settings.ConnectionTimeoutSeconds)
                            db.HolooScore = score
                            db.LooksLikeHoloo = score >= 4
                            If db.LooksLikeHoloo Then
                                db.Summary = "ساختار هلو تشخیص داده شد"
                            End If
                        Catch
                            db.HolooScore = 0
                            db.LooksLikeHoloo = False
                        End Try
                    Next
                End Using

                Return list.OrderByDescending(Function(x) x.LooksLikeHoloo).
                    ThenByDescending(Function(x) x.HolooScore).
                    ThenBy(Function(x) x.Name).
                    ToList()
            End Function, ct).ConfigureAwait(False)
    End Function

    Public Async Function ProbeDatabaseAsync(settings As SqlConnectionSettings, databaseName As String, Optional ct As CancellationToken = Nothing) As Task(Of HolooProbeResult)
        Return Await Task.Run(
            Function()
                ct.ThrowIfCancellationRequested()
                If String.IsNullOrWhiteSpace(databaseName) Then
                    Throw New ArgumentException("نام دیتابیس خالی است.")
                End If

                Dim result As New HolooProbeResult With {.DatabaseName = databaseName}
                Using conn = OpenConnection(settings, databaseName)
                    Using cmdVer As New SqlCommand("SELECT @@VERSION;", conn)
                        cmdVer.CommandTimeout = settings.ConnectionTimeoutSeconds
                        Dim version = Convert.ToString(cmdVer.ExecuteScalar())
                        If Not String.IsNullOrWhiteSpace(version) Then
                            result.ServerVersion = version.Split({ControlChars.Cr, ControlChars.Lf}, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
                        End If
                    End Using

                    Using cmdCount As New SqlCommand("SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE';", conn)
                        cmdCount.CommandTimeout = settings.ConnectionTimeoutSeconds
                        result.TableCount = Convert.ToInt32(cmdCount.ExecuteScalar())
                    End Using

                    Dim existing = GetExistingTables(conn, settings.ConnectionTimeoutSeconds)
                    Dim foundKeys = 0
                    For Each keyTable In KeyTables
                        If existing.Contains(keyTable) Then
                            foundKeys += 1
                        Else
                            result.MissingKeyTables.Add(keyTable)
                        End If
                    Next
                    result.LooksLikeHoloo = foundKeys >= 4

                    For Each labelPair In CountLabels
                        Dim tableName = labelPair.Key
                        If Not existing.Contains(tableName) Then Continue For
                        ct.ThrowIfCancellationRequested()
                        Try
                            Dim count = GetTableRowCount(conn, tableName, settings.ConnectionTimeoutSeconds)
                            result.Counts(labelPair.Value) = count
                        Catch ex As Exception
                            result.Notes.Add("خطا در شمارش " & tableName & ": " & ex.Message)
                        End Try
                    Next

                    ' نام شرکت در صورت وجود
                    If existing.Contains("CompName") Then
                        Try
                            Using cmd As New SqlCommand("SELECT TOP 1 * FROM CompName;", conn)
                                cmd.CommandTimeout = settings.ConnectionTimeoutSeconds
                                Using reader = cmd.ExecuteReader()
                                    If reader.Read() Then
                                        For i = 0 To reader.FieldCount - 1
                                            Dim col = reader.GetName(i)
                                            If col.IndexOf("name", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
                                               col.IndexOf("co", StringComparison.OrdinalIgnoreCase) >= 0 Then
                                                If Not reader.IsDBNull(i) Then
                                                    Dim val = Convert.ToString(reader.GetValue(i))
                                                    If Not String.IsNullOrWhiteSpace(val) Then
                                                        result.Notes.Add("اطلاعات شرکت (CompName." & col & "): " & val)
                                                        Exit For
                                                    End If
                                                End If
                                            End If
                                        Next
                                    End If
                                End Using
                            End Using
                        Catch
                        End Try
                    End If
                End Using
                Return result
            End Function, ct).ConfigureAwait(False)
    End Function

    Private Shared Function OpenConnection(settings As SqlConnectionSettings, databaseName As String) As SqlConnection
        Dim cs = settings.BuildConnectionString(databaseName)
        Dim conn As New SqlConnection(cs)
        Try
            conn.Open()
            Return conn
        Catch ex As SqlException
            conn.Dispose()
            Throw New InvalidOperationException(TranslateSqlError(ex), ex)
        Catch ex As Exception
            conn.Dispose()
            Throw New InvalidOperationException("اتصال به SQL Server برقرار نشد: " & ex.Message, ex)
        End Try
    End Function

    Private Shared Function TranslateSqlError(ex As SqlException) As String
        If ex.Number = 18456 Then Return "نام کاربری یا رمز عبور SQL Server نادرست است."
        If ex.Number = 4060 Then Return "دسترسی به دیتابیس امکان‌پذیر نیست."
        If ex.Number = 53 OrElse ex.Number = -1 Then Return "سرور SQL در دسترس نیست. نام سرور/Instance را بررسی کنید."
        If ex.Message.IndexOf("certificate", StringComparison.OrdinalIgnoreCase) >= 0 Then
            Return "خطای گواهی SSL. گزینه TrustServerCertificate را فعال کنید."
        End If
        Return "خطای SQL Server: " & ex.Message
    End Function

    Private Shared Function ScoreHolooDatabase(conn As SqlConnection, databaseName As String, timeout As Integer) As Integer
        Dim score = 0
        Dim sql =
            "SELECT COUNT(*) FROM [" & databaseName.Replace("]", "]]") & "].INFORMATION_SCHEMA.TABLES " &
            "WHERE TABLE_TYPE='BASE TABLE' AND TABLE_NAME IN ('CUSTOMER','ARTICLE','FACTURE','FACTART','SARFASL','SANAD','TYPE_ANB','NEWBANK');"
        Using cmd As New SqlCommand(sql, conn)
            cmd.CommandTimeout = timeout
            score = Convert.ToInt32(cmd.ExecuteScalar())
        End Using
        Return score
    End Function

    Private Shared Function GetExistingTables(conn As SqlConnection, timeout As Integer) As HashSet(Of String)
        Dim set_ As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
        Using cmd As New SqlCommand("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE';", conn)
            cmd.CommandTimeout = timeout
            Using reader = cmd.ExecuteReader()
                While reader.Read()
                    set_.Add(reader.GetString(0))
                End While
            End Using
        End Using
        Return set_
    End Function

    Private Shared Function GetTableRowCount(conn As SqlConnection, tableName As String, timeout As Integer) As Long
        ' نام جدول از لیست ثابت ما می‌آید؛ با براکت ایمن می‌شود
        Dim safe = "[" & tableName.Replace("]", "]]") & "]"
        Using cmd As New SqlCommand("SELECT COUNT_BIG(*) FROM " & safe & ";", conn)
            cmd.CommandTimeout = timeout
            Return Convert.ToInt64(cmd.ExecuteScalar())
        End Using
    End Function
End Class
