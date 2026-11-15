Imports System.Collections.Generic
Imports System.Globalization
Imports System.Linq
Imports System.Security.Cryptography
Imports System.Text

''' <summary>اثرانگشت پایدار از سند هلو برای تشخیص ویرایش در همگام‌سازی.</summary>
Friend NotInheritable Class FingerprintUtil
    Private Sub New()
    End Sub

    Public Shared Function Hash(parts As IEnumerable(Of String)) As String
        Dim raw = String.Join(ChrW(31), parts.Select(Function(p) If(p, "").Trim()))
        Using sha = SHA256.Create()
            Dim bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(raw))
            Dim sb As New StringBuilder(bytes.Length * 2)
            For Each b In bytes
                sb.Append(b.ToString("x2"))
            Next
            Return sb.ToString()
        End Using
    End Function

    Private Shared Function N(value As Double) As String
        Return Math.Round(value, 2).ToString("0.00", CultureInfo.InvariantCulture)
    End Function

    Private Shared Function D(value As Date) As String
        Return value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
    End Function

    Private Shared Function DOpt(value As Date?) As String
        If Not value.HasValue Then Return ""
        Return D(value.Value)
    End Function

    Public Shared Function ForInvoice(inv As HolooInvoiceHeader) As String
        Dim parts As New List(Of String) From {
            inv.FacType, inv.FacCode, D(inv.FacDate), inv.CustomerCode,
            N(inv.SumPrice), N(inv.Takhfif), N(inv.SumLevy), N(inv.SumScot),
            N(inv.FNaghd), N(inv.FCheck), N(inv.FNesieh), N(inv.Card), N(inv.FHaval),
            inv.Comment, inv.SanadCode.ToString()
        }
        If inv.Lines IsNot Nothing Then
            For Each ln In inv.Lines.OrderBy(Function(x) If(x.ArticleCode, "")).ThenBy(Function(x) x.Quantity)
                parts.Add(If(ln.ArticleCode, ""))
                parts.Add(N(ln.Quantity))
                parts.Add(N(ln.UnitPrice))
                parts.Add(N(ln.ForeignUnitPrice))
                parts.Add(N(ln.LineDiscount))
                parts.Add(N(ln.Levy))
                parts.Add(N(ln.Scot))
                parts.Add(ln.MoneyCode.ToString())
            Next
        End If
        Return Hash(parts)
    End Function

    Public Shared Function ForReceipt(row As HolooReceiptLikeSanad) As String
        Return Hash({
            row.SanadCode.ToString(), D(row.SanadDate), If(row.IsReceipt, "R", "P"),
            row.PersonMoien, N(row.PersonAmount),
            row.CounterCol, row.CounterMoien, row.CounterTafzili, N(row.CounterAmount),
            row.CounterName, row.Comment
        })
    End Function

    Public Shared Function ForExpenseIncome(row As HolooExpenseIncomeSanad) As String
        Dim parts As New List(Of String) From {
            row.SanadCode.ToString(), D(row.SanadDate), If(row.IsIncome, "I", "E"), row.Comment
        }
        If row.ItemLines IsNot Nothing Then
            For Each it In row.ItemLines.OrderBy(Function(x) If(x.MoienCode, "")).ThenBy(Function(x) x.Amount)
                parts.Add(If(it.MoienCode, ""))
                parts.Add(If(it.Name, ""))
                parts.Add(N(it.Amount))
            Next
        End If
        If row.CounterpartyLines IsNot Nothing Then
            For Each c In row.CounterpartyLines.OrderBy(Function(x) If(x.ColCode, "")).ThenBy(Function(x) If(x.MoienCode, ""))
                parts.Add(If(c.ColCode, ""))
                parts.Add(If(c.MoienCode, ""))
                parts.Add(If(c.TafziliCode, ""))
                parts.Add(N(c.Amount))
            Next
        End If
        Return Hash(parts)
    End Function

    Public Shared Function ForManual(row As HolooManualJournal) As String
        Dim parts As New List(Of String) From {
            row.SanadCode.ToString(), D(row.SanadDate), row.SanadType.ToString(),
            row.Comment, If(row.SkipReason, "")
        }
        If row.Lines IsNot Nothing Then
            For Each ln In row.Lines
                parts.Add(If(ln.ColCode, ""))
                parts.Add(If(ln.MoienCode, ""))
                parts.Add(If(ln.TafziliCode, ""))
                parts.Add(N(ln.Debit))
                parts.Add(N(ln.Credit))
            Next
        End If
        Return Hash(parts)
    End Function

    Public Shared Function ForCheckContent(row As HolooCheckRow) As String
        Return Hash({
            row.CheckCode.ToString(), row.CheckNumber,
            DOpt(row.ExportDate), DOpt(row.AttainDate), DOpt(row.ReceiveDate),
            row.SourcePersonCode, row.DestPersonCode,
            If(row.IsPayable, "1", "0"), If(row.IsVoid, "1", "0"),
            N(row.Amount), row.BankCode, row.AccountNumber, row.BankName, row.Comment
        })
    End Function
End Class
