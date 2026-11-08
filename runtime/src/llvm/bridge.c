#include "../emerald_runtime_internal.h"
#include "llvm_compat.h"

#include <stdint.h>
#include <sys/wait.h>

static void **emerald_llvm_handles;
static uint32_t emerald_llvm_handle_count = 1;
static uint32_t emerald_llvm_handle_capacity;
static char emerald_llvm_last_error_value[4096];
static char emerald_llvm_last_link_command[16384];
static char emerald_llvm_last_link_output[16384];
static char emerald_llvm_last_link_error[16384];
static char emerald_llvm_last_runtime_command[16384];
static char emerald_llvm_last_runtime_output[16384];
static char emerald_llvm_last_runtime_error[16384];

static void emerald_llvm_copy(char *target, size_t capacity, const char *value) {
    if (capacity == 0) {
        return;
    }

    const char *source = value == NULL ? "" : value;
    snprintf(target, capacity, "%s", source);
}

static const char *emerald_llvm_text(EmeraldString *value) {
    return value == NULL ? "" : emerald_runtime_cstr(value);
}

static EmeraldString *emerald_llvm_string(const char *value) {
    return emerald_string_from_cstr(value == NULL ? "" : value);
}

static void emerald_llvm_reserve_handles(uint32_t required) {
    if (emerald_llvm_handle_capacity > required) {
        return;
    }

    uint32_t capacity = emerald_llvm_handle_capacity == 0 ? 1024 : emerald_llvm_handle_capacity;
    while (capacity <= required) {
        if (capacity > UINT32_MAX / 2) {
            emerald_flow_fail(required);
        }
        capacity *= 2;
    }

    void **next = calloc(capacity, sizeof(void *));
    if (next == NULL) {
        emerald_flow_fail((uint64_t) capacity * sizeof(void *));
    }

    if (emerald_llvm_handles != NULL) {
        memcpy(next, emerald_llvm_handles, (size_t) emerald_llvm_handle_capacity * sizeof(void *));
        free(emerald_llvm_handles);
    }

    emerald_llvm_handles = next;
    emerald_llvm_handle_capacity = capacity;
}

static int32_t emerald_llvm_store(void *pointer) {
    if (pointer == NULL) {
        return 0;
    }

    emerald_llvm_reserve_handles(emerald_llvm_handle_count + 1);
    uint32_t handle = emerald_llvm_handle_count++;
    emerald_llvm_handles[handle] = pointer;
    return (int32_t) handle;
}

static void *emerald_llvm_get(int32_t handle) {
    if (handle == EMERALD_UAF_SENTINEL) {
        emerald_uaf_report("emerald_llvm_get", NULL);
    }

    if (handle <= 0 || (uint32_t) handle >= emerald_llvm_handle_count || emerald_llvm_handles == NULL) {
        return NULL;
    }

    return emerald_llvm_handles[(uint32_t) handle];
}

static void emerald_llvm_remove(int32_t handle) {
    if (handle <= 0 || (uint32_t) handle >= emerald_llvm_handle_count || emerald_llvm_handles == NULL) {
        return;
    }

    emerald_llvm_handles[(uint32_t) handle] = NULL;
}

static int32_t emerald_llvm_object_handle(void *object) {
    return object == NULL ? 0 : *((int32_t *) object);
}

static EmeraldList *emerald_llvm_list(EmeraldLlvmListObject *value) {
    return value == NULL ? NULL : value->items;
}

static LLVMTypeRef *emerald_llvm_type_list(EmeraldLlvmListObject *value, unsigned *count) {
    EmeraldList *list = emerald_llvm_list(value);
    *count = list == NULL ? 0 : (unsigned) list->length;
    if (*count == 0) {
        return NULL;
    }

    LLVMTypeRef *values = calloc(*count, sizeof(LLVMTypeRef));
    if (values == NULL) {
        emerald_flow_fail((uint64_t) *count * sizeof(LLVMTypeRef));
    }

    for (unsigned index = 0; index < *count; index++) {
        void *object = emerald_list_get(list, (int32_t) index);
        int32_t handle = emerald_llvm_object_handle(object);
        if (handle == EMERALD_UAF_SENTINEL) {
            emerald_uaf_report("emerald_llvm_type_list", object);
        }
        values[index] = (LLVMTypeRef) emerald_llvm_get(handle);
    }

    return values;
}

static LLVMValueRef *emerald_llvm_value_list(EmeraldLlvmListObject *value, unsigned *count) {
    EmeraldList *list = emerald_llvm_list(value);
    *count = list == NULL ? 0 : (unsigned) list->length;
    if (*count == 0) {
        return NULL;
    }

    LLVMValueRef *values = calloc(*count, sizeof(LLVMValueRef));
    if (values == NULL) {
        emerald_flow_fail((uint64_t) *count * sizeof(LLVMValueRef));
    }

    for (unsigned index = 0; index < *count; index++) {
        void *object = emerald_list_get(list, (int32_t) index);
        int32_t handle = emerald_llvm_object_handle(object);
        if (handle == EMERALD_UAF_SENTINEL) {
            emerald_uaf_report("emerald_llvm_value_list", object);
        }
        values[index] = (LLVMValueRef) emerald_llvm_get(handle);
    }

    return values;
}

static int emerald_llvm_has_arg(EmeraldLlvmListObject *value, const char *argument) {
    EmeraldList *args = emerald_llvm_list(value);
    if (args == NULL) {
        return 0;
    }

    for (uint64_t index = 0; index < args->length; index++) {
        EmeraldString *entry = emerald_list_get(args, (int32_t) index);
        if (strcmp(emerald_llvm_text(entry), argument) == 0) {
            return 1;
        }
    }

    return 0;
}

static void emerald_llvm_append_quoted(char *command, size_t capacity, const char *value) {
    size_t length = strlen(command);
    if (length + 4 >= capacity) {
        return;
    }

    command[length++] = ' ';
    command[length++] = '\'';
    command[length] = '\0';

    const char *cursor = value == NULL ? "" : value;
    while (*cursor != '\0' && length + 6 < capacity) {
        if (*cursor == '\'') {
            memcpy(command + length, "'\\''", 4);
            length += 4;
        } else {
            command[length++] = *cursor;
        }
        cursor++;
    }

    command[length++] = '\'';
    command[length] = '\0';
}

static int emerald_llvm_run(const char *command, char *output, size_t output_capacity) {
    char complete[32768];
    snprintf(complete, sizeof(complete), "%s 2>&1", command);
    FILE *process = popen(complete, "r");
    if (process == NULL) {
        emerald_llvm_copy(output, output_capacity, strerror(errno));
        return 1;
    }

    size_t length = 0;
    while (length + 1 < output_capacity) {
        size_t read = fread(output + length, 1, output_capacity - length - 1, process);
        length += read;
        if (read == 0) {
            break;
        }
    }
    output[length] = '\0';

    int status = pclose(process);
    if (status == -1) {
        return 1;
    }

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }

    return 1;
}

static const char *emerald_llvm_cc(EmeraldLlvmListObject *value) {
    const char *command = getenv("EMERALD_CC");
    if (command == NULL || command[0] == '\0') {
        command = getenv("CC");
    }
    if (command == NULL || command[0] == '\0') {
        command = "clang";
    }

    EmeraldList *extra_args = emerald_llvm_list(value);
    if (extra_args == NULL) {
        return command;
    }

    for (uint64_t index = 0; index < extra_args->length; index++) {
        const char *argument = emerald_llvm_text(emerald_list_get(extra_args, (int32_t) index));
        const char *prefix = "--emerald-cc=";
        if (strncmp(argument, prefix, strlen(prefix)) == 0) {
            return argument + strlen(prefix);
        }
    }

    return command;
}

static int emerald_llvm_skip_extra(const char *argument) {
    return strncmp(argument, "--emerald-cc=", 13) == 0 || strncmp(argument, "--emerald-target=", 17) == 0;
}

static void emerald_llvm_append_extra(char *command, size_t capacity, EmeraldLlvmListObject *value) {
    EmeraldList *extra_args = emerald_llvm_list(value);
    if (extra_args == NULL) {
        return;
    }

    for (uint64_t index = 0; index < extra_args->length; index++) {
        const char *argument = emerald_llvm_text(emerald_list_get(extra_args, (int32_t) index));
        if (!emerald_llvm_skip_extra(argument)) {
            emerald_llvm_append_quoted(command, capacity, argument);
        }
    }
}

static const char *emerald_llvm_runtime_file(const char *name, char *buffer, size_t capacity) {
    const char *home = getenv("EMERALD_HOME");
    if (home != NULL && home[0] != '\0') {
        snprintf(buffer, capacity, "%s/runtime/%s", home, name);
        if (access(buffer, F_OK) == 0) {
            return buffer;
        }
    }

    snprintf(buffer, capacity, "runtime/%s", name);
    if (access(buffer, F_OK) == 0) {
        return buffer;
    }

    buffer[0] = '\0';
    return buffer;
}

int32_t emerald_llvm_initialize_native_target(void) {
#if defined(__x86_64__) || defined(__i386__)
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
#elif defined(__aarch64__)
    LLVMInitializeAArch64TargetInfo();
    LLVMInitializeAArch64Target();
    LLVMInitializeAArch64TargetMC();
    LLVMInitializeAArch64AsmPrinter();
    LLVMInitializeAArch64AsmParser();
#endif
    emerald_llvm_last_error_value[0] = '\0';
    return 1;
}

int32_t emerald_llvm_initialize_target(EmeraldString *triple) {
    const char *value = emerald_llvm_text(triple);
    if (strstr(value, "aarch64") != NULL || strstr(value, "arm64") != NULL) {
        LLVMInitializeAArch64TargetInfo();
        LLVMInitializeAArch64Target();
        LLVMInitializeAArch64TargetMC();
        LLVMInitializeAArch64AsmPrinter();
        LLVMInitializeAArch64AsmParser();
        return 1;
    }

    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
    return 1;
}

EmeraldString *emerald_llvm_default_target_triple(void) {
    char *value = LLVMGetDefaultTargetTriple();
    EmeraldString *result = emerald_llvm_string(value);
    LLVMDisposeMessage(value);
    return result;
}

EmeraldString *emerald_llvm_normalize_target_triple(EmeraldString *triple) {
    char *value = LLVMNormalizeTargetTriple(emerald_llvm_text(triple));
    EmeraldString *result = emerald_llvm_string(value);
    LLVMDisposeMessage(value);
    return result;
}

int32_t emerald_llvm_lookup_target(EmeraldString *triple) {
    LLVMTargetRef target = NULL;
    char *message = NULL;
    int status = LLVMGetTargetFromTriple(emerald_llvm_text(triple), &target, &message);
    if (status == 0) {
        emerald_llvm_last_error_value[0] = '\0';
        return emerald_llvm_store(target);
    }

    emerald_llvm_copy(emerald_llvm_last_error_value, sizeof(emerald_llvm_last_error_value), message == NULL ? "LLVM target lookup failed" : message);
    if (message != NULL) {
        LLVMDisposeMessage(message);
    }
    return 0;
}

EmeraldString *emerald_llvm_last_error(void) { return emerald_llvm_string(emerald_llvm_last_error_value); }
EmeraldString *emerald_llvm_native_object_extension(void) {
#if defined(_WIN32)
    return emerald_llvm_string(".obj");
#else
    return emerald_llvm_string(".o");
#endif
}
EmeraldString *emerald_llvm_native_executable_extension(void) {
#if defined(_WIN32)
    return emerald_llvm_string(".exe");
#else
    return emerald_llvm_string("");
#endif
}
EmeraldString *emerald_llvm_target_name(int32_t target) { return emerald_llvm_string(LLVMGetTargetName((LLVMTargetRef) emerald_llvm_get(target))); }
EmeraldString *emerald_llvm_target_description(int32_t target) { return emerald_llvm_string(LLVMGetTargetDescription((LLVMTargetRef) emerald_llvm_get(target))); }

int32_t emerald_llvm_create_target_machine(int32_t target, EmeraldString *triple, EmeraldString *cpu, EmeraldString *features, int32_t optimization_level) {
    if (optimization_level < 0) optimization_level = 0;
    if (optimization_level > 3) optimization_level = 3;
    LLVMTargetMachineRef machine = LLVMCreateTargetMachine((LLVMTargetRef) emerald_llvm_get(target), emerald_llvm_text(triple), emerald_llvm_text(cpu), emerald_llvm_text(features), (LLVMCodeGenOptLevel) optimization_level, LLVMRelocDefault, LLVMCodeModelDefault);
    if (machine == NULL) {
        emerald_llvm_copy(emerald_llvm_last_error_value, sizeof(emerald_llvm_last_error_value), "LLVM target machine creation failed");
        return 0;
    }
    return emerald_llvm_store(machine);
}

void emerald_llvm_dispose_target_machine(int32_t machine) {
    LLVMTargetMachineRef value = emerald_llvm_get(machine);
    if (value != NULL) LLVMDisposeTargetMachine(value);
    emerald_llvm_remove(machine);
}

int32_t emerald_llvm_target_machine_apply_data_layout(int32_t machine, int32_t module) {
    LLVMTargetDataRef data = LLVMCreateTargetDataLayout((LLVMTargetMachineRef) emerald_llvm_get(machine));
    if (data == NULL) return 0;
    LLVMSetModuleDataLayout((LLVMModuleRef) emerald_llvm_get(module), data);
    LLVMDisposeTargetData(data);
    return 1;
}

static int32_t emerald_llvm_emit_file(int32_t machine, int32_t module, EmeraldString *path, LLVMCodeGenFileType type) {
    char *message = NULL;
    char filename[4096];
    snprintf(filename, sizeof(filename), "%s", emerald_llvm_text(path));
    int status = LLVMTargetMachineEmitToFile((LLVMTargetMachineRef) emerald_llvm_get(machine), (LLVMModuleRef) emerald_llvm_get(module), filename, type, &message);
    if (status == 0) return 1;
    emerald_llvm_copy(emerald_llvm_last_error_value, sizeof(emerald_llvm_last_error_value), message == NULL ? "LLVM target emission failed" : message);
    if (message != NULL) LLVMDisposeMessage(message);
    return 0;
}

int32_t emerald_llvm_target_machine_emit_object_file(int32_t machine, int32_t module, EmeraldString *path) { return emerald_llvm_emit_file(machine, module, path, LLVMObjectFile); }
int32_t emerald_llvm_target_machine_emit_assembly_file(int32_t machine, int32_t module, EmeraldString *path) { return emerald_llvm_emit_file(machine, module, path, LLVMAssemblyFile); }

/* Attribute sets for runtime entry points that generated code calls. Every
   entry must hold for the C implementation in runtime/src: the attributes are
   copied from template declarations parsed by LLVM itself, so the encoding of
   memory effects always matches the linked LLVM version. Anything not listed
   only receives nounwind (Emerald has no unwinding; panics abort or exit). */
static const char emerald_llvm_attribute_templates[] =
    "declare void @emerald_attr_pure() nounwind willreturn memory(read)\n"
    "declare noalias ptr @emerald_attr_alloc(i64) nounwind allocsize(0)\n"
    "declare noalias ptr @emerald_attr_fresh() nounwind\n"
    "declare void @emerald_attr_noreturn() nounwind noreturn cold\n"
    "declare void @emerald_attr_cold() nounwind cold\n"
    "declare void @emerald_attr_default() nounwind\n";

typedef struct EmeraldLlvmAttributeRule {
    const char *function;
    const char *attributes;
} EmeraldLlvmAttributeRule;

static const EmeraldLlvmAttributeRule emerald_llvm_attribute_rules[] = {
    /* Read-only queries over String/List payloads: no allocation, no Flow
       bookkeeping, no failure path. */
    {"emerald_string_equals", "emerald_attr_pure"},
    {"emerald_string_length", "emerald_attr_pure"},
    {"emerald_string_starts_with", "emerald_attr_pure"},
    {"emerald_string_ends_with", "emerald_attr_pure"},
    {"emerald_string_contains", "emerald_attr_pure"},
    {"emerald_string_index_of", "emerald_attr_pure"},
    {"emerald_string_char_at", "emerald_attr_pure"},
    {"emerald_string_hash_int64", "emerald_attr_pure"},
    {"emerald_list_length", "emerald_attr_pure"},
    /* Fresh, uniquely addressed payloads of the requested size. The pool
       allocator is excluded: it hands out the same slot again. */
    {"emerald_flow_alloc", "emerald_attr_alloc"},
    {"emerald_flow_alloc_atomic", "emerald_attr_alloc"},
    {"emerald_flow_bond_alloc", "emerald_attr_alloc"},
    {"emerald_flow_shard_alloc", "emerald_attr_alloc"},
    {"emerald_list_new_typed", "emerald_attr_fresh"},
    /* Terminating diagnostics and the slow paths only reached on failure. */
    {"emerald_panic", "emerald_attr_noreturn"},
    {"emerald_process_exit", "emerald_attr_noreturn"},
    {"__emerald_list_index_fail", "emerald_attr_noreturn"},
    {"emerald_int64_add", "emerald_attr_cold"},
    {"emerald_int64_sub", "emerald_attr_cold"},
    {"emerald_int64_mul", "emerald_attr_cold"},
    {"emerald_int64_div", "emerald_attr_cold"},
    {"emerald_int64_rem", "emerald_attr_cold"},
    {"emerald_int64_neg", "emerald_attr_cold"},
    {"emerald_int64_to_int32_checked", "emerald_attr_cold"},
};

static void emerald_llvm_copy_attributes(LLVMValueRef source, LLVMValueRef target, unsigned index) {
    unsigned count = LLVMGetAttributeCountAtIndex(source, index);
    if (count == 0) return;
    LLVMAttributeRef attributes[16];
    if (count > 16) count = 16;
    LLVMGetAttributesAtIndex(source, index, attributes);
    for (unsigned item = 0; item < count; item++) {
        LLVMAddAttributeAtIndex(target, index, attributes[item]);
    }
}

static void emerald_llvm_apply_template(LLVMModuleRef templates, const char *name, LLVMValueRef function) {
    LLVMValueRef source = LLVMGetNamedFunction(templates, name);
    if (source == NULL) return;
    emerald_llvm_copy_attributes(source, function, (unsigned) -1);
    emerald_llvm_copy_attributes(source, function, 0);
}

static void emerald_llvm_annotate_module(LLVMModuleRef module) {
    LLVMModuleRef templates = NULL;
    char *message = NULL;
    LLVMMemoryBufferRef buffer = LLVMCreateMemoryBufferWithMemoryRangeCopy(emerald_llvm_attribute_templates, sizeof(emerald_llvm_attribute_templates) - 1, "emerald-attributes");
    if (buffer == NULL || LLVMParseIRInContext(LLVMGetModuleContext(module), buffer, &templates, &message) != 0) {
        /* Attributes only enable optimizations; never fail the build here. */
        if (message != NULL) LLVMDisposeMessage(message);
        return;
    }

    for (LLVMValueRef function = LLVMGetFirstFunction(module); function != NULL; function = LLVMGetNextFunction(function)) {
        const char *name = LLVMGetValueName(function);
        if (name == NULL || strncmp(name, "llvm.", 5) == 0) continue;
        const char *rule = "emerald_attr_default";
        for (size_t index = 0; index < sizeof(emerald_llvm_attribute_rules) / sizeof(emerald_llvm_attribute_rules[0]); index++) {
            if (strcmp(name, emerald_llvm_attribute_rules[index].function) == 0) {
                rule = emerald_llvm_attribute_rules[index].attributes;
                break;
            }
        }
        emerald_llvm_apply_template(templates, rule, function);
    }

    LLVMDisposeModule(templates);
}

/* The optimizer gets a TargetMachine for the module's own triple so the
   pipeline uses the real cost model (TTI) instead of LLVM's generic one. */
static LLVMTargetMachineRef emerald_llvm_module_machine(LLVMModuleRef module) {
    const char *triple = LLVMGetTarget(module);
    if (triple == NULL || triple[0] == '\0') return NULL;
    LLVMTargetRef target = NULL;
    char *message = NULL;
    if (LLVMGetTargetFromTriple(triple, &target, &message) != 0) {
        if (message != NULL) LLVMDisposeMessage(message);
        return NULL;
    }
    return LLVMCreateTargetMachine(target, triple, "generic", "", LLVMCodeGenLevelDefault, LLVMRelocDefault, LLVMCodeModelDefault);
}

int32_t emerald_llvm_run_passes(int32_t module, EmeraldString *passes) {
    LLVMModuleRef module_ref = (LLVMModuleRef) emerald_llvm_get(module);
    if (module_ref == NULL) {
        emerald_llvm_copy(emerald_llvm_last_error_value, sizeof(emerald_llvm_last_error_value), "LLVM run passes received an invalid module handle");
        return 0;
    }
    emerald_llvm_annotate_module(module_ref);
    LLVMTargetMachineRef machine = emerald_llvm_module_machine(module_ref);
    LLVMPassBuilderOptionsRef options = LLVMCreatePassBuilderOptions();
    LLVMErrorRef error = LLVMRunPasses(module_ref, emerald_llvm_text(passes), machine, options);
    LLVMDisposePassBuilderOptions(options);
    if (machine != NULL) LLVMDisposeTargetMachine(machine);
    if (error != NULL) {
        char *message = LLVMGetErrorMessage(error);
        emerald_llvm_copy(emerald_llvm_last_error_value, sizeof(emerald_llvm_last_error_value), message == NULL ? "LLVM pass pipeline failed" : message);
        if (message != NULL) LLVMDisposeErrorMessage(message);
        return 0;
    }
    return 1;
}

int32_t emerald_llvm_link_executable(EmeraldString *output, EmeraldLlvmListObject *object_files_value, EmeraldLlvmListObject *library_paths_value, EmeraldLlvmListObject *libraries_value, EmeraldLlvmListObject *extra_args) {
    EmeraldList *object_files = emerald_llvm_list(object_files_value);
    EmeraldList *library_paths = emerald_llvm_list(library_paths_value);
    EmeraldList *libraries = emerald_llvm_list(libraries_value);
    emerald_llvm_last_link_command[0] = '\0';
    emerald_llvm_last_link_output[0] = '\0';
    emerald_llvm_last_link_error[0] = '\0';
    snprintf(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), "%s", emerald_llvm_cc(extra_args));

    for (uint64_t index = 0; object_files != NULL && index < object_files->length; index++) {
        emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), emerald_llvm_text(emerald_list_get(object_files, (int32_t) index)));
    }

    for (uint64_t index = 0; library_paths != NULL && index < library_paths->length; index++) {
        char value[4096];
        snprintf(value, sizeof(value), "-L%s", emerald_llvm_text(emerald_list_get(library_paths, (int32_t) index)));
        emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), value);
    }

    for (uint64_t index = 0; libraries != NULL && index < libraries->length; index++) {
        char value[4096];
        snprintf(value, sizeof(value), "-l%s", emerald_llvm_text(emerald_list_get(libraries, (int32_t) index)));
        emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), value);
    }

    emerald_llvm_append_extra(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), extra_args);

    const char *enable_llvm = getenv("EMERALD_RUNTIME_ENABLE_LLVM");
    if (enable_llvm != NULL && strcmp(enable_llvm, "1") == 0) {
        const char *directory = getenv("EMERALD_LLVM_LIB_DIR");
        const char *library = getenv("EMERALD_LLVM_LIBRARY");
        if (directory != NULL && directory[0] != '\0') {
            char value[4096];
            snprintf(value, sizeof(value), "-L%s", directory);
            emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), value);
        }
        char value[4096];
        snprintf(value, sizeof(value), "-l%s", library == NULL || library[0] == '\0' ? "LLVM" : library);
        emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), value);
    }

#if !defined(_WIN32)
    if (!emerald_llvm_has_arg(extra_args, "-pie") && !emerald_llvm_has_arg(extra_args, "-no-pie")) {
        emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), "-no-pie");
    }
#endif

    emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), "-o");
    emerald_llvm_append_quoted(emerald_llvm_last_link_command, sizeof(emerald_llvm_last_link_command), emerald_llvm_text(output));

    int status = emerald_llvm_run(emerald_llvm_last_link_command, emerald_llvm_last_link_output, sizeof(emerald_llvm_last_link_output));
    if (status != 0) emerald_llvm_copy(emerald_llvm_last_link_error, sizeof(emerald_llvm_last_link_error), emerald_llvm_last_link_output);
    return status == 0;
}

EmeraldString *emerald_llvm_linker_last_command(void) { return emerald_llvm_string(emerald_llvm_last_link_command); }
EmeraldString *emerald_llvm_linker_last_output(void) { return emerald_llvm_string(emerald_llvm_last_link_output); }
EmeraldString *emerald_llvm_linker_last_error(void) { return emerald_llvm_string(emerald_llvm_last_link_error); }

EmeraldString *emerald_llvm_runtime_source_path(void) {
    char path[4096];
    return emerald_llvm_string(emerald_llvm_runtime_file("emerald_runtime.c", path, sizeof(path)));
}
EmeraldString *emerald_llvm_runtime_header_path(void) {
    char path[4096];
    return emerald_llvm_string(emerald_llvm_runtime_file("emerald_runtime.h", path, sizeof(path)));
}
EmeraldString *emerald_llvm_runtime_flow_library_name(void) { return emerald_llvm_string(""); }
EmeraldString *emerald_llvm_runtime_flow_library_path(void) { return emerald_llvm_string(""); }

int32_t emerald_llvm_compile_runtime_object(EmeraldString *source, EmeraldString *output, EmeraldLlvmListObject *extra_args) {
    emerald_llvm_last_runtime_command[0] = '\0';
    emerald_llvm_last_runtime_output[0] = '\0';
    emerald_llvm_last_runtime_error[0] = '\0';
    snprintf(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "%s", emerald_llvm_cc(extra_args));
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-std=c11");
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-O2");

    const char *enable_llvm = getenv("EMERALD_RUNTIME_ENABLE_LLVM");
    if (enable_llvm != NULL && strcmp(enable_llvm, "1") == 0) {
        emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-DEMERALD_RUNTIME_ENABLE_LLVM=1");
    }

    emerald_llvm_append_extra(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), extra_args);
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-c");
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), emerald_llvm_text(source));
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-o");
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), emerald_llvm_text(output));

    int status = emerald_llvm_run(emerald_llvm_last_runtime_command, emerald_llvm_last_runtime_output, sizeof(emerald_llvm_last_runtime_output));
    if (status != 0) emerald_llvm_copy(emerald_llvm_last_runtime_error, sizeof(emerald_llvm_last_runtime_error), emerald_llvm_last_runtime_output);
    return status == 0;
}

int32_t emerald_llvm_compile_ir_object(EmeraldString *source, EmeraldString *output, EmeraldLlvmListObject *extra_args) {
    emerald_llvm_last_runtime_command[0] = '\0';
    emerald_llvm_last_runtime_output[0] = '\0';
    emerald_llvm_last_runtime_error[0] = '\0';
    snprintf(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "%s", emerald_llvm_cc(extra_args));
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-O2");

    const char *enable_llvm = getenv("EMERALD_RUNTIME_ENABLE_LLVM");
    if (enable_llvm != NULL && strcmp(enable_llvm, "1") == 0) {
        emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-DEMERALD_RUNTIME_ENABLE_LLVM=1");
    }

    emerald_llvm_append_extra(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), extra_args);
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-c");
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), emerald_llvm_text(source));
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), "-o");
    emerald_llvm_append_quoted(emerald_llvm_last_runtime_command, sizeof(emerald_llvm_last_runtime_command), emerald_llvm_text(output));

    int status = emerald_llvm_run(emerald_llvm_last_runtime_command, emerald_llvm_last_runtime_output, sizeof(emerald_llvm_last_runtime_output));
    if (status != 0) emerald_llvm_copy(emerald_llvm_last_runtime_error, sizeof(emerald_llvm_last_runtime_error), emerald_llvm_last_runtime_output);
    return status == 0;
}

EmeraldString *emerald_llvm_runtime_last_command(void) { return emerald_llvm_string(emerald_llvm_last_runtime_command); }
EmeraldString *emerald_llvm_runtime_last_output(void) { return emerald_llvm_string(emerald_llvm_last_runtime_output); }
EmeraldString *emerald_llvm_runtime_last_error(void) { return emerald_llvm_string(emerald_llvm_last_runtime_error); }

int32_t emerald_llvm_create_context(void) { return emerald_llvm_store(LLVMContextCreate()); }
void emerald_llvm_dispose_context(int32_t handle) { LLVMContextRef value = emerald_llvm_get(handle); if (value != NULL) LLVMContextDispose(value); emerald_llvm_remove(handle); }
int32_t emerald_llvm_create_module(int32_t context, EmeraldString *name) { return emerald_llvm_store(LLVMModuleCreateWithNameInContext(emerald_llvm_text(name), emerald_llvm_get(context))); }
void emerald_llvm_dispose_module(int32_t handle) { LLVMModuleRef value = emerald_llvm_get(handle); if (value != NULL) LLVMDisposeModule(value); emerald_llvm_remove(handle); }
void emerald_llvm_module_set_target(int32_t module, EmeraldString *triple) { LLVMSetTarget(emerald_llvm_get(module), emerald_llvm_text(triple)); }
EmeraldString *emerald_llvm_module_to_ir(int32_t module) { char *value = LLVMPrintModuleToString(emerald_llvm_get(module)); EmeraldString *result = emerald_llvm_string(value); if (value != NULL) LLVMDisposeMessage(value); return result; }
int32_t emerald_llvm_module_write_ir(int32_t module, EmeraldString *path) { char *message = NULL; int status = LLVMPrintModuleToFile(emerald_llvm_get(module), emerald_llvm_text(path), &message); if (message != NULL) LLVMDisposeMessage(message); return status == 0; }
int32_t emerald_llvm_module_verify(int32_t module) { char *message = NULL; int status = LLVMVerifyModule(emerald_llvm_get(module), LLVMReturnStatusAction, &message); if (message != NULL) LLVMDisposeMessage(message); return status == 0; }
EmeraldString *emerald_llvm_module_verify_message(int32_t module) { char *message = NULL; int status = LLVMVerifyModule(emerald_llvm_get(module), LLVMReturnStatusAction, &message); if (status == 0) return emerald_llvm_string(""); EmeraldString *result = emerald_llvm_string(message == NULL ? "LLVM verification failed" : message); if (message != NULL) LLVMDisposeMessage(message); return result; }

int32_t emerald_llvm_create_builder(int32_t context) { return emerald_llvm_store(LLVMCreateBuilderInContext(emerald_llvm_get(context))); }
void emerald_llvm_dispose_builder(int32_t handle) { LLVMBuilderRef value = emerald_llvm_get(handle); if (value != NULL) LLVMDisposeBuilder(value); emerald_llvm_remove(handle); }
int32_t emerald_llvm_current_block(int32_t builder) { return emerald_llvm_store(LLVMGetInsertBlock(emerald_llvm_get(builder))); }

int32_t emerald_llvm_void_type(int32_t context) { return emerald_llvm_store(LLVMVoidTypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_i1_type(int32_t context) { return emerald_llvm_store(LLVMInt1TypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_i8_type(int32_t context) { return emerald_llvm_store(LLVMInt8TypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_i16_type(int32_t context) { return emerald_llvm_store(LLVMInt16TypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_i32_type(int32_t context) { return emerald_llvm_store(LLVMInt32TypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_i64_type(int32_t context) { return emerald_llvm_store(LLVMInt64TypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_int_type(int32_t context, int32_t bits) { return emerald_llvm_store(LLVMIntTypeInContext(emerald_llvm_get(context), (unsigned) bits)); }
int32_t emerald_llvm_float_type(int32_t context) { return emerald_llvm_store(LLVMFloatTypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_double_type(int32_t context) { return emerald_llvm_store(LLVMDoubleTypeInContext(emerald_llvm_get(context))); }
int32_t emerald_llvm_opaque_pointer_type(int32_t context) { return emerald_llvm_store(LLVMPointerTypeInContext(emerald_llvm_get(context), 0)); }
int32_t emerald_llvm_pointer_type(int32_t type) { return emerald_llvm_store(LLVMPointerType(emerald_llvm_get(type), 0)); }
int32_t emerald_llvm_array_type(int32_t type, int32_t count) { return emerald_llvm_store(LLVMArrayType(emerald_llvm_get(type), (unsigned) count)); }
int32_t emerald_llvm_struct_type(int32_t context, EmeraldLlvmListObject *elements, int32_t packed) { unsigned count; LLVMTypeRef *values = emerald_llvm_type_list(elements, &count); int32_t result = emerald_llvm_store(LLVMStructTypeInContext(emerald_llvm_get(context), values, count, packed)); free(values); return result; }
int32_t emerald_llvm_named_struct_type(int32_t context, EmeraldString *name) { return emerald_llvm_store(LLVMStructCreateNamed(emerald_llvm_get(context), emerald_llvm_text(name))); }
void emerald_llvm_struct_set_body(int32_t type, EmeraldLlvmListObject *elements, int32_t packed) { unsigned count; LLVMTypeRef *values = emerald_llvm_type_list(elements, &count); LLVMStructSetBody(emerald_llvm_get(type), values, count, packed); free(values); }
int32_t emerald_llvm_function_type(int32_t return_type) { return emerald_llvm_store(LLVMFunctionType(emerald_llvm_get(return_type), NULL, 0, 0)); }
int32_t emerald_llvm_function_type_with_params(int32_t return_type, EmeraldLlvmListObject *params, int32_t variadic) { unsigned count; LLVMTypeRef *values = emerald_llvm_type_list(params, &count); int32_t result = emerald_llvm_store(LLVMFunctionType(emerald_llvm_get(return_type), values, count, variadic)); free(values); return result; }
EmeraldString *emerald_llvm_type_to_ir(int32_t type) { char *value = LLVMPrintTypeToString(emerald_llvm_get(type)); EmeraldString *result = emerald_llvm_string(value); if (value != NULL) LLVMDisposeMessage(value); return result; }
int32_t emerald_llvm_size_of(int32_t type) { return emerald_llvm_store(LLVMSizeOf(emerald_llvm_get(type))); }
int32_t emerald_llvm_align_of(int32_t type) { return emerald_llvm_store(LLVMAlignOf(emerald_llvm_get(type))); }

int32_t emerald_llvm_add_function(int32_t module, EmeraldString *name, int32_t type) { return emerald_llvm_store(LLVMAddFunction(emerald_llvm_get(module), emerald_llvm_text(name), emerald_llvm_get(type))); }
int32_t emerald_llvm_get_function(int32_t module, EmeraldString *name) { return emerald_llvm_store(LLVMGetNamedFunction(emerald_llvm_get(module), emerald_llvm_text(name))); }
int32_t emerald_llvm_function_parameter_count(int32_t function) { return (int32_t) LLVMCountParams(emerald_llvm_get(function)); }
int32_t emerald_llvm_function_parameter(int32_t function, int32_t index) { return emerald_llvm_store(LLVMGetParam(emerald_llvm_get(function), (unsigned) index)); }
int32_t emerald_llvm_append_block(int32_t context, int32_t function, EmeraldString *name) { return emerald_llvm_store(LLVMAppendBasicBlockInContext(emerald_llvm_get(context), emerald_llvm_get(function), emerald_llvm_text(name))); }
EmeraldString *emerald_llvm_block_name(int32_t block) { return emerald_llvm_string(LLVMGetBasicBlockName(emerald_llvm_get(block))); }

int32_t emerald_llvm_add_global(int32_t module, EmeraldString *name, int32_t type) { return emerald_llvm_store(LLVMAddGlobal(emerald_llvm_get(module), emerald_llvm_get(type), emerald_llvm_text(name))); }
int32_t emerald_llvm_get_global(int32_t module, EmeraldString *name) { return emerald_llvm_store(LLVMGetNamedGlobal(emerald_llvm_get(module), emerald_llvm_text(name))); }
void emerald_llvm_global_set_initializer(int32_t global, int32_t value) { LLVMSetInitializer(emerald_llvm_get(global), emerald_llvm_get(value)); }
void emerald_llvm_global_set_constant(int32_t global, int32_t constant) { LLVMSetGlobalConstant(emerald_llvm_get(global), constant); }
void emerald_llvm_value_set_linkage(int32_t value, int32_t linkage) {
    LLVMLinkage native_linkage = LLVMExternalLinkage;

    if (linkage == 7) {
        native_linkage = LLVMInternalLinkage;
    } else if (linkage == 8) {
        native_linkage = LLVMPrivateLinkage;
    }

    LLVMSetLinkage(emerald_llvm_get(value), native_linkage);
}
int32_t emerald_llvm_value_type(int32_t value) { return emerald_llvm_store(LLVMTypeOf(emerald_llvm_get(value))); }
EmeraldString *emerald_llvm_value_name(int32_t value) { return emerald_llvm_string(LLVMGetValueName(emerald_llvm_get(value))); }
void emerald_llvm_value_set_name(int32_t value, EmeraldString *name) { LLVMSetValueName(emerald_llvm_get(value), emerald_llvm_text(name)); }
EmeraldString *emerald_llvm_value_to_ir(int32_t value) { char *text = LLVMPrintValueToString(emerald_llvm_get(value)); EmeraldString *result = emerald_llvm_string(text); if (text != NULL) LLVMDisposeMessage(text); return result; }

void emerald_llvm_position_at_end(int32_t builder, int32_t block) { LLVMPositionBuilderAtEnd(emerald_llvm_get(builder), emerald_llvm_get(block)); }
void emerald_llvm_return_void(int32_t builder) { LLVMBuildRetVoid(emerald_llvm_get(builder)); }
void emerald_llvm_return_value(int32_t builder, int32_t value) { LLVMBuildRet(emerald_llvm_get(builder), emerald_llvm_get(value)); }
int32_t emerald_llvm_build_branch(int32_t builder, int32_t block) { return emerald_llvm_store(LLVMBuildBr(emerald_llvm_get(builder), emerald_llvm_get(block))); }
int32_t emerald_llvm_build_conditional_branch(int32_t builder, int32_t condition, int32_t true_block, int32_t false_block) { return emerald_llvm_store(LLVMBuildCondBr(emerald_llvm_get(builder), emerald_llvm_get(condition), emerald_llvm_get(true_block), emerald_llvm_get(false_block))); }
int32_t emerald_llvm_build_unreachable(int32_t builder) { return emerald_llvm_store(LLVMBuildUnreachable(emerald_llvm_get(builder))); }

int32_t emerald_llvm_const_int(int32_t type, int64_t value) { return emerald_llvm_store(LLVMConstInt(emerald_llvm_get(type), (uint64_t) value, 1)); }
int32_t emerald_llvm_const_bool(int32_t type, int32_t value) { return emerald_llvm_store(LLVMConstInt(emerald_llvm_get(type), value ? 1 : 0, 0)); }
int32_t emerald_llvm_const_null(int32_t type) { return emerald_llvm_store(LLVMConstNull(emerald_llvm_get(type))); }
int32_t emerald_llvm_const_pointer_null(int32_t type) { return emerald_llvm_store(LLVMConstPointerNull(emerald_llvm_get(type))); }
int32_t emerald_llvm_const_string(int32_t context, EmeraldString *text, int32_t null_terminate) { return emerald_llvm_store(LLVMConstStringInContext(emerald_llvm_get(context), emerald_llvm_text(text), (unsigned) (text == NULL ? 0 : text->length), null_terminate ? 0 : 1)); }
int32_t emerald_llvm_const_struct(int32_t context, EmeraldLlvmListObject *items, int32_t packed) { unsigned count; LLVMValueRef *values = emerald_llvm_value_list(items, &count); int32_t result = emerald_llvm_store(LLVMConstStructInContext(emerald_llvm_get(context), values, count, packed)); free(values); return result; }
int32_t emerald_llvm_const_array(int32_t type, EmeraldLlvmListObject *items) { unsigned count; LLVMValueRef *values = emerald_llvm_value_list(items, &count); int32_t result = emerald_llvm_store(LLVMConstArray(emerald_llvm_get(type), values, count)); free(values); return result; }

#define EMERALD_LLVM_BINARY(name, llvm_name) int32_t emerald_llvm_##name(int32_t builder, int32_t left, int32_t right, EmeraldString *label) { return emerald_llvm_store(llvm_name(emerald_llvm_get(builder), emerald_llvm_get(left), emerald_llvm_get(right), emerald_llvm_text(label))); }
EMERALD_LLVM_BINARY(build_add, LLVMBuildAdd)
EMERALD_LLVM_BINARY(build_sub, LLVMBuildSub)
EMERALD_LLVM_BINARY(build_mul, LLVMBuildMul)
EMERALD_LLVM_BINARY(build_signed_div, LLVMBuildSDiv)
EMERALD_LLVM_BINARY(build_unsigned_div, LLVMBuildUDiv)
EMERALD_LLVM_BINARY(build_signed_rem, LLVMBuildSRem)
EMERALD_LLVM_BINARY(build_unsigned_rem, LLVMBuildURem)
EMERALD_LLVM_BINARY(build_and, LLVMBuildAnd)
EMERALD_LLVM_BINARY(build_or, LLVMBuildOr)
EMERALD_LLVM_BINARY(build_xor, LLVMBuildXor)
EMERALD_LLVM_BINARY(build_shift_left, LLVMBuildShl)
EMERALD_LLVM_BINARY(build_logical_shift_right, LLVMBuildLShr)
EMERALD_LLVM_BINARY(build_arithmetic_shift_right, LLVMBuildAShr)
#undef EMERALD_LLVM_BINARY

int32_t emerald_llvm_build_neg(int32_t builder, int32_t value, EmeraldString *label) { return emerald_llvm_store(LLVMBuildNeg(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_not(int32_t builder, int32_t value, EmeraldString *label) { return emerald_llvm_store(LLVMBuildNot(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_int_compare(int32_t builder, int32_t predicate, int32_t left, int32_t right, EmeraldString *label) { return emerald_llvm_store(LLVMBuildICmp(emerald_llvm_get(builder), (LLVMIntPredicate) predicate, emerald_llvm_get(left), emerald_llvm_get(right), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_alloca(int32_t builder, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildAlloca(emerald_llvm_get(builder), emerald_llvm_get(type), emerald_llvm_text(label))); }

/* Fixed-size compiler locals have one slot per function activation. Creating
   them in a loop body would grow the stack until the function returns. Keep the
   caller's insertion point unchanged; initialization still runs at its site. */
int32_t emerald_llvm_build_entry_alloca(int32_t builder, int32_t type, EmeraldString *label) {
    LLVMBuilderRef caller = emerald_llvm_get(builder);
    LLVMTypeRef slot_type = emerald_llvm_get(type);
    LLVMBasicBlockRef current = caller == NULL ? NULL : LLVMGetInsertBlock(caller);
    if (current == NULL || slot_type == NULL) return 0;
    LLVMBasicBlockRef entry = LLVMGetEntryBasicBlock(LLVMGetBasicBlockParent(current));
    LLVMBuilderRef slots = LLVMCreateBuilderInContext(LLVMGetTypeContext(slot_type));
    LLVMValueRef first = LLVMGetFirstInstruction(entry);
    while (first != NULL && LLVMIsAPHINode(first) != NULL) {
        first = LLVMGetNextInstruction(first);
    }
    if (first != NULL) LLVMPositionBuilderBefore(slots, first);
    else LLVMPositionBuilderAtEnd(slots, entry);
    LLVMValueRef value = LLVMBuildAlloca(slots, slot_type, emerald_llvm_text(label));
    LLVMDisposeBuilder(slots);
    return emerald_llvm_store(value);
}
int32_t emerald_llvm_build_load(int32_t builder, int32_t type, int32_t pointer, EmeraldString *label) { return emerald_llvm_store(LLVMBuildLoad2(emerald_llvm_get(builder), emerald_llvm_get(type), emerald_llvm_get(pointer), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_store(int32_t builder, int32_t value, int32_t pointer) {
    LLVMBuilderRef native_builder = emerald_llvm_get(builder);
    LLVMValueRef native_pointer = emerald_llvm_get(pointer);
    LLVMValueRef native_value = emerald_llvm_get(value);

    /* Reference emission uses handle 0 as its missing/default value. Passing
       NULL into LLVMBuildStore crashes inside LLVM; materialize the typed null
       expected for an alloca-backed local instead. */
    if (native_value == NULL && native_pointer != NULL && LLVMIsAAllocaInst(native_pointer) != NULL) {
        native_value = LLVMConstNull(LLVMGetAllocatedType(native_pointer));
    }

    if (native_builder == NULL || native_pointer == NULL || native_value == NULL) {
        emerald_flow_fail(0);
    }

    return emerald_llvm_store(LLVMBuildStore(native_builder, native_value, native_pointer));
}
int32_t emerald_llvm_build_gep(int32_t builder, int32_t source_type, int32_t pointer, EmeraldLlvmListObject *indices, EmeraldString *label) { unsigned count; LLVMValueRef *values = emerald_llvm_value_list(indices, &count); int32_t result = emerald_llvm_store(LLVMBuildGEP2(emerald_llvm_get(builder), emerald_llvm_get(source_type), emerald_llvm_get(pointer), values, count, emerald_llvm_text(label))); free(values); return result; }
int32_t emerald_llvm_build_inbounds_gep(int32_t builder, int32_t source_type, int32_t pointer, EmeraldLlvmListObject *indices, EmeraldString *label) { unsigned count; LLVMValueRef *values = emerald_llvm_value_list(indices, &count); int32_t result = emerald_llvm_store(LLVMBuildInBoundsGEP2(emerald_llvm_get(builder), emerald_llvm_get(source_type), emerald_llvm_get(pointer), values, count, emerald_llvm_text(label))); free(values); return result; }
int32_t emerald_llvm_build_global_string_pointer(int32_t builder, EmeraldString *text, EmeraldString *label) { return emerald_llvm_store(LLVMBuildGlobalStringPtr(emerald_llvm_get(builder), emerald_llvm_text(text), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_call(int32_t builder, int32_t function_type, int32_t function, EmeraldLlvmListObject *args, EmeraldString *label) { unsigned count; LLVMValueRef *values = emerald_llvm_value_list(args, &count); int32_t result = emerald_llvm_store(LLVMBuildCall2(emerald_llvm_get(builder), emerald_llvm_get(function_type), emerald_llvm_get(function), values, count, emerald_llvm_text(label))); free(values); return result; }
int32_t emerald_llvm_build_phi(int32_t builder, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildPhi(emerald_llvm_get(builder), emerald_llvm_get(type), emerald_llvm_text(label))); }
void emerald_llvm_add_incoming(int32_t phi, int32_t value, int32_t block) { LLVMValueRef values[1] = { emerald_llvm_get(value) }; LLVMBasicBlockRef blocks[1] = { emerald_llvm_get(block) }; LLVMAddIncoming(emerald_llvm_get(phi), values, blocks, 1); }
int32_t emerald_llvm_build_select(int32_t builder, int32_t condition, int32_t true_value, int32_t false_value, EmeraldString *label) { return emerald_llvm_store(LLVMBuildSelect(emerald_llvm_get(builder), emerald_llvm_get(condition), emerald_llvm_get(true_value), emerald_llvm_get(false_value), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_truncate(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildTrunc(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_zero_extend(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildZExt(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_sign_extend(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildSExt(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_pointer_to_int(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildPtrToInt(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_int_to_pointer(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildIntToPtr(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }
int32_t emerald_llvm_build_bit_cast(int32_t builder, int32_t value, int32_t type, EmeraldString *label) { return emerald_llvm_store(LLVMBuildBitCast(emerald_llvm_get(builder), emerald_llvm_get(value), emerald_llvm_get(type), emerald_llvm_text(label))); }

int32_t emerald_llvm_const_integer_text(int32_t type, EmeraldString *text) {
    return emerald_llvm_store(LLVMConstInt(emerald_llvm_get(type), (uint64_t) emerald_string_to_int64(text), 1));
}
int32_t emerald_llvm_const_float_text(int32_t type, EmeraldString *text) {
    const char *literal = emerald_llvm_text(text);
    char *end;
    errno = 0;
    double parsed = strtod(literal, &end);
    if (*end != '\0' || !isfinite(parsed)) emerald_number_fail("invalid or overflowing Float literal");
    return emerald_llvm_store(LLVMConstRealOfStringAndSize(emerald_llvm_get(type), literal, (unsigned) text->length));
}
int32_t emerald_llvm_build_extract_value(int32_t builder, int32_t value, int32_t index, EmeraldString *name) {
    return emerald_llvm_store(LLVMBuildExtractValue(emerald_llvm_get(builder), emerald_llvm_get(value), (unsigned) index, emerald_llvm_text(name)));
}
int32_t emerald_llvm_build_float_operation(int32_t builder, int32_t left, int32_t right, int32_t operation, EmeraldString *name) {
    LLVMBuilderRef b = emerald_llvm_get(builder);
    LLVMValueRef l = emerald_llvm_get(left);
    LLVMValueRef r = emerald_llvm_get(right);
    const char *n = emerald_llvm_text(name);
    LLVMValueRef result;
    switch (operation) {
    case 0: result = LLVMBuildFAdd(b, l, r, n); break;
    case 1: result = LLVMBuildFSub(b, l, r, n); break;
    case 2: result = LLVMBuildFMul(b, l, r, n); break;
    case 3: result = LLVMBuildFDiv(b, l, r, n); break;
    case 4: result = LLVMBuildFRem(b, l, r, n); break;
    case 5: result = LLVMBuildFCmp(b, LLVMRealOLT, l, r, n); break;
    case 6: result = LLVMBuildFCmp(b, LLVMRealOLE, l, r, n); break;
    case 7: result = LLVMBuildFCmp(b, LLVMRealOGT, l, r, n); break;
    case 8: result = LLVMBuildFCmp(b, LLVMRealOGE, l, r, n); break;
    case 9: result = LLVMBuildFCmp(b, LLVMRealOEQ, l, r, n); break;
    case 10: result = LLVMBuildFCmp(b, LLVMRealUNE, l, r, n); break;
    case 11: result = LLVMBuildSIToFP(b, l, emerald_llvm_get(right), n); break;
    case 12: result = LLVMBuildFNeg(b, l, n); break;
    default: emerald_number_fail("invalid Float operation"); return 0;
    }
    return emerald_llvm_store(result);
}
