#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  constexpr unsigned int kDefaultWidth = 1280;
  constexpr unsigned int kDefaultHeight = 800;
  RECT work_area{};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  HMONITOR monitor =
      ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale = dpi > 0 ? dpi / 96.0 : 1.0;
  int work_w = static_cast<int>((work_area.right - work_area.left) / scale);
  int work_h = static_cast<int>((work_area.bottom - work_area.top) / scale);
  unsigned int win_w =
      work_w > 0 && static_cast<int>(kDefaultWidth) > work_w
          ? static_cast<unsigned int>(work_w)
          : kDefaultWidth;
  unsigned int win_h =
      work_h > 0 && static_cast<int>(kDefaultHeight) > work_h
          ? static_cast<unsigned int>(work_h)
          : kDefaultHeight;
  unsigned int origin_x =
      work_w > static_cast<int>(win_w)
          ? static_cast<unsigned int>((work_w - static_cast<int>(win_w)) / 2)
          : 10;
  unsigned int origin_y =
      work_h > static_cast<int>(win_h)
          ? static_cast<unsigned int>((work_h - static_cast<int>(win_h)) / 2)
          : 10;
  Win32Window::Point origin(origin_x, origin_y);
  Win32Window::Size size(win_w, win_h);
  if (!window.Create(L"OpenRC", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
