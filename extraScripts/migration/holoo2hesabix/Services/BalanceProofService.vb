Imports System.Data.SqlClient
Imports System.IO
Imports System.Text
Imports Newtonsoft.Json

''' <summary>
''' گزارش اثبات پارتیشن و جمع بدهکار/بستانکار هلو به تفکیک bucket.
''' </summary>
Friend Class BalanceProofService
    Public Class ProofBucket
        Public Property Bucket As String
        Public Property DocumentCount As Long
        Public Property Debit As Double
        Public Property Credit As Double
    End Class

    Public Class BalanceProofReport
        Public Property GeneratedAt As String
        Public Property HolooDatabase As String
        Public Property BusinessId As Integer
        Public Property Buckets As New List(Of ProofBucket)
        Public Property ManualWithoutFacture As Long
        Public Property FactureLinkedExcludedFromManual As Long
        Public Property Notes As New List(Of String)
    End Class

    Public Function BuildHolooProof(settings As SqlConnectionSettings, businessId As Integer) As BalanceProofReport
        Dim report As New BalanceProofReport With {
            .GeneratedAt = DateTime.Now.ToString("s"),
            .HolooDatabase = settings.Database,
            .BusinessId = businessId
        }
        Using conn As New SqlConnection(settings.BuildConnectionString(settings.Database))
            conn.Open()
            Using cmd As New SqlCommand(
                "SELECT bucket, COUNT(*) docs, " &
                "ISNULL(SUM(deb),0), ISNULL(SUM(cred),0) FROM (" &
                "  SELECT CASE " &
                "    WHEN s.Sanad_Code=1 THEN 'OPENING' " &
                "    WHEN ISNULL(s.Sanad_Type,0)=5 OR EXISTS(SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) THEN 'CHECK_GL_SKIP' " &
                "    WHEN EXISTS(SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "      OR (ISNULL(s.SaveFromFacture,0)=1 AND ISNULL(s.Sanad_Type,0) IN (0,13,14)) THEN 'INVOICE_GL_SKIP' " &
                "    WHEN EXISTS(SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702')) THEN 'EXPENSE_INCOME' " &
                "    WHEN ISNULL(s.Sanad_Type,0)=20 THEN 'RECEIPT_PAYMENT' " &
                "    WHEN ISNULL(s.SaveFromFacture,0)=0 AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                "      AND NOT EXISTS(SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "      AND NOT EXISTS(SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                "      AND NOT EXISTS(SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702')) THEN 'MANUAL' " &
                "    ELSE 'OTHER' END AS bucket, " &
                "    (SELECT ISNULL(SUM(l.Bed),0) FROM SND_LIST l WHERE l.Sanad_Code=s.Sanad_Code AND LTRIM(RTRIM(l.Col_Code)) NOT IN ('005','006')) deb, " &
                "    (SELECT ISNULL(SUM(l.Bes),0) FROM SND_LIST l WHERE l.Sanad_Code=s.Sanad_Code AND LTRIM(RTRIM(l.Col_Code)) NOT IN ('005','006')) cred " &
                "  FROM SANAD s WHERE ISNULL(s.[Delete],0)=0" &
                ") t GROUP BY bucket ORDER BY bucket;", conn)
                cmd.CommandTimeout = 300
                Using r = cmd.ExecuteReader()
                    While r.Read()
                        report.Buckets.Add(New ProofBucket With {
                            .Bucket = Convert.ToString(r.GetValue(0)),
                            .DocumentCount = Convert.ToInt64(r.GetValue(1)),
                            .Debit = Convert.ToDouble(r.GetValue(2)),
                            .Credit = Convert.ToDouble(r.GetValue(3))
                        })
                    End While
                End Using
            End Using

            Using cmd As New SqlCommand(
                "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                "AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) " &
                "AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) " &
                "AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));", conn)
                report.ManualWithoutFacture = Convert.ToInt64(cmd.ExecuteScalar())
            End Using
            Using cmd As New SqlCommand(
                "SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 " &
                "AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) " &
                "AND EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0);", conn)
                report.FactureLinkedExcludedFromManual = Convert.ToInt64(cmd.ExecuteScalar())
            End Using
        End Using

        report.Notes.Add("005/006 از جمع بدهکار/بستانکار حذف شده‌اند.")
        report.Notes.Add("INVOICE_GL_SKIP و CHECK_GL_SKIP نباید دوباره به‌صورت سند دستی منتقل شوند.")
        report.Notes.Add("جمع فاکتور در حسابیکس از API فاکتور می‌آید؛ سند Type13/14 همان فاکتور دوبل نیست.")
        Return report
    End Function

    Public Function SaveReport(report As BalanceProofReport, businessId As Integer, holooDatabase As String) As String
        Dim dir = IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Holoo2Hesabix", "proofs")
        IO.Directory.CreateDirectory(dir)
        Dim safeDb = If(holooDatabase, "db").Replace("\"c, "_"c).Replace("/"c, "_"c).Replace(":"c, "_"c)
        Dim filePath = IO.Path.Combine(dir, "proof_biz" & businessId.ToString() & "_" & safeDb & "_" & DateTime.Now.ToString("yyyyMMdd_HHmmss") & ".json")
        IO.File.WriteAllText(filePath, JsonConvert.SerializeObject(report, Formatting.Indented), Encoding.UTF8)

        Dim txt = IO.Path.ChangeExtension(filePath, ".txt")
        Dim sb As New StringBuilder()
        sb.AppendLine("Holoo balance proof — " & report.GeneratedAt)
        sb.AppendLine("DB=" & report.HolooDatabase & " BusinessId=" & report.BusinessId.ToString())
        sb.AppendLine("ManualWithoutFacture=" & report.ManualWithoutFacture.ToString())
        sb.AppendLine("FactureLinkedExcludedFromManual=" & report.FactureLinkedExcludedFromManual.ToString())
        sb.AppendLine()
        sb.AppendLine("Bucket`tDocs`tDebit`tCredit")
        For Each b In report.Buckets
            sb.AppendLine(b.Bucket & "`t" & b.DocumentCount.ToString() & "`t" & b.Debit.ToString("0.##") & "`t" & b.Credit.ToString("0.##"))
        Next
        For Each n In report.Notes
            sb.AppendLine("NOTE: " & n)
        Next
        IO.File.WriteAllText(txt, sb.ToString(), Encoding.UTF8)
        Return filePath
    End Function
End Class
