Imports System.Collections.Concurrent
Imports System.Net
Imports System.Threading
Imports Newtonsoft.Json.Linq

''' <summary>
''' انتقال اسناد سال‌به‌سال: FY، افتتاحیه، فاکتور، انبار، دریافت، چک، هزینه/درآمد.
''' سندهای Type=5 هلو (مرتبط با چک) عمداً کپی نمی‌شوند — GL از API چک ساخته می‌شود.
''' </summary>
Friend Class DocumentTransferService
    Private ReadOnly _docs As New HolooDocumentReader()
    ' تک‌فاکتور با موازی‌سازی ملایم — بیش از ۳ کارگر روی این API باعث timeout دسته‌جمعی می‌شود
    Private Const InvoiceChunk As Integer = 1
    Private Const InvoiceParallelism As Integer = 3
    Private Const InvoiceRequestTimeoutSeconds As Integer = 90
    Private Const WarehouseChunk As Integer = 100
    Private Const ReceiptChunk As Integer = 50
    Private Const ExpenseChunk As Integer = 40

    ''' <summary>اگر >0 باشد، از هر ماژول اسناد فقط همین تعداد نمونه منتقل می‌شود (تست سریع).</summary>
    Public Property SampleLimit As Integer = 0

    Public Event ProgressChanged As EventHandler(Of TransferProgressEventArgs)

    Private Function ApplySample(Of T)(rows As List(Of T), moduleTitle As String) As List(Of T)
        If rows Is Nothing Then Return New List(Of T)()
        If SampleLimit <= 0 OrElse rows.Count <= SampleLimit Then Return rows
        RaiseProgress(moduleTitle, 0, rows.Count,
                      "حالت نمونه: " & SampleLimit.ToString() & " از " & rows.Count.ToString() & " سند")
        Return rows.Take(SampleLimit).ToList()
    End Function

    Public Async Function RunAsync(
        session As MigrationSession,
        api As HesabixApiClient,
        selectedModules As IEnumerable(Of MigrationModule),
        currencyId As Integer,
        Optional resetCheckpoint As Boolean = False,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of String)
        Dim businessId = session.SelectedBusiness.Id
        Dim store As New CheckpointStore(businessId, session.SelectedDatabase)
        If resetCheckpoint Then
            ' reset کامل قبلاً در base انجام شده.
        End If
        Dim cp = store.LoadOrCreate(session.ApiBaseUrl, businessId, session.SqlSettings.Server, session.SelectedDatabase)
        api.Configure(session.ApiBaseUrl, session.ApiKey)

        Dim mods = selectedModules.Where(Function(m) MigrationModuleInfo.IsDocumentModule(m)).OrderBy(Function(m) CInt(m)).ToList()
        If mods.Count = 0 Then Return store.FilePath

        Dim years = If(session.Preflight?.FiscalYears, New List(Of DetectedFiscalYear)())
        If years.Count = 0 Then
            RaiseProgress("سال مالی", 0, 0, "سال مالی کشف‌شده وجود ندارد", True)
            Return store.FilePath
        End If

        If mods.Contains(MigrationModule.FiscalYearsAndOpening) OrElse
           mods.Contains(MigrationModule.Invoices) OrElse
           mods.Contains(MigrationModule.ReceiptsPayments) OrElse
           mods.Contains(MigrationModule.Checks) OrElse
           mods.Contains(MigrationModule.ExpenseIncome) OrElse
           mods.Contains(MigrationModule.ManualJournals) Then
            Await EnsureFiscalYears(session, api, businessId, years, ct).ConfigureAwait(False)
        End If

        Dim personMap = cp.EnsureModule(MigrationModule.Persons.ToString())
        Dim productMap = cp.EnsureModule(MigrationModule.Products.ToString())
        Dim bankMap = cp.EnsureModule(MigrationModule.BankAccounts.ToString())
        Dim cashMap = cp.EnsureModule(MigrationModule.CashRegisters.ToString())
        Dim pettyMap = cp.EnsureModule(MigrationModule.PettyCash.ToString())
        Dim warehouseMap = cp.EnsureModule(MigrationModule.Warehouses.ToString())
        Dim invoiceMap = cp.EnsureModule(MigrationModule.Invoices.ToString())

        RaiseProgress("نگاشت سرفصل", 0, 0, "ساخت نگاشت بانک/صندوق/هزینه از SARFASL...")
        Dim mapper As New HolooSarfaslMapper()
        Await Task.Run(Sub() mapper.Build(session.SqlSettings, bankMap, cashMap, pettyMap, personMap), ct).ConfigureAwait(False)

        Dim defaultCashId = If(cashMap.Done.Count = 1, cashMap.Done.Values.First(), 0)
        Dim defaultBankId = If(bankMap.Done.Count = 1, bankMap.Done.Values.First(), 0)
        Dim defaultPettyId = If(pettyMap.Done.Count = 1, pettyMap.Done.Values.First(), 0)
        ' فقط وقتی دقیقاً یک برگ منتقل شده؛ DefaultLeaf* به‌عنوان dump ممنوع است

        Try
            Dim proof = Await Task.Run(Function() New BalanceProofService().BuildHolooProof(session.SqlSettings, businessId), ct).ConfigureAwait(False)
            Dim proofPath = New BalanceProofService().SaveReport(proof, businessId, session.SelectedDatabase)
            RaiseProgress("اثبات تراز", 0, 0, "گزارش پارتیشن هلو ذخیره شد: " & proofPath)
        Catch ex As Exception
            RaiseProgress("اثبات تراز", 0, 0, "هشدار گزارش اثبات: " & ex.Message, True)
        End Try

        Dim accountCodeMap As Dictionary(Of String, Integer) = Nothing
        Dim catalog As SarfaslCatalog = Nothing
        Dim profile = session.SarfaslProfile
        If mods.Contains(MigrationModule.ExpenseIncome) OrElse
           mods.Contains(MigrationModule.FiscalYearsAndOpening) OrElse
           mods.Contains(MigrationModule.ManualJournals) Then
            accountCodeMap = Await api.ListAccountCodeMapAsync(businessId, ct).ConfigureAwait(False)
            catalog = New SarfaslCatalog(api, businessId, accountCodeMap)
        End If

        Dim moneyToCurrency As Dictionary(Of Integer, Integer) = Nothing
        Dim isMultiCurrency = String.Equals(session.Preflight?.CurrencyMode?.Mode, "MultiCurrency", StringComparison.OrdinalIgnoreCase)
        If isMultiCurrency Then
            moneyToCurrency = Await BuildHolooMoneyToCurrencyMapAsync(session, api, currencyId, ct).ConfigureAwait(False)
        End If

        Dim firstYear = True
        Dim earliestStart = years.Min(Function(y) y.StartDate)
        For Each fy In years.OrderBy(Function(y) y.StartDate)
            ct.ThrowIfCancellationRequested()
            If fy.HesabixId <= 0 Then
                RaiseProgress(fy.Title, 0, 0, "شناسه سال مالی حسابیکس نامشخص — رد شد", True)
                Continue For
            End If

            RaiseProgress(fy.Title, 0, 0, "تعویض نرم سال مالی جاری...")
            Await api.SetCurrentFiscalYearAsync(businessId, fy.HesabixId, ct).ConfigureAwait(False)

            If firstYear AndAlso mods.Contains(MigrationModule.FiscalYearsAndOpening) Then
                Await TransferOpeningBalance(
                    session, api, businessId, currencyId, fy,
                    personMap, bankMap, cashMap, pettyMap, warehouseMap, productMap,
                    mapper, accountCodeMap, catalog, profile,
                    cp, store, ct).ConfigureAwait(False)
            End If

            Dim yearInvoiceIds As New List(Of Integer)

            If mods.Contains(MigrationModule.Invoices) Then
                yearInvoiceIds = Await TransferInvoicesForYear(
                    session, api, businessId, currencyId, fy,
                    personMap, productMap, invoiceMap, mapper,
                    defaultCashId, defaultBankId, defaultPettyId,
                    moneyToCurrency, isMultiCurrency,
                    cp, store, ct).ConfigureAwait(False)
            End If

            If mods.Contains(MigrationModule.WarehouseDocs) Then
                Dim whIds = yearInvoiceIds
                If whIds.Count = 0 AndAlso mods.Contains(MigrationModule.Invoices) Then
                    ' resume: فاکتورهای قبلاً منتقل‌شده همین سال را هم حواله کن
                    Dim yearRows = Await Task.Run(Function() _docs.ReadInvoicesInRange(session.SqlSettings, fy.StartDate, fy.EndDate), ct).ConfigureAwait(False)
                    whIds = yearRows.
                        Where(Function(r) invoiceMap.Done.ContainsKey(r.Key)).
                        Select(Function(r) invoiceMap.Done(r.Key)).
                        Where(Function(id) id > 0).
                        Distinct().
                        ToList()
                End If
                If whIds.Count > 0 Then
                    Await PostWarehouseForInvoices(api, businessId, whIds, cp, store, ct).ConfigureAwait(False)
                End If
            End If

            If mods.Contains(MigrationModule.ReceiptsPayments) Then
                Await TransferStandaloneReceipts(
                    session, api, businessId, currencyId, fy,
                    personMap, mapper, defaultCashId, defaultBankId, defaultPettyId,
                    cp, store, ct).ConfigureAwait(False)
            End If

            If mods.Contains(MigrationModule.Checks) Then
                Await TransferChecksForYear(
                    session, api, businessId, currencyId, fy,
                    personMap, mapper, defaultBankId,
                    earliestStart, firstYear,
                    cp, store, ct).ConfigureAwait(False)
            End If

            If mods.Contains(MigrationModule.ExpenseIncome) Then
                Await TransferExpenseIncomeForYear(
                    session, api, businessId, currencyId, fy,
                    personMap, mapper, accountCodeMap, catalog, profile,
                    defaultCashId, defaultBankId, defaultPettyId,
                    cp, store, ct).ConfigureAwait(False)
            End If

            If mods.Contains(MigrationModule.ManualJournals) Then
                Await TransferManualJournalsForYear(
                    session, api, businessId, currencyId, fy,
                    personMap, mapper, accountCodeMap, catalog, profile,
                    defaultCashId, defaultBankId, defaultPettyId,
                    cp, store, ct).ConfigureAwait(False)
            End If

            firstYear = False
            RaiseProgress(fy.Title, 1, 1, "پایان پردازش سال")
        Next

        If mods.Contains(MigrationModule.Invoices) AndAlso SampleLimit <= 0 AndAlso invoiceMap.Failed.Count = 0 Then
            invoiceMap.Completed = True
            store.Save(cp)
        End If

        Return store.FilePath
    End Function

    Private Async Function EnsureFiscalYears(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        years As List(Of DetectedFiscalYear),
        ct As CancellationToken
    ) As Task
        ' سال پیش‌فرض کسب‌وکار جدید اغلب با آخرین سال هلو همپوشانی دارد؛ قبل از ensure جابه‌جا می‌کنیم.
        Await AlignDefaultFiscalYearForMigration(api, businessId, years, ct).ConfigureAwait(False)

        Dim slices = years.Select(Function(y) New HolooFiscalYearSlice With {
            .Title = y.Title,
            .StartDate = y.StartDate,
            .EndDate = y.EndDate
        }).ToList()
        RaiseProgress("سال مالی", 0, years.Count, "ایجاد/بازیابی سال‌های مالی...")
        Dim ensured = Await api.EnsureFiscalYearsAsync(businessId, slices, years.First().StartDate, ct).ConfigureAwait(False)
        ApplyFiscalYearIds(years, ensured.Items)

        If years.Any(Function(y) y.HesabixId <= 0) Then
            Dim listed = Await api.ListFiscalYearsAsync(businessId, ct).ConfigureAwait(False)
            ApplyFiscalYearIds(years, listed)
        End If

        Dim unresolved = years.Where(Function(y) y.HesabixId <= 0).Select(Function(y) y.Title).ToList()
        If unresolved.Count > 0 Then
            RaiseProgress("سال مالی", years.Count, years.Count,
                          "آماده: ایجاد " & ensured.CreatedCount.ToString() & " / موجود " & ensured.ReusedCount.ToString() &
                          " — بدون شناسه: " & String.Join("، ", unresolved), True)
        Else
            RaiseProgress("سال مالی", years.Count, years.Count,
                          "آماده: ایجاد " & ensured.CreatedCount.ToString() & " / موجود " & ensured.ReusedCount.ToString() &
                          " — همه " & years.Count.ToString() & " سال نگاشت شد")
        End If
    End Function

    Private Async Function AlignDefaultFiscalYearForMigration(
        api As HesabixApiClient,
        businessId As Integer,
        years As List(Of DetectedFiscalYear),
        ct As CancellationToken
    ) As Task
        If years Is Nothing OrElse years.Count = 0 Then Return
        Dim listed As List(Of HesabixFiscalYear) = Nothing
        Try
            listed = Await api.ListFiscalYearsAsync(businessId, ct).ConfigureAwait(False)
        Catch
            Return
        End Try
        If listed Is Nothing OrElse listed.Count <> 1 Then Return

        Dim only = listed(0)
        Dim existingStart As Date
        Dim existingEnd As Date
        If Not TryParseApiDate(If(Not String.IsNullOrWhiteSpace(only.StartDate), only.StartDate, ""), existingStart) Then Return
        ' end از raw ترجیح دارد؛ اگر نبود از Start+1year تقریبی کافی نیست — فقط با start چک همپوشانی
        Dim endRawOk = TryParseApiDate(If(only.EndDate, ""), existingEnd)
        If Not endRawOk Then existingEnd = existingStart.AddYears(1).AddDays(-1)

        Dim overlaps = years.Any(Function(y) y.StartDate <= existingEnd AndAlso y.EndDate >= existingStart)
        If Not overlaps Then Return

        Dim first = years.OrderBy(Function(y) y.StartDate).First()
        RaiseProgress("سال مالی", 0, years.Count,
                      "سال پیش‌فرض همپوشان یافت شد — تنظیم به «" & first.Title & "»...")
        Try
            Await api.UpdateCurrentFiscalYearAsync(businessId, first.Title, first.StartDate, first.EndDate, ct).ConfigureAwait(False)
            first.HesabixId = only.Id
        Catch ex As Exception
            RaiseProgress("سال مالی", 0, years.Count, "هشدار تنظیم سال پیش‌فرض: " & ex.Message, True)
        End Try
    End Function

    Private Shared Sub ApplyFiscalYearIds(years As List(Of DetectedFiscalYear), items As IEnumerable(Of HesabixFiscalYear))
        If items Is Nothing Then Return
        For Each item In items
            If item Is Nothing OrElse item.Id <= 0 Then Continue For
            Dim match = MatchDetectedFiscalYear(years, item)
            If match IsNot Nothing AndAlso match.HesabixId <= 0 Then
                match.HesabixId = item.Id
            End If
        Next
    End Sub

    Private Shared Function MatchDetectedFiscalYear(years As List(Of DetectedFiscalYear), item As HesabixFiscalYear) As DetectedFiscalYear
        Dim startParsed As Date
        If TryParseApiDate(item.StartDate, startParsed) Then
            Dim byDate = years.FirstOrDefault(Function(y) y.HesabixId <= 0 AndAlso y.StartDate = startParsed.Date)
            If byDate IsNot Nothing Then Return byDate
            ' تحمل یک روز اختلاف به‌خاطر timezone/جلالی
            byDate = years.FirstOrDefault(Function(y) y.HesabixId <= 0 AndAlso Math.Abs((y.StartDate - startParsed.Date).TotalDays) <= 1)
            If byDate IsNot Nothing Then Return byDate
        End If
        If Not String.IsNullOrWhiteSpace(item.Title) Then
            Dim byTitle = years.FirstOrDefault(Function(y) y.HesabixId <= 0 AndAlso
                String.Equals(y.Title.Trim(), item.Title.Trim(), StringComparison.OrdinalIgnoreCase))
            If byTitle IsNot Nothing Then Return byTitle
        End If
        Return Nothing
    End Function

    Private Shared Function TryParseApiDate(value As String, ByRef parsed As Date) As Boolean
        parsed = Date.MinValue
        If String.IsNullOrWhiteSpace(value) Then Return False
        Dim s = value.Trim()
        ' ترجیح ISO گریگوری: yyyy-MM-dd
        Dim exact As Date
        If Date.TryParseExact(s, "yyyy-MM-dd", Globalization.CultureInfo.InvariantCulture,
                              Globalization.DateTimeStyles.None, exact) Then
            parsed = exact.Date
            Return True
        End If
        If Date.TryParseExact(s, "yyyy-MM-ddTHH:mm:ss", Globalization.CultureInfo.InvariantCulture,
                              Globalization.DateTimeStyles.AssumeUniversal Or Globalization.DateTimeStyles.AdjustToUniversal, exact) Then
            parsed = exact.Date
            Return True
        End If
        ' جلالی نمایشی مثل 1402/01/01 را عمداً رد می‌کنیم تا با سال میلادی اشتباه نشود
        If s.Contains("/"c) AndAlso s.Length >= 8 Then
            Dim parts = s.Split("/"c)
            Dim yPart As Integer
            If parts.Length >= 1 AndAlso Integer.TryParse(parts(0), yPart) AndAlso yPart > 1300 AndAlso yPart < 1600 Then
                Return False
            End If
        End If
        If Date.TryParse(s, Globalization.CultureInfo.InvariantCulture, Globalization.DateTimeStyles.AssumeLocal, exact) Then
            parsed = exact.Date
            Return True
        End If
        Return False
    End Function

    Private Async Function TransferOpeningBalance(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        bankMap As ModuleCheckpoint,
        cashMap As ModuleCheckpoint,
        pettyMap As ModuleCheckpoint,
        warehouseMap As ModuleCheckpoint,
        productMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        accountCodeMap As Dictionary(Of String, Integer),
        catalog As SarfaslCatalog,
        profile As SarfaslProfile,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.FiscalYearsAndOpening.ToString())
        Dim obKey = "OB:" & fy.HesabixId.ToString()
        If modCp.Done.ContainsKey(obKey) Then
            RaiseProgress("افتتاحیه", 0, 0, "قبلاً ثبت شده — رد شد")
            Return
        End If

        Dim sanadCode = Await Task.Run(Function() _docs.FindOpeningSanadCode(session.SqlSettings), ct).ConfigureAwait(False)
        If sanadCode <= 0 Then
            RaiseProgress("افتتاحیه", 0, 0, "سند افتتاحیه در هلو یافت نشد — رد شد", True)
            Return
        End If
        Dim lines = Await Task.Run(Function() _docs.ReadOpeningLines(session.SqlSettings, sanadCode), ct).ConfigureAwait(False)
        RaiseProgress("افتتاحیه", 0, lines.Count, "ساخت تراز افتتاحیه از سند " & sanadCode.ToString() & "...")

        Dim arId = Await ResolveAccountId(accountCodeMap, api, businessId, "10401", ct).ConfigureAwait(False)
        Dim apId = Await ResolveAccountId(accountCodeMap, api, businessId, "20201", ct).ConfigureAwait(False)
        Dim bankAccId = Await ResolveAccountId(accountCodeMap, api, businessId, "10203", ct).ConfigureAwait(False)
        Dim cashAccId = Await ResolveAccountId(accountCodeMap, api, businessId, "10202", ct).ConfigureAwait(False)
        Dim pettyAccId = Await ResolveAccountId(accountCodeMap, api, businessId, "10201", ct).ConfigureAwait(False)
        Dim invAccId = Await ResolveAccountId(accountCodeMap, api, businessId, "10102", ct).ConfigureAwait(False)
        Dim notesPayId = Await ResolveAccountId(accountCodeMap, api, businessId, "20202", ct).ConfigureAwait(False)
        Dim equityId = Await ResolveAccountId(accountCodeMap, api, businessId, "30106", ct).ConfigureAwait(False)
        If equityId <= 0 Then equityId = Await ResolveAccountId(accountCodeMap, api, businessId, "30101", ct).ConfigureAwait(False)

        Dim merged As New Dictionary(Of String, ObMergeBucket)(StringComparer.Ordinal)
        Dim skipped = 0
        Dim blockReasons As New List(Of String)

        For Each ln In lines
            If ln.Debit <= 0 AndAlso ln.Credit <= 0 Then Continue For
            Dim col = If(ln.ColCode, "").Trim()
            If col = "005" OrElse col = "006" Then Continue For

            If col = "401" AndAlso mapper.IsLoan401(ln.MoienCode) Then
                Dim loanAcctId As Integer = 0
                If catalog IsNot Nothing Then
                    loanAcctId = Await catalog.EnsureLoanBusinessAccountAsync(ln.MoienCode, ln.SarfaslName, ct).ConfigureAwait(False)
                End If
                If loanAcctId <= 0 Then
                    skipped += 1
                    blockReasons.Add("وام بدون حساب: " & ln.SarfaslName)
                    Continue For
                End If
                Dim bLoan = GetOrAddBucket(merged, "A:LOAN:" & ln.MoienCode)
                bLoan.AccountId = loanAcctId
                bLoan.AccountCode = HolooSarfaslMapper.SuggestBusinessLoanCode(ln.MoienCode)
                bLoan.Debit += ln.Debit
                bLoan.Credit += ln.Credit
                bLoan.Description = If(String.IsNullOrWhiteSpace(bLoan.Description), If(ln.SarfaslName, ln.Comment), bLoan.Description)

            ElseIf col = "103" OrElse col = "401" Then
                Dim personId = mapper.ResolvePersonOnCol(col, ln.MoienCode)
                If personId <= 0 Then personId = ResolvePersonByMoien(personMap, ln.MoienCode)
                If personId <= 0 Then
                    skipped += 1
                    blockReasons.Add("شخص یافت نشد: " & col & "|" & ln.MoienCode & " " & ln.SarfaslName)
                    Continue For
                End If
                Dim b = GetOrAddBucket(merged, "P:" & personId.ToString())
                b.PersonId = personId
                b.IsApSide = (col = "401") OrElse b.IsApSide
                b.Debit += ln.Debit
                b.Credit += ln.Credit
                b.Description = If(String.IsNullOrWhiteSpace(b.Description), If(ln.SarfaslName, ln.Comment), b.Description)

            ElseIf col = "102" Then
                Dim bankId = mapper.ResolveBank(col, ln.MoienCode, ln.TafziliCode, Nothing, ln.SarfaslName)
                If bankAccId <= 0 OrElse bankId <= 0 Then
                    skipped += 1
                    blockReasons.Add("بانک نگاشت نشد: " & ln.SarfaslName)
                    Continue For
                End If
                Dim b = GetOrAddBucket(merged, "B:" & bankId.ToString())
                b.BankAccountId = bankId
                b.AccountId = bankAccId
                b.Debit += ln.Debit
                b.Credit += ln.Credit
                b.Description = If(String.IsNullOrWhiteSpace(b.Description), If(ln.SarfaslName, ln.Comment), b.Description)

            ElseIf col = "101" Then
                Dim isPetty As Boolean
                Dim cashOrPettyId = mapper.ResolveCashOrPetty(col, ln.MoienCode, ln.TafziliCode, isPetty)
                Dim acct = If(isPetty, pettyAccId, cashAccId)
                If acct <= 0 OrElse cashOrPettyId <= 0 Then
                    skipped += 1
                    blockReasons.Add("صندوق/تنخواه نگاشت نشد: " & ln.SarfaslName)
                    Continue For
                End If
                Dim b = GetOrAddBucket(merged, If(isPetty, "T:", "C:") & cashOrPettyId.ToString())
                b.AccountId = acct
                If isPetty Then b.PettyCashId = cashOrPettyId Else b.CashRegisterId = cashOrPettyId
                b.Debit += ln.Debit
                b.Credit += ln.Credit
                b.Description = If(String.IsNullOrWhiteSpace(b.Description), If(ln.SarfaslName, ln.Comment), b.Description)

            ElseIf col = "402" Then
                If notesPayId <= 0 Then
                    skipped += 1
                    blockReasons.Add("اسناد پرداختنی (402) — حساب 20202 یافت نشد")
                    Continue For
                End If
                Dim b = GetOrAddBucket(merged, "A:20202")
                b.AccountId = notesPayId
                b.AccountCode = "20202"
                b.Debit += ln.Debit
                b.Credit += ln.Credit
                b.Description = If(String.IsNullOrWhiteSpace(b.Description), If(ln.SarfaslName, "اسناد پرداختنی"), b.Description)

            Else
                Dim code = ResolveMappedAccountCode(profile, col, ln.MoienCode, ln.SarfaslName)
                If String.IsNullOrWhiteSpace(code) Then
                    skipped += 1
                    blockReasons.Add("سرفصل بدون نگاشت: " & col & "|" & ln.MoienCode & " " & ln.SarfaslName)
                    Continue For
                End If
                Dim acctId As Integer = 0
                If accountCodeMap Is Nothing OrElse Not accountCodeMap.TryGetValue(code, acctId) OrElse acctId <= 0 Then
                    acctId = Await ResolveAccountId(accountCodeMap, api, businessId, code, ct).ConfigureAwait(False)
                End If
                If acctId <= 0 Then
                    skipped += 1
                    blockReasons.Add("کد حسابیکس یافت نشد: " & code)
                    Continue For
                End If
                Dim b = GetOrAddBucket(merged, "A:" & code)
                b.AccountId = acctId
                b.AccountCode = code
                b.Debit += ln.Debit
                b.Credit += ln.Credit
                b.Description = If(String.IsNullOrWhiteSpace(b.Description), If(ln.SarfaslName, ln.Comment), b.Description)
            End If
        Next

        If blockReasons.Count > 0 Then
            RaiseProgress("افتتاحیه", 0, 0,
                          "نگاشت ناقص — افتتاحیه ثبت نمی‌شود (" & blockReasons.Count.ToString() & "): " &
                          String.Join("؛ ", blockReasons.Take(8)), True)
            modCp.Failed(obKey) = "خطوط نگاشت‌نشده: " & blockReasons.Count.ToString()
            store.Save(cp)
            Return
        End If

        Dim accountLines As New JArray()
        For Each kv In merged
            Dim b = kv.Value
            Dim debit = ApiDateFormat.RoundMoney(b.Debit)
            Dim credit = ApiDateFormat.RoundMoney(b.Credit)
            If debit > 0 AndAlso credit > 0 Then
                If debit >= credit Then
                    debit = ApiDateFormat.RoundMoney(debit - credit)
                    credit = 0
                Else
                    credit = ApiDateFormat.RoundMoney(credit - debit)
                    debit = 0
                End If
            End If
            If debit <= 0 AndAlso credit <= 0 Then Continue For

            If b.PersonId > 0 Then
                Dim preferAp = b.IsApSide OrElse credit > debit
                Dim acctId = If(preferAp, apId, arId)
                If acctId <= 0 Then acctId = If(debit >= credit, arId, apId)
                If acctId <= 0 Then Continue For
                accountLines.Add(New JObject From {
                    {"account_id", acctId},
                    {"person_id", b.PersonId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", b.Description}
                })
            ElseIf b.BankAccountId > 0 Then
                accountLines.Add(New JObject From {
                    {"account_id", If(b.AccountId > 0, b.AccountId, bankAccId)},
                    {"bank_account_id", b.BankAccountId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", b.Description}
                })
            ElseIf b.CashRegisterId > 0 OrElse b.PettyCashId > 0 Then
                Dim jo As New JObject From {
                    {"account_id", b.AccountId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", b.Description}
                }
                If b.CashRegisterId > 0 Then jo("cash_register_id") = b.CashRegisterId Else jo("petty_cash_id") = b.PettyCashId
                accountLines.Add(jo)
            ElseIf b.AccountId > 0 Then
                accountLines.Add(New JObject From {
                    {"account_id", b.AccountId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", b.Description}
                })
            End If
        Next

        ' مقدار کالا برای کاردکس؛ cost_price=0 تا GL موجودی از Col106 دوبل نشود
        Dim inventoryLines As New JArray()
        Dim defaultWhId = If(warehouseMap.Done.Count = 1, warehouseMap.Done.Values.First(), 0)
        Dim qtyRows = Await Task.Run(Function() _docs.ReadProductOpeningQuantities(session.SqlSettings), ct).ConfigureAwait(False)
        For Each q In qtyRows
            Dim productId As Integer = 0
            If Not productMap.Done.TryGetValue(q.Item1, productId) OrElse productId <= 0 Then Continue For
            Dim whId As Integer = 0
            If q.Item4.HasValue AndAlso warehouseMap.Done.ContainsKey(q.Item4.Value.ToString()) Then
                whId = warehouseMap.Done(q.Item4.Value.ToString())
            ElseIf defaultWhId > 0 Then
                whId = defaultWhId
            End If
            If whId <= 0 Then Continue For
            inventoryLines.Add(New JObject From {
                {"product_id", productId},
                {"quantity", Math.Round(q.Item2, 4)},
                {"description", "موجودی اول دوره Holoo"},
                {"extra_info", New JObject From {
                    {"warehouse_id", whId},
                    {"movement", "in"},
                    {"cost_price", 0}
                }}
            })
        Next

        If accountLines.Count < 2 AndAlso inventoryLines.Count = 0 Then
            RaiseProgress("افتتاحیه", 0, 0, "خطوط قابل نگاشت کافی نیست (رد شده: " & skipped.ToString() & ")", True)
            Return
        End If

        ' بستن اختلاف ریالی در کلاینت تا به وابستگی نسخه سرور (تلرانس 0.01) نباشد
        If equityId > 0 AndAlso accountLines.Count > 0 Then
            Dim sumDebit As Double = 0
            Dim sumCredit As Double = 0
            For Each lnTok As JToken In accountLines
                Dim ln = TryCast(lnTok, JObject)
                If ln Is Nothing Then Continue For
                sumDebit += CDbl(If(ln("debit"), 0))
                sumCredit += CDbl(If(ln("credit"), 0))
            Next
            Dim balDiff = ApiDateFormat.RoundMoney(sumDebit - sumCredit)
            If Math.Abs(balDiff) >= 0.01 Then
                If balDiff > 0 Then
                    accountLines.Add(New JObject From {
                        {"account_id", equityId},
                        {"debit", 0},
                        {"credit", balDiff},
                        {"description", "بستن اختلاف تراز افتتاحیه (مهاجرت)"}
                    })
                Else
                    accountLines.Add(New JObject From {
                        {"account_id", equityId},
                        {"debit", Math.Abs(balDiff)},
                        {"credit", 0},
                        {"description", "بستن اختلاف تراز افتتاحیه (مهاجرت)"}
                    })
                End If
                RaiseProgress("افتتاحیه", 0, 0, "اختلاف " & balDiff.ToString("0.00") & " به حقوق صاحبان سهام بسته شد")
            End If
        End If

        Dim payload As New JObject From {
            {"fiscal_year_id", fy.HesabixId},
            {"document_date", ApiDateFormat.ToIsoDate(fy.StartDate)},
            {"currency_id", currencyId},
            {"account_lines", accountLines},
            {"inventory_lines", inventoryLines},
            {"auto_balance_to_equity", True}
        }
        If invAccId > 0 Then payload("inventory_account_id") = invAccId
        If equityId > 0 Then payload("equity_account_id") = equityId

        Try
            Await api.UpsertOpeningBalanceAsync(businessId, payload, ct).ConfigureAwait(False)
            Await api.PostOpeningBalanceAsync(businessId, fy.HesabixId, ct).ConfigureAwait(False)
            modCp.Done(obKey) = fy.HesabixId
            modCp.Failed.Remove(obKey)
            If modCp.Failed.Count = 0 Then modCp.Completed = True
            store.Save(cp)
            RaiseProgress("افتتاحیه", accountLines.Count, accountLines.Count,
                          "ثبت شد: " & accountLines.Count.ToString() & " خط حساب + " & inventoryLines.Count.ToString() &
                          " قلم موجودی (رد " & skipped.ToString() & ")")
        Catch ex As Exception
            modCp.Failed(obKey) = ex.Message
            store.Save(cp)
            RaiseProgress("افتتاحیه", 0, 0, "خطا: " & ex.Message, True)
        End Try
    End Function

    Private Shared Function GetOrAddBucket(merged As Dictionary(Of String, ObMergeBucket), key As String) As ObMergeBucket
        Dim b As ObMergeBucket = Nothing
        If Not merged.TryGetValue(key, b) Then
            b = New ObMergeBucket()
            merged(key) = b
        End If
        Return b
    End Function

    Private Class ObMergeBucket
        Public Property AccountId As Integer
        Public Property AccountCode As String
        Public Property PersonId As Integer
        Public Property BankAccountId As Integer
        Public Property CashRegisterId As Integer
        Public Property PettyCashId As Integer
        Public Property IsApSide As Boolean
        Public Property Debit As Double
        Public Property Credit As Double
        Public Property Description As String
    End Class

    Private Shared Async Function ResolveAccountId(
        map As Dictionary(Of String, Integer),
        api As HesabixApiClient,
        businessId As Integer,
        code As String,
        ct As CancellationToken
    ) As Task(Of Integer)
        Dim id As Integer
        If map IsNot Nothing AndAlso map.TryGetValue(code, id) AndAlso id > 0 Then Return id
        Return Await api.FindAccountIdByCodeAsync(businessId, code, ct).ConfigureAwait(False)
    End Function

    Private Async Function TransferInvoicesForYear(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        productMap As ModuleCheckpoint,
        invoiceMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        moneyToCurrency As Dictionary(Of Integer, Integer),
        isMultiCurrency As Boolean,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task(Of List(Of Integer))
        Dim createdIds As New List(Of Integer)
        RaiseProgress("فاکتور " & fy.Title, 0, 0, "خواندن فاکتورها از هلو...")
        Dim rows = Await Task.Run(Function() _docs.ReadInvoicesInRange(session.SqlSettings, fy.StartDate, fy.EndDate), ct).ConfigureAwait(False)
        Dim settleMap = Await Task.Run(
            Function() _docs.ReadSettlementHintsForSanads(session.SqlSettings, rows.Select(Function(r) r.SanadCode)),
            ct).ConfigureAwait(False)
        Dim pendingRaw = rows.Where(Function(r) Not invoiceMap.Done.ContainsKey(r.Key)).ToList()
        Dim pending As List(Of HolooInvoiceHeader)
        If SampleLimit > 0 AndAlso pendingRaw.Count > SampleLimit Then
            ' از هر Fac_Type تا SampleLimit نمونه (مثلاً ۲ فروش + ۲ خرید)
            pending = pendingRaw.
                GroupBy(Function(r) If(r.FacType, "").Trim().ToUpperInvariant()).
                SelectMany(Function(g) g.OrderBy(Function(x) x.FacDate).Take(SampleLimit)).
                OrderBy(Function(x) x.FacDate).ThenBy(Function(x) x.FacCode).
                ToList()
            RaiseProgress("فاکتور " & fy.Title, 0, pendingRaw.Count,
                          "حالت نمونه: " & pending.Count.ToString() & " فاکتور متنوع از " & pendingRaw.Count.ToString())
        Else
            pending = pendingRaw
        End If
        RaiseProgress("فاکتور " & fy.Title, invoiceMap.Done.Count, rows.Count,
                      "آماده‌سازی " & pending.Count.ToString() & " فاکتور (از " & rows.Count.ToString() & ")...")

        Dim queue As New ConcurrentQueue(Of PreparedInvoiceItem)()
        Dim processed = rows.Count - pending.Count
        For Each inv In pending
            ct.ThrowIfCancellationRequested()
            Dim hint As HolooInvoiceSettlementHint = Nothing
            If inv.SanadCode > 0 Then settleMap.TryGetValue(inv.SanadCode, hint)
            Dim failReason As String = Nothing
            Dim payload = BuildInvoicePayload(
                inv, currencyId, personMap, productMap, mapper, hint,
                defaultCashId, defaultBankId, defaultPettyId,
                moneyToCurrency, isMultiCurrency, failReason)
            If payload Is Nothing Then
                invoiceMap.Failed(inv.Key) = If(failReason, "نگاشت شخص/کالا/تسویه ناقص یا نوع نامعتبر")
                processed += 1
                RaiseProgress("فاکتور " & fy.Title, processed, rows.Count, "رد: " & inv.Key & " — " & invoiceMap.Failed(inv.Key), True)
                Continue For
            End If
            queue.Enqueue(New PreparedInvoiceItem With {
                .Key = inv.Key,
                .Payload = payload
            })
        Next

        Dim workerCount = Math.Max(1, Math.Min(InvoiceParallelism, Math.Max(1, queue.Count)))
        RaiseProgress("فاکتور " & fy.Title, processed, rows.Count,
                      "ارسال موازی " & queue.Count.ToString() & " فاکتور با " & workerCount.ToString() & " کارگر...")

        Dim state As New InvoiceParallelState With {
            .Processed = processed,
            .TotalRows = rows.Count,
            .ModuleTitle = "فاکتور " & fy.Title,
            .Gate = New Object(),
            .CreatedIds = createdIds,
            .SuccessSinceSave = 0
        }

        Dim workers As New List(Of Task)()
        For i = 1 To workerCount
            workers.Add(InvoiceWorkerLoopAsync(api, businessId, fy, queue, invoiceMap, store, cp, state, ct))
        Next
        Await Task.WhenAll(workers.ToArray()).ConfigureAwait(False)

        SyncLock state.Gate
            store.Save(cp)
        End SyncLock
        RaiseProgress(state.ModuleTitle, state.Processed, state.TotalRows,
                      "پایان فاکتور سال: موفق " & invoiceMap.Done.Count.ToString() &
                      " / شکست " & invoiceMap.Failed.Count.ToString())
        Return createdIds
    End Function

    Private Class PreparedInvoiceItem
        Public Property Key As String
        Public Property Payload As JObject
    End Class

    Private Class InvoiceParallelState
        Public Property Processed As Integer
        Public Property TotalRows As Integer
        Public Property ModuleTitle As String
        Public Property Gate As Object
        Public Property CreatedIds As List(Of Integer)
        Public Property SuccessSinceSave As Integer
    End Class

    Private Async Function InvoiceWorkerLoopAsync(
        api As HesabixApiClient,
        businessId As Integer,
        fy As DetectedFiscalYear,
        queue As ConcurrentQueue(Of PreparedInvoiceItem),
        invoiceMap As ModuleCheckpoint,
        store As CheckpointStore,
        cp As TransferCheckpoint,
        state As InvoiceParallelState,
        ct As CancellationToken
    ) As Task
        While True
            ct.ThrowIfCancellationRequested()
            Dim batch As New List(Of PreparedInvoiceItem)()
            Dim one As PreparedInvoiceItem = Nothing
            While batch.Count < InvoiceChunk AndAlso queue.TryDequeue(one)
                batch.Add(one)
            End While
            If batch.Count = 0 Then Exit While

            Dim items As New JArray()
            Dim keys As New List(Of String)()
            For Each it In batch
                items.Add(New JObject From {
                    {"client_ref", it.Key},
                    {"payload", it.Payload}
                })
                keys.Add(it.Key)
            Next

            Dim localProcessed As New IntHolder With {.Value = 0}
            Dim localCreated As New List(Of Integer)()
            Dim localMap As New ModuleCheckpoint()

            ' heartbeat: suppressProgress hides per-batch noise, but long API waits must still surface
            SyncLock state.Gate
                RaiseProgress(state.ModuleTitle, state.Processed, state.TotalRows,
                              "ارسال دسته " & batch.Count.ToString() & " فاکتور (صف ~" & queue.Count.ToString() & ")...")
            End SyncLock

            Await SendInvoiceChunkWithRetry(
                api, businessId, fy, items, keys, localMap, localCreated, localProcessed, state.TotalRows, store, cp, ct,
                skipCheckpointSave:=True, suppressProgress:=True).ConfigureAwait(False)

            Dim showProgress As Boolean = False
            Dim progressCurrent As Integer = 0
            Dim progressMsg As String = Nothing
            Dim progressIsError As Boolean = False

            SyncLock state.Gate
                For Each k In keys
                    state.Processed += 1
                    Dim doneId As Integer = 0
                    Dim failMsg As String = Nothing
                    If localMap.Done.TryGetValue(k, doneId) AndAlso doneId > 0 Then
                        invoiceMap.Done(k) = doneId
                        invoiceMap.Failed.Remove(k)
                        state.CreatedIds.Add(doneId)
                        state.SuccessSinceSave += 1
                    ElseIf localMap.Failed.TryGetValue(k, failMsg) Then
                        invoiceMap.Failed(k) = If(failMsg, "خطا")
                        progressIsError = True
                        progressMsg = "خطا: " & k & " — " & invoiceMap.Failed(k)
                        state.SuccessSinceSave = 0
                    Else
                        ' timeout رها‌شده: Failed نکن تا resume بعدی دوباره صف کند
                        state.Processed -= 1
                        state.SuccessSinceSave = 0
                    End If
                Next
                progressCurrent = state.Processed
                If state.SuccessSinceSave >= 5 OrElse (state.Processed Mod 10 = 0) OrElse progressIsError Then
                    store.Save(cp)
                    If Not progressIsError Then state.SuccessSinceSave = 0
                End If
                If progressIsError OrElse state.Processed Mod 5 = 0 OrElse state.Processed >= state.TotalRows Then
                    showProgress = True
                    If Not progressIsError Then
                        progressMsg = "موازی: " & invoiceMap.Done.Count.ToString() & " موفق / صف ~" & queue.Count.ToString()
                    End If
                End If
            End SyncLock

            If showProgress Then
                RaiseProgress(state.ModuleTitle, progressCurrent, state.TotalRows, progressMsg, progressIsError)
            End If
        End While
    End Function

    Private Shared Function IsTransientTimeout(ex As Exception) As Boolean
        If ex Is Nothing Then Return False
        If TypeOf ex Is OperationCanceledException Then
            ' CancelAfter per-request — transient. Parent cancel is checked by caller via ct.
            Return True
        End If
        If TypeOf ex Is TaskCanceledException Then Return True
        If TypeOf ex.InnerException Is TaskCanceledException Then Return True
        If TypeOf ex.InnerException Is OperationCanceledException Then Return True
        If TypeOf ex Is TimeoutException Then Return True
        Dim apiEx = TryCast(ex, HesabixApiException)
        If apiEx IsNot Nothing Then
            If apiEx.StatusCode = 408 OrElse apiEx.StatusCode = 429 OrElse
               apiEx.StatusCode = 500 OrElse
               apiEx.StatusCode = 502 OrElse apiEx.StatusCode = 503 OrElse apiEx.StatusCode = 504 Then
                Return True
            End If
        End If
        Return IsTransientFailureMessage(If(ex.Message, ""))
    End Function

    Private Shared Function IsTransientFailureMessage(msg As String) As Boolean
        If String.IsNullOrWhiteSpace(msg) Then Return False
        Return msg.IndexOf("canceled", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("timeout", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("زمان", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("504", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("502", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("503", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("500", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("internal", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("خطای داخلی", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("خطا داخلي", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("temporarily", StringComparison.OrdinalIgnoreCase) >= 0 OrElse
               msg.IndexOf("Unavailable", StringComparison.OrdinalIgnoreCase) >= 0
    End Function

    Private Async Function SendInvoiceChunkWithRetry(
        api As HesabixApiClient,
        businessId As Integer,
        fy As DetectedFiscalYear,
        items As JArray,
        chunkKeys As List(Of String),
        invoiceMap As ModuleCheckpoint,
        createdIds As List(Of Integer),
        processedHolder As IntHolder,
        totalRows As Integer,
        store As CheckpointStore,
        cp As TransferCheckpoint,
        ct As CancellationToken,
        Optional skipCheckpointSave As Boolean = False,
        Optional suppressProgress As Boolean = False
    ) As Task
        If items Is Nothing OrElse items.Count = 0 Then Return

            Dim attempt = 0
            Const maxAttempts As Integer = 5
            While attempt < maxAttempts
            attempt += 1
            If ct.IsCancellationRequested Then Throw New OperationCanceledException(ct)
            Dim bulk As BulkUpsertResult = Nothing
            Dim sendErr As Exception = Nothing
            Try
                Using invCts = CancellationTokenSource.CreateLinkedTokenSource(ct)
                    invCts.CancelAfter(TimeSpan.FromSeconds(InvoiceRequestTimeoutSeconds))
                    bulk = Await api.BulkUpsertInvoicesAsync(businessId, items, invCts.Token).ConfigureAwait(False)
                End Using
            Catch ex As Exception
                If ct.IsCancellationRequested Then Throw
                sendErr = ex
            End Try

            If sendErr Is Nothing AndAlso bulk IsNot Nothing Then
                Dim byClientRef = IndexByClientRef(bulk)
                Dim retryItems As New JArray()
                Dim retryKeys As New List(Of String)()
                For i = 0 To chunkKeys.Count - 1
                    Dim k = chunkKeys(i)
                    Dim r = ResolveItem(byClientRef, bulk, i, k)
                    If r IsNot Nothing AndAlso r.IsSuccess AndAlso r.EntityId > 0 Then
                        processedHolder.Value += 1
                        invoiceMap.Done(k) = r.EntityId
                        invoiceMap.Failed.Remove(k)
                        createdIds.Add(r.EntityId)
                    Else
                        Dim msg = If(r Is Nothing, "نتیجه برنگشت", If(r.Message, r.ErrorCode))
                        If IsTransientFailureMessage(If(msg, "")) AndAlso attempt < maxAttempts Then
                            retryItems.Add(items(i))
                            retryKeys.Add(k)
                        Else
                            processedHolder.Value += 1
                            invoiceMap.Failed(k) = If(msg, "خطا")
                            RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows, "خطا: " & k & " — " & invoiceMap.Failed(k), True)
                        End If
                    End If
                Next
                If retryItems.Count > 0 AndAlso attempt < maxAttempts Then
                    Dim delayMs = 2000 * attempt
                    RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows,
                                  "خطای موقت روی " & retryItems.Count.ToString() & " فاکتور — صبر " & (delayMs \ 1000).ToString() & "ث...", True)
                    Await Task.Delay(delayMs, ct).ConfigureAwait(False)
                    items = retryItems
                    chunkKeys = retryKeys
                    Continue While
                End If
                If Not suppressProgress Then
                    RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows,
                                  "دسته: ایجاد " & bulk.Created.ToString() & " / شکست " & bulk.Failed.ToString())
                End If
                If Not skipCheckpointSave Then store.Save(cp)
                Return
            End If

            If IsTransientTimeout(sendErr) AndAlso items.Count > 1 Then
                Dim half = Math.Max(1, items.Count \ 2)
                RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows,
                              "timeout — شکستن دسته به " & half.ToString() & " + " & (items.Count - half).ToString() & "...", True)
                Dim a As New JArray()
                Dim b As New JArray()
                Dim ak As New List(Of String)
                Dim bk As New List(Of String)
                For i = 0 To items.Count - 1
                    If i < half Then
                        a.Add(items(i)) : ak.Add(chunkKeys(i))
                    Else
                        b.Add(items(i)) : bk.Add(chunkKeys(i))
                    End If
                Next
                Await SendInvoiceChunkWithRetry(api, businessId, fy, a, ak, invoiceMap, createdIds, processedHolder, totalRows, store, cp, ct, skipCheckpointSave, suppressProgress).ConfigureAwait(False)
                Await SendInvoiceChunkWithRetry(api, businessId, fy, b, bk, invoiceMap, createdIds, processedHolder, totalRows, store, cp, ct, skipCheckpointSave, suppressProgress).ConfigureAwait(False)
                Return
            End If

            If IsTransientTimeout(sendErr) AndAlso attempt < maxAttempts Then
                Dim delayMs = 3000 * attempt
                RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows,
                              "timeout/504 — صبر " & (delayMs \ 1000).ToString() & "ث و تلاش " & (attempt + 1).ToString() & "...", True)
                Await Task.Delay(delayMs, ct).ConfigureAwait(False)
                Continue While
            End If

            ' timeout مکرر: Failed نکن تا resume بعدی دوباره صف کند
            If IsTransientTimeout(sendErr) Then
                RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows,
                              "timeout پایدار روی " & chunkKeys.Count.ToString() & " فاکتور — برای resume بعدی رها شد", True)
                Return
            End If

            Dim errMsg = If(sendErr Is Nothing, "خطای ناشناخته", sendErr.Message)
            For Each k In chunkKeys
                invoiceMap.Failed(k) = errMsg
                processedHolder.Value += 1
                RaiseProgress("فاکتور " & fy.Title, processedHolder.Value, totalRows, "خطای bulk: " & k & " — " & errMsg, True)
            Next
            If Not skipCheckpointSave Then store.Save(cp)
            Return
        End While
    End Function

    Private Class IntHolder
        Public Property Value As Integer
    End Class

    Private Shared Function BuildInvoicePayload(
        inv As HolooInvoiceHeader,
        currencyId As Integer,
        personMap As ModuleCheckpoint,
        productMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        settleHint As HolooInvoiceSettlementHint,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        moneyToCurrency As Dictionary(Of Integer, Integer),
        isMultiCurrency As Boolean,
        ByRef failReason As String
    ) As JObject
        failReason = Nothing
        Dim invType = HolooDocumentReader.MapFacTypeToInvoiceType(inv.FacType)
        If String.IsNullOrWhiteSpace(invType) Then
            failReason = "نوع فاکتور نامعتبر: " & inv.FacType.ToString()
            Return Nothing
        End If

        Dim needsPerson = HolooDocumentReader.InvoiceRequiresPerson(inv.FacType)
        Dim personId As Integer = 0
        If needsPerson Then
            If Not personMap.Done.TryGetValue(inv.CustomerCode, personId) OrElse personId <= 0 Then
                failReason = "شخص نگاشت نشد: " & inv.CustomerCode
                Return Nothing
            End If
        End If

        Dim invCurrencyId = currencyId
        If isMultiCurrency AndAlso moneyToCurrency IsNot Nothing Then
            Dim foreignCode = inv.Lines.
                Where(Function(ln) ln.MoneyCode > 0 AndAlso moneyToCurrency.ContainsKey(ln.MoneyCode)).
                Select(Function(ln) ln.MoneyCode).
                GroupBy(Function(c) c).
                OrderByDescending(Function(g) g.Count()).
                Select(Function(g) g.Key).
                FirstOrDefault()
            If foreignCode > 0 Then invCurrencyId = moneyToCurrency(foreignCode)
        End If

        Dim lines As New JArray()
        Dim missingProducts As New List(Of String)()
        For Each ln In inv.Lines
            If String.IsNullOrWhiteSpace(ln.ArticleCode) OrElse ln.Quantity = 0 Then Continue For
            Dim productId As Integer = 0
            If Not productMap.Done.TryGetValue(ln.ArticleCode, productId) OrElse productId <= 0 Then
                missingProducts.Add(ln.ArticleCode)
                Continue For
            End If
            Dim unitPrice = ln.UnitPrice
            If isMultiCurrency AndAlso ln.ForeignUnitPrice > 0 AndAlso ln.MoneyCode > 0 AndAlso
               moneyToCurrency IsNot Nothing AndAlso moneyToCurrency.ContainsKey(ln.MoneyCode) AndAlso
               moneyToCurrency(ln.MoneyCode) <> currencyId Then
                unitPrice = ln.ForeignUnitPrice
            End If
            Dim taxAmt = ln.Levy + ln.Scot
            Dim lineExtra As New JObject From {
                {"unit_price", Math.Round(unitPrice, 2)},
                {"line_discount", Math.Round(ln.LineDiscount, 2)},
                {"tax_amount", Math.Round(taxAmt, 2)},
                {"holoo_money_code", ln.MoneyCode}
            }
            lines.Add(New JObject From {
                {"product_id", productId},
                {"quantity", ln.Quantity},
                {"extra_info", lineExtra}
            })
        Next
        If missingProducts.Count > 0 Then
            failReason = "کالای نگاشت‌نشده: " & String.Join(",", missingProducts.Distinct().Take(5))
            Return Nothing
        End If
        If lines.Count = 0 Then
            failReason = "هیچ خط کالای معتبری ندارد"
            Return Nothing
        End If

        Dim cashId = 0
        Dim bankId = 0
        Dim extraUnsettleNote As String = Nothing
        If settleHint IsNot Nothing Then
            If Not String.IsNullOrWhiteSpace(settleHint.CashMoien) Then
                Dim isPetty As Boolean
                Dim resolved = mapper.ResolveCashOrPetty("101", settleHint.CashMoien, settleHint.CashTafzili, isPetty)
                If resolved > 0 Then cashId = resolved
            End If
            If Not String.IsNullOrWhiteSpace(settleHint.BankMoien) OrElse Not String.IsNullOrWhiteSpace(settleHint.BankName) Then
                Dim resolvedBank = mapper.ResolveBank("102", settleHint.BankMoien, settleHint.BankTafzili, Nothing, settleHint.BankName)
                If resolvedBank > 0 Then bankId = resolvedBank
            End If
        End If
        ' بدون dump به sole-default: فقط resolve قطعی از hint/سرفصل

        Dim payments As New JArray()
        If inv.FNaghd > 0 AndAlso cashId > 0 Then
            Dim isPettyPay As Boolean = False
            If settleHint IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(settleHint.CashMoien) Then
                mapper.ResolveCashOrPetty("101", settleHint.CashMoien, settleHint.CashTafzili, isPettyPay)
            End If
            If isPettyPay Then
                payments.Add(New JObject From {
                    {"amount", Math.Round(inv.FNaghd, 2)},
                    {"transaction_type", "petty_cash"},
                    {"petty_cash_id", cashId},
                    {"transaction_date", ApiDateFormat.ToIsoDate(inv.FacDate)}
                })
            Else
                payments.Add(New JObject From {
                    {"amount", Math.Round(inv.FNaghd, 2)},
                    {"transaction_type", "cash_register"},
                    {"cash_register_id", cashId},
                    {"transaction_date", ApiDateFormat.ToIsoDate(inv.FacDate)}
                })
            End If
        ElseIf inv.FNaghd > 0 AndAlso cashId <= 0 Then
            ' تسویه نقد نمی‌نشیند؛ مانده نسیه می‌ماند (کل فاکتور Fail نمی‌شود)
            extraUnsettleNote = "نقد بدون نگاشت صندوق"
        End If
        Dim cardOrHaval = inv.Card + inv.FHaval
        If cardOrHaval > 0 AndAlso bankId > 0 Then
            payments.Add(New JObject From {
                {"amount", Math.Round(cardOrHaval, 2)},
                {"transaction_type", "bank"},
                {"bank_id", bankId},
                {"transaction_date", ApiDateFormat.ToIsoDate(inv.FacDate)}
            })
        ElseIf cardOrHaval > 0 AndAlso bankId <= 0 Then
            If String.IsNullOrWhiteSpace(extraUnsettleNote) Then
                extraUnsettleNote = "کارت/حواله بدون نگاشت بانک"
            Else
                extraUnsettleNote &= "; کارت/حواله بدون نگاشت بانک"
            End If
        End If
        ' FCheck: مانده به‌صورت نسیه (AR/AP) می‌ماند؛ ماژول چک با ایجاد چک، AR→اسناد دریافتنی را می‌بندد

        Dim extra As New JObject From {
            {"post_inventory", False},
            {"auto_post_warehouse", False},
            {"ignore_credit_check", True},
            {"source", "holoo"},
            {"holoo_fac_type", inv.FacType},
            {"holoo_fac_code", inv.FacCode},
            {"holoo_sanad_code", inv.SanadCode}
        }
        If personId > 0 Then extra("person_id") = personId
        If inv.Takhfif > 0 Then
            extra("global_discount") = New JObject From {
                {"type", "amount"},
                {"value", Math.Round(inv.Takhfif, 2)}
            }
        End If
        If inv.FCheck > 0 Then
            extra("holoo_fcheck") = Math.Round(inv.FCheck, 2)
            extra("holoo_check_settlement") = "via_checks_module"
        End If
        If Not String.IsNullOrWhiteSpace(extraUnsettleNote) Then
            extra("holoo_unsettle_note") = extraUnsettleNote
        End If

        Dim payload As New JObject From {
            {"invoice_type", invType},
            {"document_date", ApiDateFormat.ToIsoDate(inv.FacDate)},
            {"currency_id", invCurrencyId},
            {"description", If(String.IsNullOrWhiteSpace(inv.Comment), "Holoo " & inv.Key, inv.Comment)},
            {"lines", lines},
            {"extra_info", extra}
        }
        If payments.Count > 0 Then payload("payments") = payments
        Return payload
    End Function

    Private Async Function PostWarehouseForInvoices(
        api As HesabixApiClient,
        businessId As Integer,
        invoiceIds As List(Of Integer),
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.WarehouseDocs.ToString())
        Dim offset = 0
        While offset < invoiceIds.Count
            ct.ThrowIfCancellationRequested()
            Dim take = Math.Min(WarehouseChunk, invoiceIds.Count - offset)
            Dim chunk = invoiceIds.GetRange(offset, take)
            Dim chunkKey = "WH:" & String.Join(",", chunk)
            If modCp.Done.ContainsKey(chunkKey) Then
                offset += take
                Continue While
            End If
            Dim attempt = 0
            Dim ok As Boolean = False
            Dim lastErr As String = Nothing
            While attempt < 3 AndAlso Not ok
                attempt += 1
                Dim retryDelayMs As Integer = 0
                Try
                    Await api.BulkWarehouseOperationsAsync(businessId, chunk, "create_draft", ct).ConfigureAwait(False)
                    Await api.BulkWarehouseOperationsAsync(businessId, chunk, "post_drafts", ct).ConfigureAwait(False)
                    ok = True
                Catch ex As Exception
                    lastErr = If(ex.Message, "خطا")
                    If (IsTransientTimeout(ex) OrElse IsTransientFailureMessage(lastErr)) AndAlso attempt < 3 Then
                        retryDelayMs = 2000 * attempt
                    End If
                End Try
                If Not ok AndAlso retryDelayMs > 0 Then
                    Await Task.Delay(retryDelayMs, ct).ConfigureAwait(False)
                ElseIf Not ok Then
                    Exit While
                End If
            End While
            If ok Then
                modCp.Done(chunkKey) = chunk.Count
                modCp.Failed.Remove(chunkKey)
                For Each id In chunk
                    modCp.Done("INVWH:" & id.ToString()) = id
                Next
                RaiseProgress("انبار", offset + take, invoiceIds.Count, "حواله draft/post برای " & take.ToString() & " فاکتور")
            Else
                modCp.Failed(chunkKey) = If(lastErr, "خطای انبار")
                RaiseProgress("انبار", offset + take, invoiceIds.Count, "خطای انبار: " & If(lastErr, "?"), True)
            End If
            store.Save(cp)
            offset += take
        End While
    End Function

    Private Async Function TransferStandaloneReceipts(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.ReceiptsPayments.ToString())
        Dim rows = Await Task.Run(Function() _docs.ReadReceiptLikeSanadsInRange(session.SqlSettings, fy.StartDate, fy.EndDate), ct).ConfigureAwait(False)
        Dim pending = ApplySample(rows.Where(Function(r) Not modCp.Done.ContainsKey(r.Key)).ToList(), "دریافت/پرداخت " & fy.Title)
        RaiseProgress("دریافت/پرداخت " & fy.Title, modCp.Done.Count, rows.Count, "ارسال " & pending.Count.ToString() & " سند...")

        Dim offset = 0
        Dim processed = rows.Count - pending.Count
        While offset < pending.Count
            ct.ThrowIfCancellationRequested()
            Dim take = Math.Min(ReceiptChunk, pending.Count - offset)
            Dim chunk = pending.GetRange(offset, take)
            Dim items As New JArray()
            Dim keys As New List(Of String)

            For Each row In chunk
                Dim personId = mapper.ResolvePerson(row.PersonMoien)
                If personId <= 0 Then personId = ResolvePersonByMoien(personMap, row.PersonMoien)
                If personId <= 0 Then
                    modCp.Failed(row.Key) = "شخص یافت نشد: " & row.PersonMoien
                    processed += 1
                    Continue For
                End If
                Dim payload = BuildReceiptPaymentPayload(row, currencyId, personId, mapper, defaultCashId, defaultBankId, defaultPettyId)
                If payload Is Nothing Then
                    modCp.Failed(row.Key) = "حساب بانکی/صندوق قابل نگاشت نیست"
                    processed += 1
                    Continue For
                End If
                items.Add(New JObject From {{"client_ref", row.Key}, {"payload", payload}})
                keys.Add(row.Key)
            Next

            If items.Count = 0 Then
                offset += take
                store.Save(cp)
                Continue While
            End If

            Dim attempt = 0
            Dim sent As Boolean = False
            While attempt < 3 AndAlso Not sent
                attempt += 1
                Dim retryDelayMs As Integer = 0
                Dim catchFail As Boolean = False
                Dim catchMsg As String = Nothing
                Try
                    Dim bulk = Await api.BulkUpsertReceiptsPaymentsAsync(businessId, items, True, ct).ConfigureAwait(False)
                    Dim byClientRef = IndexByClientRef(bulk)
                    Dim retryItems As New JArray()
                    Dim retryKeys As New List(Of String)()
                    For i = 0 To keys.Count - 1
                        Dim k = keys(i)
                        Dim r = ResolveItem(byClientRef, bulk, i, k)
                        If r IsNot Nothing AndAlso r.IsSuccess AndAlso r.EntityId > 0 Then
                            processed += 1
                            modCp.Done(k) = r.EntityId
                            modCp.Failed.Remove(k)
                        Else
                            Dim msg = If(r Is Nothing, "نتیجه برنگشت", If(r.Message, r.ErrorCode))
                            If IsTransientFailureMessage(If(msg, "")) AndAlso attempt < 3 Then
                                retryItems.Add(items(i))
                                retryKeys.Add(k)
                            Else
                                processed += 1
                                modCp.Failed(k) = If(msg, "خطا")
                                RaiseProgress("دریافت/پرداخت", processed, rows.Count, "خطا: " & k, True)
                            End If
                        End If
                    Next
                    If retryItems.Count > 0 AndAlso attempt < 3 Then
                        items = retryItems
                        keys = retryKeys
                        retryDelayMs = 2000 * attempt
                    Else
                        RaiseProgress("دریافت/پرداخت " & fy.Title, processed, rows.Count,
                                      "دسته ایجاد " & bulk.Created.ToString() & " / شکست " & bulk.Failed.ToString())
                        sent = True
                    End If
                Catch ex As Exception
                    If IsTransientTimeout(ex) AndAlso attempt < 3 Then
                        retryDelayMs = 3000 * attempt
                    Else
                        catchFail = True
                        catchMsg = ex.Message
                        sent = True
                    End If
                End Try
                If catchFail Then
                    For Each k In keys
                        modCp.Failed(k) = catchMsg
                        processed += 1
                    Next
                    RaiseProgress("دریافت/پرداخت", processed, rows.Count, "خطای bulk: " & catchMsg, True)
                ElseIf retryDelayMs > 0 AndAlso Not sent Then
                    Await Task.Delay(retryDelayMs, ct).ConfigureAwait(False)
                End If
            End While
            store.Save(cp)
            offset += take
        End While

        If SampleLimit <= 0 AndAlso modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Function BuildReceiptPaymentPayload(
        row As HolooReceiptLikeSanad,
        currencyId As Integer,
        personId As Integer,
        mapper As HolooSarfaslMapper,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer
    ) As JObject
        Dim amount = Math.Round(row.PersonAmount, 2)
        If amount <= 0 Then Return Nothing

        Dim accountLine As JObject = Nothing
        If row.CounterCol = "101" Then
            Dim isPetty As Boolean
            Dim cashId = mapper.ResolveCashOrPetty(row.CounterCol, row.CounterMoien, row.CounterTafzili, isPetty)
            ' ممنوع: dump به صندوق/تنخواه پیش‌فرض — بدون resolve قطعی Fail
            If cashId <= 0 Then Return Nothing
            If isPetty Then
                accountLine = New JObject From {
                    {"amount", amount},
                    {"transaction_type", "petty_cash"},
                    {"petty_cash_id", cashId},
                    {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)}
                }
            Else
                accountLine = New JObject From {
                    {"amount", amount},
                    {"transaction_type", "cash_register"},
                    {"cash_register_id", cashId},
                    {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)}
                }
            End If
        Else
            Dim bankId = mapper.ResolveBank(row.CounterCol, row.CounterMoien, row.CounterTafzili, Nothing, row.CounterName)
            If bankId <= 0 Then Return Nothing
            accountLine = New JObject From {
                {"amount", amount},
                {"transaction_type", "bank"},
                {"bank_id", bankId},
                {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)}
            }
        End If

        Return New JObject From {
            {"document_type", If(row.IsReceipt, "receipt", "payment")},
            {"document_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
            {"currency_id", currencyId},
            {"description", If(String.IsNullOrWhiteSpace(row.Comment), "Holoo " & row.Key, row.Comment)},
            {"person_lines", New JArray From {
                New JObject From {{"person_id", personId}, {"amount", amount}}
            }},
            {"account_lines", New JArray From {accountLine}},
            {"extra_info", New JObject From {{"source", "holoo"}, {"holoo_sanad_code", row.SanadCode}}}
        }
    End Function

    Private Async Function TransferChecksForYear(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        defaultBankId As Integer,
        earliestStart As Date,
        isFirstYear As Boolean,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.Checks.ToString())
        Dim clearCp = cp.EnsureModule("ChecksClear")
        Dim rows = Await Task.Run(Function() _docs.ReadChecksInRange(session.SqlSettings, fy.StartDate, fy.EndDate), ct).ConfigureAwait(False)

        ' ایجاد در سال صدور؛ چک‌های قبل از اولین سال کشف‌شده در سال اول ثبت می‌شوند
        Dim toCreate = ApplySample(rows.Where(Function(r) Not r.IsVoid AndAlso Not modCp.Done.ContainsKey(r.Key) AndAlso (
            (r.IssueDate >= fy.StartDate AndAlso r.IssueDate <= fy.EndDate) OrElse
            (isFirstYear AndAlso r.IssueDate < earliestStart)
        )).ToList(), "چک " & fy.Title)

        RaiseProgress("چک " & fy.Title, modCp.Done.Count, rows.Count, "ایجاد " & toCreate.Count.ToString() & " چک...")

        Dim i = 0
        For Each row In toCreate
            ct.ThrowIfCancellationRequested()
            i += 1
            Dim personCode = If(row.IsPayable, If(row.DestPersonCode, row.SourcePersonCode), row.SourcePersonCode)
            Dim personId = mapper.ResolvePerson(personCode)
            If personId <= 0 Then personId = ResolvePersonByMoien(personMap, personCode)
            If personId <= 0 AndAlso Not String.IsNullOrWhiteSpace(row.DestPersonCode) Then
                personId = mapper.ResolvePerson(row.DestPersonCode)
                If personId <= 0 Then personId = ResolvePersonByMoien(personMap, row.DestPersonCode)
            End If
            If personId <= 0 Then
                modCp.Failed(row.Key) = "شخص چک یافت نشد: " & personCode
                RaiseProgress("چک", i, toCreate.Count, "رد شخص: " & row.Key, True)
                store.Save(cp)
                Continue For
            End If
            If row.Amount <= 0 Then
                modCp.Failed(row.Key) = "مبلغ نامعتبر"
                Continue For
            End If

            Dim issue = row.IssueDate
            Dim due = row.DueDate
            If due < issue Then due = issue

            Dim checkNumber = If(String.IsNullOrWhiteSpace(row.CheckNumber), "HLO-" & row.CheckCode.ToString(), row.CheckNumber.Trim())
            Dim payload As New JObject From {
                {"type", If(row.IsPayable, "transferred", "received")},
                {"person_id", personId},
                {"issue_date", ApiDateFormat.ToIsoDate(issue)},
                {"due_date", ApiDateFormat.ToIsoDate(due)},
                {"check_number", checkNumber},
                {"amount", Math.Round(row.Amount, 2)},
                {"currency_id", currencyId},
                {"document_date", ApiDateFormat.ToIsoDate(issue)},
                {"document_description", If(String.IsNullOrWhiteSpace(row.Comment), "Holoo " & row.Key, row.Comment)}
            }
            If Not String.IsNullOrWhiteSpace(row.BankName) Then payload("bank_name") = row.BankName

            Dim createdId As Integer = 0
            Dim createError As String = Nothing
            Dim attempt = 0
            While attempt < 3 AndAlso createdId <= 0
                attempt += 1
                createError = Nothing
                Dim retryDelayMs As Integer = 0
                Try
                    createdId = Await api.CreateCheckAsync(businessId, payload, ct).ConfigureAwait(False)
                Catch ex As Exception
                    createError = If(ex.Message, "خطا")
                    If (IsTransientTimeout(ex) OrElse IsTransientFailureMessage(createError)) AndAlso attempt < 3 Then
                        retryDelayMs = 2000 * attempt
                    End If
                End Try
                If createdId > 0 Then Exit While
                If retryDelayMs > 0 Then
                    Await Task.Delay(retryDelayMs, ct).ConfigureAwait(False)
                    Continue While
                End If
                If createError IsNot Nothing Then Exit While
                If attempt < 3 Then
                    Await Task.Delay(1500 * attempt, ct).ConfigureAwait(False)
                End If
            End While

            If createdId <= 0 AndAlso createError IsNot Nothing AndAlso
               createError.IndexOf("DUPLICATE", StringComparison.OrdinalIgnoreCase) >= 0 Then
                payload("check_number") = "H" & row.CheckCode.ToString() & "-" & checkNumber
                createError = Nothing
                Try
                    createdId = Await api.CreateCheckAsync(businessId, payload, ct).ConfigureAwait(False)
                Catch ex2 As Exception
                    createError = If(ex2.Message, "خطا")
                End Try
            End If

            If createdId > 0 Then
                modCp.Done(row.Key) = createdId
                modCp.Failed.Remove(row.Key)
                RaiseProgress("چک " & fy.Title, i, toCreate.Count, "ایجاد: " & CStr(payload("check_number")))
                If row.IsReturned Then
                    Try
                        Await api.ReturnCheckAsync(createdId, "to_drawer", row.DueDate, ct).ConfigureAwait(False)
                        clearCp.Done("RET:" & row.CheckCode.ToString()) = createdId
                    Catch exRet As Exception
                        clearCp.Failed("RET:" & row.CheckCode.ToString()) = exRet.Message
                        RaiseProgress("عودت چک", i, toCreate.Count, "خطا عودت: " & row.Key & " — " & exRet.Message, True)
                    End Try
                End If
            Else
                modCp.Failed(row.Key) = If(createError, "خطا")
                RaiseProgress("چک", i, toCreate.Count, "خطا: " & row.Key & " — " & modCp.Failed(row.Key), True)
            End If
            store.Save(cp)
        Next

        ' عودت چک‌هایی که قبلاً ایجاد شده و در این سال برگشت خورده‌اند
        Dim returnCp = clearCp
        Dim returnCandidates = rows.Where(Function(r) Not r.IsVoid AndAlso r.IsReturned AndAlso
            r.DueDate >= fy.StartDate AndAlso r.DueDate <= fy.EndDate).ToList()
        For Each row In returnCandidates
            ct.ThrowIfCancellationRequested()
            Dim retKey = "RET:" & row.CheckCode.ToString()
            If returnCp.Done.ContainsKey(retKey) Then Continue For
            Dim checkId As Integer = 0
            If Not modCp.Done.TryGetValue(row.Key, checkId) OrElse checkId <= 0 Then
                returnCp.Failed(retKey) = "چک هنوز ایجاد نشده"
                Continue For
            End If
            Try
                Await api.ReturnCheckAsync(checkId, "to_drawer", row.DueDate, ct).ConfigureAwait(False)
                returnCp.Done(retKey) = checkId
                returnCp.Failed.Remove(retKey)
            Catch ex As Exception
                returnCp.Failed(retKey) = ex.Message
                RaiseProgress("عودت چک", 0, returnCandidates.Count, "خطا: " & row.Key & " — " & ex.Message, True)
            End Try
            store.Save(cp)
        Next

        ' سپرده به جریان وصول (10404) برای چک‌های DarJaryan که هنوز پاس نشده‌اند
        Dim depositCandidates = rows.Where(Function(r) Not r.IsVoid AndAlso Not r.IsReturned AndAlso r.IsInProcess AndAlso Not r.IsCleared AndAlso
            r.ClearDate >= fy.StartDate AndAlso r.ClearDate <= fy.EndDate).ToList()
        For Each row In depositCandidates
            ct.ThrowIfCancellationRequested()
            Dim depKey = "DEP:" & row.CheckCode.ToString()
            If clearCp.Done.ContainsKey(depKey) Then Continue For
            Dim checkId As Integer = 0
            If Not modCp.Done.TryGetValue(row.Key, checkId) OrElse checkId <= 0 Then
                clearCp.Failed(depKey) = "چک هنوز ایجاد نشده"
                Continue For
            End If
            Dim bankId = mapper.ResolveBank("102", "", "", row.AccountNumber, row.BankName)
            If bankId <= 0 Then
                clearCp.Failed(depKey) = "بانک سپرده یافت نشد: " & row.AccountNumber
                Continue For
            End If
            Try
                Await api.DepositCheckAsync(checkId, bankId, row.ClearDate, ct).ConfigureAwait(False)
                clearCp.Done(depKey) = checkId
                clearCp.Failed.Remove(depKey)
            Catch ex As Exception
                clearCp.Failed(depKey) = ex.Message
                RaiseProgress("سپرده چک", 0, depositCandidates.Count, "خطا DEP " & row.CheckCode.ToString() & ": " & ex.Message, True)
            End Try
            store.Save(cp)
        Next

        ' وصول چک‌هایی که در این سال پاس شده‌اند (حتی اگر قبلاً ایجاد شده باشند)
        Dim clearCandidates = rows.Where(Function(r) Not r.IsVoid AndAlso Not r.IsReturned AndAlso r.IsCleared AndAlso
            r.ClearDate >= fy.StartDate AndAlso r.ClearDate <= fy.EndDate).ToList()
        Dim cleared = 0
        For Each row In clearCandidates
            ct.ThrowIfCancellationRequested()
            Dim clearKey = "CLR:" & row.CheckCode.ToString()
            If clearCp.Done.ContainsKey(clearKey) Then Continue For

            Dim checkId As Integer = 0
            If Not modCp.Done.TryGetValue(row.Key, checkId) OrElse checkId <= 0 Then
                clearCp.Failed(clearKey) = "چک هنوز ایجاد نشده"
                Continue For
            End If

            Dim bankId = mapper.ResolveBank("102", "", "", row.AccountNumber, row.BankName)
            If bankId <= 0 Then
                clearCp.Failed(clearKey) = "بانک وصول یافت نشد: " & row.AccountNumber
                Continue For
            End If

            Try
                ' اگر قبلاً در جریان وصول بوده و deposit نشده، اول deposit
                If row.IsInProcess Then
                    Dim depKey = "DEP:" & row.CheckCode.ToString()
                    If Not clearCp.Done.ContainsKey(depKey) Then
                        Try
                            Await api.DepositCheckAsync(checkId, bankId, row.ClearDate, ct).ConfigureAwait(False)
                            clearCp.Done(depKey) = checkId
                        Catch
                            ' ممکن است از قبل deposited باشد — clear را ادامه بده
                        End Try
                    End If
                End If
                Await api.ClearCheckAsync(checkId, bankId, row.ClearDate, ct).ConfigureAwait(False)
                clearCp.Done(clearKey) = checkId
                clearCp.Failed.Remove(clearKey)
                cleared += 1
            Catch ex As Exception
                clearCp.Failed(clearKey) = ex.Message
                RaiseProgress("وصول چک", cleared, clearCandidates.Count, "خطا CLR " & row.CheckCode.ToString() & ": " & ex.Message, True)
            End Try
            store.Save(cp)
        Next
        RaiseProgress("وصول چک " & fy.Title, cleared, clearCandidates.Count, "وصول " & cleared.ToString() & " از " & clearCandidates.Count.ToString())

        If SampleLimit <= 0 AndAlso modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Async Function TransferExpenseIncomeForYear(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        accountCodeMap As Dictionary(Of String, Integer),
        catalog As SarfaslCatalog,
        profile As SarfaslProfile,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.ExpenseIncome.ToString())
        If accountCodeMap Is Nothing Then
            accountCodeMap = Await api.ListAccountCodeMapAsync(businessId, ct).ConfigureAwait(False)
        End If
        If catalog Is Nothing Then catalog = New SarfaslCatalog(api, businessId, accountCodeMap)

        Dim expenses = Await Task.Run(Function() _docs.ReadExpenseIncomeSanadsInRange(session.SqlSettings, fy.StartDate, fy.EndDate, False), ct).ConfigureAwait(False)
        Dim incomes = Await Task.Run(Function() _docs.ReadExpenseIncomeSanadsInRange(session.SqlSettings, fy.StartDate, fy.EndDate, True), ct).ConfigureAwait(False)
        Dim rows = expenses.Concat(incomes).OrderBy(Function(r) r.SanadDate).ThenBy(Function(r) r.SanadCode).ToList()
        Dim pending = ApplySample(rows.Where(Function(r) Not modCp.Done.ContainsKey(r.Key)).ToList(), "هزینه/درآمد " & fy.Title)
        RaiseProgress("هزینه/درآمد " & fy.Title, modCp.Done.Count, rows.Count, "ارسال " & pending.Count.ToString() & " سند متوازن...")

        Dim offset = 0
        Dim processed = rows.Count - pending.Count
        While offset < pending.Count
            ct.ThrowIfCancellationRequested()
            Dim take = Math.Min(ExpenseChunk, pending.Count - offset)
            Dim chunk = pending.GetRange(offset, take)
            Dim items As New JArray()
            Dim keys As New List(Of String)

            For Each row In chunk
                Dim payload = Await BuildExpenseIncomePayloadAsync(
                    row, currencyId, personMap, mapper, accountCodeMap, catalog, profile,
                    defaultCashId, defaultBankId, defaultPettyId, ct).ConfigureAwait(False)
                If payload Is Nothing Then
                    modCp.Failed(row.Key) = "نگاشت حساب/طرف‌حساب ناقص"
                    processed += 1
                    Continue For
                End If
                items.Add(New JObject From {{"client_ref", row.Key}, {"payload", payload}})
                keys.Add(row.Key)
            Next

            If items.Count = 0 Then
                offset += take
                store.Save(cp)
                Continue While
            End If

            Dim attempt = 0
            Dim sent As Boolean = False
            While attempt < 3 AndAlso Not sent
                attempt += 1
                Dim retryDelayMs As Integer = 0
                Dim catchFail As Boolean = False
                Dim catchMsg As String = Nothing
                Try
                    Dim bulk = Await api.BulkUpsertExpenseIncomeAsync(businessId, items, True, ct).ConfigureAwait(False)
                    Dim byClientRef = IndexByClientRef(bulk)
                    Dim retryItems As New JArray()
                    Dim retryKeys As New List(Of String)()
                    For i = 0 To keys.Count - 1
                        Dim k = keys(i)
                        Dim r = ResolveItem(byClientRef, bulk, i, k)
                        If r IsNot Nothing AndAlso r.IsSuccess AndAlso r.EntityId > 0 Then
                            processed += 1
                            modCp.Done(k) = r.EntityId
                            modCp.Failed.Remove(k)
                        Else
                            Dim msg = If(r Is Nothing, "نتیجه برنگشت", If(r.Message, r.ErrorCode))
                            If IsTransientFailureMessage(If(msg, "")) AndAlso attempt < 3 Then
                                retryItems.Add(items(i))
                                retryKeys.Add(k)
                            Else
                                processed += 1
                                modCp.Failed(k) = If(msg, "خطا")
                                RaiseProgress("هزینه/درآمد", processed, rows.Count, "خطا: " & k, True)
                            End If
                        End If
                    Next
                    If retryItems.Count > 0 AndAlso attempt < 3 Then
                        items = retryItems
                        keys = retryKeys
                        retryDelayMs = 2000 * attempt
                    Else
                        RaiseProgress("هزینه/درآمد " & fy.Title, processed, rows.Count,
                                      "دسته ایجاد " & bulk.Created.ToString() & " / شکست " & bulk.Failed.ToString())
                        sent = True
                    End If
                Catch ex As Exception
                    If IsTransientTimeout(ex) AndAlso attempt < 3 Then
                        retryDelayMs = 3000 * attempt
                    Else
                        catchFail = True
                        catchMsg = ex.Message
                        sent = True
                    End If
                End Try
                If catchFail Then
                    For Each k In keys
                        modCp.Failed(k) = catchMsg
                        processed += 1
                    Next
                    RaiseProgress("هزینه/درآمد", processed, rows.Count, "خطای bulk: " & catchMsg, True)
                ElseIf retryDelayMs > 0 AndAlso Not sent Then
                    Await Task.Delay(retryDelayMs, ct).ConfigureAwait(False)
                End If
            End While
            store.Save(cp)
            offset += take
        End While

        If SampleLimit <= 0 AndAlso modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Async Function BuildExpenseIncomePayloadAsync(
        row As HolooExpenseIncomeSanad,
        currencyId As Integer,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        accountCodeMap As Dictionary(Of String, Integer),
        catalog As SarfaslCatalog,
        profile As SarfaslProfile,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        ct As CancellationToken
    ) As Task(Of JObject)
        Dim itemLines As New JArray()
        Dim itemTotal As Double = 0
        For Each it In row.ItemLines
            If it.Amount <= 0 Then Continue For
            Dim name = If(String.IsNullOrWhiteSpace(it.Name),
                          If(row.IsIncome, mapper.IncomeName(it.MoienCode), mapper.ExpenseName(it.MoienCode)),
                          it.Name)
            Dim code As String = Nothing
            If profile IsNot Nothing Then
                Dim pe = profile.Find(If(row.IsIncome, "702", "601"), it.MoienCode)
                If pe IsNot Nothing AndAlso pe.Exempt Then Return Nothing
                If pe IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(pe.OverrideCode) Then code = pe.OverrideCode.Trim()
            End If
            If String.IsNullOrWhiteSpace(code) Then
                code = If(row.IsIncome,
                          HolooSarfaslMapper.MapIncomeToFixedCode(name, it.MoienCode),
                          HolooSarfaslMapper.MapExpenseToFixedCode(name, it.MoienCode))
            End If
            Dim acctId As Integer = 0
            If Not String.IsNullOrWhiteSpace(code) Then
                If accountCodeMap Is Nothing OrElse Not accountCodeMap.TryGetValue(code, acctId) OrElse acctId <= 0 Then
                    If catalog IsNot Nothing Then
                        acctId = Await catalog.ResolveOrCreateAsync(code, Nothing, Nothing, ct).ConfigureAwait(False)
                    End If
                    If acctId <= 0 Then Return Nothing
                End If
            ElseIf Not row.IsIncome AndAlso catalog IsNot Nothing AndAlso
                   (mapper.NeedsBusinessExpenseAccount(it.MoienCode) OrElse String.IsNullOrWhiteSpace(code)) Then
                acctId = Await catalog.EnsureExpenseBusinessAccountAsync(it.MoienCode, name, ct).ConfigureAwait(False)
                If acctId <= 0 Then Return Nothing
            ElseIf row.IsIncome AndAlso catalog IsNot Nothing AndAlso String.IsNullOrWhiteSpace(code) Then
                acctId = Await catalog.EnsureIncomeBusinessAccountAsync(it.MoienCode, name, ct).ConfigureAwait(False)
                If acctId <= 0 Then Return Nothing
            Else
                Return Nothing
            End If
            Dim amt = Math.Round(it.Amount, 2)
            itemTotal += amt
            itemLines.Add(New JObject From {
                {"account_id", acctId},
                {"amount", amt},
                {"description", name}
            })
        Next
        If itemLines.Count = 0 Then Return Nothing

        Dim counterLines As New JArray()
        Dim cpTotal As Double = 0
        For Each cpLine In row.CounterpartyLines
            If cpLine.Amount <= 0 Then Continue For
            Dim col = If(cpLine.ColCode, "").Trim()
            Dim amt = Math.Round(cpLine.Amount, 2)
            Dim jo As JObject = Nothing
            If col = "103" OrElse (col = "401" AndAlso Not mapper.IsLoan401(cpLine.MoienCode)) Then
                Dim personId = mapper.ResolvePersonOnCol(col, cpLine.MoienCode)
                If personId <= 0 Then personId = ResolvePersonByMoien(personMap, cpLine.MoienCode)
                If personId <= 0 Then Return Nothing
                ' درآمد+شخص: API قدیمی 1211 می‌خواست؛ از 10401 (کنترل دریافتنی فاکتور) استفاده می‌کنیم
                Dim arId As Integer = 0
                If row.IsIncome AndAlso accountCodeMap IsNot Nothing Then
                    accountCodeMap.TryGetValue("10401", arId)
                End If
                If row.IsIncome AndAlso arId > 0 Then
                    jo = New JObject From {
                        {"account_id", arId},
                        {"person_id", personId},
                        {"amount", amt},
                        {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                        {"description", cpLine.Name}
                    }
                Else
                    jo = New JObject From {
                        {"transaction_type", "person"},
                        {"person_id", personId},
                        {"amount", amt},
                        {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                        {"description", cpLine.Name}
                    }
                End If
            ElseIf col = "401" AndAlso mapper.IsLoan401(cpLine.MoienCode) Then
                Dim loanId = Await catalog.EnsureLoanBusinessAccountAsync(cpLine.MoienCode, cpLine.Name, ct).ConfigureAwait(False)
                If loanId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"transaction_type", "account"},
                    {"account_id", loanId},
                    {"amount", amt},
                    {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                    {"description", cpLine.Name}
                }
            ElseIf col = "101" Then
                Dim isPetty As Boolean
                Dim cashId = mapper.ResolveCashOrPetty(col, cpLine.MoienCode, cpLine.TafziliCode, isPetty)
                If cashId <= 0 Then Return Nothing
                If isPetty Then
                    jo = New JObject From {
                        {"transaction_type", "petty_cash"},
                        {"petty_cash_id", cashId},
                        {"amount", amt},
                        {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                        {"description", cpLine.Name}
                    }
                Else
                    jo = New JObject From {
                        {"transaction_type", "cash_register"},
                        {"cash_register_id", cashId},
                        {"amount", amt},
                        {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                        {"description", cpLine.Name}
                    }
                End If
            ElseIf col = "102" Then
                Dim bankId = mapper.ResolveBank(col, cpLine.MoienCode, cpLine.TafziliCode, Nothing, cpLine.Name)
                If bankId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"transaction_type", "bank"},
                    {"bank_id", bankId},
                    {"amount", amt},
                    {"transaction_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
                    {"description", cpLine.Name}
                }
            Else
                Return Nothing
            End If
            counterLines.Add(jo)
            cpTotal += amt
        Next

        If counterLines.Count = 0 Then Return Nothing
        If Math.Abs(itemTotal - cpTotal) > 0.02 Then Return Nothing

        Return New JObject From {
            {"document_type", If(row.IsIncome, "income", "expense")},
            {"document_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
            {"currency_id", currencyId},
            {"description", If(String.IsNullOrWhiteSpace(row.Comment), "Holoo " & row.Key, row.Comment)},
            {"item_lines", itemLines},
            {"counterparty_lines", counterLines},
            {"extra_info", New JObject From {{"source", "holoo"}, {"holoo_sanad_code", row.SanadCode}, {"holoo_bucket", "EXPENSE_INCOME"}}}
        }
    End Function

    Private Async Function TransferManualJournalsForYear(
        session As MigrationSession,
        api As HesabixApiClient,
        businessId As Integer,
        currencyId As Integer,
        fy As DetectedFiscalYear,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        accountCodeMap As Dictionary(Of String, Integer),
        catalog As SarfaslCatalog,
        profile As SarfaslProfile,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        cp As TransferCheckpoint,
        store As CheckpointStore,
        ct As CancellationToken
    ) As Task
        Dim modCp = cp.EnsureModule(MigrationModule.ManualJournals.ToString())
        If accountCodeMap Is Nothing Then
            accountCodeMap = Await api.ListAccountCodeMapAsync(businessId, ct).ConfigureAwait(False)
        End If
        If catalog Is Nothing Then catalog = New SarfaslCatalog(api, businessId, accountCodeMap)
        Dim rows = Await Task.Run(Function() _docs.ReadManualJournalsInRange(session.SqlSettings, fy.StartDate, fy.EndDate), ct).ConfigureAwait(False)
        Dim pending = ApplySample(rows.Where(Function(r) Not modCp.Done.ContainsKey(r.Key)).ToList(), "اسناد دستی " & fy.Title)
        RaiseProgress("اسناد دستی " & fy.Title, modCp.Done.Count, rows.Count, "ارسال " & pending.Count.ToString() & " سند متوازن...")

        Dim i = 0
        For Each row In pending
            ct.ThrowIfCancellationRequested()
            i += 1
            If Not String.IsNullOrWhiteSpace(row.SkipReason) Then
                modCp.Failed(row.Key) = row.SkipReason
                RaiseProgress("اسناد دستی", i, pending.Count, "رد مبدأ: " & row.Key & " — " & row.SkipReason, True)
                store.Save(cp)
                Continue For
            End If
            Dim payload = Await BuildManualJournalPayloadAsync(
                row, currencyId, personMap, mapper, accountCodeMap, catalog, profile,
                defaultCashId, defaultBankId, defaultPettyId, ct).ConfigureAwait(False)
            If payload Is Nothing Then
                modCp.Failed(row.Key) = "نگاشت خطوط ناقص یا نامتوازن"
                RaiseProgress("اسناد دستی", i, pending.Count, "رد: " & row.Key, True)
                store.Save(cp)
                Continue For
            End If
            Try
                Dim docId = Await api.CreateManualDocumentAsync(businessId, payload, ct).ConfigureAwait(False)
                If docId > 0 Then
                    modCp.Done(row.Key) = docId
                    modCp.Failed.Remove(row.Key)
                Else
                    modCp.Failed(row.Key) = "شناسه سند برنگشت"
                End If
            Catch ex As Exception
                modCp.Failed(row.Key) = ex.Message
                RaiseProgress("اسناد دستی", i, pending.Count, "خطا: " & row.Key & " — " & ex.Message, True)
            End Try
            If i Mod 20 = 0 Then
                RaiseProgress("اسناد دستی " & fy.Title, i, pending.Count, "پیشرفت...")
                store.Save(cp)
            End If
        Next
        If SampleLimit <= 0 AndAlso modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
        RaiseProgress("اسناد دستی " & fy.Title, pending.Count, pending.Count,
                      "تمام — موفق " & modCp.Done.Count.ToString() & " / شکست " & modCp.Failed.Count.ToString())
    End Function

    Private Shared Async Function BuildManualJournalPayloadAsync(
        row As HolooManualJournal,
        currencyId As Integer,
        personMap As ModuleCheckpoint,
        mapper As HolooSarfaslMapper,
        accountCodeMap As Dictionary(Of String, Integer),
        catalog As SarfaslCatalog,
        profile As SarfaslProfile,
        defaultCashId As Integer,
        defaultBankId As Integer,
        defaultPettyId As Integer,
        ct As CancellationToken
    ) As Task(Of JObject)
        Dim lines As New JArray()
        Dim bed As Double = 0
        Dim bes As Double = 0
        For Each ln In row.Lines
            Dim col = If(ln.ColCode, "").Trim()
            If col = "005" OrElse col = "006" Then Continue For
            Dim debit = Math.Round(ln.Debit, 2)
            Dim credit = Math.Round(ln.Credit, 2)
            If debit <= 0 AndAlso credit <= 0 Then Continue For

            Dim jo As JObject = Nothing
            If col = "401" AndAlso mapper.IsLoan401(ln.MoienCode) Then
                Dim loanId = Await catalog.EnsureLoanBusinessAccountAsync(ln.MoienCode, ln.SarfaslName, ct).ConfigureAwait(False)
                If loanId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"account_id", loanId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            ElseIf col = "103" OrElse col = "401" Then
                Dim personId = mapper.ResolvePersonOnCol(col, ln.MoienCode)
                If personId <= 0 Then personId = ResolvePersonByMoien(personMap, ln.MoienCode)
                If personId <= 0 Then Return Nothing
                Dim preferAp = (col = "401") OrElse credit > debit
                Dim code = If(preferAp, "20201", "10401")
                Dim acctId As Integer = 0
                If Not accountCodeMap.TryGetValue(code, acctId) OrElse acctId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"account_id", acctId},
                    {"person_id", personId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            ElseIf col = "102" Then
                Dim bankId = mapper.ResolveBank(col, ln.MoienCode, ln.TafziliCode, Nothing, ln.SarfaslName)
                Dim acctId As Integer = 0
                If Not accountCodeMap.TryGetValue("10203", acctId) OrElse acctId <= 0 OrElse bankId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"account_id", acctId},
                    {"bank_account_id", bankId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            ElseIf col = "101" Then
                Dim isPetty As Boolean
                Dim cashId = mapper.ResolveCashOrPetty(col, ln.MoienCode, ln.TafziliCode, isPetty)
                Dim code = If(isPetty, "10201", "10202")
                Dim acctId As Integer = 0
                If Not accountCodeMap.TryGetValue(code, acctId) OrElse acctId <= 0 OrElse cashId <= 0 Then Return Nothing
                jo = New JObject From {
                    {"account_id", acctId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
                If isPetty Then jo("petty_cash_id") = cashId Else jo("cash_register_id") = cashId
            ElseIf col = "601" Then
                Dim code As String = Nothing
                If profile IsNot Nothing Then
                    Dim pe = profile.Find("601", ln.MoienCode)
                    If pe IsNot Nothing AndAlso pe.Exempt Then Return Nothing
                    If pe IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(pe.OverrideCode) Then code = pe.OverrideCode.Trim()
                End If
                If String.IsNullOrWhiteSpace(code) Then code = HolooSarfaslMapper.MapExpenseToFixedCode(ln.SarfaslName, ln.MoienCode)
                Dim acctId As Integer = 0
                If Not String.IsNullOrWhiteSpace(code) AndAlso accountCodeMap.TryGetValue(code, acctId) AndAlso acctId > 0 Then
                    ' ok
                Else
                    acctId = Await catalog.EnsureExpenseBusinessAccountAsync(ln.MoienCode, ln.SarfaslName, ct).ConfigureAwait(False)
                    If acctId <= 0 Then Return Nothing
                End If
                jo = New JObject From {
                    {"account_id", acctId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            ElseIf col = "702" Then
                Dim code As String = Nothing
                If profile IsNot Nothing Then
                    Dim pe = profile.Find("702", ln.MoienCode)
                    If pe IsNot Nothing AndAlso pe.Exempt Then Return Nothing
                    If pe IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(pe.OverrideCode) Then code = pe.OverrideCode.Trim()
                End If
                If String.IsNullOrWhiteSpace(code) Then code = HolooSarfaslMapper.MapIncomeToFixedCode(ln.SarfaslName, ln.MoienCode)
                Dim acctId As Integer = 0
                If Not String.IsNullOrWhiteSpace(code) AndAlso accountCodeMap.TryGetValue(code, acctId) AndAlso acctId > 0 Then
                    ' ok
                Else
                    acctId = Await catalog.EnsureIncomeBusinessAccountAsync(ln.MoienCode, ln.SarfaslName, ct).ConfigureAwait(False)
                    If acctId <= 0 Then Return Nothing
                End If
                jo = New JObject From {
                    {"account_id", acctId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            Else
                Dim code = ResolveMappedAccountCode(profile, col, ln.MoienCode, ln.SarfaslName)
                If String.IsNullOrWhiteSpace(code) Then Return Nothing
                Dim acctId As Integer = 0
                If Not accountCodeMap.TryGetValue(code, acctId) OrElse acctId <= 0 Then
                    If catalog IsNot Nothing Then
                        acctId = Await catalog.ResolveOrCreateAsync(code, Nothing, Nothing, ct).ConfigureAwait(False)
                    End If
                    If acctId <= 0 Then Return Nothing
                End If
                jo = New JObject From {
                    {"account_id", acctId},
                    {"debit", debit},
                    {"credit", credit},
                    {"description", ln.SarfaslName}
                }
            End If
            lines.Add(jo)
            bed += debit
            bes += credit
        Next
        If lines.Count < 2 Then Return Nothing
        If Math.Abs(bed - bes) > 0.02 Then Return Nothing

        Dim bucket = If(If(row.Comment, "").IndexOf("[EI-FALLBACK]", StringComparison.OrdinalIgnoreCase) >= 0,
                        "EXPENSE_INCOME_FALLBACK", "MANUAL")
        Return New JObject From {
            {"document_date", ApiDateFormat.ToIsoDate(row.SanadDate)},
            {"currency_id", currencyId},
            {"description", If(String.IsNullOrWhiteSpace(row.Comment), "Holoo " & row.Key, row.Comment)},
            {"lines", lines},
            {"extra_info", New JObject From {
                {"source", "holoo"},
                {"holoo_sanad_code", row.SanadCode},
                {"holoo_sanad_type", row.SanadType},
                {"holoo_bucket", bucket}
            }}
        }
    End Function

    Private Shared Function ResolveMappedAccountCode(
        profile As SarfaslProfile,
        col As String,
        moien As String,
        sarfaslName As String
    ) As String
        If profile IsNot Nothing Then
            Dim pe = profile.Find(col, moien)
            If pe IsNot Nothing Then
                If pe.Exempt Then Return Nothing
                If Not String.IsNullOrWhiteSpace(pe.OverrideCode) Then Return pe.OverrideCode.Trim()
            End If
        End If
        Return HolooSarfaslMapper.MapColToFixedCode(col, moien, sarfaslName)
    End Function

    Private Shared Function ResolvePersonByMoien(personMap As ModuleCheckpoint, moien As String) As Integer
        If String.IsNullOrWhiteSpace(moien) Then Return 0
        Dim key = moien.Trim()
        Dim id As Integer
        If personMap.Done.TryGetValue(key, id) Then Return id
        Dim trimmed = key.TrimStart("0"c)
        If trimmed.Length > 0 AndAlso personMap.Done.TryGetValue(trimmed, id) Then Return id
        For Each kv In personMap.Done
            If String.Equals(kv.Key.TrimStart("0"c), key.TrimStart("0"c), StringComparison.OrdinalIgnoreCase) Then
                Return kv.Value
            End If
        Next
        Return 0
    End Function

    Private Async Function BuildHolooMoneyToCurrencyMapAsync(
        session As MigrationSession,
        api As HesabixApiClient,
        defaultCurrencyId As Integer,
        ct As CancellationToken
    ) As Task(Of Dictionary(Of Integer, Integer))
        Dim map As New Dictionary(Of Integer, Integer)
        Dim holooMoney = Await Task.Run(Function() New HolooBaseDataReader().ReadCurrencies(session.SqlSettings), ct).ConfigureAwait(False)
        Dim hesabix = Await api.ListCurrenciesAsync(ct).ConfigureAwait(False)
        For Each hm In holooMoney
            Dim matched = hesabix.FirstOrDefault(Function(c) _
                String.Equals(If(c.Title, "").Trim(), If(hm.Name, "").Trim(), StringComparison.OrdinalIgnoreCase) OrElse
                String.Equals(If(c.Code, "").Trim(), If(hm.Name, "").Trim(), StringComparison.OrdinalIgnoreCase) OrElse
                String.Equals(If(c.Code, "").Trim(), hm.Code.ToString(), StringComparison.OrdinalIgnoreCase))
            If matched IsNot Nothing AndAlso matched.Id > 0 Then
                map(hm.Code) = matched.Id
            ElseIf hm.IsBase Then
                map(hm.Code) = defaultCurrencyId
            End If
        Next
        If Not map.ContainsKey(1) Then map(1) = defaultCurrencyId
        Return map
    End Function

    Private Shared Function IndexByClientRef(bulk As BulkUpsertResult) As Dictionary(Of String, BulkUpsertItemResult)
        Dim map As New Dictionary(Of String, BulkUpsertItemResult)(StringComparer.Ordinal)
        If bulk Is Nothing OrElse bulk.Results Is Nothing Then Return map
        For Each r In bulk.Results
            If Not String.IsNullOrWhiteSpace(r.ClientRef) AndAlso Not map.ContainsKey(r.ClientRef) Then
                map(r.ClientRef) = r
            End If
        Next
        Return map
    End Function

    Private Shared Function ResolveItem(
        byClientRef As Dictionary(Of String, BulkUpsertItemResult),
        bulk As BulkUpsertResult,
        indexInChunk As Integer,
        clientRef As String
    ) As BulkUpsertItemResult
        Dim found As BulkUpsertItemResult = Nothing
        If byClientRef IsNot Nothing AndAlso byClientRef.TryGetValue(clientRef, found) Then Return found
        If bulk IsNot Nothing AndAlso bulk.Results IsNot Nothing Then
            For Each r In bulk.Results
                If r.Index = indexInChunk Then Return r
            Next
            If indexInChunk >= 0 AndAlso indexInChunk < bulk.Results.Count Then Return bulk.Results(indexInChunk)
        End If
        Return Nothing
    End Function

    Private Sub RaiseProgress(moduleTitle As String, current As Integer, total As Integer, message As String, Optional isError As Boolean = False)
        RaiseEvent ProgressChanged(Me, New TransferProgressEventArgs With {
            .ModuleTitle = moduleTitle,
            .Current = current,
            .Total = total,
            .Message = message,
            .IsError = isError
        })
    End Sub
End Class
