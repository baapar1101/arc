Imports System.Data.SqlClient

''' <summary>
''' نگاشت سرفصل هلو (Col/Moien/Tafzili) به موجودیت‌های حسابیکس و کد حساب ثابت/اختصاصی.
''' قاعده: بدون مقصد قطعی → ۰ / Nothing؛ هرگز FirstOrDefault یا سطل پیش‌فرض 70401.
''' </summary>
Friend Class HolooSarfaslMapper
    Private ReadOnly _bankBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _cashBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _pettyBySarKey As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _personByMoien As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _expenseNameByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _incomeNameByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _bankByAccountNumber As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _bankByHolooId As New Dictionary(Of Integer, Integer)
    Private ReadOnly _matchedBankNames As New List(Of Tuple(Of String, Integer))
    Private ReadOnly _loanMoien401 As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
    Private _defaultLeafCashId As Integer
    Private _defaultLeafPettyId As Integer

    Public ReadOnly Property DefaultLeafCashId As Integer
        Get
            Return _defaultLeafCashId
        End Get
    End Property

    Public ReadOnly Property DefaultLeafPettyId As Integer
        Get
            Return _defaultLeafPettyId
        End Get
    End Property

    Private Shared ReadOnly ExpenseByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
        {"0001", "70503"}, {"0002", "70504"}, {"0003", "70506"},
        {"0004", "70405"}, {"0064", "70405"}, {"0066", "70405"},
        {"0005", "70802"}, {"0006", "70407"}, {"0008", "70702"}, {"0009", "70902"},
        {"0052", "70403"}, {"0060", "70201"}, {"0063", "70502"}, {"0065", "70406"},
        {"0067", "70501"}, {"0068", "70211"}, {"0070", "70903"}
    }

    ''' <summary>معین‌هایی که معادل عمومی ندارند؛ باید حساب اختصاصی ساخته شوند (نه 70401).</summary>
    Private Shared ReadOnly ExpenseNeedsBusinessAccount As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
        "0007", "0055", "0056", "0057", "0058", "0059", "0061", "0062", "0069"
    }

    Private Shared ReadOnly IncomeByMoien As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
        {"0001", "60203"}, {"0002", "60203"},
        {"0003", "60101"}, {"0004", "60104"}
    }

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
        _bankByHolooId.Clear()
        _matchedBankNames.Clear()
        _loanMoien401.Clear()
        _defaultLeafCashId = 0
        _defaultLeafPettyId = 0

        Using conn = Open(settings)
            Dim banks As New List(Of Tuple(Of Integer, String, String))
            Using cmd As New SqlCommand(
                "SELECT Id, ISNULL(Account_N,''), ISNULL(NULLIF(MyNameAcound,''), ISNULL(TaitleBank,'')), " &
                "ISNULL(Col_Code,''), ISNULL(Moien_Code,''), ISNULL(Tafzili_Code,''), ISNULL(Bank_Code,'') " &
                "FROM ACOUND_N;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim holooId = Convert.ToInt32(r.GetValue(0))
                        Dim accNo = Convert.ToString(r.GetValue(1)).Trim()
                        Dim title = Convert.ToString(r.GetValue(2)).Trim()
                        Dim colLink = Convert.ToString(r.GetValue(3)).Trim()
                        Dim moienLink = Convert.ToString(r.GetValue(4)).Trim()
                        Dim tafLink = Convert.ToString(r.GetValue(5)).Trim()
                        Dim hesabixId As Integer = 0
                        If bankMap.Done.TryGetValue(holooId.ToString(), hesabixId) AndAlso hesabixId > 0 Then
                            _bankByHolooId(holooId) = hesabixId
                            banks.Add(Tuple.Create(hesabixId, accNo, title))
                            If accNo.Length > 0 AndAlso Not _bankByAccountNumber.ContainsKey(accNo) Then
                                _bankByAccountNumber(accNo) = hesabixId
                            End If
                            ' لینک مستقیم سرفصل در ACOUND_N — منبع اصلی نگاشت بانک
                            If colLink = "102" OrElse colLink.Length = 0 Then
                                Dim c = If(colLink.Length > 0, colLink, "102")
                                If moienLink.Length > 0 OrElse tafLink.Length > 0 Then
                                    _bankBySarKey(MakeKey(c, moienLink, tafLink)) = hesabixId
                                    If tafLink.Length > 0 Then
                                        Dim parentKey = MakeKey(c, moienLink, "")
                                        If Not _bankBySarKey.ContainsKey(parentKey) Then
                                            _bankBySarKey(parentKey) = hesabixId
                                        End If
                                    End If
                                    If title.Length > 0 Then RememberBankName(title, hesabixId)
                                    If accNo.Length > 0 Then RememberBankName(accNo, hesabixId)
                                End If
                            End If
                        End If
                    End While
                End Using
            End Using

            Using cmd As New SqlCommand(
                "SELECT Col_Code, ISNULL(Moien_Code,''), ISNULL(Tafzili_Code,''), ISNULL(Sarfasl_Name,'') " &
                "FROM SARFASL WHERE ISNULL([Delete],0)=0 AND Col_Code IN ('101','102','401','601','702');", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim col = Convert.ToString(r.GetValue(0)).Trim()
                        Dim moien = Convert.ToString(r.GetValue(1)).Trim()
                        Dim taf = Convert.ToString(r.GetValue(2)).Trim()
                        Dim name = Convert.ToString(r.GetValue(3)).Trim()
                        Dim key = MakeKey(col, moien, taf)

                        If col = "102" Then
                            If Not _bankBySarKey.ContainsKey(key) Then
                                Dim matched = MatchBankExact(banks, name)
                                If matched > 0 Then
                                    _bankBySarKey(key) = matched
                                    RememberBankName(name, matched)
                                End If
                            Else
                                RememberBankName(name, _bankBySarKey(key))
                            End If
                        ElseIf col = "101" Then
                            ' نگاشت نام سرفصل به Cash بعداً از جدول Cash پر می‌شود
                        ElseIf col = "401" AndAlso moien.Length > 0 Then
                            If LooksLikeLoan(name) Then _loanMoien401.Add(moien)
                        ElseIf col = "601" AndAlso moien.Length > 0 Then
                            _expenseNameByMoien(moien) = name
                        ElseIf col = "702" AndAlso moien.Length > 0 Then
                            _incomeNameByMoien(moien) = name
                        End If
                    End While
                End Using
            End Using

            ' پر کردن سرفصل‌های بانک بدون شماره حساب از روی هم‌نام‌های تطبیق‌شده
            Using cmd As New SqlCommand(
                "SELECT ISNULL(Moien_Code,''), ISNULL(Tafzili_Code,''), ISNULL(Sarfasl_Name,'') " &
                "FROM SARFASL WHERE ISNULL([Delete],0)=0 AND Col_Code='102';", conn)
                Dim pending As New List(Of Tuple(Of String, String, String))
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim moien = Convert.ToString(r.GetValue(0)).Trim()
                        Dim taf = Convert.ToString(r.GetValue(1)).Trim()
                        Dim name = Convert.ToString(r.GetValue(2)).Trim()
                        Dim key = MakeKey("102", moien, taf)
                        If Not _bankBySarKey.ContainsKey(key) Then
                            pending.Add(Tuple.Create(moien, taf, name))
                        End If
                    End While
                End Using
                For Each p In pending
                    Dim bridged = BridgeBankBySiblingName(p.Item3)
                    If bridged > 0 Then
                        _bankBySarKey(MakeKey("102", p.Item1, p.Item2)) = bridged
                        RememberBankName(p.Item3, bridged)
                    End If
                Next
            End Using

            ' صندوق/تنخواه: اول از Sarfasl_Code جدول Cash، بعد تطبیق نام
            Dim cashRows As New List(Of Tuple(Of Integer, String, Boolean))
            Dim leafCash As New HashSet(Of Integer)
            Dim leafPetty As New HashSet(Of Integer)
            Using cmd As New SqlCommand(
                "SELECT Id, ISNULL(S_Name,''), ISNULL(S_Type,0), ISNULL(Sarfasl_Code,''), ISNULL(Parent_Id,0) FROM Cash;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim hid = Convert.ToInt32(r.GetValue(0))
                        Dim nm = Convert.ToString(r.GetValue(1)).Trim()
                        Dim isReg = Convert.ToInt32(r.GetValue(2)) = 1
                        Dim sarCode = Convert.ToString(r.GetValue(3)).Trim()
                        Dim parentId = Convert.ToInt32(r.GetValue(4))
                        Dim hx As Integer = 0
                        Dim mapOk = False
                        If isReg Then
                            If cashMap.Done.TryGetValue(hid.ToString(), hx) AndAlso hx > 0 Then
                                cashRows.Add(Tuple.Create(hx, nm, True))
                                mapOk = True
                            End If
                        Else
                            If pettyMap.Done.TryGetValue(hid.ToString(), hx) AndAlso hx > 0 Then
                                cashRows.Add(Tuple.Create(hx, nm, False))
                                mapOk = True
                            End If
                        End If
                        If mapOk AndAlso hx > 0 Then
                            Dim parsed = ParseHolooSarfaslCode(sarCode)
                            If parsed IsNot Nothing Then
                                Dim key = MakeKey(parsed.Item1, parsed.Item2, parsed.Item3)
                                If isReg Then _cashBySarKey(key) = hx Else _pettyBySarKey(key) = hx
                                ' برگ عملیاتی: Tafzili دارد یا Parent_Id>0
                                If parentId > 0 OrElse (parsed.Item3 IsNot Nothing AndAlso parsed.Item3.Length > 0) Then
                                    If isReg Then leafCash.Add(hx) Else leafPetty.Add(hx)
                                End If
                            End If
                        End If
                    End While
                End Using
            End Using
            If leafCash.Count = 1 Then _defaultLeafCashId = leafCash.First()
            If leafPetty.Count = 1 Then _defaultLeafPettyId = leafPetty.First()

            Using cmd As New SqlCommand(
                "SELECT ISNULL(Moien_Code,''), ISNULL(Tafzili_Code,''), ISNULL(Sarfasl_Name,'') " &
                "FROM SARFASL WHERE ISNULL([Delete],0)=0 AND Col_Code='101' AND ISNULL(Moien_Code,'')<>'';", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim moien = Convert.ToString(r.GetValue(0)).Trim()
                        Dim taf = Convert.ToString(r.GetValue(1)).Trim()
                        Dim name = Convert.ToString(r.GetValue(2)).Trim()
                        Dim key = MakeKey("101", moien, taf)
                        Dim wantPetty = (moien = "0002") OrElse name.Contains("تنخواه")
                        If wantPetty Then
                            If _pettyBySarKey.ContainsKey(key) Then Continue While
                        Else
                            If _cashBySarKey.ContainsKey(key) Then Continue While
                        End If
                        Dim matched = MatchCashByName(cashRows, name, wantPetty)
                        If matched > 0 Then
                            If wantPetty Then _pettyBySarKey(key) = matched Else _cashBySarKey(key) = matched
                        End If
                    End While
                End Using
            End Using

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

    Public Function IsLoan401(moien As String) As Boolean
        Dim m = If(moien, "").Trim()
        If m.Length = 0 Then Return False
        If _loanMoien401.Contains(m) Then Return True
        Return _loanMoien401.Contains(m.TrimStart("0"c))
    End Function

    Public Function NeedsBusinessExpenseAccount(moien As String) As Boolean
        Dim m = If(moien, "").Trim()
        Return ExpenseNeedsBusinessAccount.Contains(m)
    End Function

    ''' <summary>بدون fallback به اولین بانک. ۰ یعنی نامشخص.</summary>
    Public Function ResolveBank(col As String, moien As String, tafzili As String, Optional accountNumber As String = Nothing, Optional sarfaslName As String = Nothing) As Integer
        If Not String.IsNullOrWhiteSpace(accountNumber) Then
            Dim acc = accountNumber.Trim()
            Dim id As Integer
            If _bankByAccountNumber.TryGetValue(acc, id) Then Return id
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
        Return 0
    End Function

    ''' <summary>بدون fallback به اولین صندوق وقتی چندتا وجود دارد.</summary>
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
        isPetty = (If(moien, "").Trim() = "0002")
        Return 0
    End Function

    Public Function ResolvePerson(moienOrCode As String) As Integer
        If String.IsNullOrWhiteSpace(moienOrCode) Then Return 0
        Dim k = moienOrCode.Trim()
        Dim id As Integer
        If _personByMoien.TryGetValue(k, id) Then Return id
        If _personByMoien.TryGetValue(k.TrimStart("0"c), id) Then Return id
        Return 0
    End Function

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
    ''' نگاشت Col(+Moien) هلو به کد حساب ثابت حسابیکس.
    ''' Nothing یعنی Skip (کنترل) یا نیاز به حساب اختصاصی / بعداً resolve.
    ''' </summary>
    Public Shared Function MapColToFixedCode(col As String, Optional moien As String = Nothing, Optional sarfaslName As String = Nothing) As String
        Dim c = If(col, "").Trim()
        Dim m = If(moien, "").Trim()
        Dim n = Normalize(sarfaslName)
        Select Case c
            Case "005", "006", "105", "620" : Return Nothing
            Case "001" : Return "80101"
            Case "002" : Return "80102"
            Case "101" : Return "10202"
            Case "102" : Return "10203"
            Case "103" : Return "10401"
            Case "104"
                If n.Contains("ضمانت") OrElse n.Contains("سپرده") Then Return "10302"
                If m = "0002" OrElse n.Contains("جریان وصول") OrElse n.Contains("جريان وصول") Then Return "10404"
                Return "10403"
            Case "106" : Return "10102"
            Case "107"
                If m = "0004" OrElse n.Contains("مالیات") OrElse n.Contains("ماليات") OrElse n.Contains("عوارض") Then Return "10104"
                Return "10101"
            Case "205"
                If n.Contains("زمین") OrElse n.Contains("زمين") Then Return "10701"
                If n.Contains("ساختمان") Then Return "10702"
                If n.Contains("وسیله") OrElse n.Contains("وسيله") OrElse n.Contains("نقلیه") OrElse n.Contains("نقليه") Then Return "10703"
                Return "10704"
            Case "207", "403" : Return "20401"
            Case "401" : Return "20201"
            Case "402" : Return "20202"
            Case "404" : Return "30105"
            Case "501", "506" : Return "30101"
            Case "502" : Return "30106"
            Case "503" : Return "40001"
            Case "601" : Return MapExpenseToFixedCode(sarfaslName, m)
            Case "702" : Return MapIncomeToFixedCode(sarfaslName, m)
            Case "801" : Return "40001"
            Case "802" : Return "40002"
            Case "803", "905" : Return "40003"
            Case "901" : Return "50001"
            Case "902" : Return "50002"
            Case "903", "904" : Return "50003"
            Case Else : Return Nothing
        End Select
    End Function

    ''' <summary>
    ''' کد هزینه. بدون تطبیق صریح → Nothing (نه 70401).
    ''' معین‌های NeedsBusinessAccount هم Nothing برمی‌گردانند تا لایه ساخت حساب اختصاصی وارد شود.
    ''' </summary>
    Public Shared Function MapExpenseToFixedCode(holooName As String, Optional moien As String = Nothing) As String
        Dim m = If(moien, "").Trim()
        If m.Length > 0 Then
            If ExpenseNeedsBusinessAccount.Contains(m) Then Return Nothing
            Dim byMoien As String = Nothing
            If ExpenseByMoien.TryGetValue(m, byMoien) Then Return byMoien
        End If

        Dim n = Normalize(holooName)
        If n.Length = 0 Then Return Nothing
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
        If n.Contains("جريمه") OrElse n.Contains("جریمه") OrElse n.Contains("ديركرد") OrElse n.Contains("دیرکرد") Then Return "70903"
        Return Nothing
    End Function

    Public Shared Function MapIncomeToFixedCode(holooName As String, Optional moien As String = Nothing) As String
        Dim m = If(moien, "").Trim()
        If m.Length > 0 Then
            Dim byMoien As String = Nothing
            If IncomeByMoien.TryGetValue(m, byMoien) Then Return byMoien
        End If
        Dim n = Normalize(holooName)
        If n.Contains("حمل") OrElse n.Contains("تخلیه") OrElse n.Contains("تخليه") Then Return "60104"
        If n.Contains("خدمات") OrElse n.Contains("حق العمل") OrElse n.Contains("حق‌العمل") Then Return "60101"
        If n.Length = 0 AndAlso m.Length = 0 Then Return Nothing
        ' بدون تطبیق صریح → Nothing (نه dump به 60203)
        Return Nothing
    End Function

    Public Shared Function MakeKey(col As String, moien As String, tafzili As String) As String
        Return (If(col, "")).Trim() & "|" & (If(moien, "")).Trim() & "|" & (If(tafzili, "")).Trim()
    End Function

    Public Shared Function LooksLikeLoan(name As String) As Boolean
        Dim n = Normalize(name)
        If n.Length = 0 Then Return False
        Return n.Contains("وام") OrElse n.Contains("تسهیلات") OrElse n.Contains("تسهيلات") OrElse
               n.Contains("قسط") OrElse n.Contains("قوامين") OrElse n.Contains("قوامین")
    End Function

    ''' <summary>کد پیشنهادی حساب اختصاصی زیر گروه درآمد برای معین 702 ناشناس.</summary>
    Public Shared Function SuggestBusinessIncomeCode(moien As String) As String
        Dim m = If(moien, "").Trim().PadLeft(4, "0"c)
        If m.Length > 4 Then m = m.Substring(m.Length - 4)
        Return "6019702" & m
    End Function

    ''' <summary>کد پیشنهادی حساب اختصاصی زیر گروه هزینه برای معین 601.</summary>
    Public Shared Function SuggestBusinessExpenseCode(moien As String) As String
        Dim m = If(moien, "").Trim().PadLeft(4, "0"c)
        If m.Length > 4 Then m = m.Substring(m.Length - 4)
        Return "7049601" & m
    End Function

    ''' <summary>کد پیشنهادی وام زیر 20501 برای معین 401.</summary>
    Public Shared Function SuggestBusinessLoanCode(moien As String) As String
        Dim m = If(moien, "").Trim().PadLeft(4, "0"c)
        If m.Length > 4 Then m = m.Substring(m.Length - 4)
        Return "20519401" & m
    End Function

    Private Sub RememberBankName(name As String, hesabixId As Integer)
        If hesabixId <= 0 OrElse String.IsNullOrWhiteSpace(name) Then Return
        _matchedBankNames.Add(Tuple.Create(name.Trim(), hesabixId))
    End Sub

    ''' <summary>
    ''' برای سرفصل بانک بدون شماره حساب (مثل «بانک پست بانک »)، از هم‌نام‌های قبلاً تطبیق‌شده استفاده کن.
    ''' فقط وقتی یک شناسه واحد پیشنهاد شود — در غیر این صورت ۰ (Block).
    ''' </summary>
    Private Function BridgeBankBySiblingName(sarfaslName As String) As Integer
        Dim n = Normalize(sarfaslName)
        If n.Length < 4 Then Return 0
        ' حذف کلمات عمومی برای مقایسه معنادار
        Dim core = n.Replace("بانک", "").Replace("بانك", "").Replace("جاري", "").Replace("جاری", "").
            Replace("حساب", "").Replace("ريالي", "").Replace("ریالی", "").Trim()
        If core.Length < 2 Then Return 0
        Dim hits As New HashSet(Of Integer)
        For Each m In _matchedBankNames
            Dim mn = Normalize(m.Item1)
            If mn.Length = 0 Then Continue For
            If mn.Contains(core) OrElse core.Contains(NormalizeBankCore(mn)) Then
                hits.Add(m.Item2)
            End If
        Next
        If hits.Count = 1 Then Return hits.First()
        Return 0
    End Function

    Private Shared Function NormalizeBankCore(n As String) As String
        Return n.Replace("بانک", "").Replace("بانك", "").Replace("جاري", "").Replace("جاری", "").
            Replace("حساب", "").Replace("ريالي", "").Replace("ریالی", "").Trim()
    End Function

    Private Shared Function MatchBankExact(banks As List(Of Tuple(Of Integer, String, String)), sarfaslName As String) As Integer
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

    Private Shared Function MatchCashByName(rows As List(Of Tuple(Of Integer, String, Boolean)), sarfaslName As String, wantPetty As Boolean) As Integer
        If rows Is Nothing OrElse rows.Count = 0 Then Return 0
        Dim candidates = rows.Where(Function(x) x.Item3 = Not wantPetty).ToList()
        If candidates.Count = 0 Then Return 0
        If candidates.Count = 1 Then Return candidates(0).Item1
        Dim n = Normalize(sarfaslName)
        If n.Length = 0 Then Return 0
        ' اولویت ۱: تطبیق دقیق نام
        For Each c In candidates
            If Normalize(c.Item2) = n Then Return c.Item1
        Next
        Dim bestId = 0
        Dim bestLen = 0
        For Each c In candidates
            Dim cn = Normalize(c.Item2)
            If cn.Length >= 2 AndAlso (n.Contains(cn) OrElse cn.Contains(n)) Then
                ' فاصله طول کمتر = شباهت بهتر؛ در تساوی طول کوتاه‌تر ترجیح داده می‌شود تا «صندوقها» بر «صندوق» نچربد اشتباهی
                Dim score = Math.Min(cn.Length, n.Length)
                If score > bestLen Then
                    bestLen = score
                    bestId = c.Item1
                ElseIf score = bestLen AndAlso bestId > 0 AndAlso cn.Length = n.Length Then
                    bestId = c.Item1
                End If
            End If
        Next
        Return bestId
    End Function

    ''' <summary>
    ''' کد سرفصل فشرده هلو مثل 10100010001 → Col=101, Moien=0001, Tafzili=0001
    ''' </summary>
    Public Shared Function ParseHolooSarfaslCode(code As String) As Tuple(Of String, String, String)
        Dim s = If(code, "").Trim()
        If s.Length < 3 Then Return Nothing
        Dim col = s.Substring(0, 3)
        If Not col.All(Function(ch) Char.IsDigit(ch)) Then Return Nothing
        Dim rest = s.Substring(3)
        Dim moien = ""
        Dim taf = ""
        If rest.Length >= 4 Then
            moien = rest.Substring(0, 4)
            If rest.Length >= 8 Then
                taf = rest.Substring(4, 4)
            ElseIf rest.Length > 4 Then
                taf = rest.Substring(4)
            End If
        ElseIf rest.Length > 0 Then
            moien = rest.PadLeft(4, "0"c)
        End If
        Return Tuple.Create(col, moien, taf)
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
