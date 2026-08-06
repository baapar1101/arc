Imports System.Threading

Friend Class PreflightService
    Private ReadOnly _reader As New HolooBaseDataReader()

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

        api.Configure(session.ApiBaseUrl, session.ApiKey)
        Dim biz = Await api.GetBusinessDetailsAsync(session.SelectedBusiness.Id, ct).ConfigureAwait(True)
        report.HesabixBusinessName = If(biz.Name, session.SelectedBusiness.Name)
        report.HesabixCurrencyId = biz.DefaultCurrencyId
        report.HesabixCurrencyCode = If(biz.DefaultCurrencyCode, "")
        report.HesabixCurrencyTitle = If(biz.DefaultCurrencyTitle, "")

        report.CurrencyMatched = CurrenciesMatch(report.HolooBaseCurrency, report.HesabixCurrencyCode, report.HesabixCurrencyTitle)

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

        For Each opt In MigrationModuleInfo.GetBaseModules()
            ct.ThrowIfCancellationRequested()
            Dim moduleKey = opt.ModuleKey
            Dim count = Await Task.Run(Function() _reader.CountModule(session.SqlSettings, moduleKey), ct).ConfigureAwait(True)
            report.ModuleCounts(opt.ModuleKey.ToString()) = count
            If count = 0 Then
                report.Issues.Add(New PreflightIssue With {
                    .Severity = "warning",
                    .Title = opt.Title,
                    .Detail = "در دیتابیس هلو رکوردی برای این بخش یافت نشد."
                })
            End If
        Next

        report.Issues.Add(New PreflightIssue With {
            .Severity = "info",
            .Title = "محدوده این فاز",
            .Detail = "فقط اطلاعات پایه منتقل می‌شود. فاکتور، اسناد حسابداری، اسناد انبار، سرفصل و چک‌های عملیاتی در فاز بعد هستند."
        })

        Return report
    End Function

    Private Shared Function CurrenciesMatch(holooName As String, hesabixCode As String, hesabixTitle As String) As Boolean
        Dim h = NormalizeCurrencyText(holooName)
        Dim c = NormalizeCurrencyText(hesabixCode)
        Dim t = NormalizeCurrencyText(hesabixTitle)
        If String.IsNullOrWhiteSpace(h) Then Return False

        ' ریال ایران / IRR / IRT / ريال (ی عربی هلو) همگی یک خانواده هستند
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
        ' بعد از نرمال‌سازی، هم «ریال» و هم «ريال» به یک شکل می‌رسند
        If text.Contains("ریال") OrElse text.Contains("rial") Then Return True
        Return False
    End Function

    ''' <summary>
    ''' یکسان‌سازی حروف عربی/فارسی و حذف پسوندهای رایج برای مقایسه ارز.
    ''' هلو اغلب از ی عربی (ي) استفاده می‌کند؛ حسابیکس از ی فارسی (ی).
    ''' </summary>
    Private Shared Function NormalizeCurrencyText(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return ""
        Dim s = value.Trim().ToLowerInvariant()
        s = s.Replace("ي", "ی") ' Arabic Yeh -> Persian Yeh
        s = s.Replace("ى", "ی") ' Alef Maksura-like Yeh
        s = s.Replace("ك", "ک") ' Arabic Kaf -> Persian Kaf
        s = s.Replace("آ", "ا").Replace("أ", "ا").Replace("إ", "ا").Replace("ة", "ه")
        s = s.Replace("‌", "") ' ZWNJ
        s = s.Replace(" ", "").Replace("-", "").Replace("_", "")
        s = s.Replace("ایران", "").Replace("iran", "").Replace("iranian", "")
        Return s
    End Function
End Class
