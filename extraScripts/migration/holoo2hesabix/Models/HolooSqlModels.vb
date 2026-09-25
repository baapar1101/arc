Friend Class SqlConnectionSettings
    Public Property Server As String = "localhost"
    Public Property UseWindowsAuth As Boolean = False
    Public Property UserName As String = "sa"
    Public Property Password As String = ""
    Public Property Database As String = ""
    Public Property TrustServerCertificate As Boolean = True
    Public Property ConnectionTimeoutSeconds As Integer = 15

    Public Function BuildConnectionString(Optional databaseOverride As String = Nothing) As String
        Dim db = If(databaseOverride, Database)
        If String.IsNullOrWhiteSpace(db) Then db = "master"

        Dim builder As New SqlClient.SqlConnectionStringBuilder()
        builder.DataSource = Server.Trim()
        builder.InitialCatalog = db.Trim()
        builder.ConnectTimeout = ConnectionTimeoutSeconds
        builder.ApplicationName = "Holoo2Hesabix"

        If UseWindowsAuth Then
            builder.IntegratedSecurity = True
        Else
            builder.IntegratedSecurity = False
            builder.UserID = If(UserName, "").Trim()
            builder.Password = If(Password, "")
        End If

        Dim cs = builder.ConnectionString
        ' سازگار با .NET Framework 4.6.1 و SQL Serverهای جدید
        If TrustServerCertificate Then
            If cs.IndexOf("TrustServerCertificate", StringComparison.OrdinalIgnoreCase) < 0 Then
                cs &= ";TrustServerCertificate=True"
            End If
            If cs.IndexOf("Encrypt=", StringComparison.OrdinalIgnoreCase) < 0 Then
                cs &= ";Encrypt=False"
            End If
        End If
        Return cs
    End Function
End Class

Friend Class HolooDatabaseInfo
    Public Property Name As String
    Public Property LooksLikeHoloo As Boolean
    Public Property HolooScore As Integer
    Public Property Summary As String

    Public Overrides Function ToString() As String
        If LooksLikeHoloo Then
            Return Name & "  ★ هلو"
        End If
        Return Name
    End Function
End Class

Friend Class HolooProbeResult
    Public Property DatabaseName As String
    Public Property LooksLikeHoloo As Boolean
    Public Property ServerVersion As String
    Public Property TableCount As Integer
    Public Property Counts As New Dictionary(Of String, Long)
    Public Property MissingKeyTables As New List(Of String)
    Public Property Notes As New List(Of String)

    Public ReadOnly Property SummaryText As String
        Get
            Dim lines As New List(Of String)
            lines.Add("دیتابیس: " & DatabaseName)
            If Not String.IsNullOrWhiteSpace(ServerVersion) Then
                lines.Add("نسخه SQL Server: " & ServerVersion)
            End If
            lines.Add("تعداد جداول: " & TableCount.ToString())
            If LooksLikeHoloo Then
                lines.Add("تشخیص: ساختار شبیه برنامه هلو است.")
            Else
                lines.Add("تشخیص: ساختار هلو به‌طور کامل پیدا نشد.")
            End If
            If Counts.Count > 0 Then
                lines.Add("")
                lines.Add("خلاصه رکوردها:")
                For Each kv In Counts.OrderBy(Function(x) x.Key)
                    lines.Add("  • " & kv.Key & ": " & kv.Value.ToString("N0"))
                Next
            End If
            If MissingKeyTables.Count > 0 Then
                lines.Add("")
                lines.Add("جداول کلیدی یافت‌نشده: " & String.Join(", ", MissingKeyTables))
            End If
            For Each n In Notes
                lines.Add(n)
            Next
            Return String.Join(Environment.NewLine, lines)
        End Get
    End Property
End Class
