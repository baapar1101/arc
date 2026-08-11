Imports System.Net
Imports System.Net.Http
Imports System.Net.Http.Headers
Imports System.Text
Imports System.Threading
Imports Newtonsoft.Json
Imports Newtonsoft.Json.Linq

Friend Class HesabixApiException
    Inherits Exception

    Public ReadOnly Property StatusCode As Integer
    Public ReadOnly Property ErrorCode As String

    Public Sub New(message As String, Optional statusCode As Integer = 0, Optional errorCode As String = Nothing, Optional inner As Exception = Nothing)
        MyBase.New(message, inner)
        Me.StatusCode = statusCode
        Me.ErrorCode = errorCode
    End Sub
End Class

Friend Class HesabixApiClient
    Implements IDisposable

    Private ReadOnly _http As HttpClient
    Private ReadOnly _sync As New Object()
    Private _disposed As Boolean
    Private _baseUrl As String = ""
    Private _apiKey As String = ""

    Public Sub New()
        Dim handler As New HttpClientHandler()
        handler.AutomaticDecompression = DecompressionMethods.GZip Or DecompressionMethods.Deflate
        _http = New HttpClient(handler)
        ' فاکتور گروهی و افتتاحیه روی سرور ممکن است بیش از ۵ دقیقه طول بکشد
        _http.Timeout = TimeSpan.FromMinutes(60)
        _http.DefaultRequestHeaders.Accept.Clear()
        _http.DefaultRequestHeaders.Accept.Add(New MediaTypeWithQualityHeaderValue("application/json"))
        ' BaseAddress عمداً تنظیم نمی‌شود؛ بعد از اولین درخواست قابل تغییر نیست.
    End Sub

    Public Sub SetBaseUrl(baseUrl As String)
        If String.IsNullOrWhiteSpace(baseUrl) Then
            Throw New ArgumentException("آدرس سرور حسابیکس خالی است.")
        End If
        SyncLock _sync
            _baseUrl = baseUrl.Trim().TrimEnd("/"c)
        End SyncLock
    End Sub

    Public Sub Configure(baseUrl As String, apiKey As String)
        SetBaseUrl(baseUrl)
        If String.IsNullOrWhiteSpace(apiKey) Then
            Throw New ArgumentException("کلید API خالی است.")
        End If
        SetApiKey(apiKey)
    End Sub

    Public Sub SetApiKey(apiKey As String)
        SyncLock _sync
            _apiKey = If(apiKey, "").Trim()
        End SyncLock
    End Sub

    Public Sub ClearApiKey()
        SyncLock _sync
            _apiKey = ""
        End SyncLock
    End Sub

    Public Async Function GetCaptchaAsync(Optional ct As CancellationToken = Nothing) As Task(Of CaptchaChallenge)
        ClearApiKey()
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/auth/captcha", Nothing, includeAuth:=False, ct:=ct).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Return New CaptchaChallenge With {
            .CaptchaId = GetString(data, "captcha_id"),
            .ImageBase64 = GetString(data, "image_base64"),
            .TtlSeconds = GetInt(data, "ttl_seconds")
        }
    End Function

    Public Async Function LoginAsync(identifier As String, password As String, captchaId As String, captchaCode As String, Optional ct As CancellationToken = Nothing) As Task(Of LoginResult)
        ClearApiKey()
        Dim payload As New JObject From {
            {"identifier", identifier},
            {"password", password},
            {"captcha_id", captchaId},
            {"captcha_code", captchaCode},
            {"device_id", "holoo2hesabix-desktop"}
        }
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/auth/login", payload, includeAuth:=False, ct:=ct).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Dim apiKey = GetString(data, "api_key")
        If String.IsNullOrWhiteSpace(apiKey) Then
            Throw New HesabixApiException("سرور کلید API برنگرداند.")
        End If
        Dim userToken = data("user")
        Dim user As HesabixUser
        If userToken IsNot Nothing AndAlso userToken.Type = JTokenType.Object Then
            user = ParseUser(DirectCast(userToken, JObject))
        Else
            user = New HesabixUser()
        End If
        SetApiKey(apiKey)
        Return New LoginResult With {.ApiKey = apiKey, .User = user}
    End Function

    Public Async Function GetMeAsync(Optional ct As CancellationToken = Nothing) As Task(Of HesabixUser)
        Dim root = Await GetJsonAsync("api/v1/auth/me", ct).ConfigureAwait(False)
        Return ParseUser(GetDataToken(root))
    End Function

    Public Async Function ListBusinessesAsync(Optional take As Integer = 100, Optional ct As CancellationToken = Nothing) As Task(Of List(Of HesabixBusiness))
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/businesses/list?take=" & take.ToString() & "&skip=0", Nothing, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Dim items = GetItemsArray(data)
        Dim list As New List(Of HesabixBusiness)
        For Each item As JToken In items
            Dim obj = TryCast(item, JObject)
            If obj Is Nothing Then Continue For
            list.Add(New HesabixBusiness With {
                .Id = GetInt(obj, "id"),
                .Name = GetString(obj, "name"),
                .BusinessType = GetString(obj, "business_type"),
                .BusinessField = GetString(obj, "business_field"),
                .OwnerId = GetNullableInt(obj, "owner_id"),
                .CreatedAt = GetString(obj, "created_at")
            })
        Next
        Return list
    End Function

    Public Async Function ListCurrenciesAsync(Optional ct As CancellationToken = Nothing) As Task(Of List(Of CurrencyInfo))
        Dim root = Await GetJsonAsync("api/v1/currencies", ct).ConfigureAwait(False)
        Dim dataToken = root("data")
        Dim list As New List(Of CurrencyInfo)
        Dim items As JArray
        If dataToken IsNot Nothing AndAlso dataToken.Type = JTokenType.Array Then
            items = DirectCast(dataToken, JArray)
        ElseIf dataToken IsNot Nothing AndAlso dataToken.Type = JTokenType.Object Then
            items = GetItemsArray(DirectCast(dataToken, JObject))
        Else
            items = New JArray()
        End If
        For Each item As JToken In items
            Dim obj = TryCast(item, JObject)
            If obj Is Nothing Then Continue For
            list.Add(ParseCurrency(obj))
        Next
        Return list
    End Function

    Public Async Function CreateBusinessAsync(request As NewBusinessRequest, Optional ct As CancellationToken = Nothing) As Task(Of HesabixBusiness)
        Dim payload As New JObject From {
            {"name", request.Name},
            {"business_type", request.BusinessType},
            {"business_field", request.BusinessField},
            {"default_currency_id", request.DefaultCurrencyId},
            {"include_sample_data", request.IncludeSampleData}
        }
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/businesses", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return ParseBusiness(GetDataToken(root))
    End Function

    Public Async Function GetBusinessDetailsAsync(businessId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of HesabixBusiness)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/businesses/" & businessId.ToString() & "/details", New JObject(), includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return ParseBusiness(GetDataToken(root))
    End Function

    Public Async Function CreatePersonAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/persons/businesses/" & businessId.ToString() & "/persons/create", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    ''' <summary>
    ''' ایجاد/به‌روزرسانی گروهی اشخاص. هر آیتم: { client_ref?, person_id?, payload }.
    ''' حداکثر ۱۰۰۰ آیتم در هر درخواست (سمت سرور).
    ''' </summary>
    Public Async Function BulkUpsertPersonsAsync(
        businessId As Integer,
        items As JArray,
        Optional createIfUpdateMissing As Boolean = True,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of BulkUpsertResult)
        Dim body As New JObject From {
            {"items", items},
            {"create_if_update_missing", createIfUpdateMissing}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/persons/businesses/" & businessId.ToString() & "/persons/bulk-upsert",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return ParseBulkUpsertResult(GetDataToken(root), "person_id")
    End Function

    Public Async Function CreateWarehouseAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/warehouses/business/" & businessId.ToString(), payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Dim id = GetInt(data, "id")
        If id = 0 AndAlso data("item") IsNot Nothing Then id = GetInt(DirectCast(data("item"), JObject), "id")
        Return id
    End Function

    Public Async Function CreateBankAccountAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/bank-accounts/businesses/" & businessId.ToString() & "/bank-accounts/create", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    Public Async Function CreateCashRegisterAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/cash-registers/businesses/" & businessId.ToString() & "/cash-registers/create", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    Public Async Function CreatePettyCashAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/petty-cash/businesses/" & businessId.ToString() & "/petty-cash/create", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    Public Async Function CreateProductAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/products/business/" & businessId.ToString(), payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    ''' <summary>
    ''' ایجاد/به‌روزرسانی گروهی کالا. هر آیتم: { client_ref?, product_id?, payload }.
    ''' حداکثر ۱۰۰۰ آیتم در هر درخواست (سمت سرور).
    ''' </summary>
    Public Async Function BulkUpsertProductsAsync(
        businessId As Integer,
        items As JArray,
        Optional createIfUpdateMissing As Boolean = True,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of BulkUpsertResult)
        Dim body As New JObject From {
            {"items", items},
            {"create_if_update_missing", createIfUpdateMissing}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/products/business/" & businessId.ToString() & "/bulk-upsert",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return ParseBulkUpsertResult(GetDataToken(root), "product_id")
    End Function

    Public Async Function ListWarehousesAsync(businessId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of Dictionary(Of String, Integer))
        Dim root = Await GetJsonAsync("api/v1/warehouses/business/" & businessId.ToString(), ct).ConfigureAwait(False)
        Dim map As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
        For Each itemToken In GetItemsArray(GetDataToken(root))
            If itemToken Is Nothing OrElse itemToken.Type <> JTokenType.Object Then Continue For
            Dim item = DirectCast(itemToken, JObject)
            Dim code = GetString(item, "code")
            Dim id = GetInt(item, "id")
            If Not String.IsNullOrWhiteSpace(code) AndAlso id > 0 AndAlso Not map.ContainsKey(code.Trim()) Then
                map(code.Trim()) = id
            End If
        Next
        Return map
    End Function

    Public Async Function FindPersonIdByCodeAsync(businessId As Integer, code As Integer, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim payload As New JObject From {
            {"search", code.ToString()},
            {"search_fields", New JArray From {"code"}},
            {"take", 50},
            {"skip", 0}
        }
        Dim root = Await SendJsonAsync(HttpMethod.Post, "api/v1/persons/businesses/" & businessId.ToString() & "/persons", payload, includeAuth:=True, ct:=ct).ConfigureAwait(False)
        For Each itemToken In GetItemsArray(GetDataToken(root))
            If itemToken Is Nothing OrElse itemToken.Type <> JTokenType.Object Then Continue For
            Dim item = DirectCast(itemToken, JObject)
            If GetInt(item, "code") = code Then
                Return GetInt(item, "id")
            End If
        Next
        Return 0
    End Function

    Public Async Function FindProductIdByCodeAsync(businessId As Integer, code As String, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        If String.IsNullOrWhiteSpace(code) Then Return 0
        Dim payload As New JObject From {
            {"search", code.Trim()},
            {"search_fields", New JArray From {"code"}},
            {"take", 50},
            {"skip", 0}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/products/business/" & businessId.ToString() & "/search",
            payload,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Dim codeNorm = code.Trim()
        For Each itemToken In GetItemsArray(GetDataToken(root))
            If itemToken Is Nothing OrElse itemToken.Type <> JTokenType.Object Then Continue For
            Dim item = DirectCast(itemToken, JObject)
            Dim itemCode = GetString(item, "code")
            If Not String.IsNullOrWhiteSpace(itemCode) AndAlso
               String.Equals(itemCode.Trim(), codeNorm, StringComparison.OrdinalIgnoreCase) Then
                Return GetInt(item, "id")
            End If
        Next
        Return 0
    End Function

    Public Async Function HasCurrentFiscalYearAsync(businessId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of Boolean)
        Try
            Dim root = Await GetJsonAsync("api/v1/business/" & businessId.ToString() & "/fiscal-years", ct).ConfigureAwait(False)
            Dim items = GetItemsArray(GetDataToken(root))
            Return items IsNot Nothing AndAlso items.Count > 0
        Catch
            Return False
        End Try
    End Function

    Public Async Function ListFiscalYearsAsync(businessId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of List(Of HesabixFiscalYear))
        Dim root = Await GetJsonAsync("api/v1/business/" & businessId.ToString() & "/fiscal-years", ct).ConfigureAwait(False)
        Dim list As New List(Of HesabixFiscalYear)
        For Each itemToken In GetItemsArray(GetDataToken(root))
            Dim obj = TryCast(itemToken, JObject)
            If obj Is Nothing Then Continue For
            list.Add(ParseFiscalYear(obj))
        Next
        Return list
    End Function

    Public Async Function UpdateCurrentFiscalYearAsync(
        businessId As Integer,
        title As String,
        startDate As Date,
        endDate As Date,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of HesabixFiscalYear)
        Dim body As New JObject From {
            {"title", title},
            {"start_date", ApiDateFormat.ToIsoDate(startDate)},
            {"end_date", ApiDateFormat.ToIsoDate(endDate)}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Put,
            "api/v1/business/" & businessId.ToString() & "/fiscal-years/current",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Return ParseFiscalYear(data)
    End Function

    Public Async Function EnsureFiscalYearsAsync(
        businessId As Integer,
        years As IEnumerable(Of HolooFiscalYearSlice),
        Optional currentStartDate As Date? = Nothing,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of EnsureFiscalYearsResult)
        Dim arr As New JArray()
        For Each y In years
            arr.Add(New JObject From {
                {"title", y.Title},
                {"start_date", ApiDateFormat.ToIsoDate(y.StartDate)},
                {"end_date", ApiDateFormat.ToIsoDate(y.EndDate)}
            })
        Next
        Dim body As New JObject From {{"years", arr}}
        If currentStartDate.HasValue Then
            body("current_start_date") = ApiDateFormat.ToIsoDate(currentStartDate.Value)
        End If
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/business/" & businessId.ToString() & "/fiscal-years/migration/ensure",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Dim result As New EnsureFiscalYearsResult With {
            .CreatedCount = GetInt(data, "created_count"),
            .ReusedCount = GetInt(data, "reused_count")
        }
        Dim currentTok = data("current")
        If currentTok IsNot Nothing AndAlso currentTok.Type = JTokenType.Object Then
            result.Current = ParseFiscalYear(DirectCast(currentTok, JObject))
        End If
        For Each itemToken In GetItemsArray(data)
            Dim obj = TryCast(itemToken, JObject)
            If obj Is Nothing Then Continue For
            result.Items.Add(ParseFiscalYear(obj))
        Next
        ' برخی پاسخ‌ها items را مستقیم در data.items دارند؛ GetItemsArray همان را می‌خواند.
        If result.Items.Count = 0 Then
            Dim itemsTok = data("items")
            If itemsTok IsNot Nothing AndAlso itemsTok.Type = JTokenType.Array Then
                For Each itemToken In DirectCast(itemsTok, JArray)
                    Dim obj = TryCast(itemToken, JObject)
                    If obj Is Nothing Then Continue For
                    result.Items.Add(ParseFiscalYear(obj))
                Next
            End If
        End If
        Return result
    End Function

    Public Async Function SetCurrentFiscalYearAsync(businessId As Integer, fiscalYearId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of HesabixFiscalYear)
        ' مهم: از مسیر .../fiscal-years/{id}/set-current استفاده می‌کنیم.
        ' مسیر .../migration/set-current با پارامتر {fiscal_year_id} تداخل داشت و "migration" به‌عنوان int پارس می‌شد.
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/business/" & businessId.ToString() & "/fiscal-years/" & fiscalYearId.ToString() & "/set-current",
            New JObject(),
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Return ParseFiscalYear(data)
    End Function

    Public Async Function BulkUpsertInvoicesAsync(
        businessId As Integer,
        items As JArray,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of BulkUpsertResult)
        Dim body As New JObject From {
            {"items", items},
            {"migration_mode", True}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/invoices/business/" & businessId.ToString() & "/bulk-upsert",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return ParseBulkUpsertResult(GetDataToken(root), "invoice_id")
    End Function

    Public Async Function BulkUpsertReceiptsPaymentsAsync(
        businessId As Integer,
        items As JArray,
        Optional migrationMode As Boolean = True,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of BulkUpsertResult)
        Dim body As New JObject From {
            {"items", items},
            {"migration_mode", migrationMode}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/businesses/" & businessId.ToString() & "/receipts-payments/bulk-upsert",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return ParseBulkUpsertResult(GetDataToken(root), "document_id")
    End Function

    Public Async Function BulkUpsertExpenseIncomeAsync(
        businessId As Integer,
        items As JArray,
        Optional migrationMode As Boolean = True,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of BulkUpsertResult)
        Dim body As New JObject From {
            {"items", items},
            {"migration_mode", migrationMode}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/businesses/" & businessId.ToString() & "/expense-income/bulk-upsert",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return ParseBulkUpsertResult(GetDataToken(root), "document_id")
    End Function

    Public Async Function CreateCheckAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/businesses/" & businessId.ToString() & "/checks/create",
            payload,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    Public Async Function CreateManualDocumentAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/businesses/" & businessId.ToString() & "/documents/manual",
            payload,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return GetInt(GetDataToken(root), "id")
    End Function

    Public Async Function ClearCheckAsync(checkId As Integer, bankAccountId As Integer, Optional documentDate As Date? = Nothing, Optional ct As CancellationToken = Nothing) As Task
        Dim body As New JObject From {{"bank_account_id", bankAccountId}}
        If documentDate.HasValue Then body("document_date") = ApiDateFormat.ToIsoDate(documentDate.Value)
        Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/checks/" & checkId.ToString() & "/actions/clear",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
    End Function

    Public Async Function ReturnCheckAsync(
        checkId As Integer,
        Optional returnType As String = "to_drawer",
        Optional documentDate As Date? = Nothing,
        Optional ct As CancellationToken = Nothing
    ) As Task
        Dim body As New JObject From {{"return_type", returnType}}
        If documentDate.HasValue Then body("document_date") = ApiDateFormat.ToIsoDate(documentDate.Value)
        Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/checks/" & checkId.ToString() & "/actions/return",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
    End Function

    Public Async Function ListAccountCodeMapAsync(businessId As Integer, Optional ct As CancellationToken = Nothing) As Task(Of Dictionary(Of String, Integer))
        Dim root = Await GetJsonAsync("api/v1/accounts/business/" & businessId.ToString(), ct).ConfigureAwait(False)
        Dim map As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
        For Each itemToken In GetItemsArray(GetDataToken(root))
            Dim obj = TryCast(itemToken, JObject)
            If obj Is Nothing Then Continue For
            Dim code = GetString(obj, "code")
            Dim id = GetInt(obj, "id")
            If Not String.IsNullOrWhiteSpace(code) AndAlso id > 0 AndAlso Not map.ContainsKey(code.Trim()) Then
                map(code.Trim()) = id
            End If
        Next
        Return map
    End Function

    Public Async Function UpsertOpeningBalanceAsync(businessId As Integer, payload As JObject, Optional ct As CancellationToken = Nothing) As Task(Of JObject)
        Dim root = Await SendJsonAsync(
            HttpMethod.Put,
            "api/v1/businesses/" & businessId.ToString() & "/opening-balance",
            payload,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return GetDataToken(root)
    End Function

    Public Async Function PostOpeningBalanceAsync(businessId As Integer, fiscalYearId As Integer, Optional ct As CancellationToken = Nothing) As Task
        Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/businesses/" & businessId.ToString() & "/opening-balance/post?fiscal_year_id=" & fiscalYearId.ToString(),
            New JObject(),
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
    End Function

    Public Async Function FindAccountIdByCodeAsync(businessId As Integer, code As String, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        If String.IsNullOrWhiteSpace(code) Then Return 0
        Dim root = Await GetJsonAsync("api/v1/accounts/business/" & businessId.ToString(), ct).ConfigureAwait(False)
        Dim data = GetDataToken(root)
        Dim items = GetItemsArray(data)
        If items.Count = 0 Then
            Dim dataTok = root("data")
            If dataTok IsNot Nothing AndAlso dataTok.Type = JTokenType.Array Then
                items = DirectCast(dataTok, JArray)
            End If
        End If
        Dim codeNorm = code.Trim()
        For Each itemToken In items
            Dim obj = TryCast(itemToken, JObject)
            If obj Is Nothing Then Continue For
            Dim itemCode = GetString(obj, "code")
            If String.Equals(If(itemCode, "").Trim(), codeNorm, StringComparison.OrdinalIgnoreCase) Then
                Return GetInt(obj, "id")
            End If
        Next
        Return 0
    End Function

    Public Async Function BulkWarehouseOperationsAsync(
        businessId As Integer,
        invoiceIds As IEnumerable(Of Integer),
        operation As String,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of JObject)
        Dim ids As New JArray()
        For Each id In invoiceIds
            ids.Add(id)
        Next
        Dim body As New JObject From {
            {"invoice_ids", ids},
            {"operation", operation}
        }
        Dim root = Await SendJsonAsync(
            HttpMethod.Post,
            "api/v1/warehouse-docs/business/" & businessId.ToString() & "/invoices/bulk-warehouse-operations",
            body,
            includeAuth:=True,
            ct:=ct
        ).ConfigureAwait(False)
        Return GetDataToken(root)
    End Function

    Private Shared Function ParseFiscalYear(obj As JObject) As HesabixFiscalYear
        ' start_date ممکن است جلالی فرمت‌شده باشد؛ برای پارس ماشینی start_date_raw ارجح است
        Dim startRaw = GetString(obj, "start_date_raw")
        Dim endRaw = GetString(obj, "end_date_raw")
        Return New HesabixFiscalYear With {
            .Id = GetInt(obj, "id"),
            .Title = GetString(obj, "title"),
            .StartDate = If(Not String.IsNullOrWhiteSpace(startRaw), startRaw, GetString(obj, "start_date")),
            .EndDate = If(Not String.IsNullOrWhiteSpace(endRaw), endRaw, GetString(obj, "end_date")),
            .IsCurrent = GetBool(obj, "is_current", False)
        }
    End Function

    Private Shared Function ParseBusiness(data As JObject) As HesabixBusiness
        Dim biz As New HesabixBusiness With {
            .Id = GetInt(data, "id"),
            .Name = GetString(data, "name"),
            .BusinessType = GetString(data, "business_type"),
            .BusinessField = GetString(data, "business_field"),
            .OwnerId = GetNullableInt(data, "owner_id"),
            .CreatedAt = GetString(data, "created_at"),
            .DefaultCurrencyId = GetInt(data, "default_currency_id")
        }
        Dim currencyToken = data("default_currency")
        If currencyToken IsNot Nothing AndAlso currencyToken.Type = JTokenType.Object Then
            Dim currencyObj = DirectCast(currencyToken, JObject)
            If biz.DefaultCurrencyId = 0 Then biz.DefaultCurrencyId = GetInt(currencyObj, "id")
            biz.DefaultCurrencyCode = GetString(currencyObj, "code")
            biz.DefaultCurrencyTitle = GetString(currencyObj, "title")
            If String.IsNullOrWhiteSpace(biz.DefaultCurrencyTitle) Then biz.DefaultCurrencyTitle = GetString(currencyObj, "name")
        End If
        Return biz
    End Function

    Private Shared Function ParseUser(data As JObject) As HesabixUser
        Return New HesabixUser With {
            .Id = GetInt(data, "id"),
            .Email = GetString(data, "email"),
            .Mobile = GetString(data, "mobile"),
            .FirstName = GetString(data, "first_name"),
            .LastName = GetString(data, "last_name"),
            .IsActive = GetBool(data, "is_active", True)
        }
    End Function

    Private Shared Function ParseCurrency(item As JObject) As CurrencyInfo
        Return New CurrencyInfo With {
            .Id = GetInt(item, "id"),
            .Name = GetString(item, "name"),
            .Title = GetString(item, "title"),
            .Symbol = GetString(item, "symbol"),
            .Code = GetString(item, "code")
        }
    End Function

    Private Function GetBaseUrlSnapshot() As String
        SyncLock _sync
            Return _baseUrl
        End SyncLock
    End Function

    Private Function GetApiKeySnapshot() As String
        SyncLock _sync
            Return _apiKey
        End SyncLock
    End Function

    Private Function BuildRequestUri(relativeUrl As String) As Uri
        Dim baseUrl = GetBaseUrlSnapshot()
        If String.IsNullOrWhiteSpace(baseUrl) Then
            Throw New HesabixApiException("ابتدا آدرس سرور حسابیکس را وارد کنید.")
        End If
        Dim path = relativeUrl.TrimStart("/"c)
        Return New Uri(baseUrl & "/" & path)
    End Function

    Private Async Function GetJsonAsync(relativeUrl As String, ct As CancellationToken) As Task(Of JObject)
        Return Await SendJsonAsync(HttpMethod.Get, relativeUrl, Nothing, includeAuth:=True, ct:=ct).ConfigureAwait(False)
    End Function

    Private Async Function SendJsonAsync(method As HttpMethod, relativeUrl As String, payload As JToken, includeAuth As Boolean, ct As CancellationToken) As Task(Of JObject)
        Using request As New HttpRequestMessage(method, BuildRequestUri(relativeUrl))
            If includeAuth Then
                Dim key = GetApiKeySnapshot()
                If Not String.IsNullOrWhiteSpace(key) Then
                    request.Headers.TryAddWithoutValidation("Authorization", "ApiKey " & key)
                End If
            End If

            If payload IsNot Nothing Then
                request.Content = New StringContent(payload.ToString(Formatting.None), Encoding.UTF8, "application/json")
            End If

            Dim response As HttpResponseMessage = Nothing
            Try
                response = Await _http.SendAsync(request, HttpCompletionOption.ResponseContentRead, ct).ConfigureAwait(False)
            Catch ex As OperationCanceledException
                Throw
            Catch ex As Exception
                Throw New HesabixApiException("اتصال به سرور حسابیکس برقرار نشد. آدرس سرور و اینترنت را بررسی کنید.", inner:=ex)
            End Try

            Using response
                Dim body = Await response.Content.ReadAsStringAsync().ConfigureAwait(False)
                Dim root As JObject
                Try
                    If String.IsNullOrWhiteSpace(body) Then
                        root = New JObject()
                    Else
                        root = JObject.Parse(body)
                    End If
                Catch ex As Exception
                    Throw New HesabixApiException("پاسخ نامعتبر از سرور (کد " & CInt(response.StatusCode).ToString() & ").", CInt(response.StatusCode), inner:=ex)
                End Try

                Dim success = True
                Dim successToken = root("success")
                If successToken IsNot Nothing AndAlso successToken.Type = JTokenType.Boolean Then
                    success = successToken.Value(Of Boolean)()
                End If

                If Not response.IsSuccessStatusCode OrElse Not success Then
                    Dim message As String = Nothing
                    Dim errorCode As String = Nothing
                    Dim errToken = root("error")
                    If errToken IsNot Nothing AndAlso errToken.Type = JTokenType.Object Then
                        Dim errObj = DirectCast(errToken, JObject)
                        message = GetString(errObj, "message")
                        errorCode = GetString(errObj, "code")
                        Dim details = errObj("details")
                        If details IsNot Nothing AndAlso details.Type = JTokenType.Array AndAlso details.HasValues Then
                            Dim first = details(0)
                            If first IsNot Nothing AndAlso first.Type = JTokenType.Object Then
                                Dim detailMsg = GetString(DirectCast(first, JObject), "msg")
                                If Not String.IsNullOrWhiteSpace(detailMsg) Then
                                    If String.IsNullOrWhiteSpace(message) Then
                                        message = detailMsg
                                    Else
                                        message = message & " — " & detailMsg
                                    End If
                                End If
                            End If
                        End If
                    End If
                    If String.IsNullOrWhiteSpace(message) Then message = GetString(root, "message")
                    If String.IsNullOrWhiteSpace(errorCode) Then errorCode = GetString(root, "error_code")
                    If String.IsNullOrWhiteSpace(message) Then
                        message = "خطای سرور (کد " & CInt(response.StatusCode).ToString() & ")"
                    End If
                    Throw New HesabixApiException(message, CInt(response.StatusCode), errorCode)
                End If

                Return root
            End Using
        End Using
    End Function

    Private Shared Function GetDataToken(root As JObject) As JObject
        Dim data = root("data")
        If data IsNot Nothing AndAlso data.Type = JTokenType.Object Then
            Return DirectCast(data, JObject)
        End If
        If data IsNot Nothing AndAlso data.Type = JTokenType.Array Then
            Return New JObject From {{"items", data}}
        End If
        Return root
    End Function

    Private Shared Function GetItemsArray(data As JObject) As JArray
        Dim items = data("items")
        If items IsNot Nothing AndAlso items.Type = JTokenType.Array Then
            Return DirectCast(items, JArray)
        End If
        Return New JArray()
    End Function

    Private Shared Function ParseBulkUpsertResult(data As JObject, entityIdField As String) As BulkUpsertResult
        Dim result As New BulkUpsertResult()
        Dim resultsToken = If(data Is Nothing, Nothing, data("results"))
        If resultsToken IsNot Nothing AndAlso resultsToken.Type = JTokenType.Array Then
            For Each itemToken As JToken In DirectCast(resultsToken, JArray)
                If itemToken Is Nothing OrElse itemToken.Type <> JTokenType.Object Then Continue For
                Dim item = DirectCast(itemToken, JObject)
                result.Results.Add(New BulkUpsertItemResult With {
                    .Index = GetInt(item, "index"),
                    .ClientRef = GetString(item, "client_ref"),
                    .Status = GetString(item, "status"),
                    .EntityId = GetInt(item, entityIdField),
                    .ErrorCode = GetString(item, "error_code"),
                    .Message = GetString(item, "message")
                })
            Next
        End If
        Dim summary = If(data Is Nothing, Nothing, data("summary"))
        If summary IsNot Nothing AndAlso summary.Type = JTokenType.Object Then
            Dim s = DirectCast(summary, JObject)
            result.Total = GetInt(s, "total")
            result.Created = GetInt(s, "created")
            result.Updated = GetInt(s, "updated")
            result.Failed = GetInt(s, "failed")
        Else
            result.Total = result.Results.Count
            For Each r In result.Results
                If String.Equals(r.Status, "created", StringComparison.OrdinalIgnoreCase) Then
                    result.Created += 1
                ElseIf String.Equals(r.Status, "updated", StringComparison.OrdinalIgnoreCase) Then
                    result.Updated += 1
                ElseIf String.Equals(r.Status, "failed", StringComparison.OrdinalIgnoreCase) Then
                    result.Failed += 1
                End If
            Next
        End If
        Return result
    End Function

    Private Shared Function GetString(token As JToken, name As String) As String
        If token Is Nothing Then Return Nothing
        Dim prop = token(name)
        If prop Is Nothing OrElse prop.Type = JTokenType.Null Then Return Nothing
        Return prop.ToString()
    End Function

    Private Shared Function GetInt(token As JToken, name As String) As Integer
        Dim prop = If(token Is Nothing, Nothing, token(name))
        If prop Is Nothing OrElse prop.Type = JTokenType.Null Then Return 0
        Dim value As Integer
        If Integer.TryParse(prop.ToString(), value) Then Return value
        Return 0
    End Function

    Private Shared Function GetNullableInt(token As JToken, name As String) As Integer?
        Dim prop = If(token Is Nothing, Nothing, token(name))
        If prop Is Nothing OrElse prop.Type = JTokenType.Null Then Return Nothing
        Dim value As Integer
        If Integer.TryParse(prop.ToString(), value) Then Return value
        Return Nothing
    End Function

    Private Shared Function GetBool(token As JToken, name As String, Optional defaultValue As Boolean = False) As Boolean
        Dim prop = If(token Is Nothing, Nothing, token(name))
        If prop Is Nothing OrElse prop.Type = JTokenType.Null Then Return defaultValue
        Dim value As Boolean
        If Boolean.TryParse(prop.ToString(), value) Then Return value
        Return defaultValue
    End Function

    Public Sub Dispose() Implements IDisposable.Dispose
        If _disposed Then Return
        _disposed = True
        _http.Dispose()
    End Sub
End Class
