import json
from unittest.mock import patch
import httpx
import pytest
from app.services.providers.payamresan_sms_provider import PayamResanSmsProvider
from app.services.providers.sms_provider import SmsProvider
from tests.test_sepidar_native_projection import native_db


def test_send_request_shape_and_success_id():
    seen=[]
    def handler(request):
        seen.append(json.loads(request.content));return httpx.Response(200,json={'success':True,'result':[{'messageId':12345}]})
    provider=PayamResanSmsProvider('test-not-real-key','99990000',transport=httpx.MockTransport(handler))
    assert provider.send_text('+989121234567','سلام')==(True,'12345',None)
    assert seen[0]['Sender']==99990000 and seen[0]['Recipients'][0]['Destination']==9121234567
    assert seen[0]['Text']=='سلام' and seen[0]['Recipients'][0]['UserTraceId']


@pytest.mark.parametrize('body',[{'success':False,'errorCode':1,'error':'DO_NOT_LEAK_SECRET'}, {'Success':False,'ErrorCode':2},[],{'success':'true'},{'success':True,'result':[{'success':False}]}])
def test_fail_closed_and_do_not_echo_vendor_secrets(body):
    provider=PayamResanSmsProvider('test-key','9999',transport=httpx.MockTransport(lambda r:httpx.Response(200,json=body)))
    ok,mid,error=provider.send_text('09121234567','test')
    assert not ok and mid is None and 'DO_NOT_LEAK_SECRET' not in error


def test_timeout_does_not_retry_or_expose_content():
    requests=[]
    def handler(request):requests.append(request);raise httpx.ReadTimeout('secret text test-key',request=request)
    provider=PayamResanSmsProvider('test-key','9999',transport=httpx.MockTransport(handler))
    result=provider.send_text('09121234567','private')
    assert not result[0] and len(requests)==1 and 'test-key' not in result[2] and 'نامشخص' in result[2]


def test_invalid_input_does_not_make_request():
    provider=PayamResanSmsProvider('test-key','9999',transport=httpx.MockTransport(lambda r:pytest.fail('Unexpected send')))
    assert not provider.send_text('bad','test')[0]
    assert not provider.send_text('09121234567',' ')[0]


def test_shared_sms_router_uses_provider_without_password():
    provider=SmsProvider(provider_name='payamresan',api_key='test-key',sender='9999')
    assert provider.is_configured() and isinstance(provider._provider,PayamResanSmsProvider)
    provider._provider.transport=httpx.MockTransport(lambda r:httpx.Response(200,json={'success':True,'result':123}))
    with patch('app.services.sms_destination_rate_limit.check_and_record_destination_sms',return_value=None):
        assert provider.send_text_with_details(to_phone='09121234567',text='test')==(True,'123',None)


def test_encrypted_configuration_masked_and_existing_provider_preserved(native_db):
    from app.services.system_settings_service import set_notifications_settings,get_effective_notifications_settings
    from adapters.db.models.system_setting import SystemSetting
    from sqlalchemy import select
    from adapters.api.v1.admin.system_settings import _mask_notifications_secrets,_unwrap_notifications_payload,NotificationsConfigPayload
    db=native_db
    cfg=set_notifications_settings(db,sms_provider_name='sunwaysms',sms_sender='3000',sms_api_key='old-key',
        sms_payamresan_api_key='new-test-key-never-real',sms_payamresan_sender='9999000')
    stored=db.scalars(select(SystemSetting).where(SystemSetting.key=='sms_payamresan_api_key')).one()
    assert stored.value_string is None and 'new-test-key' not in stored.value_json
    assert get_effective_notifications_settings(db)['sms_provider_name']=='sunwaysms'
    assert get_effective_notifications_settings(db)['sms_api_key']=='old-key'
    masked=_mask_notifications_secrets(cfg)
    assert masked['sms_payamresan_api_key_configured'] and 'new-test-key' not in str(masked)
    payload=NotificationsConfigPayload(sms_payamresan_api_key=masked['sms_payamresan_api_key'])
    assert _unwrap_notifications_payload(payload)['sms_payamresan_api_key'] is None
    set_notifications_settings(db,sms_provider_name='payamresan')
    effective=get_effective_notifications_settings(db)
    assert effective['sms_api_key']=='new-test-key-never-real' and effective['sms_sender']=='9999000'
