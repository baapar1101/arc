Imports System.IO
Imports System.Threading
Imports Newtonsoft.Json

''' <summary>
''' اجرای بدون UI: اطلاعات پایه + سال مالی/افتتاحیه روی کسب‌وکار تست.
''' Usage: Holoo2Hesabix.exe --e2e-opening --api-key KEY [--business-id N | --create-business NAME]
''' </summary>
Friend NotInheritable Class E2eOpeningRunner
    Private Sub New()
    End Sub

    Public Shared Function Run(args As String()) As Integer
        Dim apiKey = Arg(args, "--api-key")
        Dim businessId = ParseInt(Arg(args, "--business-id"))
        Dim createName = Arg(args, "--create-business")
        Dim docsOnly = args.Any(Function(a) String.Equals(a, "--docs-only", StringComparison.OrdinalIgnoreCase))
        Dim withManual = args.Any(Function(a) String.Equals(a, "--with-manual", StringComparison.OrdinalIgnoreCase))
        Dim withInvoices = args.Any(Function(a) String.Equals(a, "--with-invoices", StringComparison.OrdinalIgnoreCase))
        Dim withAllDocs = args.Any(Function(a) String.Equals(a, "--with-all-docs", StringComparison.OrdinalIgnoreCase))
        Dim sampleLimit = ParseInt(Arg(args, "--sample"))
        Dim sqlServer = If(Arg(args, "--sql-server"), "localhost")
        Dim sqlUser = If(Arg(args, "--sql-user"), "sa")
        Dim sqlPass = If(Arg(args, "--sql-pass"), Environment.GetEnvironmentVariable("HOLOO_SQL_PASS"))
        If String.IsNullOrWhiteSpace(sqlPass) Then sqlPass = ""
        Dim sqlDb = If(Arg(args, "--sql-db"), "Holoo1")
        Dim baseUrl = If(Arg(args, "--api-base"), MigrationSession.DefaultApiBaseUrl)
        Dim outDir = Arg(args, "--out")
        If String.IsNullOrWhiteSpace(outDir) Then
            outDir = "d:\hesabixArc\.eyeban"
        End If
        outDir = Path.GetFullPath(outDir)
        Directory.CreateDirectory(outDir)

        If String.IsNullOrWhiteSpace(apiKey) Then
            Console.Error.WriteLine("ERROR: --api-key required")
            Return 2
        End If
        If businessId <= 0 AndAlso String.IsNullOrWhiteSpace(createName) Then
            createName = "holoo-e2e-opening-" & DateTime.Now.ToString("yyyyMMdd-HHmmss")
        End If

        Dim logPath = Path.Combine(outDir, "e2e-opening-log.txt")
        Dim resultPath = Path.Combine(outDir, "e2e-opening-result.json")
        File.WriteAllText(logPath, "")
        Dim log As Action(Of String) =
            Sub(msg)
                Dim line = DateTime.Now.ToString("s") & " " & msg
                Console.WriteLine(line)
                File.AppendAllText(logPath, line & Environment.NewLine)
            End Sub

        Try
            Return RunCore(apiKey, businessId, createName, docsOnly, withManual, withInvoices, withAllDocs, sampleLimit, sqlServer, sqlUser, sqlPass, sqlDb, baseUrl, resultPath, log).GetAwaiter().GetResult()
        Catch ex As Exception
            log("FATAL: " & ex.ToString())
            File.WriteAllText(resultPath, JsonConvert.SerializeObject(New With {
                .success = False,
                .error = ex.Message,
                .stack = ex.ToString()
            }, Formatting.Indented))
            Return 1
        End Try
    End Function

    Private Shared Async Function RunCore(
        apiKey As String,
        businessId As Integer,
        createName As String,
        docsOnly As Boolean,
        withManual As Boolean,
        withInvoices As Boolean,
        withAllDocs As Boolean,
        sampleLimit As Integer,
        sqlServer As String,
        sqlUser As String,
        sqlPass As String,
        sqlDb As String,
        baseUrl As String,
        resultPath As String,
        log As Action(Of String)
    ) As Task(Of Integer)
        Dim api As New HesabixApiClient()
        api.Configure(baseUrl, apiKey)
        Dim currentUser = Await api.GetMeAsync().ConfigureAwait(False)
        log("auth ok user=" & currentUser.DisplayName)

        Dim session As New MigrationSession With {
            .ApiBaseUrl = baseUrl,
            .ApiKey = apiKey,
            .CurrentUser = currentUser,
            .SqlSettings = New SqlConnectionSettings With {
                .Server = sqlServer,
                .UserName = sqlUser,
                .Password = sqlPass,
                .Database = sqlDb,
                .TrustServerCertificate = True
            },
            .SelectedDatabase = sqlDb,
            .IsSqlConnected = True
        }

        Dim sql As New HolooSqlService()
        Dim probe = Await sql.ProbeDatabaseAsync(session.SqlSettings, sqlDb).ConfigureAwait(False)
        If Not probe.LooksLikeHoloo Then
            Throw New InvalidOperationException("Holoo SQL probe failed: " & probe.SummaryText)
        End If
        session.HolooProbe = probe
        log("sql ok db=" & sqlDb & " tables=" & probe.TableCount.ToString())

        Dim currencyId As Integer
        If businessId <= 0 Then
            Dim currencies = Await api.ListCurrenciesAsync().ConfigureAwait(False)
            Dim irr = currencies.FirstOrDefault(Function(c) String.Equals(c.Code, "IRR", StringComparison.OrdinalIgnoreCase) OrElse
                                                             (c.Title IsNot Nothing AndAlso c.Title.Contains("ریال")))
            If irr Is Nothing Then irr = currencies.FirstOrDefault()
            If irr Is Nothing Then Throw New InvalidOperationException("No currency available")
            Dim req As New NewBusinessRequest With {
                .Name = createName,
                .BusinessType = "شرکت",
                .BusinessField = "بازرگانی",
                .DefaultCurrencyId = irr.Id,
                .IncludeSampleData = False
            }
            Dim biz = Await api.CreateBusinessAsync(req).ConfigureAwait(False)
            businessId = biz.Id
            currencyId = biz.DefaultCurrencyId
            If currencyId <= 0 Then currencyId = irr.Id
            session.SelectedBusiness = biz
            log("created business id=" & businessId.ToString() & " name=" & biz.Name)
        Else
            Dim biz = Await api.GetBusinessDetailsAsync(businessId).ConfigureAwait(False)
            session.SelectedBusiness = biz
            currencyId = biz.DefaultCurrencyId
            log("using business id=" & businessId.ToString() & " name=" & biz.Name)
        End If
        If currencyId <= 0 Then Throw New InvalidOperationException("Business currency id missing")

        ' پایه + افتتاحیه (+ اختیاری اسناد دستی)
        Dim selected = MigrationModuleInfo.GetAllModules()
        For Each m In selected
            If withAllDocs Then
                ' انبار جداگانه است و اغلب permission inventory.write ندارد؛ برای E2E حسابداری پیش‌فرض خاموش
                m.Selected = m.ModuleKey <> MigrationModule.WarehouseDocs
            Else
                m.Selected = MigrationModuleInfo.IsBaseModule(m.ModuleKey) OrElse
                             m.ModuleKey = MigrationModule.FiscalYearsAndOpening OrElse
                             (withManual AndAlso m.ModuleKey = MigrationModule.ManualJournals) OrElse
                             (withInvoices AndAlso (m.ModuleKey = MigrationModule.Invoices OrElse m.ModuleKey = MigrationModule.WarehouseDocs))
            End If
        Next
        session.SelectedModules = selected

        Dim profile As SarfaslProfile = Nothing
        If docsOnly Then
            ' docs-only: اگر پروفایل قفل‌شده بدون critical داریم، از rebuild سخت‌گیرانه عبور نکن
            Dim storeEarly As New SarfaslProfileStore(businessId, sqlDb)
            Dim previous = storeEarly.Load()
            If previous IsNot Nothing AndAlso previous.Locked AndAlso previous.CriticalUnmappedCount = 0 Then
                ' preflight را اجرا کن ولی اگر critical تازه ظاهر شد و قفل قبلی سالم است، قفل قبلی را نگه دار
                Dim preflight = Await New PreflightService().BuildReportAsync(session, api).ConfigureAwait(False)
                session.Preflight = preflight
                session.AllowCurrencyMismatch = Not preflight.CurrencyMatched
                Dim rebuilt = session.SarfaslProfile
                If rebuilt IsNot Nothing AndAlso rebuilt.CriticalUnmappedCount = 0 Then
                    profile = rebuilt
                Else
                    log("docs-only: keep locked profile (rebuilt critical=" &
                        If(rebuilt Is Nothing, "n/a", rebuilt.CriticalUnmappedCount.ToString()) & ")")
                    profile = previous
                    session.SarfaslProfile = previous
                End If
            Else
                log("preflight...")
                Dim preflight = Await New PreflightService().BuildReportAsync(session, api).ConfigureAwait(False)
                session.Preflight = preflight
                session.AllowCurrencyMismatch = Not preflight.CurrencyMatched
                profile = session.SarfaslProfile
            End If
        Else
            log("preflight...")
            Dim preflight = Await New PreflightService().BuildReportAsync(session, api).ConfigureAwait(False)
            session.Preflight = preflight
            session.AllowCurrencyMismatch = Not preflight.CurrencyMatched
            profile = session.SarfaslProfile
        End If
        If profile Is Nothing Then
            Throw New InvalidOperationException("Sarfasl profile was not built")
        End If
        If profile.CriticalUnmappedCount > 0 Then
            Throw New InvalidOperationException("Critical unmapped sarfasl: " & profile.CriticalUnmappedCount.ToString())
        End If
        Dim store As New SarfaslProfileStore(businessId, sqlDb)
        store.LockAndSave(profile)
        session.SarfaslProfileLocked = True
        log("profile locked unmapped=" & profile.UnmappedCount.ToString() & " critical=0 path=" & store.FilePath)

        Dim mods = selected.Where(Function(x) x.Selected AndAlso x.Enabled).Select(Function(x) x.ModuleKey).ToList()
        Dim baseSvc As New BaseDataTransferService()
        AddHandler baseSvc.ProgressChanged, Sub(s, e) log("BASE [" & e.ModuleTitle & "] " & e.Message &
            If(e.IsError, " ERR", ""))
        Dim docSvc As New DocumentTransferService()
        If sampleLimit > 0 Then
            docSvc.SampleLimit = sampleLimit
            log("sample-limit=" & sampleLimit.ToString() & " (per module)")
        End If
        AddHandler docSvc.ProgressChanged, Sub(s, e) log("DOC [" & e.ModuleTitle & "] " & e.Message &
            If(e.IsError, " ERR", ""))

        Dim cpPath As String
        If docsOnly Then
            log("docs-only: skip base transfer")
            ' فقط کلیدهای OB ناموفق را پاک کن تا تلاش مجدد شود؛ موفق‌ها دست نخورند
            Dim storeCp As New CheckpointStore(businessId, sqlDb)
            Dim cp0 = storeCp.LoadOrCreate(baseUrl, businessId, sqlServer, sqlDb)
            Dim fy0 = cp0.EnsureModule(MigrationModule.FiscalYearsAndOpening.ToString())
            Dim failKeys = fy0.Failed.Keys.Where(Function(k) k.StartsWith("OB:")).ToList()
            For Each k In failKeys
                fy0.Failed.Remove(k)
            Next
            storeCp.Save(cp0)
            cpPath = storeCp.FilePath
        Else
            log("base transfer (skip person/product OB)...")
            cpPath = Await baseSvc.RunAsync(session, api, mods, currencyId, resetCheckpoint:=True, skipOpeningBalances:=True).ConfigureAwait(False)
            log("base done checkpoint=" & cpPath)
        End If

        log("opening transfer...")
        cpPath = Await docSvc.RunAsync(session, api, mods, currencyId, resetCheckpoint:=False).ConfigureAwait(False)
        log("docs done checkpoint=" & cpPath)

        Dim cp = New CheckpointStore(businessId, sqlDb).LoadOrCreate(baseUrl, businessId, sqlServer, sqlDb)
        Dim fyMod = cp.EnsureModule(MigrationModule.FiscalYearsAndOpening.ToString())
        Dim obDone = fyMod.Done.Keys.Where(Function(k) k.StartsWith("OB:")).ToList()
        Dim obFailed = fyMod.Failed.Where(Function(kv) kv.Key.StartsWith("OB:")).ToList()
        Dim manMod = cp.EnsureModule(MigrationModule.ManualJournals.ToString())

        Dim proofPath = ""
        Try
            Dim proof = New BalanceProofService().BuildHolooProof(session.SqlSettings, businessId)
            proofPath = New BalanceProofService().SaveReport(proof, businessId, sqlDb)
        Catch ex As Exception
            log("proof warn: " & ex.Message)
        End Try

        Dim success = obDone.Count > 0 AndAlso obFailed.Count = 0
        If withManual Then
            success = success AndAlso manMod.Failed.Count = 0 AndAlso manMod.Done.Count > 0
        End If
        Dim invMod = cp.EnsureModule(MigrationModule.Invoices.ToString())
        If withInvoices OrElse withAllDocs Then
            success = success AndAlso invMod.Failed.Count = 0 AndAlso invMod.Done.Count > 0
        End If
        Dim rcpMod = cp.EnsureModule(MigrationModule.ReceiptsPayments.ToString())
        Dim chkMod = cp.EnsureModule(MigrationModule.Checks.ToString())
        Dim expMod = cp.EnsureModule(MigrationModule.ExpenseIncome.ToString())
        If withAllDocs Then
            success = success AndAlso rcpMod.Failed.Count = 0 AndAlso chkMod.Failed.Count = 0 AndAlso expMod.Failed.Count = 0 AndAlso manMod.Failed.Count = 0
            success = success AndAlso (rcpMod.Done.Count > 0 OrElse chkMod.Done.Count > 0 OrElse expMod.Done.Count > 0 OrElse manMod.Done.Count > 0)
        End If
        Dim result = New With {
            .success = success,
            .businessId = businessId,
            .businessName = session.SelectedBusiness.Name,
            .currencyId = currencyId,
            .openingDoneKeys = obDone,
            .openingFailed = obFailed.ToDictionary(Function(kv) kv.Key, Function(kv) kv.Value),
            .manualDone = manMod.Done.Count,
            .manualFailed = manMod.Failed.Count,
            .manualFailedSample = manMod.Failed.Take(10).ToDictionary(Function(kv) kv.Key, Function(kv) kv.Value),
            .invoiceDone = invMod.Done.Count,
            .invoiceFailed = invMod.Failed.Count,
            .invoiceFailedSample = invMod.Failed.Take(15).ToDictionary(Function(kv) kv.Key, Function(kv) kv.Value),
            .receiptsDone = rcpMod.Done.Count,
            .receiptsFailed = rcpMod.Failed.Count,
            .checksDone = chkMod.Done.Count,
            .checksFailed = chkMod.Failed.Count,
            .expenseDone = expMod.Done.Count,
            .expenseFailed = expMod.Failed.Count,
            .checkpointPath = cpPath,
            .profilePath = store.FilePath,
            .proofPath = proofPath,
            .unmappedCount = profile.UnmappedCount,
            .fiscalYears = If(session.Preflight Is Nothing, New List(Of Object)(),
                session.Preflight.FiscalYears.Select(Function(y) New With {
                    .title = y.Title,
                    .hesabixId = y.HesabixId,
                    .start = y.StartDate.ToString("yyyy-MM-dd"),
                    .end = y.EndDate.ToString("yyyy-MM-dd")
                }).Cast(Of Object)().ToList())
        }
        File.WriteAllText(resultPath, JsonConvert.SerializeObject(result, Formatting.Indented), Text.Encoding.UTF8)
        log("RESULT success=" & success.ToString() & " written=" & resultPath)
        Return If(success, 0, 1)
    End Function

    Private Shared Function Arg(args As String(), name As String) As String
        For i = 0 To args.Length - 1
            If String.Equals(args(i), name, StringComparison.OrdinalIgnoreCase) Then
                If i + 1 < args.Length AndAlso Not args(i + 1).StartsWith("--") Then Return args(i + 1)
                Return "1"
            End If
            If args(i).StartsWith(name & "=", StringComparison.OrdinalIgnoreCase) Then
                Return args(i).Substring(name.Length + 1)
            End If
        Next
        Return Nothing
    End Function

    Private Shared Function ParseInt(s As String) As Integer
        Dim n As Integer
        If Integer.TryParse(If(s, ""), n) Then Return n
        Return 0
    End Function
End Class
