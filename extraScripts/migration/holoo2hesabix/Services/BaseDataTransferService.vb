Imports System.Threading
Imports Newtonsoft.Json.Linq

Friend Class BaseDataTransferService
    Private ReadOnly _reader As New HolooBaseDataReader()

    ''' <summary>حداکثر آیتم در هر درخواست bulk (کمتر از سقف ۱۰۰۰ سرور برای ایمنی timeout/OB).</summary>
    Private Const BulkChunkSize As Integer = 100
    ''' <summary>وقتی مانده افتتاحیه در chunk هست، دسته‌ها کوچک‌تر می‌شوند.</summary>
    Private Const BulkChunkSizeWithOpeningBalance As Integer = 50

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
        Dim pending As New List(Of HolooPersonRow)()
        Dim alreadyDone = 0
        For Each row In rows
            If modCp.Done.ContainsKey(row.Key) Then
                alreadyDone += 1
            Else
                pending.Add(row)
            End If
        Next
        If alreadyDone > 0 Then
            RaiseProgress("اشخاص", alreadyDone, rows.Count, "رد شده از قبل: " & alreadyDone.ToString() & " نفر")
        End If
        If pending.Count = 0 Then
            If modCp.Failed.Count = 0 Then modCp.Completed = True
            store.Save(cp)
            RaiseProgress("اشخاص", rows.Count, rows.Count, "همه اشخاص قبلاً منتقل شده‌اند")
            Return
        End If

        RaiseProgress("اشخاص", alreadyDone, rows.Count, "ارسال گروهی " & pending.Count.ToString() & " نفر...")
        Dim processed = alreadyDone
        Dim offset = 0
        While offset < pending.Count
            ct.ThrowIfCancellationRequested()
            Dim chunkRows = TakePersonChunk(pending, offset, hasFiscalYear)
            Dim items = New JArray()
            Dim chunkHasOb = False
            For Each row In chunkRows
                Dim payload = BuildPersonPayload(row, hasFiscalYear)
                If payload("opening_balance") IsNot Nothing Then chunkHasOb = True
                items.Add(New JObject From {
                    {"client_ref", row.Key},
                    {"payload", payload}
                })
            Next

            Dim bulk As BulkUpsertResult = Nothing
            Dim requestErr As Exception = Nothing
            Try
                bulk = Await api.BulkUpsertPersonsAsync(businessId, items, createIfUpdateMissing:=True, ct:=ct).ConfigureAwait(False)
            Catch ex As Exception
                requestErr = ex
            End Try

            If requestErr IsNot Nothing Then
                For Each row In chunkRows
                    modCp.Failed(row.Key) = requestErr.Message
                    RaiseProgress("اشخاص", processed + 1, rows.Count, "خطای درخواست گروهی: " & row.Name & " — " & requestErr.Message, True)
                    processed += 1
                    modCp.LastKey = row.Key
                Next
                store.Save(cp)
                offset += chunkRows.Count
                Continue While
            End If

            Dim retryNoOb As New List(Of HolooPersonRow)()
            Dim byClientRef = IndexBulkByClientRef(bulk)
            For i = 0 To chunkRows.Count - 1
                Dim row = chunkRows(i)
                Dim itemResult = ResolveBulkItem(byClientRef, bulk, i, row.Key)
                processed += 1
                modCp.LastKey = row.Key

                If itemResult IsNot Nothing AndAlso itemResult.IsSuccess AndAlso itemResult.EntityId > 0 Then
                    modCp.Done(row.Key) = itemResult.EntityId
                    modCp.Failed.Remove(row.Key)
                    Continue For
                End If

                Dim errCode = If(itemResult Is Nothing, Nothing, itemResult.ErrorCode)
                Dim errMsg = If(itemResult Is Nothing, "نتیجه bulk برای این ردیف برنگشت", If(itemResult.Message, itemResult.ErrorCode))

                If String.Equals(errCode, "NO_CURRENT_FISCAL_YEAR", StringComparison.OrdinalIgnoreCase) Then
                    hasFiscalYear = False
                    retryNoOb.Add(row)
                    processed -= 1
                    Continue For
                End If

                If String.Equals(errCode, "DUPLICATE_PERSON_CODE", StringComparison.OrdinalIgnoreCase) Then
                    Dim codeNum As Integer = 0
                    Integer.TryParse(row.Code, codeNum)
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
                        RaiseProgress("اشخاص", processed, rows.Count, "کد تکراری — لینک شد: " & row.Name)
                    Else
                        modCp.Failed(row.Key) = If(errMsg, "کد شخص تکراری است")
                        RaiseProgress("اشخاص", processed, rows.Count, "خطا: " & row.Name & " — " & modCp.Failed(row.Key), True)
                    End If
                    Continue For
                End If

                modCp.Failed(row.Key) = If(errMsg, "خطای ناشناخته")
                RaiseProgress("اشخاص", processed, rows.Count, "خطا: " & row.Name & " — " & modCp.Failed(row.Key), True)
            Next

            If retryNoOb.Count > 0 Then
                RaiseProgress("اشخاص", processed, rows.Count, "تلاش مجدد بدون مانده افتتاحیه برای " & retryNoOb.Count.ToString() & " نفر...")
                Dim retryItems As New JArray()
                For Each row In retryNoOb
                    Dim payload = BuildPersonPayload(row, includeOpeningBalance:=False)
                    retryItems.Add(New JObject From {
                        {"client_ref", row.Key},
                        {"payload", payload}
                    })
                Next
                Dim retryBulk As BulkUpsertResult = Nothing
                Dim retryErr As Exception = Nothing
                Try
                    retryBulk = Await api.BulkUpsertPersonsAsync(businessId, retryItems, True, ct).ConfigureAwait(False)
                Catch ex As Exception
                    retryErr = ex
                End Try
                If retryErr IsNot Nothing Then
                    For Each row In retryNoOb
                        processed += 1
                        modCp.Failed(row.Key) = retryErr.Message
                        modCp.LastKey = row.Key
                        RaiseProgress("اشخاص", processed, rows.Count, "خطا: " & row.Name & " — " & retryErr.Message, True)
                    Next
                Else
                    Dim retryByRef = IndexBulkByClientRef(retryBulk)
                    For i = 0 To retryNoOb.Count - 1
                        Dim row = retryNoOb(i)
                        processed += 1
                        modCp.LastKey = row.Key
                        Dim itemResult = ResolveBulkItem(retryByRef, retryBulk, i, row.Key)
                        If itemResult IsNot Nothing AndAlso itemResult.IsSuccess AndAlso itemResult.EntityId > 0 Then
                            modCp.Done(row.Key) = itemResult.EntityId
                            modCp.Failed.Remove(row.Key)
                        ElseIf itemResult IsNot Nothing AndAlso
                               String.Equals(itemResult.ErrorCode, "DUPLICATE_PERSON_CODE", StringComparison.OrdinalIgnoreCase) Then
                            Dim codeNum As Integer = 0
                            Integer.TryParse(row.Code, codeNum)
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
                            Else
                                modCp.Failed(row.Key) = If(itemResult.Message, "کد شخص تکراری است")
                                RaiseProgress("اشخاص", processed, rows.Count, "خطا: " & row.Name & " — " & modCp.Failed(row.Key), True)
                            End If
                        Else
                            Dim msg = If(itemResult Is Nothing, "نتیجه bulk برنگشت", If(itemResult.Message, itemResult.ErrorCode))
                            modCp.Failed(row.Key) = If(msg, "خطای ناشناخته")
                            RaiseProgress("اشخاص", processed, rows.Count, "خطا: " & row.Name & " — " & modCp.Failed(row.Key), True)
                        End If
                    Next
                End If
            End If

            Dim created = If(bulk Is Nothing, 0, bulk.Created)
            Dim updated = If(bulk Is Nothing, 0, bulk.Updated)
            RaiseProgress("اشخاص", processed, rows.Count,
                          "دسته " & (offset \ Math.Max(1, If(chunkHasOb, BulkChunkSizeWithOpeningBalance, BulkChunkSize)) + 1).ToString() &
                          ": ایجاد " & created.ToString() & " / به‌روز " & updated.ToString() &
                          " (مجموع " & processed.ToString() & "/" & rows.Count.ToString() & ")")
            store.Save(cp)
            offset += chunkRows.Count
        End While

        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Function TakePersonChunk(pending As List(Of HolooPersonRow), offset As Integer, hasFiscalYear As Boolean) As List(Of HolooPersonRow)
        Dim size = BulkChunkSize
        If hasFiscalYear AndAlso offset < pending.Count Then
            Dim probe = pending(offset)
            If probe.OpeningDebit > 0 OrElse probe.OpeningCredit > 0 Then
                size = BulkChunkSizeWithOpeningBalance
            Else
                ' اگر در محدودهٔ پیش‌رو مانده افتتاحیه باشد، chunk کوچک‌تر
                Dim endProbe = Math.Min(pending.Count, offset + BulkChunkSize) - 1
                For p = offset To endProbe
                    If pending(p).OpeningDebit > 0 OrElse pending(p).OpeningCredit > 0 Then
                        size = BulkChunkSizeWithOpeningBalance
                        Exit For
                    End If
                Next
            End If
        End If
        Dim take = Math.Min(size, pending.Count - offset)
        Return pending.GetRange(offset, take)
    End Function

    Private Shared Function BuildPersonPayload(row As HolooPersonRow, includeOpeningBalance As Boolean) As JObject
        Dim codeNum As Integer = 0
        Integer.TryParse(row.Code, codeNum)

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

        If includeOpeningBalance AndAlso (row.OpeningDebit > 0 OrElse row.OpeningCredit > 0) Then
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
        Return payload
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
        Dim pending As New List(Of HolooProductRow)()
        Dim alreadyDone = 0
        For Each row In rows
            If modCp.Done.ContainsKey(row.Key) Then
                alreadyDone += 1
            Else
                pending.Add(row)
            End If
        Next
        If alreadyDone > 0 Then
            RaiseProgress("کالا", alreadyDone, rows.Count, "رد شده از قبل: " & alreadyDone.ToString() & " کالا")
        End If
        If pending.Count = 0 Then
            If modCp.Failed.Count = 0 Then modCp.Completed = True
            store.Save(cp)
            RaiseProgress("کالا", rows.Count, rows.Count, "همه کالاها قبلاً منتقل شده‌اند")
            Return
        End If

        RaiseProgress("کالا", alreadyDone, rows.Count, "ارسال گروهی " & pending.Count.ToString() & " کالا...")
        Dim processed = alreadyDone
        Dim offset = 0
        While offset < pending.Count
            ct.ThrowIfCancellationRequested()
            Dim chunkRows = TakeProductChunk(pending, offset, hasFiscalYear)
            Dim items As New JArray()
            For Each row In chunkRows
                Dim payload = BuildProductPayload(row, warehouseMap, hasFiscalYear)
                items.Add(New JObject From {
                    {"client_ref", row.Key},
                    {"payload", payload}
                })
            Next

            Dim bulk As BulkUpsertResult = Nothing
            Dim requestErr As Exception = Nothing
            Try
                bulk = Await api.BulkUpsertProductsAsync(businessId, items, createIfUpdateMissing:=True, ct:=ct).ConfigureAwait(False)
            Catch ex As Exception
                requestErr = ex
            End Try

            If requestErr IsNot Nothing Then
                For Each row In chunkRows
                    modCp.Failed(row.Key) = requestErr.Message
                    RaiseProgress("کالا", processed + 1, rows.Count, "خطای درخواست گروهی: " & row.Code & " — " & requestErr.Message, True)
                    processed += 1
                    modCp.LastKey = row.Key
                Next
                store.Save(cp)
                offset += chunkRows.Count
                Continue While
            End If

            Dim retryNoOb As New List(Of HolooProductRow)()
            Dim byClientRef = IndexBulkByClientRef(bulk)
            For i = 0 To chunkRows.Count - 1
                Dim row = chunkRows(i)
                Dim itemResult = ResolveBulkItem(byClientRef, bulk, i, row.Key)
                processed += 1
                modCp.LastKey = row.Key

                If itemResult IsNot Nothing AndAlso itemResult.IsSuccess AndAlso itemResult.EntityId > 0 Then
                    modCp.Done(row.Key) = itemResult.EntityId
                    modCp.Failed.Remove(row.Key)
                    Continue For
                End If

                Dim errCode = If(itemResult Is Nothing, Nothing, itemResult.ErrorCode)
                Dim errMsg = If(itemResult Is Nothing, "نتیجه bulk برای این ردیف برنگشت", If(itemResult.Message, itemResult.ErrorCode))

                If String.Equals(errCode, "NO_CURRENT_FISCAL_YEAR", StringComparison.OrdinalIgnoreCase) Then
                    hasFiscalYear = False
                    retryNoOb.Add(row)
                    processed -= 1
                    Continue For
                End If

                If String.Equals(errCode, "DUPLICATE_PRODUCT_CODE", StringComparison.OrdinalIgnoreCase) Then
                    Dim linked = 0
                    Try
                        linked = Await api.FindProductIdByCodeAsync(businessId, row.Code, ct).ConfigureAwait(False)
                    Catch
                    End Try
                    If linked > 0 Then
                        modCp.Done(row.Key) = linked
                        modCp.Failed.Remove(row.Key)
                        RaiseProgress("کالا", processed, rows.Count, "کد تکراری — لینک شد: " & row.Code)
                    Else
                        modCp.Failed(row.Key) = If(errMsg, "کد کالا تکراری است")
                        RaiseProgress("کالا", processed, rows.Count, "خطا: " & row.Code & " — " & modCp.Failed(row.Key), True)
                    End If
                    Continue For
                End If

                modCp.Failed(row.Key) = If(errMsg, "خطای ناشناخته")
                RaiseProgress("کالا", processed, rows.Count, "خطا: " & row.Code & " — " & modCp.Failed(row.Key), True)
            Next

            If retryNoOb.Count > 0 Then
                RaiseProgress("کالا", processed, rows.Count, "تلاش مجدد بدون موجودی اولیه برای " & retryNoOb.Count.ToString() & " کالا...")
                Dim retryItems As New JArray()
                For Each row In retryNoOb
                    Dim payload = BuildProductPayload(row, warehouseMap, includeOpeningBalance:=False)
                    retryItems.Add(New JObject From {
                        {"client_ref", row.Key},
                        {"payload", payload}
                    })
                Next
                Dim retryBulk As BulkUpsertResult = Nothing
                Dim retryErr As Exception = Nothing
                Try
                    retryBulk = Await api.BulkUpsertProductsAsync(businessId, retryItems, True, ct).ConfigureAwait(False)
                Catch ex As Exception
                    retryErr = ex
                End Try
                If retryErr IsNot Nothing Then
                    For Each row In retryNoOb
                        processed += 1
                        modCp.Failed(row.Key) = retryErr.Message
                        modCp.LastKey = row.Key
                        RaiseProgress("کالا", processed, rows.Count, "خطا: " & row.Code & " — " & retryErr.Message, True)
                    Next
                Else
                    Dim retryByRef = IndexBulkByClientRef(retryBulk)
                    For i = 0 To retryNoOb.Count - 1
                        Dim row = retryNoOb(i)
                        processed += 1
                        modCp.LastKey = row.Key
                        Dim itemResult = ResolveBulkItem(retryByRef, retryBulk, i, row.Key)
                        If itemResult IsNot Nothing AndAlso itemResult.IsSuccess AndAlso itemResult.EntityId > 0 Then
                            modCp.Done(row.Key) = itemResult.EntityId
                            modCp.Failed.Remove(row.Key)
                        ElseIf itemResult IsNot Nothing AndAlso
                               String.Equals(itemResult.ErrorCode, "DUPLICATE_PRODUCT_CODE", StringComparison.OrdinalIgnoreCase) Then
                            Dim linked = 0
                            Try
                                linked = Await api.FindProductIdByCodeAsync(businessId, row.Code, ct).ConfigureAwait(False)
                            Catch
                            End Try
                            If linked > 0 Then
                                modCp.Done(row.Key) = linked
                                modCp.Failed.Remove(row.Key)
                            Else
                                modCp.Failed(row.Key) = If(itemResult.Message, "کد کالا تکراری است")
                                RaiseProgress("کالا", processed, rows.Count, "خطا: " & row.Code & " — " & modCp.Failed(row.Key), True)
                            End If
                        Else
                            Dim msg = If(itemResult Is Nothing, "نتیجه bulk برنگشت", If(itemResult.Message, itemResult.ErrorCode))
                            modCp.Failed(row.Key) = If(msg, "خطای ناشناخته")
                            RaiseProgress("کالا", processed, rows.Count, "خطا: " & row.Code & " — " & modCp.Failed(row.Key), True)
                        End If
                    Next
                End If
            End If

            Dim created = If(bulk Is Nothing, 0, bulk.Created)
            Dim updated = If(bulk Is Nothing, 0, bulk.Updated)
            RaiseProgress("کالا", processed, rows.Count,
                          "دسته: ایجاد " & created.ToString() & " / به‌روز " & updated.ToString() &
                          " (مجموع " & processed.ToString() & "/" & rows.Count.ToString() & ")")
            store.Save(cp)
            offset += chunkRows.Count
        End While

        If modCp.Failed.Count = 0 Then modCp.Completed = True
        store.Save(cp)
    End Function

    Private Shared Function TakeProductChunk(pending As List(Of HolooProductRow), offset As Integer, hasFiscalYear As Boolean) As List(Of HolooProductRow)
        Dim size = BulkChunkSize
        If hasFiscalYear AndAlso offset < pending.Count Then
            Dim endProbe = Math.Min(pending.Count, offset + BulkChunkSize) - 1
            For p = offset To endProbe
                If pending(p).FirstExist > 0 Then
                    size = BulkChunkSizeWithOpeningBalance
                    Exit For
                End If
            Next
        End If
        Dim take = Math.Min(size, pending.Count - offset)
        Return pending.GetRange(offset, take)
    End Function

    Private Shared Function BuildProductPayload(row As HolooProductRow, warehouseMap As ModuleCheckpoint, includeOpeningBalance As Boolean) As JObject
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
        If includeOpeningBalance AndAlso row.FirstExist > 0 Then
            Dim ob As New JObject()
            ob("quantity") = row.FirstExist
            ob("cost_price") = If(row.FirstBuyPrice > 0, row.FirstBuyPrice, row.PurchasePrice)
            If row.WarehouseCode.HasValue AndAlso warehouseMap.Done.ContainsKey(row.WarehouseCode.Value.ToString()) Then
                ob("warehouse_id") = warehouseMap.Done(row.WarehouseCode.Value.ToString())
            End If
            payload("opening_balance") = ob
        End If
        Return payload
    End Function

    Private Shared Function IndexBulkByClientRef(bulk As BulkUpsertResult) As Dictionary(Of String, BulkUpsertItemResult)
        Dim map As New Dictionary(Of String, BulkUpsertItemResult)(StringComparer.Ordinal)
        If bulk Is Nothing OrElse bulk.Results Is Nothing Then Return map
        For Each r In bulk.Results
            If Not String.IsNullOrWhiteSpace(r.ClientRef) AndAlso Not map.ContainsKey(r.ClientRef) Then
                map(r.ClientRef) = r
            End If
        Next
        Return map
    End Function

    Private Shared Function ResolveBulkItem(
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
            If indexInChunk >= 0 AndAlso indexInChunk < bulk.Results.Count Then
                Return bulk.Results(indexInChunk)
            End If
        End If
        Return Nothing
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
