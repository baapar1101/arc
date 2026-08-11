Imports System.Globalization

''' <summary>
''' تاریخ‌های ارسالی به API باید همیشه میلادی ISO باشند.
''' فرهنگ fa-IR برنامه برای UI است؛ ToString بدون Invariant روی PersianCalendar جلالی می‌دهد
''' (مثلاً 2023-05-19 → 1402-02-29) و در سرور به‌عنوان میلادی ذخیره می‌شود → نمایش سال ~۷۸۰.
''' </summary>
Friend Module ApiDateFormat
    Private ReadOnly Invariant As CultureInfo = CultureInfo.InvariantCulture

    Public Function ToIsoDate(value As Date) As String
        Return value.ToString("yyyy-MM-dd", Invariant)
    End Function

    Public Function ToIsoDate(value As Date?) As String
        If Not value.HasValue Then Return Nothing
        Return ToIsoDate(value.Value)
    End Function

    Public Function RoundMoney(value As Double) As Double
        Return Math.Round(value, 2, MidpointRounding.AwayFromZero)
    End Function
End Module
