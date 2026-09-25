Imports System.Data.SqlClient

Friend Class HolooInvoiceHeader
    Public Property FacCode As String
    Public Property FacType As String
    Public Property CustomerCode As String
    Public Property FacDate As Date
    Public Property SumPrice As Double
    Public Property Takhfif As Double
    Public Property SumLevy As Double
    Public Property SumScot As Double
    Public Property FNaghd As Double
    Public Property FCheck As Double
    Public Property FNesieh As Double
    Public Property Card As Double
    Public Property FHaval As Double
    Public Property Comment As String
    Public Property SanadCode As Integer
    Public Property Lines As New List(Of HolooInvoiceLine)

    Public ReadOnly Property Key As String
        Get
            Return FacType & ":" & FacCode
        End Get
    End Property
End Class

Friend Class HolooInvoiceLine
    Public Property ArticleCode As String
    Public Property Quantity As Double
    Public Property UnitPrice As Double
    Public Property ForeignUnitPrice As Double
    Public Property LineDiscount As Double
    Public Property Levy As Double
    Public Property Scot As Double
    Public Property MoneyCode As Integer
    Public Property Comment As String
End Class

Friend Class HolooInvoiceSettlementHint
    Public Property SanadCode As Integer
    Public Property CashCol As String
    Public Property CashMoien As String
    Public Property CashTafzili As String
    Public Property CashName As String
    Public Property BankCol As String
    Public Property BankMoien As String
    Public Property BankTafzili As String
    Public Property BankName As String
End Class

Friend Class HolooOpeningLine
    Public Property ColCode As String
    Public Property MoienCode As String
    Public Property TafziliCode As String
    Public Property SarfaslName As String
    Public Property Debit As Double
    Public Property Credit As Double
    Public Property Comment As String
End Class

Friend Class HolooCheckRow
    Public Property CheckCode As Integer
    Public Property CheckNumber As String
    Public Property ExportDate As Date?
    Public Property AttainDate As Date?
    Public Property ReceiveDate As Date?
    Public Property SourcePersonCode As String
    Public Property DestPersonCode As String
    Public Property IsPayable As Boolean
    Public Property IsCleared As Boolean
    Public Property IsInProcess As Boolean
    Public Property IsReturned As Boolean
    Public Property IsVoid As Boolean
    Public Property Amount As Double
    Public Property BankCode As String
    Public Property AccountNumber As String
    Public Property BankName As String
    Public Property Comment As String
    Public Property SanadCode As Integer
    Public Property SanadCode2 As Integer

    Public ReadOnly Property Key As String
        Get
            Return "CHK:" & CheckCode.ToString()
        End Get
    End Property

    Public ReadOnly Property IssueDate As Date
        Get
            If ExportDate.HasValue Then Return ExportDate.Value.Date
            If ReceiveDate.HasValue Then Return ReceiveDate.Value.Date
            If AttainDate.HasValue Then Return AttainDate.Value.Date
            Return Date.Today
        End Get
    End Property

    Public ReadOnly Property DueDate As Date
        Get
            If AttainDate.HasValue Then Return AttainDate.Value.Date
            If ReceiveDate.HasValue Then Return ReceiveDate.Value.Date
            Return IssueDate
        End Get
    End Property

    Public ReadOnly Property ClearDate As Date
        Get
            If AttainDate.HasValue Then Return AttainDate.Value.Date
            If ReceiveDate.HasValue Then Return ReceiveDate.Value.Date
            Return IssueDate
        End Get
    End Property
End Class

Friend Class HolooReceiptLikeSanad
    Public Property SanadCode As Integer
    Public Property SanadDate As Date
    Public Property Comment As String
    Public Property IsReceipt As Boolean
    Public Property PersonMoien As String
    Public Property PersonAmount As Double
    Public Property CounterCol As String
    Public Property CounterMoien As String
    Public Property CounterTafzili As String
    Public Property CounterAmount As Double
    Public Property CounterName As String

    Public ReadOnly Property Key As String
        Get
            Return "SND20:" & SanadCode.ToString()
        End Get
    End Property
End Class

Friend Class HolooExpenseIncomeSanad
    Public Property SanadCode As Integer
    Public Property SanadDate As Date
    Public Property Comment As String
    Public Property IsIncome As Boolean
    Public Property ItemLines As New List(Of HolooEiItemLine)
    Public Property CounterpartyLines As New List(Of HolooEiCounterLine)

    Public ReadOnly Property Key As String
        Get
            Return If(IsIncome, "INC:", "EXP:") & SanadCode.ToString()
        End Get
    End Property
End Class

Friend Class HolooEiItemLine
    Public Property MoienCode As String
    Public Property Name As String
    Public Property Amount As Double
End Class

Friend Class HolooEiCounterLine
    Public Property ColCode As String
    Public Property MoienCode As String
    Public Property TafziliCode As String
    Public Property Name As String
    Public Property Amount As Double
End Class

Friend Class HolooManualJournal
    Public Property SanadCode As Integer
    Public Property SanadDate As Date
    Public Property SanadType As Integer
    Public Property Comment As String
    Public Property Lines As New List(Of HolooManualJournalLine)
    ''' <summary>اگر پر باشد، سند در مبدأ قابل انتقال نیست و باید Failed شود (نه silent skip).</summary>
    Public Property SkipReason As String

    Public ReadOnly Property Key As String
        Get
            Return "JRN:" & SanadCode.ToString()
        End Get
    End Property
End Class

Friend Class HolooManualJournalLine
    Public Property ColCode As String
    Public Property MoienCode As String
    Public Property TafziliCode As String
    Public Property SarfaslName As String
    Public Property Debit As Double
    Public Property Credit As Double
End Class

Friend Class HolooDocumentReader
    Public Function ReadInvoicesInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date,
        Optional facTypes As IEnumerable(Of String) = Nothing
    ) As List(Of HolooInvoiceHeader)
        Dim types = If(facTypes, {"F", "K", "Y", "X", "Z"}).ToList()
        Dim list As New List(Of HolooInvoiceHeader)
        Using conn = Open(settings)
            Dim typeParams = String.Join(",", types.Select(Function(t, i) "@t" & i.ToString()))
            Dim sql =
                "SELECT Fac_Code, Fac_Type, C_Code, Fac_Date, ISNULL(Sum_Price,0), ISNULL(Takhfif,0), " &
                "ISNULL(Sum_Levy,0), ISNULL(Sum_Scot,0), ISNULL(FNaghd,0), ISNULL(FCheck,0), ISNULL(FNesieh,0), " &
                "ISNULL(Card,0), ISNULL(FHaval,0), ISNULL(Fac_Comment,''), ISNULL(Sanad_Code,0) " &
                "FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Date>=@s AND Fac_Date<@e " &
                "AND Fac_Type IN (" & typeParams & ") ORDER BY Fac_Date, Fac_Type, Fac_Code;"
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 300
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                For i = 0 To types.Count - 1
                    cmd.Parameters.AddWithValue("@t" & i.ToString(), types(i))
                Next
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        list.Add(New HolooInvoiceHeader With {
                            .FacCode = SafeStr(r, 0),
                            .FacType = SafeStr(r, 1),
                            .CustomerCode = SafeStr(r, 2),
                            .FacDate = Convert.ToDateTime(r.GetValue(3)).Date,
                            .SumPrice = SafeDbl(r, 4),
                            .Takhfif = SafeDbl(r, 5),
                            .SumLevy = SafeDbl(r, 6),
                            .SumScot = SafeDbl(r, 7),
                            .FNaghd = SafeDbl(r, 8),
                            .FCheck = SafeDbl(r, 9),
                            .FNesieh = SafeDbl(r, 10),
                            .Card = SafeDbl(r, 11),
                            .FHaval = SafeDbl(r, 12),
                            .Comment = SafeStr(r, 13),
                            .SanadCode = SafeInt(r, 14)
                        })
                    End While
                End Using
            End Using

            If list.Count = 0 Then Return list

            ' بارگذاری خطوط — برای حجم بالا per-invoice سنگین است؛ یک کوئری بازه‌ای
            Dim lineSql =
                "SELECT a.Fac_Code, a.Fac_Type, a.A_Code, ISNULL(a.Few_Article,0), ISNULL(a.Price_BS,0), " &
                "ISNULL(a.TakhfifSatriR,0), ISNULL(a.Levy,0), ISNULL(a.Scot,0), ISNULL(a.Money_Code,0), ISNULL(a.FacArtic_Comment,''), " &
                "ISNULL(a.Price_Dollari,0) " &
                "FROM FACTART a " &
                "INNER JOIN FACTURE f ON f.Fac_Code=a.Fac_Code AND f.Fac_Type=a.Fac_Type " &
                "WHERE ISNULL(f.[Delete],0)=0 AND f.Fac_Date>=@s AND f.Fac_Date<@e " &
                "AND f.Fac_Type IN (" & typeParams & ") " &
                "ORDER BY a.Fac_Type, a.Fac_Code, a.A_Index;"
            Dim byKey As New Dictionary(Of String, HolooInvoiceHeader)(StringComparer.Ordinal)
            For Each h In list
                byKey(h.Key) = h
            Next
            Using cmd As New SqlCommand(lineSql, conn)
                cmd.CommandTimeout = 600
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                For i = 0 To types.Count - 1
                    cmd.Parameters.AddWithValue("@t" & i.ToString(), types(i))
                Next
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim key = SafeStr(r, 1) & ":" & SafeStr(r, 0)
                        Dim header As HolooInvoiceHeader = Nothing
                        If Not byKey.TryGetValue(key, header) Then Continue While
                        header.Lines.Add(New HolooInvoiceLine With {
                            .ArticleCode = SafeStr(r, 2),
                            .Quantity = SafeDbl(r, 3),
                            .UnitPrice = SafeDbl(r, 4),
                            .LineDiscount = SafeDbl(r, 5),
                            .Levy = SafeDbl(r, 6),
                            .Scot = SafeDbl(r, 7),
                            .MoneyCode = SafeInt(r, 8),
                            .Comment = SafeStr(r, 9),
                            .ForeignUnitPrice = SafeDbl(r, 10)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    ''' <summary>
    ''' از سند اتوماتیک فاکتور، حساب صندوق/بانک تسویه را برای نگاشت دقیق استخراج می‌کند.
    ''' </summary>
    Public Function ReadSettlementHintsForSanads(
        settings As SqlConnectionSettings,
        sanadCodes As IEnumerable(Of Integer)
    ) As Dictionary(Of Integer, HolooInvoiceSettlementHint)
        Dim map As New Dictionary(Of Integer, HolooInvoiceSettlementHint)
        Dim codes = sanadCodes.Where(Function(c) c > 0).Distinct().ToList()
        If codes.Count = 0 Then Return map
        Using conn = Open(settings)
            Const chunk As Integer = 400
            Dim offset = 0
            While offset < codes.Count
                Dim take = Math.Min(chunk, codes.Count - offset)
                Dim part = codes.GetRange(offset, take)
                Dim parms = String.Join(",", part.Select(Function(c, i) "@p" & i.ToString()))
                Dim sql =
                    "SELECT l.Sanad_Code, l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), " &
                    "ISNULL(s.Sarfasl_Name,''), ISNULL(l.Bed,0), ISNULL(l.Bes,0) " &
                    "FROM SND_LIST l LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                    " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') " &
                    "WHERE l.Sanad_Code IN (" & parms & ") AND l.Col_Code IN ('101','102');"
                Using cmd As New SqlCommand(sql, conn)
                    cmd.CommandTimeout = 180
                    For i = 0 To part.Count - 1
                        cmd.Parameters.AddWithValue("@p" & i.ToString(), part(i))
                    Next
                    Using r = cmd.ExecuteReader()
                        While r.Read()
                            Dim sc = SafeInt(r, 0)
                            Dim hint As HolooInvoiceSettlementHint = Nothing
                            If Not map.TryGetValue(sc, hint) Then
                                hint = New HolooInvoiceSettlementHint With {.SanadCode = sc}
                                map(sc) = hint
                            End If
                            Dim col = SafeStr(r, 1)
                            Dim bed = SafeDbl(r, 5)
                            Dim bes = SafeDbl(r, 6)
                            ' در فروش: صندوق/بانک بدهکار؛ در خرید: بستانکار
                            If col = "101" AndAlso (bed > 0 OrElse bes > 0) Then
                                If String.IsNullOrWhiteSpace(hint.CashMoien) OrElse bed >= bes Then
                                    hint.CashCol = col
                                    hint.CashMoien = SafeStr(r, 2)
                                    hint.CashTafzili = SafeStr(r, 3)
                                    hint.CashName = SafeStr(r, 4)
                                End If
                            ElseIf col = "102" AndAlso (bed > 0 OrElse bes > 0) Then
                                If String.IsNullOrWhiteSpace(hint.BankMoien) OrElse bed >= bes Then
                                    hint.BankCol = col
                                    hint.BankMoien = SafeStr(r, 2)
                                    hint.BankTafzili = SafeStr(r, 3)
                                    hint.BankName = SafeStr(r, 4)
                                End If
                            End If
                        End While
                    End Using
                End Using
                offset += take
            End While
        End Using
        Return map
    End Function

    Public Function FindOpeningSanadCode(settings As SqlConnectionSettings) As Integer
        Using conn = Open(settings)
            Using cmd As New SqlCommand(
                "SELECT TOP 1 Sanad_Code FROM SANAD WHERE ISNULL([Delete],0)=0 AND (" &
                " Comment LIKE N'%افتتاح%' OR Sanad_Code=1) ORDER BY Sanad_Code;", conn)
                Dim o = cmd.ExecuteScalar()
                If o Is Nothing OrElse o Is DBNull.Value Then Return 0
                Return Convert.ToInt32(o)
            End Using
        End Using
    End Function

    Public Function ReadOpeningLines(settings As SqlConnectionSettings, sanadCode As Integer) As List(Of HolooOpeningLine)
        Dim list As New List(Of HolooOpeningLine)
        If sanadCode <= 0 Then Return list
        Using conn = Open(settings)
            Dim sql =
                "SELECT l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), ISNULL(s.Sarfasl_Name,''), " &
                "ISNULL(l.Bed,0), ISNULL(l.Bes,0), ISNULL(l.Comment_Line,'') " &
                "FROM SND_LIST l " &
                "LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') " &
                "WHERE l.Sanad_Code=@c ORDER BY l.[Index];"
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@c", sanadCode)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        list.Add(New HolooOpeningLine With {
                            .ColCode = SafeStr(r, 0),
                            .MoienCode = SafeStr(r, 1),
                            .TafziliCode = SafeStr(r, 2),
                            .SarfaslName = SafeStr(r, 3),
                            .Debit = SafeDbl(r, 4),
                            .Credit = SafeDbl(r, 5),
                            .Comment = SafeStr(r, 6)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadReceiptLikeSanadsInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date
    ) As List(Of HolooReceiptLikeSanad)
        Dim list As New List(Of HolooReceiptLikeSanad)
        Using conn = Open(settings)
            Dim sql =
                "SELECT s.Sanad_Code, s.Sanad_Date, ISNULL(s.Comment,'') " &
                "FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND s.Sanad_Type=20 AND s.Sanad_Date>=@s AND s.Sanad_Date<@e " &
                "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702')) " &
                "ORDER BY s.Sanad_Date, s.Sanad_Code;"
            Dim headers As New List(Of Tuple(Of Integer, Date, String))
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        headers.Add(Tuple.Create(SafeInt(r, 0), Convert.ToDateTime(r.GetValue(1)).Date, SafeStr(r, 2)))
                    End While
                End Using
            End Using

            For Each h In headers
                Dim lines As New List(Of Tuple(Of String, String, String, Double, Double, String))
                Using cmd As New SqlCommand(
                    "SELECT l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), ISNULL(l.Bed,0), ISNULL(l.Bes,0), ISNULL(s.Sarfasl_Name,'') " &
                    "FROM SND_LIST l LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                    " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') WHERE l.Sanad_Code=@c ORDER BY l.[Index];", conn)
                    cmd.Parameters.AddWithValue("@c", h.Item1)
                    Using r = cmd.ExecuteReader()
                        While r.Read()
                            lines.Add(Tuple.Create(SafeStr(r, 0), SafeStr(r, 1), SafeStr(r, 2), SafeDbl(r, 3), SafeDbl(r, 4), SafeStr(r, 5)))
                        End While
                    End Using
                End Using

                Dim personLine = lines.FirstOrDefault(Function(x) x.Item1 = "103")
                Dim cashBank = lines.FirstOrDefault(Function(x) x.Item1 = "101" OrElse x.Item1 = "102")
                If personLine Is Nothing OrElse cashBank Is Nothing Then Continue For

                Dim isReceipt = (cashBank.Item4 > 0 AndAlso personLine.Item5 > 0)
                Dim isPayment = (cashBank.Item5 > 0 AndAlso personLine.Item4 > 0)
                If Not isReceipt AndAlso Not isPayment Then Continue For

                Dim amount = If(isReceipt, personLine.Item5, personLine.Item4)
                If amount <= 0 Then amount = If(isReceipt, cashBank.Item4, cashBank.Item5)
                list.Add(New HolooReceiptLikeSanad With {
                    .SanadCode = h.Item1,
                    .SanadDate = h.Item2,
                    .Comment = h.Item3,
                    .IsReceipt = isReceipt,
                    .PersonMoien = personLine.Item2,
                    .PersonAmount = amount,
                    .CounterCol = cashBank.Item1,
                    .CounterMoien = cashBank.Item2,
                    .CounterTafzili = cashBank.Item3,
                    .CounterAmount = amount,
                    .CounterName = cashBank.Item6
                })
            Next
        End Using
        Return list
    End Function

    Public Function ReadChecksInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date
    ) As List(Of HolooCheckRow)
        Dim list As New List(Of HolooCheckRow)
        Using conn = Open(settings)
            Dim sql =
                "SELECT c.Check_Code, ISNULL(c.Check_Number,''), c.Export_Date, c.Attain_Date, c.Receive_Date, " &
                "ISNULL(c.C_Code_Source,''), ISNULL(c.C_Code_Destination,''), ISNULL(c.Daryaft_Pardakht,0), " &
                "ISNULL(c.Vosool,0), ISNULL(c.DarJaryan,0), ISNULL(c.Bargashty,0), ISNULL(c.IsEbtal,0), " &
                "ISNULL(c.Cust,0), ISNULL(c.Bank_Code,''), ISNULL(c.Account_Number,''), ISNULL(c.Comm,''), " &
                "ISNULL(c.Sanad_Code,0), ISNULL(c.Sanad_Code2,0), ISNULL(b.Bank_Name,'') " &
                "FROM [Check] c LEFT JOIN NEWBANK b ON b.Bank_Code=c.Bank_Code " &
                "WHERE ISNULL(c.[Delete],0)=0 AND (" &
                " (c.Export_Date>=@s AND c.Export_Date<@e) OR (c.Receive_Date>=@s AND c.Receive_Date<@e) OR (c.Attain_Date>=@s AND c.Attain_Date<@e)" &
                ") ORDER BY c.Check_Code;"
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        list.Add(New HolooCheckRow With {
                            .CheckCode = SafeInt(r, 0),
                            .CheckNumber = SafeStr(r, 1),
                            .ExportDate = SafeDate(r, 2),
                            .AttainDate = SafeDate(r, 3),
                            .ReceiveDate = SafeDate(r, 4),
                            .SourcePersonCode = SafeStr(r, 5),
                            .DestPersonCode = SafeStr(r, 6),
                            .IsPayable = SafeBool(r, 7),
                            .IsCleared = SafeBool(r, 8),
                            .IsInProcess = SafeBool(r, 9),
                            .IsReturned = SafeBool(r, 10),
                            .IsVoid = SafeBool(r, 11),
                            .Amount = SafeDbl(r, 12),
                            .BankCode = SafeStr(r, 13),
                            .AccountNumber = SafeStr(r, 14),
                            .Comment = SafeStr(r, 15),
                            .SanadCode = SafeInt(r, 16),
                            .SanadCode2 = SafeInt(r, 17),
                            .BankName = SafeStr(r, 18)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadExpenseIncomeSanadsInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date,
        asIncome As Boolean
    ) As List(Of HolooExpenseIncomeSanad)
        Dim list As New List(Of HolooExpenseIncomeSanad)
        Dim targetCol = If(asIncome, "702", "601")
        Using conn = Open(settings)
            Dim sql =
                "SELECT s.Sanad_Code, s.Sanad_Date, ISNULL(s.Comment,'') FROM SANAD s " &
                "WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND s.Sanad_Date>=@s AND s.Sanad_Date<@e " &
                "AND EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code=@col) " &
                "AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                "ORDER BY s.Sanad_Date, s.Sanad_Code;"
            Dim headers As New List(Of Tuple(Of Integer, Date, String))
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                cmd.Parameters.AddWithValue("@col", targetCol)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        headers.Add(Tuple.Create(SafeInt(r, 0), Convert.ToDateTime(r.GetValue(1)).Date, SafeStr(r, 2)))
                    End While
                End Using
            End Using

            For Each h In headers
                Dim lines As New List(Of Tuple(Of String, String, String, Double, Double, String))
                Using cmd As New SqlCommand(
                    "SELECT l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), ISNULL(l.Bed,0), ISNULL(l.Bes,0), ISNULL(s.Sarfasl_Name,'') " &
                    "FROM SND_LIST l LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                    " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') WHERE l.Sanad_Code=@c ORDER BY l.[Index];", conn)
                    cmd.Parameters.AddWithValue("@c", h.Item1)
                    Using r = cmd.ExecuteReader()
                        While r.Read()
                            lines.Add(Tuple.Create(SafeStr(r, 0), SafeStr(r, 1), SafeStr(r, 2), SafeDbl(r, 3), SafeDbl(r, 4), SafeStr(r, 5)))
                        End While
                    End Using
                End Using

                Dim doc As New HolooExpenseIncomeSanad With {
                    .SanadCode = h.Item1,
                    .SanadDate = h.Item2,
                    .Comment = h.Item3,
                    .IsIncome = asIncome
                }

                If asIncome Then
                    For Each ln In lines
                        If ln.Item1 = "702" AndAlso ln.Item5 > 0 Then
                            doc.ItemLines.Add(New HolooEiItemLine With {.MoienCode = ln.Item2, .Name = ln.Item6, .Amount = ln.Item5})
                        ElseIf (ln.Item1 = "101" OrElse ln.Item1 = "102" OrElse ln.Item1 = "103" OrElse ln.Item1 = "401") AndAlso ln.Item4 > 0 Then
                            doc.CounterpartyLines.Add(New HolooEiCounterLine With {
                                .ColCode = ln.Item1, .MoienCode = ln.Item2, .TafziliCode = ln.Item3, .Name = ln.Item6, .Amount = ln.Item4
                            })
                        End If
                    Next
                Else
                    For Each ln In lines
                        If ln.Item1 = "601" AndAlso ln.Item4 > 0 Then
                            doc.ItemLines.Add(New HolooEiItemLine With {.MoienCode = ln.Item2, .Name = ln.Item6, .Amount = ln.Item4})
                        ElseIf (ln.Item1 = "101" OrElse ln.Item1 = "102" OrElse ln.Item1 = "103" OrElse ln.Item1 = "401") AndAlso ln.Item5 > 0 Then
                            doc.CounterpartyLines.Add(New HolooEiCounterLine With {
                                .ColCode = ln.Item1, .MoienCode = ln.Item2, .TafziliCode = ln.Item3, .Name = ln.Item6, .Amount = ln.Item5
                            })
                        End If
                    Next
                End If

                If doc.ItemLines.Count = 0 OrElse doc.CounterpartyLines.Count = 0 Then Continue For
                Dim itemSum = doc.ItemLines.Sum(Function(x) x.Amount)
                Dim cpSum = doc.CounterpartyLines.Sum(Function(x) x.Amount)
                If Math.Abs(itemSum - cpSum) > 1.0 Then Continue For ' نامتوازن برای API هزینه — به fallback دستی می‌رود
                list.Add(doc)
            Next
        End Using
        Return list
    End Function

    ''' <summary>
    ''' اسناد دارای 601/702 که ساختار ساده هزینه/درآمد متوازن ندارند (مثلاً ترکیبی Type20)
    ''' ولی خود سند تراز است — به‌صورت MANUAL با برچسب EXPENSE_INCOME_FALLBACK تا از پارتیشن خارج نشوند.
    ''' رسید Type20 خالص (بدون 601/702) اینجا نیست؛ هزینه متوازن هم نیست.
    ''' </summary>
    Public Function ReadExpenseLikeFallbackManualsInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date
    ) As List(Of HolooManualJournal)
        Dim list As New List(Of HolooManualJournal)
        Dim openingCode = FindOpeningSanadCode(settings)
        Dim structuredKeys As New HashSet(Of Integer)()
        For Each d In ReadExpenseIncomeSanadsInRange(settings, startDate, endDateInclusive, False)
            structuredKeys.Add(d.SanadCode)
        Next
        For Each d In ReadExpenseIncomeSanadsInRange(settings, startDate, endDateInclusive, True)
            structuredKeys.Add(d.SanadCode)
        Next

        Using conn = Open(settings)
            Dim sql =
                "SELECT s.Sanad_Code, s.Sanad_Date, ISNULL(s.Sanad_Type,0), ISNULL(s.Comment,'') " &
                "FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND s.Sanad_Code<>@open AND s.Sanad_Date>=@s AND s.Sanad_Date<@e " &
                "AND ISNULL(s.Sanad_Type,0)<>5 " &
                "AND EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702')) " &
                "AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                "ORDER BY s.Sanad_Date, s.Sanad_Code;"
            Dim headers As New List(Of Tuple(Of Integer, Date, Integer, String))
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@open", openingCode)
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        headers.Add(Tuple.Create(SafeInt(r, 0), Convert.ToDateTime(r.GetValue(1)).Date, SafeInt(r, 2), SafeStr(r, 3)))
                    End While
                End Using
            End Using

            For Each h In headers
                If structuredKeys.Contains(h.Item1) Then Continue For
                Dim doc As New HolooManualJournal With {
                    .SanadCode = h.Item1,
                    .SanadDate = h.Item2,
                    .SanadType = h.Item3,
                    .Comment = If(String.IsNullOrWhiteSpace(h.Item4), "", h.Item4) & " [EI-FALLBACK]"
                }
                Dim bedSum As Double = 0
                Dim besSum As Double = 0
                Using cmd As New SqlCommand(
                    "SELECT l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), ISNULL(s.Sarfasl_Name,''), ISNULL(l.Bed,0), ISNULL(l.Bes,0) " &
                    "FROM SND_LIST l LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                    " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') WHERE l.Sanad_Code=@c ORDER BY l.[Index];", conn)
                    cmd.Parameters.AddWithValue("@c", h.Item1)
                    Using r = cmd.ExecuteReader()
                        While r.Read()
                            Dim d = SafeDbl(r, 4)
                            Dim c = SafeDbl(r, 5)
                            If d <= 0 AndAlso c <= 0 Then Continue While
                            bedSum += d
                            besSum += c
                            doc.Lines.Add(New HolooManualJournalLine With {
                                .ColCode = SafeStr(r, 0),
                                .MoienCode = SafeStr(r, 1),
                                .TafziliCode = SafeStr(r, 2),
                                .SarfaslName = SafeStr(r, 3),
                                .Debit = d,
                                .Credit = c
                            })
                        End While
                    End Using
                End Using
                If doc.Lines.Count < 2 Then
                    doc.SkipReason = "کمتر از دو خط مؤثر در مبدأ (EI-fallback)"
                    list.Add(doc)
                    Continue For
                End If
                If Math.Abs(bedSum - besSum) > 1.0 Then
                    doc.SkipReason = "نامتوازن در مبدأ (EI-fallback)"
                    list.Add(doc)
                    Continue For
                End If
                list.Add(doc)
            Next
        End Using
        Return list
    End Function

    ''' <summary>
    ''' اسناد دستی/عمومی باقی‌مانده (غیر فاکتور، غیر Type5/20، غیر لینک چک، غیر هزینه/درآمد).
    ''' هر سندی که ردیف FACTURE فعال دارد از این ماژول خارج است تا GL فاکتور دوبل نشود
    ''' (حتی اگر SaveFromFacture=0 باشد؛ نمونه Holoo1: صدها Type13/14 متصل به F/K).
    ''' </summary>
    Public Function ReadManualJournalsInRange(
        settings As SqlConnectionSettings,
        startDate As Date,
        endDateInclusive As Date
    ) As List(Of HolooManualJournal)
        Dim list As New List(Of HolooManualJournal)
        Dim openingCode = FindOpeningSanadCode(settings)
        Using conn = Open(settings)
            Dim sql =
                "SELECT s.Sanad_Code, s.Sanad_Date, ISNULL(s.Sanad_Type,0), ISNULL(s.Comment,'') " &
                "FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND s.Sanad_Code<>@open AND s.Sanad_Date>=@s AND s.Sanad_Date<@e " &
                "AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                "AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702')) " &
                "ORDER BY s.Sanad_Date, s.Sanad_Code;"
            Dim headers As New List(Of Tuple(Of Integer, Date, Integer, String))
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                cmd.Parameters.AddWithValue("@open", openingCode)
                cmd.Parameters.AddWithValue("@s", startDate)
                cmd.Parameters.AddWithValue("@e", endDateInclusive.AddDays(1))
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        headers.Add(Tuple.Create(SafeInt(r, 0), Convert.ToDateTime(r.GetValue(1)).Date, SafeInt(r, 2), SafeStr(r, 3)))
                    End While
                End Using
            End Using

            For Each h In headers
                Dim doc As New HolooManualJournal With {
                    .SanadCode = h.Item1,
                    .SanadDate = h.Item2,
                    .SanadType = h.Item3,
                    .Comment = h.Item4
                }
                Dim bedSum As Double = 0
                Dim besSum As Double = 0
                Using cmd As New SqlCommand(
                    "SELECT l.Col_Code, ISNULL(l.Moien_Code,''), ISNULL(l.Tafzili_Code,''), ISNULL(s.Sarfasl_Name,''), ISNULL(l.Bed,0), ISNULL(l.Bes,0) " &
                    "FROM SND_LIST l LEFT JOIN SARFASL s ON s.Col_Code=l.Col_Code AND ISNULL(s.Moien_Code,'')=ISNULL(l.Moien_Code,'') " &
                    " AND ISNULL(s.Tafzili_Code,'')=ISNULL(l.Tafzili_Code,'') WHERE l.Sanad_Code=@c ORDER BY l.[Index];", conn)
                    cmd.Parameters.AddWithValue("@c", h.Item1)
                    Using r = cmd.ExecuteReader()
                        While r.Read()
                            Dim d = SafeDbl(r, 4)
                            Dim c = SafeDbl(r, 5)
                            If d <= 0 AndAlso c <= 0 Then Continue While
                            bedSum += d
                            besSum += c
                            doc.Lines.Add(New HolooManualJournalLine With {
                                .ColCode = SafeStr(r, 0),
                                .MoienCode = SafeStr(r, 1),
                                .TafziliCode = SafeStr(r, 2),
                                .SarfaslName = SafeStr(r, 3),
                                .Debit = d,
                                .Credit = c
                            })
                        End While
                    End Using
                End Using
                If doc.Lines.Count < 2 Then
                    doc.SkipReason = "کمتر از دو خط مؤثر در مبدأ"
                    list.Add(doc)
                    Continue For
                End If
                If Math.Abs(bedSum - besSum) > 1.0 Then
                    doc.SkipReason = "نامتوازن در مبدأ (|Bed-Bes|>1)"
                    list.Add(doc)
                    Continue For
                End If
                list.Add(doc)
            Next
        End Using

        ' پارتیشن: Type20 ترکیبی 601/702 که API هزینه نمی‌پذیرد → دستی (بدون دوبل با EI متوازن)
        For Each fb In ReadExpenseLikeFallbackManualsInRange(settings, startDate, endDateInclusive)
            If list.Any(Function(x) x.SanadCode = fb.SanadCode) Then Continue For
            list.Add(fb)
        Next
        Return list
    End Function

    Public Function ReadProductOpeningQuantities(settings As SqlConnectionSettings) As List(Of Tuple(Of String, Double, Double, Integer?))
        Dim list As New List(Of Tuple(Of String, Double, Double, Integer?))
        Using conn = Open(settings)
            Using cmd As New SqlCommand(
                "SELECT A_Code, ISNULL(First_exist,0), ISNULL(NULLIF(FirstBuy_Price,0), ISNULL(Buy_Price,0)), Type_Anbar_C " &
                "FROM ARTICLE WHERE ISNULL([Delete],0)=0 AND ISNULL(First_exist,0)>0;", conn)
                cmd.CommandTimeout = 180
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim code = SafeStr(r, 0)
                        Dim qty = SafeDbl(r, 1)
                        Dim cost = SafeDbl(r, 2)
                        Dim wh As Integer? = Nothing
                        If Not r.IsDBNull(3) Then
                            Try
                                wh = Convert.ToInt32(r.GetValue(3))
                            Catch
                                wh = Nothing
                            End Try
                        End If
                        If code.Length > 0 AndAlso qty > 0 Then
                            list.Add(Tuple.Create(code, qty, cost, wh))
                        End If
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Shared Function MapFacTypeToInvoiceType(facType As String) As String
        Select Case (If(facType, "")).Trim().ToUpperInvariant()
            Case "F" : Return "invoice_sales"
            Case "K" : Return "invoice_purchase"
            Case "Y" : Return "invoice_sales_return"
            Case "X" : Return "invoice_purchase_return"
            Case "Z" : Return "invoice_direct_consumption" ' مصرف مستقیم کالا (Dr هزینه / Cr موجودی-خرید)
            Case Else : Return Nothing
        End Select
    End Function

    Public Shared Function InvoiceRequiresPerson(facType As String) As Boolean
        Select Case (If(facType, "")).Trim().ToUpperInvariant()
            Case "Z" : Return False
            Case Else : Return True
        End Select
    End Function

    Private Shared Function Open(settings As SqlConnectionSettings) As SqlConnection
        Dim conn As New SqlConnection(settings.BuildConnectionString(settings.Database))
        conn.Open()
        Return conn
    End Function

    Private Shared Function SafeStr(r As SqlDataReader, i As Integer) As String
        If r.IsDBNull(i) Then Return ""
        Return Convert.ToString(r.GetValue(i)).Trim()
    End Function

    Private Shared Function SafeInt(r As SqlDataReader, i As Integer) As Integer
        If r.IsDBNull(i) Then Return 0
        Return Convert.ToInt32(r.GetValue(i))
    End Function

    Private Shared Function SafeDbl(r As SqlDataReader, i As Integer) As Double
        If r.IsDBNull(i) Then Return 0
        Return Convert.ToDouble(r.GetValue(i))
    End Function

    Private Shared Function SafeBool(r As SqlDataReader, i As Integer) As Boolean
        If r.IsDBNull(i) Then Return False
        Dim v = r.GetValue(i)
        If TypeOf v Is Boolean Then Return CBool(v)
        Return Convert.ToInt32(v) <> 0
    End Function

    Private Shared Function SafeDate(r As SqlDataReader, i As Integer) As Date?
        If r.IsDBNull(i) Then Return Nothing
        Try
            Return Convert.ToDateTime(r.GetValue(i)).Date
        Catch
            Return Nothing
        End Try
    End Function
End Class
