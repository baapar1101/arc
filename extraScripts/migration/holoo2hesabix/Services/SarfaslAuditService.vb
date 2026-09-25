Imports System.Data.SqlClient
Imports System.Text

''' <summary>
''' پیش‌نمایش پوشش نگاشت سرفصل برای preflight — بدون ساخت حساب.
''' </summary>
Friend Class SarfaslAuditService
    Public Class SarfaslDecisionRow
        Public Property Col As String
        Public Property Moien As String
        Public Property Name As String
        Public Property LineCount As Long
        Public Property Decision As String ' Fixed / BusinessExpense / BusinessLoan / Person / Bank / Cash / Skip / Unmapped
        Public Property TargetCode As String
    End Class

    Public Function Audit(settings As SqlConnectionSettings) As List(Of SarfaslDecisionRow)
        Dim list As New List(Of SarfaslDecisionRow)
        Using conn As New SqlConnection(settings.BuildConnectionString(settings.Database))
            conn.Open()
            Using cmd As New SqlCommand(
                "SELECT LTRIM(RTRIM(l.Col_Code)), ISNULL(l.Moien_Code,''), MAX(ISNULL(s.Sarfasl_Name,'')), COUNT(*) " &
                "FROM SND_LIST l " &
                "INNER JOIN SANAD sn ON sn.Sanad_Code=l.Sanad_Code AND ISNULL(sn.[Delete],0)=0 " &
                "LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') " &
                "WHERE ISNULL(l.Bed,0)>0 OR ISNULL(l.Bes,0)>0 " &
                "GROUP BY LTRIM(RTRIM(l.Col_Code)), ISNULL(l.Moien_Code,'') " &
                "ORDER BY LTRIM(RTRIM(l.Col_Code)), ISNULL(l.Moien_Code,'');", conn)
                cmd.CommandTimeout = 180
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim col = Convert.ToString(r.GetValue(0)).Trim()
                        Dim moien = Convert.ToString(r.GetValue(1)).Trim()
                        Dim name = Convert.ToString(r.GetValue(2)).Trim()
                        Dim cnt = Convert.ToInt64(r.GetValue(3))
                        list.Add(Decide(col, moien, name, cnt))
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Shared Function Decide(col As String, moien As String, name As String, lineCount As Long) As SarfaslDecisionRow
        Dim row As New SarfaslDecisionRow With {
            .Col = col,
            .Moien = moien,
            .Name = name,
            .LineCount = lineCount
        }
        Select Case col
            Case "005", "006", "105", "620"
                row.Decision = "Skip"
                row.TargetCode = ""
            Case "101"
                row.Decision = If(moien = "0002" OrElse name.Contains("تنخواه"), "Petty", "Cash")
                row.TargetCode = If(row.Decision = "Petty", "10201", "10202")
            Case "102"
                row.Decision = "Bank"
                row.TargetCode = "10203"
            Case "103"
                row.Decision = "Person"
                row.TargetCode = "10401/20201"
            Case "401"
                If HolooSarfaslMapper.LooksLikeLoan(name) Then
                    row.Decision = "BusinessLoan"
                    row.TargetCode = HolooSarfaslMapper.SuggestBusinessLoanCode(moien)
                Else
                    row.Decision = "Person"
                    row.TargetCode = "20201"
                End If
            Case "601"
                Dim code = HolooSarfaslMapper.MapExpenseToFixedCode(name, moien)
                If String.IsNullOrWhiteSpace(code) Then
                    row.Decision = "BusinessExpense"
                    row.TargetCode = HolooSarfaslMapper.SuggestBusinessExpenseCode(moien)
                Else
                    row.Decision = "Fixed"
                    row.TargetCode = code
                End If
            Case "702"
                Dim inc = HolooSarfaslMapper.MapIncomeToFixedCode(name, moien)
                If String.IsNullOrWhiteSpace(inc) Then
                    row.Decision = "BusinessIncome"
                    row.TargetCode = HolooSarfaslMapper.SuggestBusinessIncomeCode(moien)
                Else
                    row.Decision = "Fixed"
                    row.TargetCode = inc
                End If
            Case Else
                Dim code = HolooSarfaslMapper.MapColToFixedCode(col, moien, name)
                If String.IsNullOrWhiteSpace(code) Then
                    row.Decision = "Unmapped"
                    row.TargetCode = ""
                Else
                    row.Decision = "Fixed"
                    row.TargetCode = code
                End If
        End Select
        Return row
    End Function

    Public Shared Function FormatReport(rows As List(Of SarfaslDecisionRow)) As String
        Dim sb As New StringBuilder()
        Dim unmapped = rows.Where(Function(x) x.Decision = "Unmapped").ToList()
        Dim biz = rows.Where(Function(x) x.Decision = "BusinessExpense" OrElse x.Decision = "BusinessLoan" OrElse x.Decision = "BusinessIncome").ToList()
        sb.AppendLine("پوشش نگاشت سرفصل: " & rows.Count.ToString("N0") & " ترکیب Col/Moien دارای مبلغ")
        sb.AppendLine("  حساب اختصاصی (ساخته می‌شود در انتقال): " & biz.Count.ToString("N0"))
        sb.AppendLine("  بدون نگاشت: " & unmapped.Count.ToString("N0"))
        If unmapped.Count > 0 Then
            For Each u In unmapped.Take(15)
                sb.AppendLine("    • " & u.Col & "|" & u.Moien & " «" & u.Name & "» خطوط=" & u.LineCount.ToString("N0"))
            Next
            If unmapped.Count > 15 Then sb.AppendLine("    … و " & (unmapped.Count - 15).ToString() & " مورد دیگر")
        End If
        For Each b In biz.Take(10)
            sb.AppendLine("  + " & b.Decision & " " & b.Col & "|" & b.Moien & " → " & b.TargetCode & " «" & b.Name & "»")
        Next
        Return sb.ToString()
    End Function
End Class
