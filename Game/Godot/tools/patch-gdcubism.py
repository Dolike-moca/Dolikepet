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
edit("SConstruct", 'sources = glob("src/*.cpp")',
     'if env["platform"] == "windows":\n    env.Append(LIBS=["user32"])\n\nsources = glob("src/*.cpp")')
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
(root / "src/private/pet_pointer_bridge.cpp").write_bytes(bridge.read_bytes())
print("Applied Native compatibility, CPU vertex and desktop pointer patches.")
