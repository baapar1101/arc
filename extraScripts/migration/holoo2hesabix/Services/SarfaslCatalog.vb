Imports System.Threading
Imports Newtonsoft.Json.Linq

''' <summary>
''' اطمینان از وجود حساب مقصد در حسابیکس: کد عمومی یا ساخت حساب اختصاصی کسب‌وکار.
''' </summary>
Friend Class SarfaslCatalog
    Private ReadOnly _codeToId As Dictionary(Of String, Integer)
    Private ReadOnly _created As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly _api As HesabixApiClient
    Private ReadOnly _businessId As Integer

    Public Sub New(api As HesabixApiClient, businessId As Integer, accountCodeMap As Dictionary(Of String, Integer))
        _api = api
        _businessId = businessId
        _codeToId = If(accountCodeMap, New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase))
    End Sub

    Public ReadOnly Property CodeMap As Dictionary(Of String, Integer)
        Get
            Return _codeToId
        End Get
    End Property

    Public Async Function ResolveOrCreateAsync(
        code As String,
        Optional parentCode As String = Nothing,
        Optional name As String = Nothing,
        Optional ct As CancellationToken = Nothing
    ) As Task(Of Integer)
        If String.IsNullOrWhiteSpace(code) Then Return 0
        Dim c = code.Trim()
        Dim id As Integer
        If _codeToId.TryGetValue(c, id) AndAlso id > 0 Then Return id
        If _created.TryGetValue(c, id) AndAlso id > 0 Then Return id

        If String.IsNullOrWhiteSpace(parentCode) OrElse String.IsNullOrWhiteSpace(name) Then
            Return Await _api.FindAccountIdByCodeAsync(_businessId, c, ct).ConfigureAwait(False)
        End If

        Dim parentId As Integer = 0
        If Not _codeToId.TryGetValue(parentCode.Trim(), parentId) OrElse parentId <= 0 Then
            parentId = Await _api.FindAccountIdByCodeAsync(_businessId, parentCode.Trim(), ct).ConfigureAwait(False)
            If parentId > 0 Then _codeToId(parentCode.Trim()) = parentId
        End If
        If parentId <= 0 Then Return 0

        Dim createFailed As Boolean = False
        Try
            id = Await _api.CreateBusinessAccountAsync(
                _businessId,
                New JObject From {
                    {"name", name.Trim()},
                    {"code", c},
                    {"account_type", "0"},
                    {"parent_id", parentId}
                },
                ct).ConfigureAwait(False)
        Catch
            createFailed = True
            id = 0
        End Try

        If createFailed OrElse id <= 0 Then
            id = Await _api.FindAccountIdByCodeAsync(_businessId, c, ct).ConfigureAwait(False)
        End If

        If id > 0 Then
            _created(c) = id
            _codeToId(c) = id
        End If
        Return id
    End Function

    ''' <summary>برای هزینه 601 بدون معادل عمومی: حساب زیر 704.</summary>
    Public Async Function EnsureExpenseBusinessAccountAsync(moien As String, name As String, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim code = HolooSarfaslMapper.SuggestBusinessExpenseCode(moien)
        Dim title = If(String.IsNullOrWhiteSpace(name), "هزینه هلو " & moien, name.Trim())
        Return Await ResolveOrCreateAsync(code, "704", title, ct).ConfigureAwait(False)
    End Function

    ''' <summary>برای درآمد 702 بدون معادل عمومی: حساب زیر 601.</summary>
    Public Async Function EnsureIncomeBusinessAccountAsync(moien As String, name As String, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim code = HolooSarfaslMapper.SuggestBusinessIncomeCode(moien)
        Dim title = If(String.IsNullOrWhiteSpace(name), "درآمد هلو " & moien, name.Trim())
        Return Await ResolveOrCreateAsync(code, "601", title, ct).ConfigureAwait(False)
    End Function

    ''' <summary>برای وام زیر 401: حساب زیر 20501.</summary>
    Public Async Function EnsureLoanBusinessAccountAsync(moien As String, name As String, Optional ct As CancellationToken = Nothing) As Task(Of Integer)
        Dim code = HolooSarfaslMapper.SuggestBusinessLoanCode(moien)
        Dim title = If(String.IsNullOrWhiteSpace(name), "وام هلو " & moien, name.Trim())
        Return Await ResolveOrCreateAsync(code, "20501", title, ct).ConfigureAwait(False)
    End Function

    Public Sub RefreshFrom(map As Dictionary(Of String, Integer))
        If map Is Nothing Then Return
        For Each kv In map
            If kv.Value > 0 AndAlso Not _codeToId.ContainsKey(kv.Key) Then
                _codeToId(kv.Key) = kv.Value
            End If
        Next
    End Sub
End Class
