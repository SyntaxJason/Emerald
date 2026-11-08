#include "../../runtime/emerald_runtime.h"

#include <stdint.h>
#include <stdlib.h>

int main(void) {
    hyperalloc_flow_init();

    if (!emerald_llvm_initialize_native_target()) {
        return 1;
    }

    EmeraldString *triple = emerald_llvm_default_target_triple();
    if (!emerald_llvm_initialize_target(triple)) {
        return 2;
    }

    int32_t context = emerald_llvm_create_context();
    int32_t module = emerald_llvm_create_module(context, emerald_string_from_cstr("emerald_selfhost_bridge"));
    emerald_llvm_module_set_target(module, triple);

    int32_t int32_type = emerald_llvm_i32_type(context);
    typedef struct EmeraldLlvmHandleObject {
        int32_t handle;
    } EmeraldLlvmHandleObject;

    EmeraldLlvmHandleObject int32_type_object = {int32_type};
    EmeraldList *parameter_types = emerald_list_new();
    emerald_list_add(parameter_types, &int32_type_object);
    EmeraldLlvmListObject parameter_types_object = {parameter_types};
    int32_t identity_type = emerald_llvm_function_type_with_params(int32_type, &parameter_types_object, 0);
    int32_t identity = emerald_llvm_add_function(module, emerald_string_from_cstr("identity"), identity_type);
    int32_t identity_block = emerald_llvm_append_block(context, identity, emerald_string_from_cstr("entry"));
    int32_t builder = emerald_llvm_create_builder(context);
    emerald_llvm_position_at_end(builder, identity_block);
    emerald_llvm_return_value(builder, emerald_llvm_function_parameter(identity, 0));

    EmeraldList *struct_types = emerald_list_new();
    emerald_list_add(struct_types, &int32_type_object);
    EmeraldLlvmListObject struct_types_object = {struct_types};
    int32_t struct_type = emerald_llvm_struct_type(context, &struct_types_object, 0);
    int32_t named_struct_type = emerald_llvm_named_struct_type(context, emerald_string_from_cstr("BridgeValue"));
    emerald_llvm_struct_set_body(named_struct_type, &struct_types_object, 0);

    int32_t constant_42 = emerald_llvm_const_int(int32_type, 42);
    EmeraldLlvmHandleObject constant_42_object = {constant_42};
    EmeraldList *constant_values = emerald_list_new();
    emerald_list_add(constant_values, &constant_42_object);
    EmeraldLlvmListObject constant_values_object = {constant_values};
    emerald_llvm_const_struct(context, &constant_values_object, 0);
    emerald_llvm_const_array(int32_type, &constant_values_object);

    int32_t function_type = emerald_llvm_function_type(int32_type);
    int32_t function = emerald_llvm_add_function(module, emerald_string_from_cstr("main"), function_type);
    int32_t block = emerald_llvm_append_block(context, function, emerald_string_from_cstr("entry"));
    emerald_llvm_position_at_end(builder, block);

    int32_t storage = emerald_llvm_build_alloca(builder, struct_type, emerald_string_from_cstr("storage"));
    int32_t zero = emerald_llvm_const_int(int32_type, 0);
    EmeraldLlvmHandleObject zero_object = {zero};
    EmeraldList *indices = emerald_list_new();
    emerald_list_add(indices, &zero_object);
    emerald_list_add(indices, &zero_object);
    EmeraldLlvmListObject indices_object = {indices};
    emerald_llvm_build_gep(builder, struct_type, storage, &indices_object, emerald_string_from_cstr("field_raw"));
    int32_t field = emerald_llvm_build_inbounds_gep(builder, struct_type, storage, &indices_object, emerald_string_from_cstr("field"));
    emerald_llvm_build_store(builder, constant_42, field);
    int32_t loaded = emerald_llvm_build_load(builder, int32_type, field, emerald_string_from_cstr("loaded"));

    EmeraldLlvmHandleObject loaded_object = {loaded};
    EmeraldList *call_args = emerald_list_new();
    emerald_list_add(call_args, &loaded_object);
    EmeraldLlvmListObject call_args_object = {call_args};
    int32_t called = emerald_llvm_build_call(builder, identity_type, identity, &call_args_object, emerald_string_from_cstr("called"));
    emerald_llvm_return_value(builder, called);

    if (!emerald_llvm_module_verify(module)) {
        return 3;
    }

    int32_t target = emerald_llvm_lookup_target(triple);
    int32_t machine = emerald_llvm_create_target_machine(target, triple, emerald_string_from_cstr("generic"), emerald_string_from_cstr(""), 2);

    if (!emerald_llvm_target_machine_apply_data_layout(machine, module)) {
        return 4;
    }

    if (!emerald_llvm_target_machine_emit_object_file(machine, module, emerald_string_from_cstr("/tmp/emerald-selfhost-bridge.o"))) {
        return 5;
    }

    EmeraldList *compile_args = emerald_list_new();
    emerald_list_add(compile_args, emerald_string_from_cstr("-DEMERALD_RUNTIME_ENABLE_LLVM=1"));
    EmeraldLlvmListObject compile_args_object = {compile_args};

    if (!emerald_llvm_compile_runtime_object(emerald_llvm_runtime_source_path(), emerald_string_from_cstr("/tmp/emerald-selfhost-runtime.o"), &compile_args_object)) {
        return 6;
    }

    EmeraldList *objects = emerald_list_new();
    emerald_list_add(objects, emerald_string_from_cstr("/tmp/emerald-selfhost-bridge.o"));
    emerald_list_add(objects, emerald_string_from_cstr("/tmp/emerald-selfhost-runtime.o"));

    EmeraldList *library_paths = emerald_list_new();
    const char *library_path = getenv("EMERALD_LLVM_LIB_DIR");
    if (library_path != NULL && library_path[0] != '\0') {
        emerald_list_add(library_paths, emerald_string_from_cstr(library_path));
    }

    EmeraldList *libraries = emerald_list_new();
    const char *library = getenv("EMERALD_LLVM_LIBRARY");
    emerald_list_add(libraries, emerald_string_from_cstr(library == NULL || library[0] == '\0' ? "LLVM" : library));

    EmeraldList *link_args = emerald_list_new();
    emerald_list_add(link_args, emerald_string_from_cstr("-ldl"));

    EmeraldLlvmListObject objects_object = {objects};
    EmeraldLlvmListObject library_paths_object = {library_paths};
    EmeraldLlvmListObject libraries_object = {libraries};
    EmeraldLlvmListObject link_args_object = {link_args};

    if (!emerald_llvm_link_executable(emerald_string_from_cstr("/tmp/emerald-selfhost-bridge-program"), &objects_object, &library_paths_object, &libraries_object, &link_args_object)) {
        return 7;
    }

    emerald_llvm_dispose_builder(builder);
    emerald_llvm_dispose_target_machine(machine);
    emerald_llvm_dispose_module(module);
    emerald_llvm_dispose_context(context);
    hyperalloc_flow_shutdown();
    return 0;
}
