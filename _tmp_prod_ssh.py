import paramiko

HOST = "194.60.230.200"
PORT = 9011
USER = "root"
PASSWORD = "@@hesabiX09183282405"

REMOTE = r"""
set -euo pipefail
eval "$(python3 - <<'PY'
from pathlib import Path
keys = ('DB_USER','DB_PASSWORD','DB_HOST','DB_PORT','DB_NAME')
vals = {}
for line in Path('/opt/hesabix/app/hesabixAPI/.env').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#') or '=' not in line: continue
    k,v=line.split('=',1)
    if k in keys:
        vals[k]=v.strip().strip('"').strip("'")
print('export DB_USER=%r' % vals['DB_USER'])
print('export DB_PASSWORD=%r' % vals['DB_PASSWORD'])
print('export DB_HOST=%r' % vals['DB_HOST'])
print('export DB_PORT=%r' % vals['DB_PORT'])
print('export DB_NAME=%r' % vals['DB_NAME'])
PY
)"
export PGPASSWORD="$DB_PASSWORD"
PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1"

echo '===== invoice header ====='
$PSQL -c "SELECT d.id, d.document_type, d.code, d.document_date, d.is_proforma,
  d.extra_info->>'post_inventory' AS post_inventory,
  d.extra_info->>'auto_post_warehouse' AS auto_post_wh,
  d.extra_info->'links' AS links
FROM documents d WHERE d.id = 216149 AND d.business_id = 2751;"

echo '===== invoice lines ====='
$PSQL -c "SELECT iil.id, iil.product_id, p.name, p.code AS product_code, p.track_inventory,
  iil.quantity,
  iil.extra_info->>'warehouse_id' AS warehouse_id,
  iil.extra_info->>'movement' AS movement,
  iil.extra_info->>'inventory_tracked' AS inventory_tracked
FROM invoice_item_lines iil
LEFT JOIN products p ON p.id = iil.product_id
WHERE iil.document_id = 216149
ORDER BY iil.id;"

echo '===== warehouse docs ====='
$PSQL -c "SELECT wd.id, wd.doc_type, wd.status, wd.document_date, wd.source_type, wd.source_document_id, wd.code
FROM warehouse_documents wd
WHERE wd.business_id = 2751 AND (wd.id = 145873 OR wd.source_document_id = 216149)
ORDER BY wd.id;"

echo '===== warehouse lines ====='
$PSQL -c "SELECT wdl.id, wdl.warehouse_document_id, wdl.product_id, p.name, wdl.quantity, wdl.movement, wdl.warehouse_id
FROM warehouse_document_lines wdl
JOIN warehouse_documents wd ON wd.id = wdl.warehouse_document_id
LEFT JOIN products p ON p.id = wdl.product_id
WHERE wd.business_id = 2751 AND (wd.id = 145873 OR wd.source_document_id = 216149)
ORDER BY wdl.warehouse_document_id, wdl.id;"

echo '===== current stock for shortage products ====='
$PSQL -c "
WITH pids AS (SELECT unnest(ARRAY[257213,703702]) AS product_id)
SELECT iil.product_id,
       iil.extra_info->>'warehouse_id' AS warehouse_id,
       d.document_type,
       d.id AS document_id,
       d.document_date,
       iil.extra_info->>'movement' AS movement,
       iil.quantity
FROM invoice_item_lines iil
JOIN documents d ON d.id = iil.document_id
WHERE d.business_id = 2751
  AND d.is_proforma = false
  AND iil.product_id IN (257213,703702)
  AND (iil.extra_info->>'warehouse_id') = '8061'
ORDER BY iil.product_id, d.document_date, d.id;
"
"""


def run(client: paramiko.SSHClient, cmd: str, timeout: int = 90) -> str:
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    code = stdout.channel.recv_exit_status()
    text = out if code == 0 else f"EXIT={code}\n{out}\nSTDERR:\n{err}"
    return text.encode("ascii", "replace").decode("ascii")


def main() -> None:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        port=PORT,
        username=USER,
        password=PASSWORD,
        timeout=25,
        allow_agent=False,
        look_for_keys=False,
    )
    print(run(client, REMOTE, timeout=90))
    client.close()


if __name__ == "__main__":
    main()
