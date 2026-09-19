Imports System.Data.SqlClient
Imports System.Threading

Friend Class HolooCompanyInfo
    Public Property Code As String
    Public Property Name As String
End Class

Friend Class HolooCurrencyInfo
    Public Property Code As Integer
    Public Property Name As String
    Public Property Rate As Double
    Public Property IsBase As Boolean
End Class

Friend Class HolooWarehouseRow
    Public Property Code As Integer
    Public Property Name As String
    Public Property ParentCode As Integer
    Public ReadOnly Property Key As String
        Get
            Return Code.ToString()
        End Get
    End Property
End Class

Friend Class HolooPersonRow
    Public Property Code As String
    Public Property Name As String
    Public Property AliasName As String
    Public Property CompanyName As String
    Public Property Mobile As String
    Public Property Phone As String
    Public Property Fax As String
    Public Property Address As String
    Public Property NationalCode As String
    Public Property EconomicCode As String
    Public Property RegistrationNumber As String
    Public Property Email As String
    Public Property IsCustomer As Boolean
    Public Property IsSupplier As Boolean
    Public Property IsEmployee As Boolean
    Public Property IsMarketer As Boolean
    Public Property IsColleague As Boolean
    Public Property IsSeller As Boolean
    Public Property City As String
    Public Property Province As String
    Public Property PostalCode As String
    Public Property CreditLimit As Double
    Public Property OpeningDebit As Double
    Public Property OpeningCredit As Double
    Public ReadOnly Property Key As String
        Get
            Return Code
        End Get
    End Property
End Class

Friend Class HolooBankAccountRow
    Public Property Id As Integer
    Public Property BankCode As String
    Public Property BankName As String
    Public Property AccountNumber As String
    Public Property BranchName As String
    Public Property Sheba As String
    Public Property CardNumber As String
    Public Property Title As String
    Public Property IsActive As Boolean
    Public ReadOnly Property Key As String
        Get
            Return If(Id > 0, Id.ToString(), BankCode & ":" & AccountNumber)
        End Get
    End Property
End Class

Friend Class HolooCashRow
    Public Property Id As Integer
    Public Property Name As String
    Public Property ParentId As Integer
    Public Property IsCashRegister As Boolean
    Public ReadOnly Property Key As String
        Get
            Return Id.ToString()
        End Get
    End Property
End Class

Friend Class HolooProductRow
    Public Property Code As String
    Public Property Name As String
    Public Property Barcode As String
    Public Property Model As String
    Public Property UnitName As String
    Public Property SalesPrice As Double
    Public Property PurchasePrice As Double
    Public Property WarehouseCode As Integer?
    Public Property IncludeTax As Boolean
    Public Property TaxRate As Double
    Public Property PurchaseTaxRate As Double
    Public Property IsActive As Boolean
    Public Property FirstExist As Double
    Public Property FirstBuyPrice As Double
    Public ReadOnly Property Key As String
        Get
            Return Code
        End Get
    End Property
End Class

Friend Class HolooBaseDataReader
    Public Function ReadCompany(settings As SqlConnectionSettings) As HolooCompanyInfo
        Using conn = Open(settings)
            Using cmd As New SqlCommand("SELECT TOP 1 CompCode, CompName FROM CompName;", conn)
                Using r = cmd.ExecuteReader()
                    If r.Read() Then
                        Return New HolooCompanyInfo With {
                            .Code = SafeStr(r, 0),
                            .Name = SafeStr(r, 1)
                        }
                    End If
                End Using
            End Using
        End Using
        Return New HolooCompanyInfo With {.Name = ""}
    End Function

    Public Function ReadCurrencies(settings As SqlConnectionSettings) As List(Of HolooCurrencyInfo)
        Dim list As New List(Of HolooCurrencyInfo)
        Using conn = Open(settings)
            Using cmd As New SqlCommand("SELECT M_Code, Money_Name, Money_Price, BaseArz FROM MONEY ORDER BY M_Code;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        list.Add(New HolooCurrencyInfo With {
                            .Code = SafeInt(r, 0),
                            .Name = SafeStr(r, 1),
                            .Rate = SafeDbl(r, 2),
                            .IsBase = SafeBool(r, 3)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function CountModule(settings As SqlConnectionSettings, m As MigrationModule) As Long
        Using conn = Open(settings)
            Dim sql = CountSql(m)
            Using cmd As New SqlCommand(sql, conn)
                Return Convert.ToInt64(cmd.ExecuteScalar())
            End Using
        End Using
    End Function

    Public Function CountSql(settings As SqlConnectionSettings, sql As String) As Long
        Using conn = Open(settings)
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                Return Convert.ToInt64(cmd.ExecuteScalar())
            End Using
        End Using
    End Function

    Public Function ReadWarehouses(settings As SqlConnectionSettings) As List(Of HolooWarehouseRow)
        Dim list As New List(Of HolooWarehouseRow)
        Using conn = Open(settings)
            Using cmd As New SqlCommand("SELECT Type_Anbar_C, Type_Anbar_N, ISNULL(ParentType_C,0) FROM TYPE_ANB ORDER BY Type_Anbar_C;", conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim name = SafeStr(r, 1)
                        If String.IsNullOrWhiteSpace(name) Then name = "انبار " & SafeInt(r, 0).ToString()
                        list.Add(New HolooWarehouseRow With {
                            .Code = SafeInt(r, 0),
                            .Name = name.Trim(),
                            .ParentCode = SafeInt(r, 2)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadPersons(settings As SqlConnectionSettings) As List(Of HolooPersonRow)
        Dim list As New List(Of HolooPersonRow)
        Using conn = Open(settings)
            Dim sql =
                "SELECT C_Code, C_Name, C_AliasName, CoName, C_Mobile, C_Tel, C_Fax, C_Address, " &
                "National_Code, Economic_Code, Register_Code, Email_Address, " &
                "ISNULL(Forosh,0), ISNULL(Kharid,0), ISNULL(Personel,0), ISNULL(Vaseteh,0), ISNULL(isHamkar,0), ISNULL(IsSeller,0), " &
                "Cust_City, Cust_Ostan, Zip_Code, ISNULL(Etebar,0), ISNULL(First_BalanceSanad,0), ISNULL(First_BalanceSanad_Bes,0) " &
                "FROM CUSTOMER WHERE ISNULL([Delete],0)=0 ORDER BY C_Code;"
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 120
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim code = SafeStr(r, 0)
                        Dim name = SafeStr(r, 1)
                        Dim aliasName = SafeStr(r, 2)
                        Dim mobile = SafeStr(r, 4)
                        If String.IsNullOrWhiteSpace(name) Then
                            name = If(Not String.IsNullOrWhiteSpace(aliasName), aliasName,
                                      If(Not String.IsNullOrWhiteSpace(mobile), mobile, "شخص " & code))
                        End If
                        list.Add(New HolooPersonRow With {
                            .Code = code,
                            .Name = name.Trim(),
                            .AliasName = aliasName,
                            .CompanyName = SafeStr(r, 3),
                            .Mobile = mobile,
                            .Phone = SafeStr(r, 5),
                            .Fax = SafeStr(r, 6),
                            .Address = SafeStr(r, 7),
                            .NationalCode = SafeStr(r, 8),
                            .EconomicCode = SafeStr(r, 9),
                            .RegistrationNumber = SafeStr(r, 10),
                            .Email = SafeStr(r, 11),
                            .IsCustomer = SafeBool(r, 12),
                            .IsSupplier = SafeBool(r, 13),
                            .IsEmployee = SafeBool(r, 14),
                            .IsMarketer = SafeBool(r, 15),
                            .IsColleague = SafeBool(r, 16),
                            .IsSeller = SafeBool(r, 17),
                            .City = SafeStr(r, 18),
                            .Province = SafeStr(r, 19),
                            .PostalCode = SafeStr(r, 20),
                            .CreditLimit = SafeDbl(r, 21),
                            .OpeningDebit = SafeDbl(r, 22),
                            .OpeningCredit = SafeDbl(r, 23)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadBankAccounts(settings As SqlConnectionSettings) As List(Of HolooBankAccountRow)
        Dim list As New List(Of HolooBankAccountRow)
        Using conn = Open(settings)
            Dim sql =
                "SELECT a.Id, a.Bank_Code, ISNULL(b.Bank_Name,''), a.Account_N, a.Branch_Name, a.Sheba_Num, a.Kart_Num, " &
                "ISNULL(NULLIF(a.MyNameAcound,''), ISNULL(NULLIF(a.TaitleBank,''), '')), ISNULL(a.IsActive,1) " &
                "FROM ACOUND_N a LEFT JOIN NEWBANK b ON a.Bank_Code = b.Bank_Code ORDER BY a.Id;"
            Using cmd As New SqlCommand(sql, conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim bankName = SafeStr(r, 2)
                        Dim account = SafeStr(r, 3)
                        Dim title = SafeStr(r, 7)
                        If String.IsNullOrWhiteSpace(title) Then
                            title = (bankName & " " & account).Trim()
                        End If
                        If String.IsNullOrWhiteSpace(title) Then title = "حساب بانکی " & SafeInt(r, 0).ToString()
                        list.Add(New HolooBankAccountRow With {
                            .Id = SafeInt(r, 0),
                            .BankCode = SafeStr(r, 1),
                            .BankName = bankName,
                            .AccountNumber = account,
                            .BranchName = SafeStr(r, 4),
                            .Sheba = SafeStr(r, 5),
                            .CardNumber = SafeStr(r, 6),
                            .Title = title.Trim(),
                            .IsActive = SafeBool(r, 8)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadCashRows(settings As SqlConnectionSettings, cashRegisters As Boolean) As List(Of HolooCashRow)
        Dim list As New List(Of HolooCashRow)
        Using conn = Open(settings)
            Dim sql =
                "SELECT Id, S_Name, ISNULL(Parent_Id,0), ISNULL(S_Type,0) FROM Cash " &
                "WHERE ISNULL(S_Type,0)=" & If(cashRegisters, "1", "0") & " ORDER BY Id;"
            Using cmd As New SqlCommand(sql, conn)
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim name = SafeStr(r, 1)
                        If String.IsNullOrWhiteSpace(name) Then name = If(cashRegisters, "صندوق ", "تنخواه ") & SafeInt(r, 0).ToString()
                        list.Add(New HolooCashRow With {
                            .Id = SafeInt(r, 0),
                            .Name = name.Trim(),
                            .ParentId = SafeInt(r, 2),
                            .IsCashRegister = cashRegisters
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Public Function ReadProducts(settings As SqlConnectionSettings) As List(Of HolooProductRow)
        Dim list As New List(Of HolooProductRow)
        Using conn = Open(settings)
            Dim sql =
                "SELECT a.A_Code, a.A_Name, a.A_Code_C, a.Model, ISNULL(u.Unit_Name,''), " &
                "ISNULL(a.Sel_Price,0), ISNULL(a.Buy_Price,0), a.Type_Anbar_C, " &
                "ISNULL(a.Include_Tax,0), ISNULL(a.Levy,0), ISNULL(a.scot,0), ISNULL(a.IsActive,1), " &
                "ISNULL(a.First_exist,0), ISNULL(NULLIF(a.FirstBuy_Price,0), ISNULL(a.Buy_Price,0)) " &
                "FROM ARTICLE a LEFT JOIN UNIT u ON a.VahedCode = u.Unit_Code " &
                "WHERE ISNULL(a.[Delete],0)=0 ORDER BY a.A_Code;"
            Using cmd As New SqlCommand(sql, conn)
                cmd.CommandTimeout = 180
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        Dim code = SafeStr(r, 0)
                        Dim name = SafeStr(r, 1)
                        If String.IsNullOrWhiteSpace(name) Then name = "کالا " & code
                        Dim barcode = SafeStr(r, 2)
                        If barcode = "." Then barcode = ""
                        Dim unitName = SafeStr(r, 4)
                        If String.IsNullOrWhiteSpace(unitName) Then unitName = "عدد"
                        Dim wh As Integer? = Nothing
                        If Not r.IsDBNull(7) Then
                            Dim w = Convert.ToInt32(r.GetValue(7))
                            If w > 0 Then wh = w
                        End If
                        list.Add(New HolooProductRow With {
                            .Code = code,
                            .Name = name.Trim(),
                            .Barcode = barcode,
                            .Model = SafeStr(r, 3),
                            .UnitName = unitName,
                            .SalesPrice = SafeDbl(r, 5),
                            .PurchasePrice = SafeDbl(r, 6),
                            .WarehouseCode = wh,
                            .IncludeTax = SafeBool(r, 8),
                            .TaxRate = SafeDbl(r, 9),
                            .PurchaseTaxRate = SafeDbl(r, 10),
                            .IsActive = SafeBool(r, 11),
                            .FirstExist = SafeDbl(r, 12),
                            .FirstBuyPrice = SafeDbl(r, 13)
                        })
                    End While
                End Using
            End Using
        End Using
        Return list
    End Function

    Private Shared Function CountSql(m As MigrationModule) As String
        Select Case m
            Case MigrationModule.Warehouses
                Return "SELECT COUNT(*) FROM TYPE_ANB;"
            Case MigrationModule.Persons
                Return "SELECT COUNT(*) FROM CUSTOMER WHERE ISNULL([Delete],0)=0;"
            Case MigrationModule.BankAccounts
                Return "SELECT COUNT(*) FROM ACOUND_N;"
            Case MigrationModule.CashRegisters
                Return "SELECT COUNT(*) FROM Cash WHERE ISNULL(S_Type,0)=1;"
            Case MigrationModule.PettyCash
                Return "SELECT COUNT(*) FROM Cash WHERE ISNULL(S_Type,0)=0;"
            Case MigrationModule.Products
                Return "SELECT COUNT(*) FROM ARTICLE WHERE ISNULL([Delete],0)=0;"
            Case MigrationModule.Invoices
                Return "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Type IN ('F','K','Y','X','Z');"
            Case MigrationModule.Checks
                Return "SELECT COUNT(*) FROM [Check] WHERE ISNULL([Delete],0)=0;"
            Case MigrationModule.ReceiptsPayments
                Return "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 AND s.Sanad_Type=20 " &
                       "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));"
            Case MigrationModule.ExpenseIncome
                Return "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                       "AND EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));"
            Case MigrationModule.ManualJournals
                Return "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                       "AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                       "AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                       "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));"
            Case MigrationModule.FiscalYearsAndOpening
                Return "SELECT COUNT(*) FROM SANAD WHERE Sanad_Code=1;"
            Case MigrationModule.WarehouseDocs
                Return "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Type IN ('F','K','Y','X','Z');"
            Case Else
                Return "SELECT 0;"
        End Select
    End Function

    Private Shared Function Open(settings As SqlConnectionSettings) As SqlConnection
        If String.IsNullOrWhiteSpace(settings.Database) Then
            Throw New InvalidOperationException("دیتابیس هلو انتخاب نشده است.")
        End If
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
End Class
