Friend Class HesabixUser
    Public Property Id As Integer
    Public Property Email As String
    Public Property Mobile As String
    Public Property FirstName As String
    Public Property LastName As String
    Public Property IsActive As Boolean

    Public ReadOnly Property DisplayName As String
        Get
            Dim full = (If(FirstName, "") & " " & If(LastName, "")).Trim()
            If Not String.IsNullOrWhiteSpace(full) Then Return full
            If Not String.IsNullOrWhiteSpace(Email) Then Return Email
            If Not String.IsNullOrWhiteSpace(Mobile) Then Return Mobile
            Return "کاربر #" & Id.ToString()
        End Get
    End Property
End Class

Friend Class HesabixBusiness
    Public Property Id As Integer
    Public Property Name As String
    Public Property BusinessType As String
    Public Property BusinessField As String
    Public Property OwnerId As Integer?
    Public Property CreatedAt As String
    Public Property DefaultCurrencyId As Integer
    Public Property DefaultCurrencyCode As String
    Public Property DefaultCurrencyTitle As String

    Public ReadOnly Property Subtitle As String
        Get
            Dim parts As New List(Of String)
            If Not String.IsNullOrWhiteSpace(BusinessType) Then parts.Add(BusinessType)
            If Not String.IsNullOrWhiteSpace(BusinessField) Then parts.Add(BusinessField)
            Return String.Join(" · ", parts)
        End Get
    End Property
End Class

Friend Class CurrencyInfo
    Public Property Id As Integer
    Public Property Name As String
    Public Property Title As String
    Public Property Symbol As String
    Public Property Code As String

    Public Overrides Function ToString() As String
        Dim label = If(Not String.IsNullOrWhiteSpace(Title), Title, Name)
        If Not String.IsNullOrWhiteSpace(Code) Then
            Return label & " (" & Code & ")"
        End If
        Return label
    End Function
End Class

Friend Class NewBusinessRequest
    Public Property Name As String
    Public Property BusinessType As String
    Public Property BusinessField As String
    Public Property DefaultCurrencyId As Integer
    Public Property IncludeSampleData As Boolean
End Class

Friend Class CaptchaChallenge
    Public Property CaptchaId As String
    Public Property ImageBase64 As String
    Public Property TtlSeconds As Integer

    Public Function ToImage() As Image
        If String.IsNullOrWhiteSpace(ImageBase64) Then Return Nothing
        Dim raw = ImageBase64.Trim()
        Dim comma = raw.IndexOf(","c)
        If raw.StartsWith("data:", StringComparison.OrdinalIgnoreCase) AndAlso comma >= 0 Then
            raw = raw.Substring(comma + 1)
        End If
        Dim bytes = Convert.FromBase64String(raw)
        Using ms As New IO.MemoryStream(bytes)
            Using img = Image.FromStream(ms)
                Return New Bitmap(img)
            End Using
        End Using
    End Function
End Class

Friend Class LoginResult
    Public Property ApiKey As String
    Public Property User As HesabixUser
End Class
