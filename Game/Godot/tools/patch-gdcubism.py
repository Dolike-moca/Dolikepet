"""Project-local compatibility patch for gd_cubism v0.9.1 + Native 5-r.5.

The existing pet uses the legacy normal/add/multiply renderer. Extended 5.3
blend/offscreen models are explicitly rejected rather than rendered incorrectly.
Also expose current CPU vertices, avoiding GPU readback during hair deformation.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def edit(relative, before, after):
    path = root / relative
    source = path.read_text(encoding="utf-8")
    if after in source:
        return
    if before in source:
        path.write_text(source.replace(before, after), encoding="utf-8")
    else:
        raise RuntimeError(f"Unexpected upstream source: {relative}: {before[:70]}")


edit("SConstruct", 'CHECK_PATH = "thirdparty/CubismNativeFramework"',
     'CHECK_PATH = "thirdparty/CubismNativeFramework-custom"')
edit("src/private/internal_cubism_renderer.cpp", "CubismRenderer::Create()",
     "CubismRenderer::Create(csmUint32 width, csmUint32 height)")
edit("src/private/internal_cubism_renderer.cpp", "InternalCubismRenderer2D()",
     "InternalCubismRenderer2D(width, height)")
edit("src/private/internal_cubism_renderer_2d.hpp", "    InternalCubismRenderer2D();",
     "    InternalCubismRenderer2D(Csm::csmUint32 width, Csm::csmUint32 height);")
edit("src/private/internal_cubism_renderer_2d.hpp", "    void DoDrawModel();",
     "    void BeforeDrawModelRenderTarget() override {}\n"
     "    void AfterDrawModelRenderTarget() override {}\n    void DoDrawModel();")
edit("src/private/internal_cubism_renderer_2d.cpp",
     "InternalCubismRenderer2D::InternalCubismRenderer2D()\n",
     "InternalCubismRenderer2D::InternalCubismRenderer2D(Csm::csmUint32 width, Csm::csmUint32 height)\n"
     "    : CubismRenderer(width, height)\n")
edit("src/private/internal_cubism_renderer_2d.cpp", "GetDrawableRenderOrders()", "GetRenderOrders()")
edit("src/private/internal_cubism_renderer_resource.cpp", "GetDrawableBlendMode(index)",
     "GetDrawableBlendModeType(index).GetColorBlendType()")
edit("src/private/internal_cubism_user_model.cpp", "    this->CreateRenderer();",
     '    if (this->_model->IsBlendModeEnabled()) {\n'
     '        ERR_PRINT("This Godot pet renderer supports normal/add/multiply models, not Cubism 5.3 extended blend/offscreen models.");\n'
     '        return false;\n'
     '    }\n'
     '    const Vector2 render_size = this->_owner_viewport->get_viewport_rect().size;\n'
     '    this->CreateRenderer(static_cast<Csm::csmUint32>(render_size.x), static_cast<Csm::csmUint32>(render_size.y));')
edit("src/private/internal_cubism_user_model.cpp",
     "this->_expressionManager->StartMotionPriority(\n"
     "            motion,\n            false,\n"
     "            GDCubismUserModel::Priority::PRIORITY_FORCE\n        );",
     "this->_expressionManager->StartMotion(motion, false);")
edit("src/private/internal_cubism_user_model.cpp", "motion->IsLoop(loop)", "motion->SetLoop(loop)")
edit("src/private/internal_cubism_user_model.cpp", "motion->IsLoopFadeIn(loop_fade_in)",
     "motion->SetLoopFadeIn(loop_fade_in)")
edit("src/gd_cubism_user_model.hpp", "Dictionary get_meshes() const;",
     "Dictionary get_meshes() const;\n    Dictionary get_raw_mesh_vertices() const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("get_meshes"), &GDCubismUserModel::get_meshes);',
     'ClassDB::bind_method(D_METHOD("get_meshes"), &GDCubismUserModel::get_meshes);\n'
     '    ClassDB::bind_method(D_METHOD("get_raw_mesh_vertices"), &GDCubismUserModel::get_raw_mesh_vertices);')
edit("src/gd_cubism_user_model.cpp",
     "void GDCubismUserModel::on_motion_finished(",
     """Dictionary GDCubismUserModel::get_raw_mesh_vertices() const {
    ERR_FAIL_COND_V(this->is_initialized() == false, Dictionary());
    Dictionary result;
    const auto* model = this->internal_model->GetModel();
    const Dictionary info = this->get_canvas_info();
    const float ppu = info["pixels_per_unit"];
    for (int index = 0; index < model->GetDrawableCount(); ++index) {
        const int count = model->GetDrawableVertexCount(index);
        const auto* vertices = model->GetDrawableVertexPositions(index);
        PackedVector2Array points;
        points.resize(count);
        for (int i = 0; i < count; ++i) {
            points.set(i, Vector2(vertices[i].X * ppu, -vertices[i].Y * ppu));
        }
        const String id(model->GetDrawableId(index)->GetString().GetRawString());
        result[id] = points;
    }
    return result;
}

void GDCubismUserModel::on_motion_finished(""")
edit("src/gd_cubism_user_model.hpp", "Dictionary get_raw_mesh_vertices() const;",
     "Dictionary get_raw_mesh_vertices() const;\n    bool set_desktop_passthrough(int64_t handle, bool enabled);")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("get_raw_mesh_vertices"), &GDCubismUserModel::get_raw_mesh_vertices);',
     'ClassDB::bind_method(D_METHOD("get_raw_mesh_vertices"), &GDCubismUserModel::get_raw_mesh_vertices);\n'
     '    ClassDB::bind_method(D_METHOD("set_desktop_passthrough", "handle", "enabled"), &GDCubismUserModel::set_desktop_passthrough);')
if 'env.Append(LIBS=["user32"])' in (root / "SConstruct").read_text(encoding="utf-8"):
    edit("SConstruct", 'env.Append(LIBS=["user32"])',
         'env.Append(LIBS=["user32", "crypt32", "ole32"])')
if 'env.Append(LIBS=["user32", "crypt32"])' in (root / "SConstruct").read_text(encoding="utf-8"):
    edit("SConstruct", 'env.Append(LIBS=["user32", "crypt32"])',
         'env.Append(LIBS=["user32", "crypt32", "ole32"])')
edit("SConstruct", 'sources = glob("src/*.cpp")',
     'if env["platform"] == "windows":\n    env.Append(LIBS=["user32", "crypt32", "ole32"])\n\nsources = glob("src/*.cpp")')
bridge = Path(__file__).resolve().parents[1] / "native/pet_pointer_bridge.cpp"
edit("src/gd_cubism_user_model.hpp", "bool set_desktop_passthrough(int64_t handle, bool enabled);",
     "bool set_desktop_passthrough(int64_t handle, bool enabled);\n"
     "    bool desktop_primary_pressed() const;\n    void release_desktop_capture(int64_t handle);")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("set_desktop_passthrough", "handle", "enabled"), &GDCubismUserModel::set_desktop_passthrough);',
     'ClassDB::bind_method(D_METHOD("set_desktop_passthrough", "handle", "enabled"), &GDCubismUserModel::set_desktop_passthrough);\n'
     '    ClassDB::bind_method(D_METHOD("desktop_primary_pressed"), &GDCubismUserModel::desktop_primary_pressed);\n'
     '    ClassDB::bind_method(D_METHOD("release_desktop_capture", "handle"), &GDCubismUserModel::release_desktop_capture);')
edit("src/gd_cubism_user_model.hpp", "void release_desktop_capture(int64_t handle);",
     "void release_desktop_capture(int64_t handle);\n    bool desktop_capture_matches(int64_t handle) const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("release_desktop_capture", "handle"), &GDCubismUserModel::release_desktop_capture);',
     'ClassDB::bind_method(D_METHOD("release_desktop_capture", "handle"), &GDCubismUserModel::release_desktop_capture);\n'
     '    ClassDB::bind_method(D_METHOD("desktop_capture_matches", "handle"), &GDCubismUserModel::desktop_capture_matches);')
edit("src/gd_cubism_user_model.hpp", "bool desktop_capture_matches(int64_t handle) const;",
     "bool desktop_capture_matches(int64_t handle) const;\n    bool restore_desktop_visibility(int64_t handle);")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("desktop_capture_matches", "handle"), &GDCubismUserModel::desktop_capture_matches);',
     'ClassDB::bind_method(D_METHOD("desktop_capture_matches", "handle"), &GDCubismUserModel::desktop_capture_matches);\n'
     '    ClassDB::bind_method(D_METHOD("restore_desktop_visibility", "handle"), &GDCubismUserModel::restore_desktop_visibility);')
(root / "src/private/pet_pointer_bridge.cpp").write_bytes(bridge.read_bytes())
edit("src/gd_cubism_user_model.hpp", "#include <godot_cpp/classes/node2d.hpp>",
     "#include <godot_cpp/classes/node2d.hpp>\n#include <godot_cpp/variant/packed_byte_array.hpp>")
edit("src/gd_cubism_user_model.hpp", "bool restore_desktop_visibility(int64_t handle);",
     "bool restore_desktop_visibility(int64_t handle);\n"
     "    PackedByteArray encrypt_desktop_secret(const PackedByteArray &plain) const;\n"
     "    PackedByteArray decrypt_desktop_secret(const PackedByteArray &encrypted) const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("restore_desktop_visibility", "handle"), &GDCubismUserModel::restore_desktop_visibility);',
     'ClassDB::bind_method(D_METHOD("restore_desktop_visibility", "handle"), &GDCubismUserModel::restore_desktop_visibility);\n'
     '    ClassDB::bind_method(D_METHOD("encrypt_desktop_secret", "plain"), &GDCubismUserModel::encrypt_desktop_secret);\n'
     '    ClassDB::bind_method(D_METHOD("decrypt_desktop_secret", "encrypted"), &GDCubismUserModel::decrypt_desktop_secret);')
secrets = Path(__file__).resolve().parents[1] / "native/pet_ai_secrets.cpp"
(root / "src/private/pet_ai_secrets.cpp").write_bytes(secrets.read_bytes())
edit("src/gd_cubism_user_model.hpp", "PackedByteArray decrypt_desktop_secret(const PackedByteArray &encrypted) const;",
     "PackedByteArray decrypt_desktop_secret(const PackedByteArray &encrypted) const;\n"
     "    Dictionary companion_activity_snapshot() const;\n"
     "    bool show_companion_without_activation(int64_t handle);\n"
     "    int64_t companion_foreground_handle() const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("decrypt_desktop_secret", "encrypted"), &GDCubismUserModel::decrypt_desktop_secret);',
     'ClassDB::bind_method(D_METHOD("decrypt_desktop_secret", "encrypted"), &GDCubismUserModel::decrypt_desktop_secret);\n'
     '    ClassDB::bind_method(D_METHOD("companion_activity_snapshot"), &GDCubismUserModel::companion_activity_snapshot);\n'
     '    ClassDB::bind_method(D_METHOD("show_companion_without_activation", "handle"), &GDCubismUserModel::show_companion_without_activation);\n'
     '    ClassDB::bind_method(D_METHOD("companion_foreground_handle"), &GDCubismUserModel::companion_foreground_handle);')
companion = Path(__file__).resolve().parents[1] / "native/pet_companion_desktop.cpp"
edit("src/gd_cubism_user_model.hpp", "int64_t companion_foreground_handle() const;",
     "int64_t companion_foreground_handle() const;\n"
     "    bool exclude_desktop_window_from_taskbar(int64_t handle, bool desktop_widget);\n"
     "    bool desktop_window_is_taskbar_hidden(int64_t handle) const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("companion_foreground_handle"), &GDCubismUserModel::companion_foreground_handle);',
     'ClassDB::bind_method(D_METHOD("companion_foreground_handle"), &GDCubismUserModel::companion_foreground_handle);\n'
     '    ClassDB::bind_method(D_METHOD("exclude_desktop_window_from_taskbar", "handle", "desktop_widget"), &GDCubismUserModel::exclude_desktop_window_from_taskbar);\n'
     '    ClassDB::bind_method(D_METHOD("desktop_window_is_taskbar_hidden", "handle"), &GDCubismUserModel::desktop_window_is_taskbar_hidden);')
edit("src/gd_cubism_user_model.hpp", "bool desktop_window_is_taskbar_hidden(int64_t handle) const;",
     "bool desktop_window_is_taskbar_hidden(int64_t handle) const;\n"
     "    bool set_companion_window_opacity(int64_t handle, double opacity);\n"
     "    double get_companion_window_opacity(int64_t handle) const;")
edit("src/gd_cubism_user_model.cpp",
     'ClassDB::bind_method(D_METHOD("desktop_window_is_taskbar_hidden", "handle"), &GDCubismUserModel::desktop_window_is_taskbar_hidden);',
     'ClassDB::bind_method(D_METHOD("desktop_window_is_taskbar_hidden", "handle"), &GDCubismUserModel::desktop_window_is_taskbar_hidden);\n'
     '    ClassDB::bind_method(D_METHOD("set_companion_window_opacity", "handle", "opacity"), &GDCubismUserModel::set_companion_window_opacity);\n'
     '    ClassDB::bind_method(D_METHOD("get_companion_window_opacity", "handle"), &GDCubismUserModel::get_companion_window_opacity);')
(root / "src/private/pet_companion_desktop.cpp").write_bytes(companion.read_bytes())
print("Applied Native compatibility, CPU vertex, desktop pointer, DPAPI and companion patches.")
