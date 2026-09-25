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

            Dim overlapManualInvoice As Long = Await Task.Run(Function() _reader.CountSql(session.SqlSettings,
                "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                "AND EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));"), ct).ConfigureAwait(True)
            Dim manualCount As Long = Await Task.Run(Function() _reader.CountModule(session.SqlSettings, MigrationModule.ManualJournals), ct).ConfigureAwait(True)
            report.ModuleCounts(MigrationModule.ManualJournals.ToString()) = manualCount
            report.Issues.Add(New PreflightIssue With {
                .Severity = "info",
                .Title = "اسناد دستی (پس از پارتیشن)",
                .Detail = "کاندید دستی بدون فاکتور/چک/هزینه: " & manualCount.ToString("N0") &
                          " — اسناد متصل به فاکتور که از دستی حذف شدند: " & overlapManualInvoice.ToString("N0") &
                          " (GL آن‌ها فقط از ماژول فاکتور ساخته می‌شود)."
            })

            Dim auditRows = Await Task.Run(Function() New SarfaslAuditService().Audit(session.SqlSettings), ct).ConfigureAwait(True)
            report.SarfaslAuditRows = auditRows
            report.RequiresSarfaslLock = True
            Dim unmapped = auditRows.Where(Function(x) x.Decision = "Unmapped").ToList()
            Dim bizAcc = auditRows.Where(Function(x) x.Decision = "BusinessExpense" OrElse x.Decision = "BusinessLoan" OrElse x.Decision = "BusinessIncome").ToList()
            report.Issues.Add(New PreflightIssue With {
                .Severity = If(unmapped.Count = 0, "info", "warning"),
                .Title = "پوشش نگاشت جدول حساب‌ها",
                .Detail = SarfaslAuditService.FormatReport(auditRows)
            })

            Dim store As New SarfaslProfileStore(session.SelectedBusiness.Id, session.SelectedDatabase)
            Dim previous = store.Load()
            Dim profile = SarfaslProfileStore.FromAudit(session.SelectedBusiness.Id, session.SelectedDatabase, auditRows, previous)
            ' قفل قبلی فقط اگر همان مجموعه سرفصل بدون Unmapped بحرانی باشد حفظ می‌شود
            If previous IsNot Nothing AndAlso previous.Locked AndAlso profile.CriticalUnmappedCount = 0 Then
                profile.Locked = True
                profile.LockedAt = previous.LockedAt
            End If
            session.SarfaslProfile = profile
            session.SarfaslProfileLocked = profile.Locked
            store.Save(profile)

            If profile.CriticalUnmappedCount > 0 Then
                report.CanProceed = False
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "error",
                    .Title = "سرفصل بحرانی بدون نگاشت",
                    .Detail = profile.CriticalUnmappedCount.ToString() & " ترکیب در Colهای ترازنامه‌ای/هزینه بدون مقصد — انتقال تا رفع نگاشت متوقف است."
                })
            ElseIf unmapped.Count > 0 Then
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "warning",
                    .Title = "سرفصل بدون نگاشت",
                    .Detail = unmapped.Count.ToString() & " ترکیب Col/Moien بدون مقصد — خطوط مربوط Fail می‌شوند."
                })
            End If
            If bizAcc.Count > 0 Then
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "info",
                    .Title = "حساب اختصاصی کسب‌وکار",
                    .Detail = bizAcc.Count.ToString() & " سرفصل (هزینه بدون معادل / وام زیر ۴۰۱) هنگام انتقال به‌صورت حساب اختصاصی زیر گروه استاندارد ساخته می‌شوند."
                })
            End If
            If Not profile.Locked Then
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "warning",
                    .Title = "قفل پروفایل نگاشت",
                    .Detail = "برای شروع انتقال اسناد، جدول نگاشت را بازبینی و گزینه «قفل پروفایل نگاشت» را تأیید کنید. مسیر: " & store.FilePath
                })
            End If
        Else
            report.RequiresSarfaslLock = False
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
