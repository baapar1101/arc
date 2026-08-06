Friend Enum MigrationModule
    Warehouses = 1
    Persons = 2
    BankAccounts = 3
    CashRegisters = 4
    PettyCash = 5
    Products = 6
End Enum

Friend NotInheritable Class MigrationModuleInfo
    Private Sub New()
    End Sub

    Public Shared Function GetBaseModules() As List(Of ModuleOption)
        Return New List(Of ModuleOption) From {
            New ModuleOption(MigrationModule.Warehouses, "انبارها", "TYPE_ANB", True, 10),
            New ModuleOption(MigrationModule.Persons, "اشخاص / طرف‌حساب‌ها", "CUSTOMER", True, 20),
            New ModuleOption(MigrationModule.BankAccounts, "حساب‌های بانکی", "ACOUND_N", True, 30),
            New ModuleOption(MigrationModule.CashRegisters, "صندوق‌ها", "Cash (S_Type=1)", True, 40),
            New ModuleOption(MigrationModule.PettyCash, "تنخواه‌گردان", "Cash (S_Type=0)", True, 50),
            New ModuleOption(MigrationModule.Products, "کالا و خدمات", "ARTICLE", True, 60)
        }
    End Function

    Public Shared Function TitleOf(m As MigrationModule) As String
        Select Case m
            Case MigrationModule.Warehouses : Return "انبارها"
            Case MigrationModule.Persons : Return "اشخاص"
            Case MigrationModule.BankAccounts : Return "حساب‌های بانکی"
            Case MigrationModule.CashRegisters : Return "صندوق‌ها"
            Case MigrationModule.PettyCash : Return "تنخواه"
            Case MigrationModule.Products : Return "کالا و خدمات"
            Case Else : Return m.ToString()
        End Select
    End Function
End Class

Friend Class ModuleOption
    Public Property ModuleKey As MigrationModule
    Public Property Title As String
    Public Property HolooSource As String
    Public Property Enabled As Boolean
    Public Property SortOrder As Integer
    Public Property Selected As Boolean = True
    Public Property SourceCount As Long = -1
    Public Property Note As String

    Public Sub New(key As MigrationModule, title As String, source As String, enabled As Boolean, sortOrder As Integer)
        ModuleKey = key
        Me.Title = title
        HolooSource = source
        Me.Enabled = enabled
        Me.SortOrder = sortOrder
    End Sub
End Class

Friend Class PreflightIssue
    Public Property Severity As String ' info | warning | error
    Public Property Title As String
    Public Property Detail As String
End Class

Friend Class PreflightReport
    Public Property HolooCompanyName As String
    Public Property HesabixBusinessName As String
    Public Property HolooBaseCurrency As String
    Public Property HesabixCurrencyTitle As String
    Public Property HesabixCurrencyCode As String
    Public Property HesabixCurrencyId As Integer
    Public Property CurrencyMatched As Boolean
    Public Property CanProceed As Boolean = True
    Public Property Issues As New List(Of PreflightIssue)
    Public Property ModuleCounts As New Dictionary(Of String, Long)
End Class

Friend Class TransferProgressEventArgs
    Inherits EventArgs
    Public Property ModuleTitle As String
    Public Property Current As Integer
    Public Property Total As Integer
    Public Property Message As String
    Public Property IsError As Boolean
End Class
