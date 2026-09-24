Imports System.IO
Imports Newtonsoft.Json

''' <summary>
''' پروفایل نگاشت سرفصل هلو→حسابیکس برای یک جفت (کسب‌وکار، دیتابیس هلو).
''' قفل پروفایل برای انتقال اسناد Full History الزامی است.
''' </summary>
Friend Class SarfaslProfileEntry
    Public Property Col As String
    Public Property Moien As String
    Public Property Name As String
    Public Property LineCount As Long
    Public Property Decision As String
    Public Property TargetCode As String
    ''' <summary>Override دستی اپراتور (کد حسابیکس یا خالی = همان Decision).</summary>
    Public Property OverrideCode As String
    Public Property Exempt As Boolean
    Public Property ExemptReason As String

    Public ReadOnly Property Key As String
        Get
            Return (If(Col, "")).Trim() & "|" & (If(Moien, "")).Trim()
        End Get
    End Property

    Public ReadOnly Property EffectiveCode As String
        Get
            If Not String.IsNullOrWhiteSpace(OverrideCode) Then Return OverrideCode.Trim()
            Return If(TargetCode, "")
        End Get
    End Property
End Class

Friend Class SarfaslProfile
    Public Property Version As Integer = 1
    Public Property BusinessId As Integer
    Public Property HolooDatabase As String
    Public Property Locked As Boolean
    Public Property LockedAt As String
    Public Property Entries As New List(Of SarfaslProfileEntry)

    Public Function Find(col As String, moien As String) As SarfaslProfileEntry
        Dim k = (If(col, "")).Trim() & "|" & (If(moien, "")).Trim()
        Return Entries.FirstOrDefault(Function(e) e.Key.Equals(k, StringComparison.OrdinalIgnoreCase))
    End Function

    Public ReadOnly Property UnmappedCount As Integer
        Get
            Return Entries.Where(Function(e) e.Decision = "Unmapped" AndAlso Not e.Exempt AndAlso String.IsNullOrWhiteSpace(e.OverrideCode)).Count()
        End Get
    End Property

    Public ReadOnly Property CriticalUnmappedCount As Integer
        Get
            Dim critical = New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
                "101", "102", "103", "104", "106", "107", "205", "401", "402", "404", "502", "601", "702"
            }
            Return Entries.Where(Function(e) _
                critical.Contains(e.Col) AndAlso
                e.Decision = "Unmapped" AndAlso
                Not e.Exempt AndAlso
                String.IsNullOrWhiteSpace(e.OverrideCode)).Count()
        End Get
    End Property
End Class

Friend Class SarfaslProfileStore
    Private ReadOnly _path As String

    Public Sub New(businessId As Integer, holooDatabase As String)
        Dim dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix", "profiles")
        Directory.CreateDirectory(dir)
        Dim safeDb = If(holooDatabase, "db").Replace("\"c, "_"c).Replace("/"c, "_"c).Replace(":"c, "_"c)
        _path = Path.Combine(dir, "sarfasl_biz" & businessId.ToString() & "_" & safeDb & ".json")
    End Sub

    Public ReadOnly Property FilePath As String
        Get
            Return _path
        End Get
    End Property

    Public Shared Function FromAudit(
        businessId As Integer,
        holooDatabase As String,
        rows As List(Of SarfaslAuditService.SarfaslDecisionRow),
        Optional previous As SarfaslProfile = Nothing
    ) As SarfaslProfile
        Dim prevMap As New Dictionary(Of String, SarfaslProfileEntry)(StringComparer.OrdinalIgnoreCase)
        If previous IsNot Nothing AndAlso previous.Entries IsNot Nothing Then
            For Each e In previous.Entries
                If Not prevMap.ContainsKey(e.Key) Then prevMap(e.Key) = e
            Next
        End If
        Dim profile As New SarfaslProfile With {
            .BusinessId = businessId,
            .HolooDatabase = holooDatabase,
            .Locked = False
        }
        For Each r In rows
            Dim entry As New SarfaslProfileEntry With {
                .Col = r.Col,
                .Moien = r.Moien,
                .Name = r.Name,
                .LineCount = r.LineCount,
                .Decision = r.Decision,
                .TargetCode = r.TargetCode
            }
            Dim old As SarfaslProfileEntry = Nothing
            If prevMap.TryGetValue(entry.Key, old) AndAlso old IsNot Nothing Then
                entry.OverrideCode = old.OverrideCode
                entry.Exempt = old.Exempt
                entry.ExemptReason = old.ExemptReason
            End If
            profile.Entries.Add(entry)
        Next
        Return profile
    End Function

    Public Function Load() As SarfaslProfile
        If Not File.Exists(_path) Then Return Nothing
        Try
            Return JsonConvert.DeserializeObject(Of SarfaslProfile)(File.ReadAllText(_path, Text.Encoding.UTF8))
        Catch
            Return Nothing
        End Try
    End Function

    Public Sub Save(profile As SarfaslProfile)
        If profile Is Nothing Then Return
        Dim json = JsonConvert.SerializeObject(profile, Formatting.Indented)
        File.WriteAllText(_path, json, Text.Encoding.UTF8)
    End Sub

    Public Sub LockAndSave(profile As SarfaslProfile)
        profile.Locked = True
        profile.LockedAt = DateTime.Now.ToString("s")
        Save(profile)
    End Sub
End Class
