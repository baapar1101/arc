#include "flutter_window.h"

#include <optional>
#include <string>

#include <flutter/encodable_value.h>
#include <shellapi.h>

#ifndef NIN_SELECT
#define NIN_SELECT (WM_USER + 0)
#endif
#ifndef NIN_KEYSELECT
#define NIN_KEYSELECT (WM_USER + 1)
#endif
#ifndef NIN_BALLOONUSERCLICK
#define NIN_BALLOONUSERCLICK (WM_USER + 5)
#endif

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayShowCommand = 40001;
constexpr UINT kTrayExitCommand = 40002;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (size <= 1) {
    return std::wstring();
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), size);
  return out;
}

const flutter::EncodableMap* AsMap(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  const auto* args = call.arguments();
  if (!args) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(args);
}

std::string MapString(const flutter::EncodableMap* args, const char* key) {
  if (!args) {
    return std::string();
  }
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return std::string();
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return std::string();
}

bool MapBool(const flutter::EncodableMap* args, const char* key, bool fallback) {
  if (!args) {
    return fallback;
  }
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return fallback;
}

void CopyToBuffer(wchar_t* dest, size_t dest_count, const std::wstring& src) {
  if (!dest || dest_count == 0) {
    return;
  }
  wcsncpy_s(dest, dest_count, src.c_str(), _TRUNCATE);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupCloseChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  close_channel_ = nullptr;

  Win32Window::OnDestroy();
}

void FlutterWindow::ApplyTrayLabels(const flutter::EncodableMap* args) {
  const std::string tooltip = MapString(args, "tooltip");
  const std::string show_label = MapString(args, "showLabel");
  const std::string exit_label = MapString(args, "exitLabel");
  if (!tooltip.empty()) {
    tray_tooltip_ = Utf16FromUtf8(tooltip);
  }
  if (!show_label.empty()) {
    tray_show_label_ = Utf16FromUtf8(show_label);
  }
  if (!exit_label.empty()) {
    tray_exit_label_ = Utf16FromUtf8(exit_label);
  }
}

void FlutterWindow::EnsureTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayIconMessage;
  nid.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  if (!nid.hIcon) {
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  CopyToBuffer(nid.szTip, ARRAYSIZE(nid.szTip), tray_tooltip_);

  if (tray_added_) {
    Shell_NotifyIconW(NIM_MODIFY, &nid);
  } else if (Shell_NotifyIconW(NIM_ADD, &nid)) {
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);
    tray_added_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  HWND hwnd = GetHandle();
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  EnsureTrayIcon();
  ShowWindow(hwnd, SW_HIDE);
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowIncomingBalloon(const std::wstring& title,
                                       const std::wstring& body) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  EnsureTrayIcon();

  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_INFO | NIF_TIP | NIF_ICON | NIF_MESSAGE;
  nid.uCallbackMessage = kTrayIconMessage;
  nid.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  if (!nid.hIcon) {
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  nid.dwInfoFlags = NIIF_INFO;
  CopyToBuffer(nid.szTip, ARRAYSIZE(nid.szTip), tray_tooltip_);
  CopyToBuffer(nid.szInfoTitle, ARRAYSIZE(nid.szInfoTitle), title);
  CopyToBuffer(nid.szInfo, ARRAYSIZE(nid.szInfo), body);
  Shell_NotifyIconW(NIM_MODIFY, &nid);

  FLASHWINFO flash = {};
  flash.cbSize = sizeof(flash);
  flash.hwnd = hwnd;
  flash.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
  flash.uCount = 8;
  flash.dwTimeout = 0;
  FlashWindowEx(&flash);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  POINT pt = {};
  GetCursorPos(&pt);
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayShowCommand, tray_show_label_.c_str());
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, tray_exit_label_.c_str());
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x,
                 pt.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
}

void FlutterWindow::NotifyDart(const char* method) {
  if (!close_channel_ || !method) {
    return;
  }
  close_channel_->InvokeMethod(method, nullptr);
}

void FlutterWindow::SetupCloseChannel() {
  close_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "hesabix/window_close",
          &flutter::StandardMethodCodec::GetInstance());

  close_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args = AsMap(call);
        if (call.method_name().compare("close") == 0) {
          RemoveTrayIcon();
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            DestroyWindow(hwnd);
          }
          result->Success();
          return;
        }
        if (call.method_name().compare("hideToTray") == 0) {
          ApplyTrayLabels(args);
          HideToTray();
          result->Success();
          return;
        }
        if (call.method_name().compare("showFromTray") == 0) {
          ShowFromTray();
          result->Success();
          return;
        }
        if (call.method_name().compare("setTray") == 0) {
          ApplyTrayLabels(args);
          if (MapBool(args, "visible", true)) {
            EnsureTrayIcon();
          } else {
            RemoveTrayIcon();
          }
          result->Success();
          return;
        }
        if (call.method_name().compare("showIncomingCall") == 0) {
          ApplyTrayLabels(args);
          const std::wstring title = Utf16FromUtf8(MapString(args, "title"));
          const std::wstring body = Utf16FromUtf8(MapString(args, "body"));
          ShowIncomingBalloon(title.empty() ? L"Incoming call" : title,
                              body.empty() ? L"Softphone" : body);
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (close_channel_) {
        close_channel_->InvokeMethod("requestClose", nullptr);
        return 0;
      }
      break;
    case WM_COMMAND:
      if (LOWORD(wparam) == kTrayShowCommand) {
        NotifyDart("trayShow");
        ShowFromTray();
        return 0;
      }
      if (LOWORD(wparam) == kTrayExitCommand) {
        NotifyDart("trayExit");
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    default:
      if (message == kTrayIconMessage) {
        const UINT event = LOWORD(lparam);
        if (event == WM_LBUTTONDBLCLK || event == NIN_SELECT ||
            event == NIN_KEYSELECT) {
          NotifyDart("trayShow");
          ShowFromTray();
          return 0;
        }
        if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
          ShowTrayMenu();
          return 0;
        }
        if (event == NIN_BALLOONUSERCLICK) {
          NotifyDart("incomingClicked");
          ShowFromTray();
          return 0;
        }
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
