#include "flutter_window.h"

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include "resource.h"

namespace {
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayMenuShow = 1001;
constexpr UINT kTrayMenuExit = 1002;

BOOL CALLBACK HideChildWindow(HWND child, LPARAM) {
  ShowWindow(child, SW_HIDE);
  return TRUE;
}

BOOL CALLBACK ShowChildWindow(HWND child, LPARAM) {
  ShowWindow(child, SW_SHOW);
  return TRUE;
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
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "maple_task_reminder/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HWND hwnd = GetHandle();
        if (call.method_name() == "hideMainWindow") {
          HideMainWindow(hwnd);
          result->Success();
          return;
        }
        if (call.method_name() == "restoreMainWindow") {
          RestoreMainWindow(hwnd);
          result->Success();
          return;
        }
        if (call.method_name() == "exitApplication") {
          result->Success();
          RemoveNativeTrayIcon();
          DestroyWindow(hwnd);
          PostQuitMessage(0);
          return;
        }
        result->NotImplemented();
      });
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();
  AddNativeTrayIcon(GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  RemoveNativeTrayIcon();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE) {
    HideMainWindow(hwnd);
    return 0;
  }

  if (message == kTrayIconMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
        RestoreMainWindow(hwnd);
        return 0;
      case WM_RBUTTONUP:
        ShowNativeTrayMenu(hwnd);
        return 0;
    }
  }

  if (message == WM_COMMAND) {
    switch (LOWORD(wparam)) {
      case kTrayMenuShow:
        RestoreMainWindow(hwnd);
        return 0;
      case kTrayMenuExit:
        RemoveNativeTrayIcon();
        DestroyWindow(hwnd);
        PostQuitMessage(0);
        return 0;
    }
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddNativeTrayIcon(HWND hwnd) {
  if (tray_icon_added_ || hwnd == nullptr) {
    return;
  }

  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = hwnd;
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"\uBA54\uC774\uD50C \uC219\uC81C\uC54C\uB9AC\uBBF8");
  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &tray_icon_data_) == TRUE;
}

void FlutterWindow::RemoveNativeTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }

  Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowNativeTrayMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    RestoreMainWindow(hwnd);
    return;
  }

  AppendMenu(menu, MF_STRING, kTrayMenuShow, L"\uC5F4\uAE30");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayMenuExit, L"\uC885\uB8CC");

  POINT cursor_position;
  GetCursorPos(&cursor_position);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, cursor_position.x, cursor_position.y, 0,
                 hwnd, nullptr);
  DestroyMenu(menu);
}

void FlutterWindow::HideMainWindow(HWND hwnd) {
  if (hwnd == nullptr || !IsWindow(hwnd) ||
      main_window_state_ == MainWindowState::kHiddenToTray) {
    return;
  }

  HWND flutter_view_window = nullptr;
  if (flutter_controller_ && flutter_controller_->view()) {
    flutter_view_window = flutter_controller_->view()->GetNativeWindow();
  }

  HWND capture = GetCapture();
  if (capture == hwnd ||
      (flutter_view_window != nullptr && capture == flutter_view_window) ||
      (capture != nullptr && IsChild(hwnd, capture))) {
    ReleaseCapture();
  }

  if (flutter_view_window != nullptr && IsWindow(flutter_view_window)) {
    ShowWindow(flutter_view_window, SW_HIDE);
  }
  EnumChildWindows(hwnd, HideChildWindow, 0);
  ShowWindow(hwnd, SW_HIDE);
  main_window_state_ = MainWindowState::kHiddenToTray;
}

void FlutterWindow::RestoreMainWindow(HWND hwnd) {
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    return;
  }

  HWND flutter_view_window = nullptr;
  if (flutter_controller_ && flutter_controller_->view()) {
    flutter_view_window = flutter_controller_->view()->GetNativeWindow();
  }

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }

  if (flutter_view_window != nullptr && IsWindow(flutter_view_window)) {
    ShowWindow(flutter_view_window, SW_SHOW);
  }
  EnumChildWindows(hwnd, ShowChildWindow, 0);

  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetActiveWindow(hwnd);
  SetForegroundWindow(hwnd);
  if (flutter_view_window != nullptr && IsWindow(flutter_view_window)) {
    SetFocus(flutter_view_window);
  }
  main_window_state_ = MainWindowState::kVisible;
}
