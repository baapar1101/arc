Imports Newtonsoft.Json
Imports Newtonsoft.Json.Linq

Friend Class ModuleCheckpoint
    Public Property Completed As Boolean
    Public Property Done As New Dictionary(Of String, Integer)
    Public Property Failed As New Dictionary(Of String, String)
    Public Property LastKey As String
End Class

Friend Class TransferCheckpoint
    Public Property Version As Integer = 1
    Public Property ApiBaseUrl As String
    Public Property BusinessId As Integer
    Public Property HolooDatabase As String
    Public Property SqlServer As String
    Public Property UpdatedAt As String
    Public Property Modules As New Dictionary(Of String, ModuleCheckpoint)

    Public Function EnsureModule(key As String) As ModuleCheckpoint
        Dim existing As ModuleCheckpoint = Nothing
        If Modules.TryGetValue(key, existing) AndAlso existing IsNot Nothing Then
            Return existing
        End If
        Dim created As New ModuleCheckpoint()
        Modules(key) = created
        Return created
    End Function
End Class

Friend Class CheckpointStore
    Private ReadOnly _path As String

    Public Sub New(businessId As Integer, holooDatabase As String)
        Dim dir = IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix", "checkpoints")
        IO.Directory.CreateDirectory(dir)
        Dim safeDb = If(holooDatabase, "db").Replace("\"c, "_"c).Replace("/"c, "_"c).Replace(":"c, "_"c)
        _path = IO.Path.Combine(dir, "biz" & businessId.ToString() & "_" & safeDb & ".json")
    End Sub

    Public ReadOnly Property FilePath As String
        Get
            Return _path
        End Get
    End Property

    Public Function LoadOrCreate(apiBaseUrl As String, businessId As Integer, sqlServer As String, holooDatabase As String) As TransferCheckpoint
        If IO.File.Exists(_path) Then
            Try
                Dim json = IO.File.ReadAllText(_path, Text.Encoding.UTF8)
                Dim cp = JsonConvert.DeserializeObject(Of TransferCheckpoint)(json)
                If cp IsNot Nothing Then
                    If cp.Modules Is Nothing Then cp.Modules = New Dictionary(Of String, ModuleCheckpoint)
                    Return cp
                End If
            Catch
            End Try
        End If
        Return New TransferCheckpoint With {
            .ApiBaseUrl = apiBaseUrl,
            .BusinessId = businessId,
            .SqlServer = sqlServer,
            .HolooDatabase = holooDatabase,
            .UpdatedAt = DateTime.Now.ToString("s")
        }
    End Function

    Public Sub Save(cp As TransferCheckpoint)
        cp.UpdatedAt = DateTime.Now.ToString("s")
        Dim json = JsonConvert.SerializeObject(cp, Formatting.Indented)
        IO.File.WriteAllText(_path, json, Text.Encoding.UTF8)
    End Sub

    Public Sub Reset()
        If IO.File.Exists(_path) Then IO.File.Delete(_path)
    End Sub
End Class
