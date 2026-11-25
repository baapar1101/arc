Imports System.IO
Imports System.Security.Cryptography
Imports Newtonsoft.Json

Friend Class SyncProfile
    Public Property Version As Integer = 1
    Public Property Enabled As Boolean
    Public Property Time1 As String = "09:00"
    Public Property Time2 As String = "17:00"
    Public Property ApiBaseUrl As String
    Public Property ApiKeyProtected As String
    Public Property SqlServer As String
    Public Property SqlWindowsAuth As Boolean
    Public Property SqlUser As String
    Public Property SqlPasswordProtected As String
    Public Property SqlDatabase As String
    Public Property BusinessId As Integer
    Public Property BusinessName As String
    Public Property Modules As New List(Of Integer)
    Public Property LastSyncAt As String
    Public Property LastSyncOk As Boolean
    Public Property LastSyncMessage As String
End Class

Friend Class SyncProfileStore
    Private ReadOnly _path As String
    Private Shared ReadOnly Entropy As Byte() = System.Text.Encoding.UTF8.GetBytes("Holoo2Hesabix.sync.v1")

    Public Sub New()
        Dim dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix")
        Directory.CreateDirectory(dir)
        _path = Path.Combine(dir, "sync-profile.json")
    End Sub

    Public ReadOnly Property FilePath As String
        Get
            Return _path
        End Get
    End Property

    Public Function Load() As SyncProfile
        If Not File.Exists(_path) Then Return Nothing
        Try
            Return JsonConvert.DeserializeObject(Of SyncProfile)(File.ReadAllText(_path, System.Text.Encoding.UTF8))
        Catch
            Return Nothing
        End Try
    End Function

    Public Sub Save(profile As SyncProfile)
        If profile Is Nothing Then Return
        Dim json = JsonConvert.SerializeObject(profile, Formatting.Indented)
        File.WriteAllText(_path, json, System.Text.Encoding.UTF8)
    End Sub

    Public Shared Function ProtectSecret(plain As String) As String
        If String.IsNullOrEmpty(plain) Then Return ""
        Dim bytes = ProtectedData.Protect(System.Text.Encoding.UTF8.GetBytes(plain), Entropy, DataProtectionScope.CurrentUser)
        Return Convert.ToBase64String(bytes)
    End Function

    Public Shared Function UnprotectSecret(protectedValue As String) As String
        If String.IsNullOrWhiteSpace(protectedValue) Then Return ""
        Try
            Dim bytes = ProtectedData.Unprotect(Convert.FromBase64String(protectedValue), Entropy, DataProtectionScope.CurrentUser)
            Return System.Text.Encoding.UTF8.GetString(bytes)
        Catch
            Return ""
        End Try
    End Function

    Public Shared Function ParseTimes(profile As SyncProfile) As List(Of TimeSpan)
        Dim list As New List(Of TimeSpan)
        AddTime(list, If(profile Is Nothing, Nothing, profile.Time1), New TimeSpan(9, 0, 0))
        AddTime(list, If(profile Is Nothing, Nothing, profile.Time2), New TimeSpan(17, 0, 0))
        Return list.Distinct().OrderBy(Function(t) t).ToList()
    End Function

    Private Shared Sub AddTime(list As List(Of TimeSpan), raw As String, fallback As TimeSpan)
        Dim t As TimeSpan
        If TimeSpan.TryParse(raw, t) Then
            list.Add(New TimeSpan(t.Hours, t.Minutes, 0))
        Else
            list.Add(fallback)
        End If
    End Sub

    Public Function CaptureFrom(session As MigrationSession, enabled As Boolean, time1 As String, time2 As String) As SyncProfile
        Dim existing = Load()
        Dim profile As New SyncProfile With {
            .Enabled = enabled,
            .Time1 = time1,
            .Time2 = time2,
            .ApiBaseUrl = session.ApiBaseUrl,
            .ApiKeyProtected = ProtectSecret(session.ApiKey),
            .SqlServer = If(session.SqlSettings Is Nothing, "", session.SqlSettings.Server),
            .SqlWindowsAuth = If(session.SqlSettings Is Nothing, False, session.SqlSettings.UseWindowsAuth),
            .SqlUser = If(session.SqlSettings Is Nothing, "", session.SqlSettings.UserName),
            .SqlPasswordProtected = ProtectSecret(If(session.SqlSettings Is Nothing, "", session.SqlSettings.Password)),
            .SqlDatabase = session.SelectedDatabase,
            .BusinessId = If(session.SelectedBusiness Is Nothing, 0, session.SelectedBusiness.Id),
            .BusinessName = If(session.SelectedBusiness Is Nothing, "", session.SelectedBusiness.Name),
            .LastSyncAt = If(existing Is Nothing, Nothing, existing.LastSyncAt),
            .LastSyncOk = If(existing Is Nothing, False, existing.LastSyncOk),
            .LastSyncMessage = If(existing Is Nothing, Nothing, existing.LastSyncMessage)
        }
        If session.SelectedModules IsNot Nothing Then
            profile.Modules = session.SelectedModules.Where(Function(m) m.Selected AndAlso m.Enabled).
                Select(Function(m) CInt(m.ModuleKey)).ToList()
        End If
        Return profile
    End Function

    Public Function TryRestoreSession(profile As SyncProfile, session As MigrationSession) As String
        If profile Is Nothing Then Return "پروفایل همگام‌سازی ذخیره نشده است."
        Dim apiKey = UnprotectSecret(profile.ApiKeyProtected)
        If String.IsNullOrWhiteSpace(apiKey) Then Return "کلید API قابل خواندن نیست. یک‌بار از برنامه همگام‌سازی را دوباره فعال کنید."
        If profile.BusinessId <= 0 Then Return "کسب‌وکار مقصد در پروفایل مشخص نیست."
        If String.IsNullOrWhiteSpace(profile.SqlDatabase) Then Return "دیتابیس هلو در پروفایل مشخص نیست."

        session.ApiBaseUrl = If(String.IsNullOrWhiteSpace(profile.ApiBaseUrl), MigrationSession.DefaultApiBaseUrl, profile.ApiBaseUrl)
        session.ApiKey = apiKey
        session.SqlSettings = New SqlConnectionSettings With {
            .Server = If(profile.SqlServer, "localhost"),
            .UseWindowsAuth = profile.SqlWindowsAuth,
            .UserName = If(profile.SqlUser, "sa"),
            .Password = UnprotectSecret(profile.SqlPasswordProtected),
            .Database = profile.SqlDatabase,
            .TrustServerCertificate = True
        }
        session.SelectedDatabase = profile.SqlDatabase
        session.IsSqlConnected = True
        session.SelectedBusiness = New HesabixBusiness With {
            .Id = profile.BusinessId,
            .Name = If(profile.BusinessName, "کسب‌وکار " & profile.BusinessId.ToString())
        }
        Dim wanted As New HashSet(Of Integer)(If(profile.Modules, New List(Of Integer)()))
        Dim mods = MigrationModuleInfo.GetAllModules()
        For Each m In mods
            m.Selected = (wanted.Count = 0) OrElse wanted.Contains(CInt(m.ModuleKey))
        Next
        session.SelectedModules = mods
        Dim pstore As New SarfaslProfileStore(profile.BusinessId, profile.SqlDatabase)
        session.SarfaslProfile = pstore.Load()
        session.SarfaslProfileLocked = session.SarfaslProfile IsNot Nothing AndAlso session.SarfaslProfile.Locked
        Return Nothing
    End Function
End Class
