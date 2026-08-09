Imports System.Data.SqlClient
Imports System.Text.RegularExpressions

''' <summary>
''' نگاشت سرفصل هلو (Col/Moien/Tafzili) به موجودیت‌های حسابیکس و کد حساب ثابت.
''' </summary>
Friend Class HolooSarfaslMapper
    Private ReadOnly _bankBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _cashBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _pettyBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _personByMoien As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _expenseNameByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _incomeNameByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _bankByAccountNumber As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)

    Public Sub Build(
        settings As SqlConnectionSettings,
        bankMap As ModuleCheckpoint,
        cashMap As ModuleCheckpoint,
        pettyMap As ModuleCheckpoint,
        personMap As ModuleCheckpoint
    )
        _bankBySarKey.Clear()
        _cashBySarKey.Clear()
        _pettyBySarKey.Clear()
        _personByMoien.Clear()
        _expenseNameByMoien.Clear()
        _incomeNameByMoien.Clear()
        _bankByAccountNumber.Clear()

        Using conn = Open(settings)
            ' بانک: Account_N → HesabixId
            Dim banks As New List(Of Tuple(Of Integer, String, String))
            Using cmd As New SqlCommand(
                "SELECT Id, ISNULL(Account_N,''), ISNULL(NULLIF(MyNameAcound,''), ISNULL(TaitleBank,'')) FROM ACOUND_N;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim holooId = Convert.ToInt32(r.GetValue(0))
                        Dim accNo = Convert.ToString(r.GetValue(1)).Trim()
                        Dim title = Convert.ToString(r.GetValue(2)).Trim()
                        Dim hesabixId As Integer = 0
                        If bankMap.Done.TryGetValue(holooId.ToString(), hesabixId) AndAlso hesabixId > 0 Then
                            banks.Add(Tuple.Create(hesabixId, accNo, title))
                            If accNo.Length > 0 AndAlso Not _bankByAccountNumber.ContainsKey(accNo) Then
                                _bankByAccountNumber(accNo) = hesabixId
                            End If
                        End If
                    End While
                End Using
            End Using

            Using cmd As New SqlCommand(
                "SELECT Col_Code, ISNULL(Moien_Code,''), ISNULL(Tafzili_Code,''), ISNULL(Sarfasl_Name,'') " &
                "FROM SARFASL WHERE ISNULL([Delete],0)=0 AND Col_Code IN ('101','102','601','702');", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim col = Convert.ToString(r.GetValue(0)).Trim()
                        Dim moien = Convert.ToString(r.GetValue(1)).Trim()
                        Dim taf = Convert.ToString(r.GetValue(2)).Trim()
                        Dim name = Convert.ToString(r.GetValue(3)).Trim()
                        Dim key = MakeKey(col, moien, taf)

                        If col = "102" Then
                            Dim matched = MatchBank(banks, name)
                            If matched > 0 Then _bankBySarKey(key) = matched
                        ElseIf col = "101" Then
                            ' 0001 صندوق، 0002 تنخواه
                            If moien = "0002" OrElse name.Contains("تنخواه") Then
                                Dim pid = pettyMap.Done.Values.FirstOrDefault()
                                If pid > 0 Then _pettyBySarKey(key) = pid
                            Else
                                Dim cid = cashMap.Done.Values.FirstOrDefault()
                                If cid > 0 Then _cashBySarKey(key) = cid
                            End If
                        ElseIf col = "601" AndAlso moien.Length > 0 Then
                            _expenseNameByMoien(moien) = name
                        ElseIf col = "702" AndAlso moien.Length > 0 Then
                            _incomeNameByMoien(moien) = name
                        End If
                    End While
                End Using
            End Using

            ' اشخاص: SarBed مثل 1030001 و SarBes مثل 4010002
            Using cmd As New SqlCommand(
                "SELECT CustCode, ISNULL(SarBed,''), ISNULL(SarBes,'') FROM CustomerSarfasl;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim cust = Convert.ToString(r.GetValue(0)).Trim()
                        Dim sarBed = Convert.ToString(r.GetValue(1)).Trim()
                        Dim sarBes = Convert.ToString(r.GetValue(2)).Trim()
                        Dim personId As Integer = 0
                        If Not personMap.Done.TryGetValue(cust, personId) OrElse personId <= 0 Then Continue While
                        IndexPerson(cust, personId)
                        IndexPersonFromSar(sarBed, personId)
                        IndexPersonFromSar(sarBes, personId)
                    End While
                End Using
            End Using
        End Using
    End Sub

    Private Sub IndexPerson(code As String, personId As Integer)
        If String.IsNullOrWhiteSpace(code) OrElse personId <= 0 Then Return
        Dim k = code.Trim()
        _personByMoien(k) = personId
        Dim trimmed = k.TrimStart("0"c)
        If trimmed.Length > 0 Then _personByMoien(trimmed) = personId
    End Sub

    Private Sub IndexPersonFromSar(sar As String, personId As Integer)
        If String.IsNullOrWhiteSpace(sar) OrElse personId <= 0 Then Return
        Dim s = sar.Trim()
        ' 1030001 / 4010002 → کلید Col|Moien و خود Moien
        If s.Length >= 4 AndAlso Char.IsDigit(s(0)) Then
            Dim col = s.Substring(0, 3)
            Dim moien = s.Substring(3)
            If moien.Length > 0 Then
                _personByMoien(col & "|" & moien) = personId
                _personByMoien(col & "|" & moien.TrimStart("0"c)) = personId
                IndexPerson(moien, personId)
            End If
        End If
    End Sub

    Public Function ResolveBank(col As String, moien As String, tafzili As String, Optional accountNumber As String = Nothing, Optional sarfaslName As String = Nothing) As Integer
        If Not String.IsNullOrWhiteSpace(accountNumber) Then
            Dim acc = accountNumber.Trim()
            Dim id As Integer
            If _bankByAccountNumber.TryGetValue(acc, id) Then Return id
            For Each kv In _bankByAccountNumber
                If acc.Contains(kv.Key) OrElse kv.Key.Contains(acc) Then Return kv.Value
            Next
        End If
        Dim key = MakeKey(col, moien, tafzili)
        Dim found As Integer
        If _bankBySarKey.TryGetValue(key, found) Then Return found
        key = MakeKey(col, moien, "")
        If _bankBySarKey.TryGetValue(key, found) Then Return found
        If Not String.IsNullOrWhiteSpace(sarfaslName) Then
            For Each kv In _bankByAccountNumber
                If kv.Key.Length >= 4 AndAlso sarfaslName.Contains(kv.Key) Then Return kv.Value
            Next
        End If
        Return _bankBySarKey.Values.FirstOrDefault()
    End Function

    Public Function ResolveCashOrPetty(col As String, moien As String, tafzili As String, ByRef isPetty As Boolean) As Integer
        Dim key = MakeKey(col, moien, tafzili)
        Dim id As Integer
        If _pettyBySarKey.TryGetValue(key, id) Then
            isPetty = True
            Return id
        End If
        If _cashBySarKey.TryGetValue(key, id) Then
            isPetty = False
            Return id
        End If
        key = MakeKey(col, moien, "")
        If _pettyBySarKey.TryGetValue(key, id) Then
            isPetty = True
            Return id
        End If
        If _cashBySarKey.TryGetValue(key, id) Then
            isPetty = False
            Return id
        End If
        isPetty = (moien = "0002")
        If isPetty Then Return _pettyBySarKey.Values.FirstOrDefault()
        Return _cashBySarKey.Values.FirstOrDefault()
    End Function

    Public Function ResolvePerson(moienOrCode As String) As Integer
        If String.IsNullOrWhiteSpace(moienOrCode) Then Return 0
        Dim k = moienOrCode.Trim()
        Dim id As Integer
        If _personByMoien.TryGetValue(k, id) Then Return id
        If _personByMoien.TryGetValue(k.TrimStart("0"c), id) Then Return id
        Return 0
    End Function

    ''' <summary>شخص روی سرفصل بستانکاران (401) یا اشخاص (103).</summary>
    Public Function ResolvePersonOnCol(col As String, moien As String) As Integer
        Dim c = If(col, "").Trim()
        Dim m = If(moien, "").Trim()
        Dim id As Integer
        If c.Length > 0 AndAlso m.Length > 0 Then
            If _personByMoien.TryGetValue(c & "|" & m, id) Then Return id
            If _personByMoien.TryGetValue(c & "|" & m.TrimStart("0"c), id) Then Return id
        End If
        Return ResolvePerson(m)
    End Function

    Public Function ExpenseName(moien As String) As String
        Dim n As String = Nothing
        If _expenseNameByMoien.TryGetValue(If(moien, "").Trim(), n) Then Return n
        Return ""
    End Function

    Public Function IncomeName(moien As String) As String
        Dim n As String = Nothing
        If _incomeNameByMoien.TryGetValue(If(moien, "").Trim(), n) Then Return n
        Return ""
    End Function

    ''' <summary>
    ''' نگاشت Col هلو به کد حساب ثابت حسابیکس (بدون تفصیل شخص/بانک).
    ''' نکته حسابداری Holoo1: 106=موجودی، 401=بستانکاران، 402=اسناد پرداختنی.
    ''' </summary>
    Public Shared Function MapColToFixedCode(col As String, Optional moien As String = Nothing, Optional sarfaslName As String = Nothing) As String
        Dim c = If(col, "").Trim()
        Dim m = If(moien, "").Trim()
        Dim n = Normalize(sarfaslName)
        Select Case c
            Case "005", "006" : Return Nothing ' کنترل تراز
            Case "101" : Return "10202" ' با تفصیل صندوق/تنخواه جایگزین می‌شود
            Case "102" : Return "10203"
            Case "103" : Return "10401" ' با جهت بدهکار/بستانکار → AR/AP
            Case "104"
                If n.Contains("ضمانت") OrElse n.Contains("سپرده") Then Return "10302"
                Return "10403"
            Case "106" : Return "10102" ' موجودی اول دوره انبار
            Case "107"
                If m = "0004" OrElse n.Contains("مالیات") Then Return "10104"
                If n.Contains("عوارض") Then Return "10104"
                Return "10101" ' پیش‌پرداخت
            Case "205" : Return "10704" ' اموال و اثاثیه
            Case "401" : Return "20201" ' بستانکاران → AP (با شخص)
            Case "402" : Return "20202" ' اسناد پرداختنی
            Case "404" : Return "30105" ' جاری شرکاء
            Case "502" : Return "30106" ' سود و زیان
            Case "601" : Return MapExpenseToFixedCode(sarfaslName)
            Case "702" : Return MapIncomeToFixedCode(sarfaslName)
            Case "801" : Return "10102" ' خرید (در سیستم دائمی → موجودی/خرید)
            Case "901" : Return "50001" ' فروش
            Case "903" : Return "60203"
            Case Else : Return Nothing
        End Select
    End Function

    ''' <summary>کد حساب ثابت حسابیکس برای هزینه هلو (601.* → 70xxx).</summary>
    Public Shared Function MapExpenseToFixedCode(holooName As String) As String
        Dim n = Normalize(holooName)
        If n.Contains("آب") AndAlso Not n.Contains("آبدار") Then Return "70503"
        If n.Contains("برق") Then Return "70504"
        If n.Contains("گاز") Then Return "70505"
        If n.Contains("تلفن") Then Return "70506"
        If n.Contains("اجاره") OrElse n.Contains("كرايه") OrElse n.Contains("کرايه") OrElse n.Contains("کرایه") Then Return "70405"
        If n.Contains("کارمزد") OrElse n.Contains("كارمزد") Then Return "70902"
        If n.Contains("حقوق") Then Return "70201"
        If n.Contains("بيمه") OrElse n.Contains("بیمه") Then Return "70211"
        If n.Contains("حمل") Then Return "70403"
        If n.Contains("ضايعات") OrElse n.Contains("ضایعات") Then Return "70407"
        If n.Contains("خوراک") OrElse n.Contains("پذیرایی") OrElse n.Contains("پذيرايي") Then Return "70502"
        If n.Contains("مصرفی") OrElse n.Contains("مصرفي") OrElse n.Contains("ملزومات") Then Return "70406"
        If n.Contains("سوخت") AndAlso n.Contains("چک") Then Return "70802"
        If n.Contains("مشکوک") OrElse n.Contains("مشكوك") Then Return "70802"
        If n.Contains("کمیسیون") OrElse n.Contains("كميسيون") OrElse n.Contains("پورسانت") OrElse n.Contains("واسطه") Then Return "70702"
        If n.Contains("تبلیغ") OrElse n.Contains("آگهی") Then Return "70701"
        If n.Contains("تعمیر") OrElse n.Contains("تعمير") Then Return "70404"
        If n.Contains("سوخت") Then Return "70501"
        Return "70401"
    End Function

    Public Shared Function MapIncomeToFixedCode(holooName As String) As String
        Dim n = Normalize(holooName)
        If n.Contains("حمل") OrElse n.Contains("تخلیه") OrElse n.Contains("تخليه") Then Return "60104"
        If n.Contains("خدمات") OrElse n.Contains("حق العمل") OrElse n.Contains("حق‌العمل") Then Return "60101"
        Return "60203"
    End Function

    Public Shared Function MakeKey(col As String, moien As String, tafzili As String) As String
        Return (If(col, "")).Trim() & "|" & (If(moien, "")).Trim() & "|" & (If(tafzili, "")).Trim()
    End Function

    Private Shared Function MatchBank(banks As List(Of Tuple(Of Integer, String, String)), sarfaslName As String) As Integer
        If String.IsNullOrWhiteSpace(sarfaslName) Then Return 0
        Dim bestId = 0
        Dim bestLen = 0
        For Each b In banks
            If b.Item2.Length >= 4 AndAlso sarfaslName.Contains(b.Item2) Then
                If b.Item2.Length > bestLen Then
                    bestLen = b.Item2.Length
                    bestId = b.Item1
                End If
            End If
        Next
        Return bestId
    End Function

    Private Shared Function Normalize(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return ""
        Dim s = value.Trim()
        s = s.Replace("ي", "ی").Replace("ك", "ک").Replace("‌", "")
        Return s
    End Function

    Private Shared Function Open(settings As SqlConnectionSettings) As SqlConnection
        Dim conn As New SqlConnection(settings.BuildConnectionString(settings.Database))
        conn.Open()
        Return conn
    End Function
End Class
