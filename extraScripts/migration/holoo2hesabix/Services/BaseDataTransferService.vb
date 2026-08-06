Imports System.Threading
Imports Newtonsoft.Json.Linq

Friend Class BaseDataTransferService
    Private ReadOnly _reader As New HolooBaseDataReader()

    Public Event ProgressChanged As EventHandler(Of TransferProgressEventArgs)

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
        If resetCheckpoint Then store.Reset()

        Dim cp = store.LoadOrCreate(session.ApiBaseUrl, businessId, session.SqlSettings.Server, session.SelectedDatabase)
        api.Configure(session.ApiBaseUrl, session.ApiKey)

        Dim warehouseMap = cp.EnsureModule(MigrationModule.Warehouses.ToString())
        Dim modules = selectedModules.OrderBy(Function(m) CInt(m)).ToList()

        For Each m In modules
            ct.ThrowIfCancellationRequested()
            Select Case m
                Case MigrationModule.Warehouses
                    Await TransferWarehouses(session, api, businessId, cp, store, ct).ConfigureAwait(False)
                Case MigrationModule.Persons
                    Await TransferPersons(session, api, businessId, cp, store, ct).ConfigureAwait(False)
                Case MigrationModule.BankAccounts
                    Await TransferBanks(session, api, businessId, currencyId, cp, store, ct).ConfigureAwait(False)
                Case MigrationModule.CashRegisters
                    Await TransferCash(session, api, businessId, currencyId, True, cp, store, ct).ConfigureAwait(False)
                Case MigrationModule.PettyCash
                    Await TransferCash(session, api, businessId, currencyId, False, cp, store, ct).ConfigureAwait(False)
                Case MigrationModule.Products
                    Await TransferProducts(session, api, businessId, warehouseMap, cp, store, ct).ConfigureAwait(False)
            End Select
        Next

        Return store.FilePath
    End Function

    Private Async Function TransferWarehouses(session As MigrationSession, api As HesabixApiClient, businessId As Integer, cp As TransferCheckpoint, store As CheckpointStore, ct As CancellationToken) As Task
        Dim key = MigrationModule.Warehouses.ToString()
        Dim modCp = cp.EnsureModule(key)
        If modCp.Completed Then
            RaiseProgress("انبارها", 0, 0, "قبلاً کامل شده — رد شد")
            Return
        End If
        Dim existing As Dictionary(Of String, Integer) = Nothing
        Try
            existing = Await api.ListWarehousesAsync(businessId, ct).ConfigureAwait(False)
        Catch
            existing = New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)
        End Try
        Dim rows = Await Task.Run(Function() _reader.ReadWarehouses(session.SqlSettings), ct).ConfigureAwait(False)
        Dim i = 0
        For Each row In rows
            ct.ThrowIfCancellationRequested()
            i += 1
            If modCp.Done.ContainsKey(row.Key) Then
                RaiseProgress("انبارها", i, rows.Count, "رد شده (قبلاً منتقل شده): " & row.Name)
                Continue For
            End If
            Dim codeKey = row.Code.ToString()
            If existing.ContainsKey(codeKey) Then
                modCp.Done(row.Key) = existing(codeKey)
                modCp.Failed.Remove(row.Key)
                RaiseProgress("انبارها", i, rows.Count, "موجود بود — لینک شد: " & row.Name)
                modCp.LastKey = row.Key
                store.Save(cp)
                Continue For
            End If
            Dim createErr As Exception = Nothing
            Dim duplicateWh As Boolean = False
            Try
                Dim payload As New JObject()
                payload("code") = codeKey
                payload("name") = row.Name
                payload("is_default") = (i = 1 AndAlso modCp.Done.Count = 0)
                Dim id = Await api.CreateWarehouseAsync(businessId, payload, ct).ConfigureAwait(False)
                modCp.Done(row.Key) = id
                modCp.Failed.Remove(row.Key)
                existing(codeKey) = id
                RaiseProgress("انبارها", i, rows.Count, "ایجاد شد: " & row.Name)
            Catch ex As HesabixApiException When String.Equals(ex.ErrorCode, "DUPLICATE_WAREHOUSE_CODE", StringComparison.OrdinalIgnoreCase)
                duplicateWh = True
                createErr = ex
            Catch ex As Exception
                createErr = ex
            End Try
            If duplicateWh Then
                Dim linked = Await TryLinkWarehouse(api, businessId, codeKey, ct).ConfigureAwait(False)
                If linked > 0 Then
                    modCp.Done(row.Key) = linked
                    modCp.Failed.Remove(row.Key)
                    existing(codeKey) = linked
                    RaiseProgress("انبارها", i, rows.Count, "کد تکراری — لینک شد: " & row.Name)
                Else
                    Dim msg = If(createErr Is Nothing, "کد انبار تکراری است", createErr.Message)
                    modCp.Failed(row.Key) = msg
                    RaiseProgress("انبارها", i, rows.Count, "خطا: " & row.Name & " — " & msg, True)
                End If
            ElseIf createErr IsNot Nothing Then
                modCp.Failed(row.Key) = createErr.Message
                RaiseProgress("انبارها", i, rows.Count, "خطا: " & row.Name & " — " & createErr.Message, True)
            End If
            modCp.LastKey = row.Key
            store.Save(cp)
        Next
        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Async Function TryLinkWarehouse(api As HesabixApiClient, businessId As Integer, code As String, ct As CancellationToken) As Task(Of Integer)
        Try
            Dim map = Await api.ListWarehousesAsync(businessId, ct).ConfigureAwait(False)
            Dim id As Integer
            If map.TryGetValue(code, id) Then Return id
        Catch
        End Try
        Return 0
    End Function

    Private Async Function TransferPersons(session As MigrationSession, api As HesabixApiClient, businessId As Integer, cp As TransferCheckpoint, store As CheckpointStore, ct As CancellationToken) As Task
        Dim key = MigrationModule.Persons.ToString()
        Dim modCp = cp.EnsureModule(key)
        If modCp.Completed Then
            RaiseProgress("اشخاص", 0, 0, "قبلاً کامل شده — رد شد")
            Return
        End If
        Dim hasFiscalYear = Await api.HasCurrentFiscalYearAsync(businessId, ct).ConfigureAwait(False)
        If Not hasFiscalYear Then
            RaiseProgress("اشخاص", 0, 0, "هشدار: سال مالی برای این کسب‌وکار تعریف نشده — مانده افتتاحیه ارسال نمی‌شود")
        End If
        Dim rows = Await Task.Run(Function() _reader.ReadPersons(session.SqlSettings), ct).ConfigureAwait(False)
        Dim i = 0
        For Each row In rows
            ct.ThrowIfCancellationRequested()
            i += 1
            If modCp.Done.ContainsKey(row.Key) Then
                RaiseProgress("اشخاص", i, rows.Count, "رد شده (قبلاً): " & row.Name)
                Continue For
            End If

            Dim codeNum As Integer = 0
            Integer.TryParse(row.Code, codeNum)

            ' اگر قبلاً با همین کد در حسابیکس ساخته شده، لینک کن
            If codeNum > 0 Then
                Try
                    Dim existingId = Await api.FindPersonIdByCodeAsync(businessId, codeNum, ct).ConfigureAwait(False)
                    If existingId > 0 Then
                        modCp.Done(row.Key) = existingId
                        modCp.Failed.Remove(row.Key)
                        RaiseProgress("اشخاص", i, rows.Count, "موجود بود — لینک شد: " & row.Name)
                        modCp.LastKey = row.Key
                        If i Mod 5 = 0 Then store.Save(cp)
                        Continue For
                    End If
                Catch
                End Try
            End If

            Dim types As New JArray()
            If row.IsCustomer Then types.Add("مشتری")
            If row.IsSupplier Then types.Add("تامین‌کننده")
            If row.IsEmployee Then types.Add("کارمند")
            If row.IsMarketer Then types.Add("بازاریاب")
            If row.IsColleague Then types.Add("همکار")
            If row.IsSeller Then types.Add("فروشنده")
            If types.Count = 0 Then types.Add("مشتری")

            Dim payload As New JObject()
            payload("alias_name") = row.Name
            payload("person_types") = types
            SetOptionalString(payload, "company_name", row.CompanyName)
            SetOptionalString(payload, "mobile", row.Mobile)
            SetOptionalString(payload, "phone", row.Phone)
            SetOptionalString(payload, "fax", row.Fax)
            SetOptionalString(payload, "address", row.Address)
            SetOptionalString(payload, "national_id", row.NationalCode)
            SetOptionalString(payload, "economic_id", row.EconomicCode)
            SetOptionalString(payload, "registration_number", row.RegistrationNumber)
            SetOptionalString(payload, "city", row.City)
            SetOptionalString(payload, "province", row.Province)
            SetOptionalString(payload, "postal_code", row.PostalCode)
            If LooksLikeEmail(row.Email) Then
                payload("email") = row.Email.Trim()
            End If
            If Not String.IsNullOrWhiteSpace(row.CompanyName) Then
                payload("legal_entity_type") = "legal"
            End If
            If row.CreditLimit > 0 Then
                payload("credit_limit") = row.CreditLimit
                payload("credit_check_enabled") = True
            End If
            If codeNum > 0 Then payload("code") = codeNum

            If hasFiscalYear AndAlso (row.OpeningDebit > 0 OrElse row.OpeningCredit > 0) Then
                Dim ob As New JObject()
                If row.OpeningDebit >= row.OpeningCredit AndAlso row.OpeningDebit > 0 Then
                    ob("amount") = row.OpeningDebit
                    ob("balance_type") = "debit"
                Else
                    ob("amount") = row.OpeningCredit
                    ob("balance_type") = "credit"
                End If
                payload("opening_balance") = ob
            End If

            Dim id As Integer = 0
            Dim createdOk As Boolean = False
            Dim needRetryNoOb As Boolean = False
            Dim duplicatePerson As Boolean = False
            Dim createErr As Exception = Nothing
            Try
                id = Await api.CreatePersonAsync(businessId, payload, ct).ConfigureAwait(False)
                createdOk = True
            Catch exFy As HesabixApiException When String.Equals(exFy.ErrorCode, "NO_CURRENT_FISCAL_YEAR", StringComparison.OrdinalIgnoreCase)
                needRetryNoOb = True
            Catch exDup As HesabixApiException When String.Equals(exDup.ErrorCode, "DUPLICATE_PERSON_CODE", StringComparison.OrdinalIgnoreCase)
                duplicatePerson = True
                createErr = exDup
            Catch ex As Exception
                createErr = ex
            End Try

            If needRetryNoOb Then
                payload.Remove("opening_balance")
                hasFiscalYear = False
                Try
                    id = Await api.CreatePersonAsync(businessId, payload, ct).ConfigureAwait(False)
                    createdOk = True
                Catch exDup As HesabixApiException When String.Equals(exDup.ErrorCode, "DUPLICATE_PERSON_CODE", StringComparison.OrdinalIgnoreCase)
                    duplicatePerson = True
                    createErr = exDup
                Catch ex As Exception
                    createErr = ex
                End Try
            End If

            If createdOk Then
                modCp.Done(row.Key) = id
                modCp.Failed.Remove(row.Key)
                RaiseProgress("اشخاص", i, rows.Count, "ایجاد شد: " & row.Name)
            ElseIf duplicatePerson Then
                Dim linked = 0
                If codeNum > 0 Then
                    Try
                        linked = Await api.FindPersonIdByCodeAsync(businessId, codeNum, ct).ConfigureAwait(False)
                    Catch
                    End Try
                End If
                If linked > 0 Then
                    modCp.Done(row.Key) = linked
                    modCp.Failed.Remove(row.Key)
                    RaiseProgress("اشخاص", i, rows.Count, "کد تکراری — لینک شد: " & row.Name)
                Else
                    Dim msg = If(createErr Is Nothing, "کد شخص تکراری است", createErr.Message)
                    modCp.Failed(row.Key) = msg
                    RaiseProgress("اشخاص", i, rows.Count, "خطا: " & row.Name & " — " & msg, True)
                End If
            ElseIf createErr IsNot Nothing Then
                modCp.Failed(row.Key) = createErr.Message
                RaiseProgress("اشخاص", i, rows.Count, "خطا: " & row.Name & " — " & createErr.Message, True)
            End If
            modCp.LastKey = row.Key
            If i Mod 5 = 0 Then store.Save(cp)
        Next
        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Async Function TransferBanks(session As MigrationSession, api As HesabixApiClient, businessId As Integer, currencyId As Integer, cp As TransferCheckpoint, store As CheckpointStore, ct As CancellationToken) As Task
        Dim key = MigrationModule.BankAccounts.ToString()
        Dim modCp = cp.EnsureModule(key)
        If modCp.Completed Then
            RaiseProgress("حساب بانکی", 0, 0, "قبلاً کامل شده — رد شد")
            Return
        End If
        Dim rows = Await Task.Run(Function() _reader.ReadBankAccounts(session.SqlSettings), ct).ConfigureAwait(False)
        Dim i = 0
        For Each row In rows
            ct.ThrowIfCancellationRequested()
            i += 1
            If modCp.Done.ContainsKey(row.Key) Then
                RaiseProgress("حساب بانکی", i, rows.Count, "رد شده (قبلاً): " & row.Title)
                Continue For
            End If
            Try
                Dim payload As New JObject()
                payload("name") = row.Title
                payload("currency_id") = currencyId
                payload("is_active") = row.IsActive
                payload("is_default") = (i = 1 AndAlso modCp.Done.Count = 0)
                payload("description") = "Holoo:" & row.Key
                SetOptionalString(payload, "branch", row.BranchName)
                SetOptionalString(payload, "account_number", row.AccountNumber)
                If LooksLikeSheba(row.Sheba) Then payload("sheba_number") = NormalizeSheba(row.Sheba)
                If LooksLikeCard(row.CardNumber) Then payload("card_number") = DigitsOnly(row.CardNumber)
                Dim id = Await api.CreateBankAccountAsync(businessId, payload, ct).ConfigureAwait(False)
                modCp.Done(row.Key) = id
                modCp.Failed.Remove(row.Key)
                RaiseProgress("حساب بانکی", i, rows.Count, "ایجاد شد: " & row.Title)
            Catch ex As Exception
                modCp.Failed(row.Key) = ex.Message
                RaiseProgress("حساب بانکی", i, rows.Count, "خطا: " & row.Title & " — " & ex.Message, True)
            End Try
            modCp.LastKey = row.Key
            store.Save(cp)
        Next
        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Async Function TransferCash(session As MigrationSession, api As HesabixApiClient, businessId As Integer, currencyId As Integer, isRegister As Boolean, cp As TransferCheckpoint, store As CheckpointStore, ct As CancellationToken) As Task
        Dim modKey = If(isRegister, MigrationModule.CashRegisters, MigrationModule.PettyCash).ToString()
        Dim title = If(isRegister, "صندوق", "تنخواه")
        Dim modCp = cp.EnsureModule(modKey)
        If modCp.Completed Then
            RaiseProgress(title, 0, 0, "قبلاً کامل شده — رد شد")
            Return
        End If
        Dim rows = Await Task.Run(Function() _reader.ReadCashRows(session.SqlSettings, isRegister), ct).ConfigureAwait(False)
        Dim i = 0
        For Each row In rows
            ct.ThrowIfCancellationRequested()
            i += 1
            If modCp.Done.ContainsKey(row.Key) Then
                RaiseProgress(title, i, rows.Count, "رد شده (قبلاً): " & row.Name)
                Continue For
            End If
            Try
                Dim payload As New JObject()
                payload("name") = row.Name
                payload("currency_id") = currencyId
                payload("is_active") = True
                payload("is_default") = (i = 1 AndAlso modCp.Done.Count = 0)
                payload("description") = "HolooCash:" & row.Key
                Dim id As Integer
                If isRegister Then
                    id = Await api.CreateCashRegisterAsync(businessId, payload, ct).ConfigureAwait(False)
                Else
                    id = Await api.CreatePettyCashAsync(businessId, payload, ct).ConfigureAwait(False)
                End If
                modCp.Done(row.Key) = id
                modCp.Failed.Remove(row.Key)
                RaiseProgress(title, i, rows.Count, "ایجاد شد: " & row.Name)
            Catch ex As Exception
                modCp.Failed(row.Key) = ex.Message
                RaiseProgress(title, i, rows.Count, "خطا: " & row.Name & " — " & ex.Message, True)
            End Try
            modCp.LastKey = row.Key
            store.Save(cp)
        Next
        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Async Function TransferProducts(session As MigrationSession, api As HesabixApiClient, businessId As Integer, warehouseMap As ModuleCheckpoint, cp As TransferCheckpoint, store As CheckpointStore, ct As CancellationToken) As Task
        Dim key = MigrationModule.Products.ToString()
        Dim modCp = cp.EnsureModule(key)
        If modCp.Completed Then
            RaiseProgress("کالا", 0, 0, "قبلاً کامل شده — رد شد")
            Return
        End If
        Dim hasFiscalYear = Await api.HasCurrentFiscalYearAsync(businessId, ct).ConfigureAwait(False)
        If Not hasFiscalYear Then
            RaiseProgress("کالا", 0, 0, "هشدار: سال مالی تعریف نشده — موجودی اولیه ارسال نمی‌شود")
        End If
        Dim rows = Await Task.Run(Function() _reader.ReadProducts(session.SqlSettings), ct).ConfigureAwait(False)
        Dim i = 0
        For Each row In rows
            ct.ThrowIfCancellationRequested()
            i += 1
            If modCp.Done.ContainsKey(row.Key) Then
                If i Mod 50 = 0 Then RaiseProgress("کالا", i, rows.Count, "رد شده‌های قبلی...")
                Continue For
            End If
            Dim unitName = If(String.IsNullOrWhiteSpace(row.UnitName), "عدد", row.UnitName.Trim())
            If unitName.Length > 32 Then unitName = unitName.Substring(0, 32)

            Dim payload As New JObject()
            payload("code") = row.Code
            payload("name") = row.Name
            payload("item_type") = "کالا"
            payload("main_unit") = unitName
            payload("base_sales_price") = row.SalesPrice
            payload("base_purchase_price") = row.PurchasePrice
            payload("track_inventory") = True
            payload("is_active") = row.IsActive
            payload("is_sales_taxable") = row.IncludeTax
            payload("is_purchase_taxable") = row.IncludeTax
            If Not String.IsNullOrWhiteSpace(row.Model) Then
                payload("catalog_model") = row.Model.Trim()
            End If
            If row.IncludeTax AndAlso row.TaxRate > 0 Then
                payload("sales_tax_rate") = row.TaxRate
            End If
            If row.IncludeTax AndAlso row.PurchaseTaxRate > 0 Then
                payload("purchase_tax_rate") = row.PurchaseTaxRate
            End If
            If Not String.IsNullOrWhiteSpace(row.Barcode) AndAlso row.Barcode <> "." Then
                Dim bc = row.Barcode.Trim()
                If bc.Length <= 50 Then
                    payload("barcode") = bc
                End If
            End If
            If row.WarehouseCode.HasValue AndAlso warehouseMap.Done.ContainsKey(row.WarehouseCode.Value.ToString()) Then
                payload("default_warehouse_id") = warehouseMap.Done(row.WarehouseCode.Value.ToString())
            End If
            If hasFiscalYear AndAlso row.FirstExist > 0 Then
                Dim ob As New JObject()
                ob("quantity") = row.FirstExist
                ob("cost_price") = If(row.FirstBuyPrice > 0, row.FirstBuyPrice, row.PurchasePrice)
                If row.WarehouseCode.HasValue AndAlso warehouseMap.Done.ContainsKey(row.WarehouseCode.Value.ToString()) Then
                    ob("warehouse_id") = warehouseMap.Done(row.WarehouseCode.Value.ToString())
                End If
                payload("opening_balance") = ob
            End If

            Dim id As Integer = 0
            Dim createdOk As Boolean = False
            Dim needRetryNoOb As Boolean = False
            Dim createErr As Exception = Nothing
            Try
                id = Await api.CreateProductAsync(businessId, payload, ct).ConfigureAwait(False)
                createdOk = True
            Catch exFy As HesabixApiException When String.Equals(exFy.ErrorCode, "NO_CURRENT_FISCAL_YEAR", StringComparison.OrdinalIgnoreCase)
                needRetryNoOb = True
            Catch ex As Exception
                createErr = ex
            End Try

            If needRetryNoOb Then
                payload.Remove("opening_balance")
                hasFiscalYear = False
                Try
                    id = Await api.CreateProductAsync(businessId, payload, ct).ConfigureAwait(False)
                    createdOk = True
                Catch ex As Exception
                    createErr = ex
                End Try
            End If

            If createdOk Then
                modCp.Done(row.Key) = id
                modCp.Failed.Remove(row.Key)
                If i Mod 10 = 0 OrElse i = rows.Count Then
                    RaiseProgress("کالا", i, rows.Count, "ایجاد شد: " & row.Name)
                    store.Save(cp)
                End If
            ElseIf createErr IsNot Nothing Then
                modCp.Failed(row.Key) = createErr.Message
                RaiseProgress("کالا", i, rows.Count, "خطا: " & row.Code & " — " & createErr.Message, True)
                store.Save(cp)
            End If
            modCp.LastKey = row.Key
        Next
        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Sub SetOptionalString(payload As JObject, name As String, value As String)
        If String.IsNullOrWhiteSpace(value) Then Return
        payload(name) = value.Trim()
    End Sub

    Private Shared Function LooksLikeEmail(value As String) As Boolean
        If String.IsNullOrWhiteSpace(value) Then Return False
        Dim v = value.Trim()
        Dim at = v.IndexOf("@"c)
        If at <= 0 OrElse at >= v.Length - 3 Then Return False
        Dim dot = v.LastIndexOf("."c)
        Return dot > at + 1 AndAlso dot < v.Length - 1
    End Function

    Private Shared Function DigitsOnly(value As String) As String
        If String.IsNullOrWhiteSpace(value) Then Return ""
        Dim sb As New System.Text.StringBuilder()
        For Each ch In value.Trim()
            If Char.IsDigit(ch) Then sb.Append(ch)
        Next
        Return sb.ToString()
    End Function

    Private Shared Function LooksLikeSheba(value As String) As Boolean
        Dim d = DigitsOnly(value)
        ' شبا ایران ۲۴ رقم؛ مقادیر مثل «0» رد می‌شوند
        Return d.Length = 24
    End Function

    Private Shared Function NormalizeSheba(value As String) As String
        Dim d = DigitsOnly(value)
        If d.Length = 24 Then Return "IR" & d
        Return value.Trim()
    End Function

    Private Shared Function LooksLikeCard(value As String) As Boolean
        Dim d = DigitsOnly(value)
        Return d.Length >= 16 AndAlso d.Length <= 19
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
