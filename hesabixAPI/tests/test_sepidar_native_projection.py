"""Real PostgreSQL projection checks; only a disposable *_sepidar_test DB is allowed."""
import os
from copy import deepcopy
from decimal import Decimal

import pytest
from sqlalchemy import MetaData, create_engine, delete, func, select, ForeignKeyConstraint
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.db.models.currency import Currency, BusinessCurrency
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.sepidar_live_import import SepidarImportSetting, SepidarImportRow, SepidarImportRun, SepidarNativeMap
from app.services.sepidar_native_service import NativeConversionError, fingerprint, project_native, assert_document_editable
from app.services.sepidar_native_service import account_report_prefix
from app.services.balance_sheet_account_classification import balance_sheet_subsection
from app.services.pnl_account_classification import pnl_account_section
from app.core.responses import ApiError


@pytest.fixture
def native_db():
    dsn = os.getenv("SEPIDAR_TEST_DSN")
    if not dsn:
        pytest.skip("SEPIDAR_TEST_DSN is not set")
    assert make_url(dsn).database.endswith("_sepidar_test")
    engine = create_engine(dsn)
    metadata = MetaData()
    models = (User, Currency, Business, BusinessCurrency, Person, Product, Account, Document, DocumentLine,
              FiscalYear, InvoiceItemLine, Warehouse, SepidarImportSetting, SepidarImportRow, SepidarImportRun, SepidarNativeMap)
    for model in models:
        model.__table__.to_metadata(metadata)
    # Unrelated optional FKs (CRM, tax, banking, attachments) are not part of this fixture.
    for table in metadata.tables.values():
        for index, constraint in enumerate(list(table.constraints)):
            if isinstance(constraint, ForeignKeyConstraint) and any(f.target_fullname.split('.')[0] not in metadata.tables for f in constraint.elements):
                for foreign_key in constraint.elements:
                    table.foreign_keys.discard(foreign_key)
                    foreign_key.parent.foreign_keys.discard(foreign_key)
                table.constraints.remove(constraint)
            elif isinstance(constraint, ForeignKeyConstraint) and constraint.name is None:
                constraint.name=f"test_fk_{table.name[:24]}_{index}"
    metadata.create_all(engine)
    try:
        with Session(engine, expire_on_commit=False) as db:
            db.add(User(id=1, password_hash="test", referral_code="native-test", first_name="Test"))
            db.add(Currency(id=1,name="rial",title="ریال",symbol="ریال",code="IRR"))
            db.flush()
            db.add(Business(id=1,name="Sepidar test",owner_id=1,business_type=BusinessType.COMPANY,
                            business_field=BusinessField.OTHER,default_currency_id=1,default_phone_region="IR"))
            db.flush()
            db.add(SepidarImportSetting(business_id=1,host="source.invalid",database_name="Sepidar01",username="reader",password_encrypted="test",native_enabled=True))
            db.commit()
            yield db
    finally:
        metadata.drop_all(engine)
        engine.dispose()


def seed(db):
    payloads = {
        'FMK.FiscalYear':[{'FiscalYearId':4,'Title':'1405','StartDate':'2026-03-21','EndDate':'2027-03-20'}],
        'GNR.Currency':[{'CurrencyID':1,'Title':'ريال'}],
        'INV.Stock':[{'StockID':1,'Code':'1','Title':'انبار'}],
        'INV.Unit':[{'UnitID':1,'Title':'عدد'}],
        'ACC.DL':[{'DLId':7,'Code':'1001'}],
        'GNR.Party':[{'PartyId':3,'Name':'مشتری','LastName':'آزمایش','Type':1,'IsCustomer':True,'DLRef':7}],
        'INV.Item':[{'ItemID':5,'Code':'004','Title':'کالا','Type':1,'UnitRef':1,'DefaultStockRef':1,'IsActive':True}],
        'ACC.Account':[{'AccountId':1,'Code':'0','Title':'حسابها','Type':0},
                       {'AccountId':2,'Code':'11','Title':'حساب','Type':3,'ParentAccountRef':1}],
        'ACC.Voucher':[{'VoucherId':50,'Number':20,'FiscalYearRef':4,'Date':'2026-10-22','State':1}],
        'ACC.VoucherItem':[{'VoucherItemId':1,'VoucherRef':50,'AccountSLRef':2,'DLRef':7,'Debit':'100.00','Credit':0},
                           {'VoucherItemId':2,'VoucherRef':50,'AccountSLRef':2,'Debit':0,'Credit':'100.00'}],
        'SLS.Invoice':[{'InvoiceId':10,'Number':1,'FiscalYearRef':4,'Date':'2026-10-22','CurrencyRef':1,'CustomerPartyRef':3,
                        'Price':'100','NetPrice':'100','Discount':0,'Tax':0,'VoucherRef':50}],
        'SLS.InvoiceItem':[{'InvoiceItemID':1,'InvoiceRef':10,'ItemRef':5,'StockRef':1,'RowID':1,
                            'Quantity':'2','Fee':'50','Price':'100','NetPrice':'100','Discount':0,'Tax':0}],
    }
    for table, records in payloads.items():
        schema,name=table.split('.')
        for index,payload in enumerate(records):
            db.add(SepidarImportRow(business_id=1,source_schema=schema,source_table=name,source_key=str(index),payload=payload,content_hash=fingerprint(payload)))
    db.commit()


def edit(db, table, index, **updates):
    schema,name=table.split('.')
    row = db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema==schema,SepidarImportRow.source_table==name,SepidarImportRow.source_key==str(index))).one()
    row.payload={**row.payload,**updates}
    row.content_hash=fingerprint(row.payload)
    db.commit()


def count(db, model):
    return db.scalar(select(func.count()).select_from(model))


def test_native_entities_reuse_original_ledger_once_and_repeat_is_idempotent(native_db):
    db=native_db; seed(db)
    project_native(db,1)
    assert count(db,Person)==count(db,Product)==count(db,Document)==1
    assert count(db,DocumentLine)==2 and count(db,InvoiceItemLine)==1
    account=db.scalars(select(Account).where(Account.code.like('101.SPD.%'))).one()
    assert account.account_type=='accounting_document' and account.parent_id is None
    assert balance_sheet_subsection(account.code)=='current_assets'
    doc=db.scalars(select(Document)).one()
    assert doc.document_type=='invoice_sales' and doc.extra_info['totals']['net']==100
    assert doc.extra_info['person_id']==db.scalars(select(Person)).one().id
    ids={m.id:(m.target_table,m.target_id) for m in db.scalars(select(SepidarNativeMap))}
    summary=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in summary['entities'].values())
    assert ids=={m.id:(m.target_table,m.target_id) for m in db.scalars(select(SepidarNativeMap))}
    assert count(db,DocumentLine)==2 and count(db,InvoiceItemLine)==1


@pytest.mark.parametrize('group,child,side,expected',[
    ('11','10',1,'current_assets'),('12','11',2,'non_current_assets'),
    ('21','10',2,'current_liabilities'),('22','10',2,'non_current_liabilities'),
    ('31','13',2,'equity'),('41','10',2,'sales'),('51','10',1,'cogs'),
    ('61','10',1,'operating_expense'),('41','12',2,'other_income'),
    ('62','11',2,'non_operating_income'),('62','11',1,'non_operating_expense'),
])
def test_source_chart_is_classified_by_native_financial_reports(group,child,side,expected):
    prefix=account_report_prefix([{'Code':'0','Type':0},{'Code':group,'Type':1},
                                  {'Code':child,'Type':2,'BalanceType':side}])
    code=f'{prefix}.SPD.0.{group}.{child}'
    assert (balance_sheet_subsection(code) or pnl_account_section(code))==expected


def test_live_update_changes_same_targets_without_duplicate_postings(native_db):
    db=native_db; seed(db); project_native(db,1)
    doc_id=db.scalars(select(Document.id)).one()
    person_id=db.scalars(select(Person.id)).one()
    edit(db,'GNR.Party',0,Name='مشتری اصلاح‌شده')
    edit(db,'SLS.Invoice',0,Price='120',NetPrice='120')
    edit(db,'SLS.InvoiceItem',0,Fee='60',Price='120',NetPrice='120')
    edit(db,'ACC.VoucherItem',0,Debit='120')
    edit(db,'ACC.VoucherItem',1,Credit='120')
    project_native(db,1)
    assert db.get(Person,person_id).first_name=='مشتری اصلاح‌شده'
    assert db.get(Document,doc_id).extra_info['totals']['net']==120
    assert count(db,Document)==1 and count(db,DocumentLine)==2
    assert db.scalar(select(func.sum(DocumentLine.debit)))==Decimal('120')
    assert db.scalar(select(func.sum(DocumentLine.credit)))==Decimal('120')
    assert db.scalars(select(InvoiceItemLine)).one().extra_info['unit_price']==60


def test_failed_financial_validation_rolls_back_all_native_changes(native_db):
    db=native_db; seed(db); project_native(db,1)
    person=db.scalars(select(Person)).one()
    old_name=person.first_name
    edit(db,'GNR.Party',0,Name='must rollback')
    edit(db,'ACC.VoucherItem',0,Debit='110')
    with pytest.raises(NativeConversionError,match='not balanced'):
        project_native(db,1)
    assert db.get(Person,person.id).first_name==old_name
    assert db.scalar(select(func.sum(DocumentLine.debit)))==Decimal('100')


def test_missing_source_reference_does_not_create_partial_entities(native_db):
    db=native_db; seed(db)
    edit(db,'SLS.InvoiceItem',0,ItemRef=999)
    with pytest.raises(NativeConversionError,match='Unresolved source reference'):
        project_native(db,1)
    assert count(db,Person)==count(db,Product)==count(db,Document)==0
    assert count(db,SepidarNativeMap)==0


def test_source_managed_financial_documents_reject_local_mutations(native_db):
    db=native_db; seed(db); project_native(db,1)
    document=db.scalars(select(Document)).one()
    with pytest.raises(ApiError):
        assert_document_editable(document)
    from app.services.invoice_service import update_invoice, delete_invoice
    with pytest.raises(ApiError):
        update_invoice(db,document.id,1,{})
    with pytest.raises(ApiError):
        delete_invoice(db,document.id)


def test_raw_sync_pipeline_updates_native_entities_on_each_poll(native_db, monkeypatch):
    from app.services import sepidar_import_service as sync
    db=native_db; seed(db)
    snapshot={}
    for row in db.scalars(select(SepidarImportRow)):
        snapshot.setdefault(f'{row.source_schema}.{row.source_table}',[]).append(deepcopy(row.payload))
    db.execute(delete(SepidarImportRow)); db.commit()
    class Cursor:
        def execute(self, query):
            self.name=query.removeprefix('SELECT * FROM [').removesuffix(']').replace('].[','.')
            self.offset=0
        def fetchmany(self, count):
            rows=snapshot[self.name][self.offset:self.offset+count]
            self.offset+=count
            return rows
    class Connection:
        def __enter__(self): return self
        def __exit__(self,*args): pass
        def cursor(self,**kwargs): return Cursor()
    monkeypatch.setattr(sync,'discover',lambda row:[{'schema':key.split('.')[0],'table':key.split('.')[1],'rows':len(value)} for key,value in snapshot.items()])
    monkeypatch.setattr(sync,'_connect',lambda row:Connection())
    monkeypatch.setattr(sync,'_primary_keys',lambda *args:[])
    sync.run_sync(db,1)
    ids=list(db.scalars(select(Document.id)))
    snapshot['GNR.Party'][0]['Name']='updated by live source'
    sync.run_sync(db,1)
    assert db.scalars(select(Person)).one().first_name=='updated by live source'
    assert ids==list(db.scalars(select(Document.id)))
    assert count(db,DocumentLine)==2 and count(db,InvoiceItemLine)==1
    summary=db.scalars(select(SepidarImportSetting)).one().native_summary
    assert summary['entities']['GNR.Party']['updated']==1
