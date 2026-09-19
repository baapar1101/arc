Imports System.Data.SqlClient

''' <summary>
''' کشف عمومی ساختار هر دیتابیس هلو: ارز، سال مالی، شمارش‌ها.
''' </summary>
Friend Class HolooDiscoveryService
    Public Function DiscoverCurrencyMode(settings As SqlConnectionSettings) As CurrencyModeInfo
        Dim info As New CurrencyModeInfo With {
            .Mode = "MonoCurrency",
            .BaseMoneyCode = 1,
            .BaseMoneyName = "",
            .DefinedCount = 0
        }
        Using conn = Open(settings)
            Using cmd As New SqlCommand("SELECT M_Code, Money_Name, Money_Price, BaseArz FROM MONEY ORDER BY M_Code;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        info.DefinedCount += 1
                        Dim code = Convert.ToInt32(r.GetValue(0))
                        Dim name = Convert.ToString(r.GetValue(1)).Trim()
                        Dim isBase = False
                        If Not r.IsDBNull(3) Then
                            Dim v = r.GetValue(3)
                            If TypeOf v Is Boolean Then
                                isBase = CBool(v)
                            Else
                                isBase = Convert.ToInt32(v) <> 0
                            End If
                        End If
                        If isBase OrElse info.BaseMoneyName = "" Then
                            info.BaseMoneyCode = code
                            info.BaseMoneyName = name
                        End If
                    End While
                End Using
            End Using

            info.InvoiceForeignUsage = ScalarLong(conn,
                "SELECT COUNT(*) FROM FACTART WHERE ISNULL(Money_Code,0) NOT IN (0," & info.BaseMoneyCode.ToString() & ");")
            info.SanadForeignUsage = ScalarLong(conn,
                "SELECT COUNT(*) FROM SND_LIST WHERE ISNULL(Bed_Arz,0)<>0 OR ISNULL(Bes_Arz,0)<>0;")
            If TableExists(conn, "AcoundCashArz") Then
                info.CashArzUsage = ScalarLong(conn, "SELECT COUNT(*) FROM AcoundCashArz;")
            End If
        End Using

        If info.InvoiceForeignUsage > 0 OrElse info.SanadForeignUsage > 0 OrElse info.CashArzUsage > 0 Then
            info.Mode = "MultiCurrency"
        Else
            info.Mode = "MonoCurrency"
        End If
        Return info
    End Function

    Public Function DiscoverFiscalYears(settings As SqlConnectionSettings) As List(Of DetectedFiscalYear)
        Dim minD As Date? = Nothing
        Dim maxD As Date? = Nothing
        Using conn = Open(settings)
            Using cmd As New SqlCommand(
                "SELECT MIN(d), MAX(d) FROM (" &
                " SELECT Sanad_Date AS d FROM SANAD WHERE ISNULL([Delete],0)=0 AND Sanad_Date IS NOT NULL" &
                " UNION ALL" &
                " SELECT Fac_Date AS d FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Date IS NOT NULL" &
                ") x;", conn)
                Using r = cmd.ExecuteReader()
                    If r.Read() AndAlso Not r.IsDBNull(0) AndAlso Not r.IsDBNull(1) Then
                        minD = Convert.ToDateTime(r.GetValue(0)).Date
                        maxD = Convert.ToDateTime(r.GetValue(1)).Date
                    End If
                End Using
            End Using
        End Using

        Dim list As New List(Of DetectedFiscalYear)
        If Not minD.HasValue OrElse Not maxD.HasValue Then Return list

        Dim starts = BuildIranianFiscalStarts(minD.Value.AddYears(-1), maxD.Value.AddYears(1))
        For i = 0 To starts.Count - 2
            Dim s = starts(i)
            Dim e = starts(i + 1).AddDays(-1)
            If e < minD.Value OrElse s > maxD.Value Then Continue For
            Dim docs = CountInRange(settings, s, e)
            If docs.Item1 <= 0 AndAlso docs.Item2 <= 0 Then Continue For
            Dim title = "سال مالی " & GuessShamsiYear(s).ToString()
            list.Add(New DetectedFiscalYear With {
                .Title = title,
                .StartDate = s,
                .EndDate = e,
                .DocumentCount = docs.Item1,
                .InvoiceCount = docs.Item2
            })
        Next
        Return list
    End Function

    Public Function CountInvoicesByType(settings As SqlConnectionSettings) As Dictionary(Of String, Long)
        Dim map As New Dictionary(Of String, Long)(StringComparer.OrdinalIgnoreCase)
        Using conn = Open(settings)
            Using cmd As New SqlCommand(
                "SELECT Fac_Type, COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0 GROUP BY Fac_Type;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        map(Convert.ToString(r.GetValue(0)).Trim()) = Convert.ToInt64(r.GetValue(1))
                    End While
                End Using
            End Using
        End Using
        Return map
    End Function

    Private Function CountInRange(settings As SqlConnectionSettings, startDate As Date, endDate As Date) As Tuple(Of Long, Long)
        Using conn = Open(settings)
            Dim sanad = ScalarLong(conn,
                "SELECT COUNT(*) FROM SANAD WHERE ISNULL([Delete],0)=0 AND Sanad_Date>=@s AND Sanad_Date<@eExclusive;",
                New SqlParameter("@s", startDate),
                New SqlParameter("@eExclusive", endDate.AddDays(1)))
            Dim fac = ScalarLong(conn,
                "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Date>=@s AND Fac_Date<@eExclusive;",
                New SqlParameter("@s", startDate),
                New SqlParameter("@eExclusive", endDate.AddDays(1)))
            Return Tuple.Create(sanad, fac)
        End Using
    End Function

    Private Shared Function BuildIranianFiscalStarts(fromDate As Date, toDate As Date) As List(Of Date)
        Dim list As New List(Of Date)
        ' شروع تقریبی سال شمسی ≈ ۲۱ مارس؛ برای کبیسه ۲۰/۲۱ را پوشش می‌دهیم با ۲۱ مارس ثابت
        Dim y = fromDate.Year - 1
        Dim endY = toDate.Year + 2
        While y <= endY
            list.Add(New Date(y, 3, 21))
            y += 1
        End While
        Return list
    End Function

    Private Shared Function GuessShamsiYear(gregorianStart As Date) As Integer
        ' تقریبی: سال شمسی ≈ میلادی - 621 وقتی شروع فروردین است
        Return gregorianStart.Year - 621
    End Function

    Private Shared Function Open(settings As SqlConnectionSettings) As SqlConnection
        Dim conn As New SqlConnection(settings.BuildConnectionString(settings.Database))
        conn.Open()
        Return conn
    End Function

    Private Shared Function TableExists(conn As SqlConnection, tableName As String) As Boolean
        Using cmd As New SqlCommand(
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' AND TABLE_NAME=@t;", conn)
            cmd.Parameters.AddWithValue("@t", tableName)
            Return Convert.ToInt32(cmd.ExecuteScalar()) > 0
        End Using
    End Function

    Private Shared Function ScalarLong(conn As SqlConnection, sql As String, ParamArray pars As SqlParameter()) As Long
        Using cmd As New SqlCommand(sql, conn)
            cmd.CommandTimeout = 180
            If pars IsNot Nothing Then
                For Each p In pars
                    cmd.Parameters.Add(p)
                Next
            End If
            Return Convert.ToInt64(cmd.ExecuteScalar())
        End Using
    End Function
End Class
