Imports System.Threading

Friend Class PreflightService
    Private ReadOnly _reader As New HolooBaseDataReader()
    Private ReadOnly _discovery As New HolooDiscoveryService()

    Public Async Function BuildReportAsync(
        session As MigrationSession,
        api As HesabixApiClient,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of PreflightReport)
        Dim report As New PreflightReport()

        Dim company = Await Task.Run(Function() _reader.ReadCompany(session.SqlSettings), ct).ConfigureAwait(True)
        report.HolooCompanyName = If(company.Name, "")

        Dim currencies = Await Task.Run(Function() _reader.ReadCurrencies(session.SqlSettings), ct).ConfigureAwait(True)
        Dim baseCur = currencies.FirstOrDefault(Function(c) c.IsBase)
        If baseCur Is Nothing Then baseCur = currencies.FirstOrDefault()
        report.HolooBaseCurrency = If(baseCur IsNot Nothing, baseCur.Name, "(نامشخص)")

        report.CurrencyMode = Await Task.Run(Function() _discovery.DiscoverCurrencyMode(session.SqlSettings), ct).ConfigureAwait(True)
        report.FiscalYears = Await Task.Run(Function() _discovery.DiscoverFiscalYears(session.SqlSettings), ct).ConfigureAwait(True)

        api.Configure(session.ApiBaseUrl, session.ApiKey)
        Dim biz = Await api.GetBusinessDetailsAsync(session.SelectedBusiness.Id, ct).ConfigureAwait(True)
        report.HesabixBusinessName = If(biz.Name, session.SelectedBusiness.Name)
        report.HesabixCurrencyId = biz.DefaultCurrencyId
        report.HesabixCurrencyCode = If(biz.DefaultCurrencyCode, "")
        report.HesabixCurrencyTitle = If(biz.DefaultCurrencyTitle, "")

        report.CurrencyMatched = CurrenciesMatch(report.HolooBaseCurrency, report.HesabixCurrencyCode, report.HesabixCurrencyTitle)

        Dim selected = If(session.SelectedModules, MigrationModuleInfo.GetAllModules())
        report.FullHistorySelected = selected.Any(Function(m) m.Selected AndAlso MigrationModuleInfo.IsDocumentModule(m.ModuleKey))

        report.Issues.Add(New PreflightIssue With {
            .Severity = "info",
            .Title = "نام شرکت / کسب‌وکار",
            .Detail = "هلو: «" & report.HolooCompanyName & "»  |  حسابیکس: «" & report.HesabixBusinessName & "»"
        })

        If report.CurrencyMatched Then
            report.Issues.Add(New PreflightIssue With {
                .Severity = "info",
                .Title = "تطبیق ارز پایه",
                .Detail = "ارز پایه هلو («" & report.HolooBaseCurrency & "») با ارز کسب‌وکار حسابیکس («" &
                          If(String.IsNullOrWhiteSpace(report.HesabixCurrencyTitle), report.HesabixCurrencyCode, report.HesabixCurrencyTitle) & "») سازگار به نظر می‌رسد."
            })
        Else
            report.CanProceed = False
            report.Issues.Add(New PreflightIssue With {
                .Severity = "error",
                .Title = "عدم تطابق ارز پایه",
                .Detail = "ارز پایه هلو: «" & report.HolooBaseCurrency & "» — ارز کسب‌وکار حسابیکس: «" &
                          report.HesabixCurrencyTitle & " / " & report.HesabixCurrencyCode & "». " &
                          "قبل از انتقال اطلاعات پایه، ارز کسب‌وکار مقصد را بررسی کنید یا تأیید دستی بدهید."
            })
        End If

        Dim cm = report.CurrencyMode
        If cm IsNot Nothing Then
            If cm.Mode = "MultiCurrency" Then
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "warning",
                    .Title = "حالت چندارزی",
                    .Detail = "استفاده ارزی عملیاتی دیده شد (فاکتور: " & cm.InvoiceForeignUsage.ToString("N0") &
                              "، سند: " & cm.SanadForeignUsage.ToString("N0") & "). " &
                              "فاکتورها با نگاشت MONEY→ارز حسابیکس و Price_Dollari منتقل می‌شوند؛ ارزهای بدون نگاشت نام روی ارز پایه می‌مانند."
                })
            Else
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "info",
                    .Title = "حالت تک‌ارزی",
                    .Detail = "ارزهای تعریف‌شده در MONEY: " & cm.DefinedCount.ToString() &
                              " — استفاده عملیاتی غیرپایه یافت نشد؛ همه اسناد با ارز پایه منتقل می‌شوند."
                })
            End If
        End If

        If report.FiscalYears.Count = 0 Then
            report.Issues.Add(New PreflightIssue With {
                .Severity = "warning",
                .Title = "سال مالی",
                .Detail = "بازه سال مالی از روی تاریخ اسناد استخراج نشد."
            })
        Else
            Dim fyText = String.Join(" | ", report.FiscalYears.Select(
                Function(f) f.Title & " (" & ApiDateFormat.ToIsoDate(f.StartDate) & "→" & ApiDateFormat.ToIsoDate(f.EndDate) &
                            "، فاکتور " & f.InvoiceCount.ToString("N0") & ")"))
            report.Issues.Add(New PreflightIssue With {
                .Severity = "info",
                .Title = "سال‌های مالی کشف‌شده",
                .Detail = fyText
            })
        End If

        For Each opt In selected.Where(Function(x) x.Enabled)
            ct.ThrowIfCancellationRequested()
            Dim moduleKey = opt.ModuleKey
            Dim count As Long = -1
            If MigrationModuleInfo.IsBaseModule(moduleKey) Then
                count = Await Task.Run(Function() _reader.CountModule(session.SqlSettings, moduleKey), ct).ConfigureAwait(True)
            ElseIf moduleKey = MigrationModule.Invoices Then
                count = Await Task.Run(Function() _reader.CountSql(session.SqlSettings,
                    "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0;"), ct).ConfigureAwait(True)
            ElseIf moduleKey = MigrationModule.ReceiptsPayments Then
                count = Await Task.Run(Function() _reader.CountSql(session.SqlSettings,
                    "SELECT COUNT(*) FROM SANAD WHERE ISNULL([Delete],0)=0 AND ISNULL(SaveFromFacture,0)=0 AND Sanad_Type=20;"), ct).ConfigureAwait(True)
            ElseIf moduleKey = MigrationModule.Checks Then
                count = Await Task.Run(Function() _reader.CountSql(session.SqlSettings,
                    "SELECT COUNT(*) FROM [Check] WHERE ISNULL([Delete],0)=0;"), ct).ConfigureAwait(True)
            ElseIf moduleKey = MigrationModule.FiscalYearsAndOpening Then
                count = report.FiscalYears.Count
            End If
            If count >= 0 Then
                report.ModuleCounts(opt.ModuleKey.ToString()) = count
                opt.SourceCount = count
                If count = 0 AndAlso MigrationModuleInfo.IsBaseModule(moduleKey) Then
                    report.Issues.Add(New PreflightIssue With {
                        .Severity = "warning",
                        .Title = opt.Title,
                        .Detail = "در دیتابیس هلو رکوردی برای این بخش یافت نشد."
                    })
                End If
            End If
        Next

        If report.FullHistorySelected Then
            report.Issues.Add(New PreflightIssue With {
                .Severity = "info",
                .Title = "حالت Full History",
                .Detail = "اشخاص/کالا بدون مانده افتتاحیه جداگانه منتقل می‌شوند؛ افتتاحیه از سند افتتاحیه سال اول و اسناد به‌ترتیب سال مالی ثبت می‌گردند."
            })
            If report.FiscalYears.Count = 0 Then
                report.CanProceed = False
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "error",
                    .Title = "سال مالی لازم است",
                    .Detail = "برای انتقال اسناد باید حداقل یک سال مالی از تاریخ‌ها استخراج شود."
                })
            End If
        Else
            report.Issues.Add(New PreflightIssue With {
                .Severity = "info",
                .Title = "محدوده انتخاب‌شده",
                .Detail = "فقط اطلاعات پایه (یا بخشی از آن) انتخاب شده است."
            })
        End If

        Return report
    End Function

    Private Shared Function CurrenciesMatch(holooName As String, hesabixCode As String, hesabixTitle As String) As Boolean
        Dim h = NormalizeCurrencyText(holooName)
        Dim c = NormalizeCurrencyText(hesabixCode)
        Dim t = NormalizeCurrencyText(hesabixTitle)
        If String.IsNullOrWhiteSpace(h) Then Return False

        Dim holooIsIrr = IsIranianRialToken(h)
        Dim hesabixIsIrr = IsIranianRialToken(c) OrElse IsIranianRialToken(t)
        If holooIsIrr AndAlso hesabixIsIrr Then Return True

        If Not String.IsNullOrWhiteSpace(t) AndAlso (h.Contains(t) OrElse t.Contains(h)) Then Return True
        If Not String.IsNullOrWhiteSpace(c) AndAlso (h.Contains(c) OrElse c.Contains(h)) Then Return True
        Return False
    End Function

    Private Shared Function IsIranianRialToken(text As String) As Boolean
        If String.IsNullOrWhiteSpace(text) Then Return False
        If text = "irr" OrElse text = "irt" OrElse text = "rial" OrElse text = "rials" Then Return True
        If text.Contains("rial") OrElse text.Contains("irr") OrElse text.Contains("irt") Then Return True
        If text.Contains("ریال") OrElse text.Contains("rial") Then Return True
        Return False
    End Function

    Private Shared Function NormalizeCurrencyText(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return ""
        Dim s = value.Trim().ToLowerInvariant()
        s = s.Replace("ي", "ی")
        s = s.Replace("ى", "ی")
        s = s.Replace("ك", "ک")
        s = s.Replace("آ", "ا").Replace("أ", "ا").Replace("إ", "ا").Replace("ة", "ه")
        s = s.Replace("‌", "")
        s = s.Replace(" ", "").Replace("-", "").Replace("_", "")
        s = s.Replace("ایران", "").Replace("iran", "").Replace("iranian", "")
        Return s
    End Function
End Class
