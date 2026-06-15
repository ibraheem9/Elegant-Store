#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Returns true if the "allow multiple instances" flag file exists in Documents/AbdElhadiStoreApp
bool IsMultipleInstancesAllowed() {
  PWSTR path = nullptr;
  bool allowed = false;
  if (SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &path) == S_OK) {
    std::wstring flag_path = path;
    flag_path += L"\\AbdElhadiStoreApp\\allow_multiple_instances.txt";
    DWORD dwAttrib = GetFileAttributesW(flag_path.c_str());
    allowed = (dwAttrib != INVALID_FILE_ATTRIBUTES && !(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
    CoTaskMemFree(path);
  }
  return allowed;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ PWSTR command_line, _In_ int show_command) {
  // Single Instance Check
  HANDLE hMutex = CreateMutex(NULL, TRUE, L"Global\\AbdElhadi_SingleInstance_Mutex");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    if (!IsMultipleInstancesAllowed()) {
      // Find existing window and bring it to foreground
      HWND hwnd = FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Abd Elhadi");
      if (hwnd) {
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
      }
      if (hMutex) CloseHandle(hMutex);
      return 0;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a new console
  // when running with a debugger.
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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Abd Elhadi", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (hMutex) CloseHandle(hMutex);

  return EXIT_SUCCESS;
}
