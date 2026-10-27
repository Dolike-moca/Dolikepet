// Windows cross-process passthrough without clipping or rebuilding the window.
// Godot's ordinary mouse_passthrough only forwards to its own process windows.
#include "../gd_cubism_user_model.hpp"
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace {
constexpr wchar_t TRANSPARENT_PROC[] = L"DolikePet.TransparentWindowProc";

LRESULT CALLBACK transparent_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto previous = reinterpret_cast<WNDPROC>(GetPropW(window, TRANSPARENT_PROC));
    // The OpenGL renderer supplies the entire alpha surface. GDI's opaque
    // background erase is otherwise briefly composited during live resizing.
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_WINDOWPOSCHANGING && lparam) {
        // Never copy old client pixels into a differently sized alpha surface.
        auto position = reinterpret_cast<WINDOWPOS *>(lparam);
        if (!(position->flags & SWP_NOSIZE)) position->flags |= SWP_NOCOPYBITS;
    }
    if (message == WM_NCDESTROY) RemovePropW(window, TRANSPARENT_PROC);
    return previous ? CallWindowProcW(previous, window, message, wparam, lparam)
                    : DefWindowProcW(window, message, wparam, lparam);
}

void preserve_transparent_resize(HWND window) {
    if (GetPropW(window, TRANSPARENT_PROC)) return;
    auto previous = reinterpret_cast<WNDPROC>(GetWindowLongPtrW(window, GWLP_WNDPROC));
    if (!previous || !SetPropW(window, TRANSPARENT_PROC, reinterpret_cast<HANDLE>(previous))) return;
    SetLastError(0);
    if (!SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(transparent_window_proc)) && GetLastError()) {
        RemovePropW(window, TRANSPARENT_PROC);
    }
}
}
#endif

bool GDCubismUserModel::desktop_primary_pressed() const {
#if defined(_WIN32)
    // Input's cached state can remain down if WM_LBUTTONUP went elsewhere.
    // GetAsyncKeyState reports physical buttons, so honor left-handed mapping.
    const int button = GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
    return (GetAsyncKeyState(button) & 0x8000) != 0;
#else
    return false;
#endif
}

bool GDCubismUserModel::restore_desktop_visibility(int64_t handle) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (!IsWindow(window) || owner != GetCurrentProcessId()) return false;
    // Godot's style rebuild can drop WS_VISIBLE on an unfocusable subwindow,
    // leaving its old DWM frame frozen while Window.visible is still true.
    // Only call for a logically visible widget after an actual flag change.
    // Restore that same HWND without activating it or recreating its surface.
    if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOWNA);
    return IsWindowVisible(window) != FALSE;
#else
    return false;
#endif
}

bool GDCubismUserModel::desktop_capture_matches(int64_t handle) const {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    return IsWindow(window) && owner == GetCurrentProcessId() && GetCapture() == window;
#else
    return false;
#endif
}

void GDCubismUserModel::release_desktop_capture(int64_t handle) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    // Release only the caller's window, never another widget or application.
    if (IsWindow(window) && owner == GetCurrentProcessId() && GetCapture() == window) {
        ReleaseCapture();
    }
#endif
}

bool GDCubismUserModel::set_desktop_passthrough(int64_t handle, bool enabled) {
#if defined(_WIN32)
    const HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (!IsWindow(window) || owner != GetCurrentProcessId()) return false;
    preserve_transparent_resize(window);
    const LONG_PTR old_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    LONG_PTR wanted = old_style | WS_EX_LAYERED;
    wanted = enabled ? (wanted | WS_EX_TRANSPARENT) : (wanted & ~WS_EX_TRANSPARENT);
    if (wanted != old_style) SetWindowLongPtrW(window, GWL_EXSTYLE, wanted);
    // Keep a constant layered style while hovering; do not call SetWindowPos,
    // change the native region, rebuild transparency or touch another process.
    if (!(old_style & WS_EX_LAYERED)) SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA);
    return true;
#else
    return false;
#endif
}
