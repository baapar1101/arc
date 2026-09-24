Friend Class MigrationSession
    Public Const DefaultApiBaseUrl As String = "https://hsxn.hesabix.ir"

    Public Property ApiBaseUrl As String = DefaultApiBaseUrl
    Public Property ApiKey As String = ""
    Public Property CurrentUser As HesabixUser
    Public Property Businesses As New List(Of HesabixBusiness)
    Public Property SelectedBusiness As HesabixBusiness

    Public Property SqlSettings As New SqlConnectionSettings()
    Public Property AvailableDatabases As List(Of HolooDatabaseInfo)
    Public Property SelectedDatabase As String
    Public Property HolooProbe As HolooProbeResult
    Public Property IsSqlConnected As Boolean

    Public Property SelectedModules As List(Of ModuleOption)
    Public Property Preflight As PreflightReport
    Public Property AllowCurrencyMismatch As Boolean
    Public Property SarfaslProfile As SarfaslProfile
    Public Property SarfaslProfileLocked As Boolean

    Public ReadOnly Property IsHesabixConnected As Boolean
        Get
            Return CurrentUser IsNot Nothing AndAlso Not String.IsNullOrWhiteSpace(ApiKey)
        End Get
    End Property

    Public ReadOnly Property CanProceedFromHesabix As Boolean
        Get
            Return IsHesabixConnected AndAlso SelectedBusiness IsNot Nothing
        End Get
    End Property

    Public ReadOnly Property CanProceedFromHolooSql As Boolean
        Get
            Return IsSqlConnected AndAlso Not String.IsNullOrWhiteSpace(SelectedDatabase)
        End Get
    End Property

    Public Sub ResetHesabixSelection()
        SelectedBusiness = Nothing
    End Sub

    Public Sub ClearHesabixAuth()
        CurrentUser = Nothing
        Businesses.Clear()
        SelectedBusiness = Nothing
        ApiKey = ""
    End Sub

    Public Sub ClearSqlSelection()
        SelectedDatabase = Nothing
        HolooProbe = Nothing
        AvailableDatabases = Nothing
        IsSqlConnected = False
        If SqlSettings IsNot Nothing Then
            SqlSettings.Database = ""
        End If
    End Sub
End Class
