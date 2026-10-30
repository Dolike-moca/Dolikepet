// Current-user Windows DPAPI. Keys never enter a child process or command line.
#include "../gd_cubism_user_model.hpp"
#include <godot_cpp/variant/packed_byte_array.hpp>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wincrypt.h>
#endif

PackedByteArray GDCubismUserModel::encrypt_desktop_secret(const PackedByteArray &plain) const {
    PackedByteArray result;
#if defined(_WIN32)
    if (plain.is_empty() || plain.size() > 16384) return result;
    DATA_BLOB input{static_cast<DWORD>(plain.size()), const_cast<BYTE *>(plain.ptr())};
    DATA_BLOB output{};
    if (CryptProtectData(&input, L"DolikePet AI credential", nullptr, nullptr, nullptr,
                         CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        result.resize(output.cbData);
        memcpy(result.ptrw(), output.pbData, output.cbData);
        SecureZeroMemory(output.pbData, output.cbData);
        LocalFree(output.pbData);
    }
#endif
    return result;
}

PackedByteArray GDCubismUserModel::decrypt_desktop_secret(const PackedByteArray &encrypted) const {
    PackedByteArray result;
#if defined(_WIN32)
    if (encrypted.is_empty() || encrypted.size() > 65536) return result;
    DATA_BLOB input{static_cast<DWORD>(encrypted.size()), const_cast<BYTE *>(encrypted.ptr())};
    DATA_BLOB output{};
    if (CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                           CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        if (output.cbData > 0 && output.cbData <= 16384) {
            result.resize(output.cbData);
            memcpy(result.ptrw(), output.pbData, output.cbData);
        }
        SecureZeroMemory(output.pbData, output.cbData);
        LocalFree(output.pbData);
    }
#endif
    return result;
}
