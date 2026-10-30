// Passive companion UI: coarse activity only; never read input content or titles.
#include "../gd_cubism_user_model.hpp"
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shobjidl.h>
#include <cwchar>
#include <cmath>

namespace {
bool own_window(HWND window) {
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    return IsWindow(window) && owner == GetCurrentProcessId();
}

// Window properties disappear with their HWND, so a recycled handle can never
// inherit our restoration state. Only this bridge's added layered bit is owned.
constexpr wchar_t companion_opacity_property[] = L"Dolike.CompanionOpacity.v1";
constexpr wchar_t companion_opacity_proc_property[] = L"Dolike.CompanionOpacityProc.v1";

LRESULT CALLBACK companion_opacity_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto previous = reinterpret_cast<WNDPROC>(GetPropW(window, companion_opacity_proc_property));
    if (message == WM_NCDESTROY) {
        RemovePropW(window, companion_opacity_property);
        RemovePropW(window, companion_opacity_proc_property);
    }
    return previous ? CallWindowProcW(previous, window, message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
}

bool ensure_companion_opacity_cleanup(HWND window) {
    if (GetPropW(window, companion_opacity_proc_property)) return true;
    const auto previous = reinterpret_cast<WNDPROC>(GetWindowLongPtrW(window, GWLP_WNDPROC));
    if (!previous || !SetPropW(window, companion_opacity_proc_property, reinterpret_cast<HANDLE>(previous))) return false;
    SetLastError(0);
    if (!SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(companion_opacity_window_proc)) && GetLastError()) {
        RemovePropW(window, companion_opacity_proc_property);
        return false;
    }
    return true;
}

void release_companion_opacity_cleanup(HWND window) {
    const auto previous = reinterpret_cast<WNDPROC>(GetPropW(window, companion_opacity_proc_property));
    // A later subclass may still forward through us. Keep that chain intact and
    // let WM_NCDESTROY remove our property in that case; the data is a procedure
    // address in this DLL, never a GDCubismUserModel or other object pointer.
    if (!previous || GetWindowLongPtrW(window, GWLP_WNDPROC) != reinterpret_cast<LONG_PTR>(companion_opacity_window_proc)) return;
    SetLastError(0);
    if (SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(previous)) != 0 || GetLastError() == 0)
        RemovePropW(window, companion_opacity_proc_property);
}

bool own_chat_window(HWND window) {
    if (!own_window(window) || GetWindowThreadProcessId(window, nullptr) != GetCurrentThreadId()) return false;
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    // The pet and bowl use per-pixel transparency and must never enter this path.
    return (style & WS_CHILD) == 0 && (style & WS_CAPTION) == WS_CAPTION;
}

bool set_extended_style(HWND window, LONG_PTR style) {
    SetLastError(0);
    return SetWindowLongPtrW(window, GWL_EXSTYLE, style) != 0 || GetLastError() == 0;
}

bool restore_companion_opacity(HWND window) {
    if (!GetPropW(window, companion_opacity_property)) {
        release_companion_opacity_cleanup(window);
        return true;
    }
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & WS_EX_LAYERED) && !set_extended_style(window, style & ~WS_EX_LAYERED)) return false;
    RemovePropW(window, companion_opacity_property);
    release_companion_opacity_cleanup(window);
    // Resume the normal OpenGL/DWM path, including the non-client title bar.
    // RedrawWindow never shows, moves, activates, or reorders the window.
    RedrawWindow(window, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN);
    return true;
}

void remove_taskbar_entry(HWND window) {
    // Remove Explorer's cached button synchronously, including the first show.
    // The helper repeats this after later shell restarts without touching focus.
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(initialized) || initialized == RPC_E_CHANGED_MODE) {
        ITaskbarList *taskbar = nullptr;
        if (SUCCEEDED(CoCreateInstance(__uuidof(TaskbarList), nullptr, CLSCTX_INPROC_SERVER,
                __uuidof(ITaskbarList), reinterpret_cast<void **>(&taskbar)))) {
            if (SUCCEEDED(taskbar->HrInit())) taskbar->DeleteTab(window);
            taskbar->Release();
        }
    }
    if (SUCCEEDED(initialized)) CoUninitialize();
}

bool input_desktop_available() {
    const HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    if (!desktop) return false;
    wchar_t name[256]{};
    DWORD needed = 0;
    const bool available = GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), &needed)
        && _wcsicmp(name, L"Default") == 0;
    CloseDesktop(desktop);
    return available;
}

bool external_fullscreen() {
    const HWND window = GetForegroundWindow();
    if (!window || own_window(window) || IsIconic(window)
        || window == GetShellWindow() || window == GetDesktopWindow()) return false;
    wchar_t class_name[64]{};
    GetClassNameW(window, class_name, 64);
    if (wcscmp(class_name, L"Progman") == 0 || wcscmp(class_name, L"WorkerW") == 0) return false;
    RECT bounds{};
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetWindowRect(window, &bounds)
        || !GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) return true;
    // A normal maximized window does not cover the taskbar. No client content is read.
    const RECT &screen = monitor.rcMonitor;
    return bounds.left <= screen.left + 2 && bounds.top <= screen.top + 2
        && bounds.right >= screen.right - 2 && bounds.bottom >= screen.bottom - 2;
}
}
#endif

Dictionary GDCubismUserModel::companion_activity_snapshot() const {
    Dictionary result;
    result["available"] = false;
    result["idle_seconds"] = 86400.0;
    result["locked"] = true;
    result["fullscreen"] = true;
#if defined(_WIN32)
    LASTINPUTINFO input{};
    input.cbSize = sizeof(input);
    if (!GetLastInputInfo(&input)) return result;
    // Unsigned DWORD subtraction deliberately handles the tick-counter wrap.
    result["idle_seconds"] = static_cast<double>(GetTickCount() - input.dwTime) / 1000.0;
    const bool unlocked = input_desktop_available();
    result["locked"] = !unlocked;
    result["fullscreen"] = !unlocked || external_fullscreen();
    result["available"] = true;
#endif
    return result;
}

bool GDCubismUserModel::show_companion_without_activation(int64_t handle) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    if (!own_window(window)) return false;
    // The caller shows its Godot window with FLAG_NO_FOCUS first. Keep it a
    // tool window, then restore visibility after any Godot style rebuild.
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    SetLastError(0);
    if (!SetWindowLongPtrW(window, GWL_EXSTYLE, (style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW)
        && GetLastError()) return false;
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
        SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    ShowWindow(window, SW_SHOWNA);
    return IsWindowVisible(window) != FALSE;
#else
    return false;
#endif
}

bool GDCubismUserModel::exclude_desktop_window_from_taskbar(int64_t handle, bool desktop_widget) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    if (!own_window(window)) return false;
    const LONG_PTR before = GetWindowLongPtrW(window, GWL_EXSTYLE);
    const LONG_PTR wanted = (before | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR wanted_style = desktop_widget ? style & ~(WS_MINIMIZEBOX | WS_MAXIMIZEBOX) : style;
    if (before != wanted) {
        SetLastError(0);
        if (!SetWindowLongPtrW(window, GWL_EXSTYLE, wanted) && GetLastError()) return false;
    }
    if (style != wanted_style) {
        SetLastError(0);
        if (!SetWindowLongPtrW(window, GWL_STYLE, wanted_style) && GetLastError()) return false;
    }
    if (before != wanted || style != wanted_style)
        SetWindowPos(window, nullptr, 0, 0, 0, 0,
            SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    // No ShowWindow: closed dialogs stay closed and keyboard focus stays put.
    remove_taskbar_entry(window);
    return true;
#else
    return false;
#endif
}

bool GDCubismUserModel::desktop_window_is_taskbar_hidden(int64_t handle) const {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    if (!own_window(window)) return false;
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    return (style & WS_EX_TOOLWINDOW) != 0 && (style & WS_EX_APPWINDOW) == 0;
#else
    return false;
#endif
}

bool GDCubismUserModel::set_companion_window_opacity(int64_t handle, double opacity) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    if (!std::isfinite(opacity) || !own_chat_window(window)) return false;
    const LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    const bool managed = GetPropW(window, companion_opacity_property) != nullptr;
    // Never overwrite an existing transparency implementation (UpdateLayeredWindow
    // and SetLayeredWindowAttributes cannot safely share an active layered HWND).
    if (!managed && (style & WS_EX_LAYERED)) return false;
    if (opacity >= 1.0) return restore_companion_opacity(window);
    if (style & WS_EX_NOREDIRECTIONBITMAP) return false;
    if (!ensure_companion_opacity_cleanup(window)) return false;
    if (!managed && !SetPropW(window, companion_opacity_property, reinterpret_cast<HANDLE>(1))) {
        release_companion_opacity_cleanup(window);
        return false;
    }
    if (!(style & WS_EX_LAYERED) && !set_extended_style(window, style | WS_EX_LAYERED)) {
        if (!managed) {
            RemovePropW(window, companion_opacity_property);
            release_companion_opacity_cleanup(window);
        }
        return false;
    }
    // Modern DWM composes our Godot/WGL window and its native caption together.
    // Do not alter CS_OWNDC: Godot shares that class with the pet and bowl.
    const BYTE alpha = static_cast<BYTE>(std::lround((opacity < 0.0 ? 0.0 : opacity) * 255.0));
    if (SetLayeredWindowAttributes(window, 0, alpha, LWA_ALPHA)) return true;
    restore_companion_opacity(window);
    return false;
#else
    return false;
#endif
}

double GDCubismUserModel::get_companion_window_opacity(int64_t handle) const {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    if (!own_chat_window(window)) return -1.0;
    if (!(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_LAYERED)) return 1.0;
    if (!GetPropW(window, companion_opacity_property)) return -1.0;
    BYTE alpha = 255;
    DWORD flags = 0;
    if (!GetLayeredWindowAttributes(window, nullptr, &alpha, &flags) || !(flags & LWA_ALPHA)) return -1.0;
    return static_cast<double>(alpha) / 255.0;
#else
    return -1.0;
#endif
}

int64_t GDCubismUserModel::companion_foreground_handle() const {
#if defined(_WIN32)
    // Used for the no-focus regression; this opaque handle reveals no content.
    return static_cast<int64_t>(reinterpret_cast<intptr_t>(GetForegroundWindow()));
#else
    return 0;
#endif
}
