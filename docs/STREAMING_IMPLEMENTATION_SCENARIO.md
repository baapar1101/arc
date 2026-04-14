# سناریوی پیاده‌سازی Streaming برای چت هوش مصنوعی

## وضعیت فعلی

### بکند (Backend)
- **Endpoint**: `/api/v1/ai/chat/sessions/{session_id}/messages` (POST)
- **متد**: `ai_service.chat_completion()` - یک response کامل برمی‌گرداند
- **Provider**: فقط متد `chat_completion()` دارد که یک response کامل برمی‌گرداند
- **ذخیره‌سازی**: بعد از دریافت کل پاسخ، پیام assistant ذخیره می‌شود

### فرانت (Frontend)
- **Service**: `AIService.sendMessage()` - یک POST request ساده
- **UI**: `AIChatDialog._sendMessage()` - منتظر می‌ماند تا کل پاسخ آماده شود

---

## سناریوی پیاده‌سازی

### هدف
- پیاده‌سازی streaming برای تجربه کاربری بهتر
- حفظ هر دو حالت streaming و non-streaming در بکند برای استفاده‌های آینده

---

## ۱. تغییرات در بکند - Provider Layer

### ۱.۱. اضافه کردن متد Streaming به Base Class

**فایل**: `hesabixAPI/app/services/ai/ai_provider.py`

- اضافه کردن متد abstract `chat_completion_stream()` به `AIProviderBase`
- این متد باید یک generator/yield کننده باشد که chunks را به صورت تدریجی برمی‌گرداند

**Signature پیشنهادی**:
```python
@abstractmethod
async def chat_completion_stream(
    self,
    messages: List[Dict[str, Any]],
    model: str,
    max_tokens: int,
    temperature: float,
    tools: Optional[List[Dict[str, Any]]] = None
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    ارسال درخواست chat completion به صورت streaming
    هر chunk شامل:
    - delta: محتوای جدید (content chunk)
    - usage: در chunk آخر
    - done: آیا streaming تمام شده است
    """
    pass
```

### ۱.۲. پیاده‌سازی در OpenAIProvider

**فایل**: `hesabixAPI/app/services/ai/ai_provider.py`

- استفاده از `stream=True` در `openai.ChatCompletion.create()`
- Iterate روی response chunks
- هر chunk را parse کرده و yield کردن
- در آخر، usage stats را yield کردن

**مثال ساختار chunk**:
```python
{
    "delta": {
        "content": "بخشی از پاسخ"
    },
    "usage": None,  # فقط در chunk آخر
    "done": False   # فقط در chunk آخر True
}
```

### ۱.۳. پیاده‌سازی در AnthropicProvider

- استفاده از streaming API Anthropic (اگر پشتیبانی می‌کند)
- یا fallback به non-streaming با توضیح در documentation

### ۱.۴. پیاده‌سازی در LocalProvider (Ollama)

- Ollama به صورت پیش‌فرض streaming را پشتیبانی می‌کند
- استفاده از `/api/chat` با `stream=True`
- Parse کردن Server-Sent Events (SSE) یا JSON stream

---

## ۲. تغییرات در بکند - Service Layer

### ۲.۱. اضافه کردن متد Streaming به AIService

**فایل**: `hesabixAPI/app/services/ai/ai_service.py`

**متد جدید**: `chat_completion_stream()`

**ویژگی‌ها**:
- مشابه `chat_completion()` اما با streaming
- همان validation ها
- همان system prompt
- همان function calling logic (اما باید بعد از streaming کامل شود)
- باید یک AsyncGenerator باشد

**نکات مهم**:
- Function calling: در streaming mode، ابتدا تمام chunks را جمع‌آوری کرده، سپس function calls را بررسی می‌کنیم
- اگر function call وجود داشت، باید یک round دوم اجرا شود (non-streaming)

**Signature**:
```python
async def chat_completion_stream(
    self,
    messages: List[Dict[str, Any]],
    tools: Optional[List[Dict[str, Any]]] = None,
    use_function_calling: bool = True,
    max_tokens_override: Optional[int] = None
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    ارسال درخواست به AI به صورت streaming
    """
```

**Flow**:
1. Validation (مثل `chat_completion`)
2. ایجاد provider
3. ساخت full_messages با system prompt
4. دریافت function definitions اگر نیاز بود
5. ارسال streaming request به provider
6. جمع‌آوری تمام chunks
7. بررسی function calls
8. اگر function call وجود داشت:
   - اجرای functions
   - ارسال مجدد (non-streaming) با نتایج
   - yield کردن کل پاسخ به صورت یک chunk
9. اگر function call نداشت:
   - yield کردن chunks به ترتیب

---

## ۳. تغییرات در بکند - API Layer

### ۳.۱. Endpoint جدید برای Streaming

**فایل**: `hesabixAPI/adapters/api/v1/ai/chat.py`

**دو رویکرد ممکن**:

#### رویکرد ۱: Query Parameter (پیشنهادی)
- استفاده از همان endpoint با query parameter `stream=true`
- اگر `stream=false` یا نبود، از endpoint فعلی استفاده شود

#### رویکرد ۲: Endpoint جداگانه
- ایجاد endpoint جدید: `/api/v1/ai/chat/sessions/{session_id}/messages/stream`

**پیشنهاد**: رویکرد ۱ (query parameter) برای سادگی

**پیاده‌سازی**:
```python
@router.post("/sessions/{session_id}/messages", summary="ارسال پیام به AI")
async def send_message(
    session_id: int = Path(...),
    request: Request = None,
    message_data: ChatMessageRequest = Body(...),
    stream: bool = Query(False, description="استفاده از streaming"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """ارسال پیام به AI - با یا بدون streaming"""
    
    # ... validation و آماده‌سازی messages ...
    
    if stream:
        return StreamingResponse(
            _stream_message(...),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
    else:
        # کد فعلی non-streaming
        ...
```

**متد helper برای streaming**:
```python
async def _stream_message(
    session_id: int,
    messages: List[Dict[str, Any]],
    ai_service: AIService,
    db: Session,
    # ... سایر پارامترها
):
    """Generator برای streaming response"""
    
    full_content = ""
    async for chunk in ai_service.chat_completion_stream(messages, ...):
        # Format کردن chunk برای SSE
        delta = chunk.get("delta", {})
        content_chunk = delta.get("content", "")
        full_content += content_chunk
        
        # ارسال chunk به client
        yield f"data: {json.dumps({'content': content_chunk, 'done': chunk.get('done', False)})}\n\n"
    
    # بعد از تمام شدن streaming:
    # 1. ذخیره پیام در دیتابیس
    # 2. بررسی سهمیه و شارژ
    # 3. ارسال chunk نهایی با usage stats
```

**نکات مهم**:
- استفاده از Server-Sent Events (SSE) format: `data: {json}\n\n`
- حفظ endpoint فعلی برای backward compatibility
- ذخیره‌سازی پیام باید بعد از کامل شدن streaming انجام شود
- بررسی سهمیه و شارژ در انتهای streaming

---

## ۴. تغییرات در فرانت - Service Layer

### ۴.۱. اضافه کردن متد Streaming به AIService

**فایل**: `hesabixUI/hesabix_ui/lib/services/ai_service.dart`

**متد جدید**: `sendMessageStream()`

**ویژگی‌ها**:
- استفاده از Dio streaming capabilities
- Parse کردن SSE format
- Return کردن Stream<String> که هر chunk محتوای جدید است

**پیاده‌سازی**:
```dart
Stream<String> sendMessageStream({
  required int sessionId,
  required String content,
  void Function(Map<String, dynamic> usage)? onComplete,
}) async* {
  final response = await _api.post<ResponseBody>(
    '/api/v1/ai/chat/sessions/$sessionId/messages?stream=true',
    data: {'content': content},
    options: Options(
      responseType: ResponseType.stream,
      headers: {'Accept': 'text/event-stream'},
    ),
  );
  
  // Parse SSE stream
  await for (final chunk in _parseSSEStream(response.data.stream)) {
    yield chunk;
  }
  
  // در صورت نیاز، onComplete callback را فراخوانی کن
}

Stream<String> _parseSSEStream(Stream<List<int>> stream) async* {
  // Parse Server-Sent Events
  // هر خط که با "data: " شروع می‌شود را parse کن
  // JSON را decode کن و content را extract کن
}
```

**نکته**: Dio در Flutter ممکن است نیاز به پکیج اضافی برای SSE parsing داشته باشد

---

## ۵. تغییرات در فرانت - UI Layer

### ۵.۱. تغییر AIChatDialog برای Streaming

**فایل**: `hesabixUI/hesabix_ui/lib/widgets/ai/ai_chat_dialog.dart`

**تغییرات اصلی**:

#### ۵.۱.۱. State Management
- اضافه کردن state برای tracking وضعیت streaming
- اضافه کردن متغیر برای نگهداری محتوای progressive

#### ۵.۱.۲. تغییر متد `_sendMessage()`
```dart
Future<void> _sendMessage() async {
  // ... آماده‌سازی پیام کاربر ...
  
  // ایجاد پیام assistant با محتوای خالی
  final assistantMessageIndex = _messages.length;
  final assistantMessage = AIChatMessage(
    sessionId: _currentSession!.id!,
    role: MessageRole.assistant,
    content: '',  // به تدریج پر می‌شود
    createdAt: DateTime.now(),
  );
  
  setState(() {
    _messages.add(assistantMessage);
    _sending = true;
  });
  _scrollToBottom();
  
  try {
    String accumulatedContent = '';
    await for (final chunk in _aiService.sendMessageStream(
      sessionId: _currentSession!.id!,
      content: content,
      onComplete: (usage) {
        // به‌روزرسانی usage stats
      },
    )) {
      accumulatedContent += chunk;
      
      // به‌روزرسانی UI به صورت real-time
      setState(() {
        _messages[assistantMessageIndex] = AIChatMessage(
          sessionId: _currentSession!.id!,
          role: MessageRole.assistant,
          content: accumulatedContent,
          createdAt: _messages[assistantMessageIndex].createdAt,
        );
      });
      _scrollToBottom();
    }
    
    setState(() {
      _sending = false;
    });
  } catch (e) {
    setState(() {
      _sending = false;
      // حذف پیام assistant در صورت خطا
      _messages.removeAt(assistantMessageIndex);
    });
    _showError('ارسال پیام ناموفق بود: $e');
  }
}
```

#### ۵.۱.۳. UI Improvements
- نمایش indicator برای streaming (مثل typing indicator)
- Smooth scrolling هنگام streaming
- امکان cancel کردن streaming (در صورت نیاز)

---

## ۶. نکات مهم و چالش‌ها

### ۶.۱. Function Calling در Streaming
**چالش**: Function calling معمولاً نیاز به کل پاسخ دارد

**راه‌حل**:
- در streaming mode، ابتدا تمام chunks را جمع‌آوری کن
- اگر function call در آخر تشخیص داده شد، یک round دوم (non-streaming) اجرا کن
- یا function calls را در همان streaming response بفرست (اگر provider پشتیبانی می‌کند)

### ۶.۲. ذخیره‌سازی پیام
**چالش**: باید بعد از کامل شدن streaming ذخیره شود

**راه‌حل**:
- در بکند، بعد از کامل شدن streaming، پیام را ذخیره کن
- Usage stats را در آخرین chunk بفرست
- در فرانت، بعد از تمام شدن stream، پیام را به‌روزرسانی کن

### ۶.۳. Error Handling
**چالش**: خطاها ممکن است در وسط streaming رخ دهند

**راه‌حل**:
- در بکند، خطا را به صورت یک chunk خاص بفرست: `{"error": "...", "done": true}`
- در فرانت، این chunk را detect کرده و خطا را نمایش بده
- Cleanup مناسب در صورت قطع شدن connection

### ۶.۴. Backward Compatibility
- Endpoint فعلی (non-streaming) باید حفظ شود
- فرانت باید قابلیت fallback به non-streaming داشته باشد در صورت خطا در streaming

### ۶.۵. Testing
- تست streaming با provider های مختلف
- تست در شرایط network ضعیف
- تست function calling در streaming mode
- تست error handling

---

## ۷. مراحل پیاده‌سازی (توصیه شده)

### فاز ۱: Backend - Provider Layer
1. اضافه کردن `chat_completion_stream()` به `AIProviderBase`
2. پیاده‌سازی در `OpenAIProvider`
3. پیاده‌سازی در `LocalProvider` (Ollama)
4. پیاده‌سازی در `AnthropicProvider` (یا skip کردن)

### فاز ۲: Backend - Service Layer
1. اضافه کردن `chat_completion_stream()` به `AIService`
2. پیاده‌سازی function calling logic برای streaming
3. تست با provider های مختلف

### فاز ۳: Backend - API Layer
1. اضافه کردن query parameter `stream` به endpoint
2. پیاده‌سازی `StreamingResponse`
3. پیاده‌سازی helper function برای SSE formatting
4. تست endpoint با curl یا Postman

### فاز ۴: Frontend - Service Layer
1. اضافه کردن `sendMessageStream()` به `AIService`
2. پیاده‌سازی SSE parser
3. تست با mock server

### فاز ۵: Frontend - UI Layer
1. تغییر `AIChatDialog` برای استفاده از streaming
2. بهبود UX (typing indicator, smooth scrolling)
3. اضافه کردن error handling
4. تست کامل

### فاز ۶: Integration & Testing
1. تست end-to-end
2. تست در شرایط مختلف (slow network, errors, function calling)
3. Performance testing
4. Documentation

---

## ۸. مثال فرمت SSE Response

```text
data: {"content":"سلام","done":false}

data: {"content":" کاربر","done":false}

data: {"content":" گرامی","done":false}

data: {"content":"!","done":false}

data: {"content":"","done":true,"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}

```

---

## ۹. منابع و مراجع

- OpenAI Streaming API: https://platform.openai.com/docs/api-reference/streaming
- Ollama Streaming: https://github.com/ollama/ollama/blob/main/docs/api.md#streaming
- FastAPI StreamingResponse: https://fastapi.tiangolo.com/advanced/custom-response/#streamingresponse
- Server-Sent Events: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
- Dio Stream Response: https://pub.dev/packages/dio

