#ifndef EMERALD_RUNTIME_H
#define EMERALD_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EmeraldString {
    uint64_t length;
    uint8_t *bytes;
} EmeraldString;

typedef struct EmeraldList {
    uint64_t length;
    uint64_t capacity;
    void **items;
    void *scratch;
    uint64_t element_size;
    int32_t element_mode;
} EmeraldList;

void emerald_flow_init(void);
void emerald_flow_shutdown(void);
void *emerald_flow_alloc(uint64_t size);
void *emerald_flow_alloc_atomic(uint64_t size);
void emerald_flow_register_static_strings(EmeraldString *const *values, uint64_t count);
void *emerald_flow_bond_alloc(uint64_t size);
void *emerald_flow_bond_promote(void *memory);
void emerald_flow_bond_retain(void *memory);
void emerald_flow_bond_release(void *memory);
uint64_t emerald_flow_bond_allocation_count(void);
uint64_t emerald_flow_bond_promotion_count(void);
uint64_t emerald_flow_bond_retain_count(void);
uint64_t emerald_flow_bond_release_count(void);
uint64_t emerald_flow_bond_live_count(void);
uint64_t emerald_flow_bond_cycle_scan_count(void);
uint64_t emerald_flow_bond_cycle_collection_count(void);
uint64_t emerald_flow_bond_cycle_collected_count(void);
uint64_t emerald_flow_bond_cycle_collected_bytes(void);
void emerald_flow_owner_enter(void *owner);
void emerald_object_set_class(void *object, int32_t tag);
int32_t emerald_object_class(void *object);
void emerald_flow_owner_leave(void *owner);
void emerald_flow_owner_reset(void *owner);
void *emerald_flow_root_detach(void *owner, void *child);
void emerald_flow_root_adopt(void *owner, void *child);
void emerald_flow_share_borrowed(void *memory);
void emerald_flow_root_replace(void *owner, void *previous, void *next);
void emerald_flow_root_release(void *memory);
uint64_t emerald_flow_root_release_count(void);
uint64_t emerald_flow_root_released_bytes(void);
uint64_t emerald_flow_root_adoption_count(void);
uint64_t emerald_flow_root_shared_fallback_count(void);
void *emerald_flow_pool_acquire(uint64_t site_id, uint64_t size);
void emerald_flow_thread_shutdown(void);
uint64_t emerald_flow_pool_slot_count(void);
uint64_t emerald_flow_pool_reuse_count(void);
uint64_t emerald_flow_shard_begin(void);
void *emerald_flow_shard_alloc(uint64_t size);
void emerald_flow_shard_register_owner(void *owner);
void emerald_flow_shard_end(uint64_t token);
uint64_t emerald_flow_shard_chunk_count(void);
uint64_t emerald_flow_shard_reuse_count(void);
uint64_t emerald_flow_shard_reset_count(void);
uint64_t emerald_flow_allocation_count(void);
uint64_t emerald_flow_allocated_bytes(void);
uint64_t emerald_flow_peak_allocation_count(void);
uint64_t emerald_flow_peak_allocated_bytes(void);
uint64_t emerald_flow_invalid_release_count(void);
uint64_t emerald_flow_container_owned_adoption_count(void);
uint64_t emerald_flow_container_owned_release_count(void);
uint64_t emerald_flow_container_inline_copy_count(void);
void *emerald_alloc(uint64_t size);
void *emerald_alloc_atomic(uint64_t size);

int64_t emerald_string_hash_int64(EmeraldString *text);
int64_t emerald_hash_int64(int64_t value);
int64_t emerald_hash_float64(double value);
int64_t emerald_hash_pointer(const void *value);
int64_t emerald_int64_add(int64_t a, int64_t b);
int64_t emerald_int64_sub(int64_t a, int64_t b);
int64_t emerald_int64_mul(int64_t a, int64_t b);
int64_t emerald_int64_div(int64_t a, int64_t b);
int64_t emerald_int64_rem(int64_t a, int64_t b);
int64_t emerald_int64_neg(int64_t a);
int32_t emerald_int64_to_int32_checked(int64_t value);
EmeraldString *emerald_int64_to_string(int64_t value);
int64_t emerald_string_to_int64(EmeraldString *value);
EmeraldString *emerald_float64_to_string(double value);
int64_t emerald_float64_to_int(double value);
EmeraldString *emerald_string_new(const uint8_t *bytes, uint64_t length);
EmeraldString *emerald_string_from_cstr(const char *text);
EmeraldString *emerald_static_string_from_cstr(const char *text);
EmeraldString *emerald_string_concat(EmeraldString *left, EmeraldString *right);
int32_t emerald_string_equals(EmeraldString *left, EmeraldString *right);
int32_t emerald_string_length(EmeraldString *value);
int32_t emerald_string_starts_with(EmeraldString *value, EmeraldString *prefix);
int32_t emerald_string_ends_with(EmeraldString *value, EmeraldString *suffix);
int32_t emerald_string_contains(EmeraldString *value, EmeraldString *needle);
EmeraldString *emerald_string_replace(EmeraldString *value, EmeraldString *needle, EmeraldString *replacement);
EmeraldString *emerald_string_substring(EmeraldString *value, int32_t start, int32_t end);
int32_t emerald_string_index_of(EmeraldString *value, EmeraldString *needle);
EmeraldList *emerald_string_split(EmeraldString *value, EmeraldString *delimiter);
EmeraldString *emerald_string_trim(EmeraldString *value);
int64_t emerald_string_last_index_of(EmeraldString *value, EmeraldString *needle);
EmeraldString *emerald_string_repeat(EmeraldString *value, int64_t count);
EmeraldString *emerald_string_trim_start(EmeraldString *value);
EmeraldString *emerald_string_trim_end(EmeraldString *value);
int32_t emerald_string_is_blank(EmeraldString *value);
int64_t emerald_string_compare(EmeraldString *left, EmeraldString *right);
EmeraldString *emerald_string_join(EmeraldList *parts, EmeraldString *separator);
int32_t emerald_int64_to_char(int64_t value);
EmeraldString *emerald_string_to_lower(EmeraldString *value);
EmeraldString *emerald_string_to_upper(EmeraldString *value);
int32_t emerald_string_to_int(EmeraldString *value);
int32_t emerald_string_char_at(EmeraldString *value, int32_t index);
EmeraldString *emerald_char_to_string(int32_t value);
int32_t emerald_char_is_digit(int32_t value);
int32_t emerald_char_is_letter(int32_t value);
int32_t emerald_char_is_whitespace(int32_t value);
EmeraldString *emerald_int_to_string(int32_t value);

EmeraldList *emerald_list_new(void);
EmeraldList *emerald_list_new_typed(int32_t element_mode, uint64_t element_size);
int32_t emerald_list_length(EmeraldList *list);
void emerald_list_add(EmeraldList *list, void *value);
void *emerald_list_get(EmeraldList *list, int32_t index);
void emerald_list_get_into(EmeraldList *list, int32_t index, void *output);
void emerald_list_set(EmeraldList *list, int32_t index, void *value);
void emerald_list_add_at(EmeraldList *list, int32_t index, void *value);
int32_t emerald_list_remove(EmeraldList *list, void *value);
void *emerald_list_remove_at(EmeraldList *list, int32_t index);
void emerald_list_remove_at_into(EmeraldList *list, int32_t index, void *output);
int32_t emerald_list_index_of(EmeraldList *list, void *value);
int32_t emerald_list_index_of_string(EmeraldList *list, EmeraldString *value);
int32_t emerald_list_remove_string(EmeraldList *list, EmeraldString *value);
void emerald_list_clear(EmeraldList *list);

void emerald_print(EmeraldString *value);
void emerald_println(EmeraldString *value);
void emerald_panic(EmeraldString *message);


void emerald_console_error_line(EmeraldString *value);
EmeraldString *emerald_console_read_line(void);

int32_t emerald_file_exists(EmeraldString *path);
int32_t emerald_file_is_file(EmeraldString *path);
EmeraldString *emerald_file_read_text(EmeraldString *path);
EmeraldList *emerald_file_read_lines(EmeraldString *path);
void emerald_file_write_text(EmeraldString *path, EmeraldString *text);
void emerald_file_append_text(EmeraldString *path, EmeraldString *text);
int32_t emerald_file_delete(EmeraldString *path);
int32_t emerald_file_size(EmeraldString *path);

int32_t emerald_directory_exists(EmeraldString *path);
int32_t emerald_directory_create(EmeraldString *path);
int32_t emerald_directory_delete(EmeraldString *path);
EmeraldList *emerald_directory_list(EmeraldString *path);

EmeraldString *emerald_path_current(void);
EmeraldString *emerald_path_join(EmeraldString *left, EmeraldString *right);
EmeraldString *emerald_path_parent(EmeraldString *path);
EmeraldString *emerald_path_file_name(EmeraldString *path);
EmeraldString *emerald_path_extension(EmeraldString *path);

EmeraldString *emerald_env_get(EmeraldString *name);
EmeraldString *emerald_env_get_or(EmeraldString *name, EmeraldString *fallback);
int32_t emerald_env_has(EmeraldString *name);
EmeraldString *emerald_env_current_directory(void);
EmeraldList *emerald_env_args(void);
int32_t emerald_time_monotonic_millis(void);
int64_t emerald_time_monotonic_nanos(void);
int64_t emerald_time_unix_millis(void);
int64_t emerald_time_local_offset_minutes(int64_t unix_seconds);
void emerald_time_sleep_millis(int64_t millis);
int64_t emerald_random_next(void);

EmeraldString *emerald_process_command(void);
void emerald_process_set_args(int32_t argc, char **argv);
EmeraldList *emerald_process_args(void);
void emerald_process_exit(int32_t code);

EmeraldString *emerald_system_os(void);
int32_t emerald_system_is_windows(void);
int32_t emerald_system_is_linux(void);
EmeraldString *emerald_system_line_separator(void);
EmeraldString *emerald_system_path_separator(void);
EmeraldString *emerald_system_directory_separator(void);
EmeraldString *emerald_system_arch(void);
int32_t emerald_system_processor_count(void);
EmeraldString *emerald_system_user_name(void);
EmeraldString *emerald_system_host_name(void);
EmeraldString *emerald_system_home_directory(void);
EmeraldString *emerald_system_temp_directory(void);

int32_t emerald_tcp_connect(EmeraldString *host, int32_t port);
int32_t emerald_tcp_listen(EmeraldString *host, int32_t port);
int32_t emerald_tcp_is_open(int32_t handle);
int32_t emerald_tcp_listener_is_open(int32_t handle);
int32_t emerald_tcp_listener_port(int32_t handle);
EmeraldString *emerald_tcp_read_text(int32_t handle);
EmeraldString *emerald_tcp_read_line(int32_t handle);
int32_t emerald_tcp_write_text(int32_t handle, EmeraldString *text);
int32_t emerald_tcp_close(int32_t handle);
int32_t emerald_tcp_accept(int32_t handle);
int32_t emerald_tcp_close_listener(int32_t handle);

int32_t emerald_udp_bind(EmeraldString *host, int32_t port);
int32_t emerald_udp_is_open(int32_t handle);
int32_t emerald_udp_local_port(int32_t handle);
int32_t emerald_udp_send_text(int32_t handle, EmeraldString *host, int32_t port, EmeraldString *text);
EmeraldString *emerald_udp_receive_text(int32_t handle);
EmeraldString *emerald_udp_last_sender_host(int32_t handle);
int32_t emerald_udp_last_sender_port(int32_t handle);
int32_t emerald_udp_close(int32_t handle);

int32_t emerald_ui_init(void);
EmeraldString *emerald_ui_backend(void);
int32_t emerald_ui_create_window(EmeraldString *title, int32_t width, int32_t height);
int32_t emerald_ui_set_html(int32_t handle, EmeraldString *html);
int32_t emerald_ui_set_title(int32_t handle, EmeraldString *title);
int32_t emerald_ui_is_open(int32_t handle);
EmeraldString *emerald_ui_poll_action(int32_t handle);
int32_t emerald_ui_show(int32_t handle);
int32_t emerald_ui_close(int32_t handle);
int32_t emerald_ui_pump(void);
int32_t emerald_ui_run(void);

#ifdef EMERALD_RUNTIME_ENABLE_LLVM
typedef struct EmeraldLlvmListObject {
    EmeraldList *items;
} EmeraldLlvmListObject;

int32_t emerald_llvm_initialize_native_target(void);
int32_t emerald_llvm_initialize_target(EmeraldString * value0);
EmeraldString * emerald_llvm_default_target_triple(void);
EmeraldString * emerald_llvm_normalize_target_triple(EmeraldString * value0);
int32_t emerald_llvm_lookup_target(EmeraldString * value0);
EmeraldString * emerald_llvm_last_error(void);
EmeraldString * emerald_llvm_native_object_extension(void);
EmeraldString * emerald_llvm_native_executable_extension(void);
EmeraldString * emerald_llvm_target_name(int32_t value0);
EmeraldString * emerald_llvm_target_description(int32_t value0);
int32_t emerald_llvm_create_target_machine(int32_t value0, EmeraldString * value1, EmeraldString * value2, EmeraldString * value3, int32_t value4);
void emerald_llvm_dispose_target_machine(int32_t value0);
int32_t emerald_llvm_target_machine_apply_data_layout(int32_t value0, int32_t value1);
int32_t emerald_llvm_target_machine_emit_object_file(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_target_machine_emit_assembly_file(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_run_passes(int32_t value0, EmeraldString * value1);
int32_t emerald_llvm_link_executable(EmeraldString * value0, EmeraldLlvmListObject * value1, EmeraldLlvmListObject * value2, EmeraldLlvmListObject * value3, EmeraldLlvmListObject * value4);
EmeraldString * emerald_llvm_linker_last_command(void);
EmeraldString * emerald_llvm_linker_last_output(void);
EmeraldString * emerald_llvm_linker_last_error(void);
EmeraldString * emerald_llvm_runtime_source_path(void);
EmeraldString * emerald_llvm_runtime_header_path(void);
int32_t emerald_llvm_compile_ir_object(EmeraldString *source, EmeraldString *output, EmeraldLlvmListObject *extra_args);
int32_t emerald_llvm_compile_runtime_object(EmeraldString * value0, EmeraldString * value1, EmeraldLlvmListObject * value2);
EmeraldString * emerald_llvm_runtime_flow_library_name(void);
EmeraldString * emerald_llvm_runtime_flow_library_path(void);
EmeraldString * emerald_llvm_runtime_last_command(void);
EmeraldString * emerald_llvm_runtime_last_output(void);
EmeraldString * emerald_llvm_runtime_last_error(void);
int32_t emerald_llvm_create_context(void);
void emerald_llvm_dispose_context(int32_t value0);
int32_t emerald_llvm_create_module(int32_t value0, EmeraldString * value1);
void emerald_llvm_dispose_module(int32_t value0);
void emerald_llvm_module_set_target(int32_t value0, EmeraldString * value1);
EmeraldString * emerald_llvm_module_to_ir(int32_t value0);
int32_t emerald_llvm_module_write_ir(int32_t value0, EmeraldString * value1);
int32_t emerald_llvm_module_verify(int32_t value0);
EmeraldString * emerald_llvm_module_verify_message(int32_t value0);
int32_t emerald_llvm_create_builder(int32_t value0);
void emerald_llvm_dispose_builder(int32_t value0);
int32_t emerald_llvm_current_block(int32_t value0);
int32_t emerald_llvm_void_type(int32_t value0);
int32_t emerald_llvm_i1_type(int32_t value0);
int32_t emerald_llvm_i8_type(int32_t value0);
int32_t emerald_llvm_i16_type(int32_t value0);
int32_t emerald_llvm_i32_type(int32_t value0);
int32_t emerald_llvm_i64_type(int32_t value0);
int32_t emerald_llvm_int_type(int32_t value0, int32_t value1);
int32_t emerald_llvm_float_type(int32_t value0);
int32_t emerald_llvm_double_type(int32_t value0);
int32_t emerald_llvm_opaque_pointer_type(int32_t value0);
int32_t emerald_llvm_pointer_type(int32_t value0);
int32_t emerald_llvm_array_type(int32_t value0, int32_t value1);
int32_t emerald_llvm_struct_type(int32_t value0, EmeraldLlvmListObject * value1, int32_t value2);
int32_t emerald_llvm_named_struct_type(int32_t value0, EmeraldString * value1);
void emerald_llvm_struct_set_body(int32_t value0, EmeraldLlvmListObject * value1, int32_t value2);
int32_t emerald_llvm_function_type(int32_t value0);
int32_t emerald_llvm_function_type_with_params(int32_t value0, EmeraldLlvmListObject * value1, int32_t value2);
EmeraldString * emerald_llvm_type_to_ir(int32_t value0);
int32_t emerald_llvm_size_of(int32_t value0);
int32_t emerald_llvm_align_of(int32_t value0);
int32_t emerald_llvm_add_function(int32_t value0, EmeraldString * value1, int32_t value2);
int32_t emerald_llvm_get_function(int32_t value0, EmeraldString * value1);
int32_t emerald_llvm_function_parameter_count(int32_t value0);
int32_t emerald_llvm_function_parameter(int32_t value0, int32_t value1);
int32_t emerald_llvm_append_block(int32_t value0, int32_t value1, EmeraldString * value2);
EmeraldString * emerald_llvm_block_name(int32_t value0);
int32_t emerald_llvm_add_global(int32_t value0, EmeraldString * value1, int32_t value2);
int32_t emerald_llvm_get_global(int32_t value0, EmeraldString * value1);
void emerald_llvm_global_set_initializer(int32_t value0, int32_t value1);
void emerald_llvm_global_set_constant(int32_t value0, int32_t value1);
void emerald_llvm_value_set_linkage(int32_t value0, int32_t value1);
int32_t emerald_llvm_value_type(int32_t value0);
EmeraldString * emerald_llvm_value_name(int32_t value0);
void emerald_llvm_value_set_name(int32_t value0, EmeraldString * value1);
EmeraldString * emerald_llvm_value_to_ir(int32_t value0);
void emerald_llvm_position_at_end(int32_t value0, int32_t value1);
void emerald_llvm_return_void(int32_t value0);
void emerald_llvm_return_value(int32_t value0, int32_t value1);
int32_t emerald_llvm_build_branch(int32_t value0, int32_t value1);
int32_t emerald_llvm_build_conditional_branch(int32_t value0, int32_t value1, int32_t value2, int32_t value3);
int32_t emerald_llvm_build_unreachable(int32_t value0);
int32_t emerald_llvm_const_integer_text(int32_t type, EmeraldString *text);
int32_t emerald_llvm_const_float_text(int32_t type, EmeraldString *text);
int32_t emerald_llvm_build_extract_value(int32_t builder, int32_t value, int32_t index, EmeraldString *name);
int32_t emerald_llvm_build_float_operation(int32_t builder, int32_t left, int32_t right, int32_t operation, EmeraldString *name);
int32_t emerald_llvm_const_int(int32_t value0, int64_t value1);
int32_t emerald_llvm_const_bool(int32_t value0, int32_t value1);
int32_t emerald_llvm_const_null(int32_t value0);
int32_t emerald_llvm_const_pointer_null(int32_t value0);
int32_t emerald_llvm_const_string(int32_t value0, EmeraldString * value1, int32_t value2);
int32_t emerald_llvm_const_struct(int32_t value0, EmeraldLlvmListObject * value1, int32_t value2);
int32_t emerald_llvm_const_array(int32_t value0, EmeraldLlvmListObject * value1);
int32_t emerald_llvm_build_add(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_sub(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_mul(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_signed_div(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_unsigned_div(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_signed_rem(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_unsigned_rem(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_neg(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_build_and(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_or(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_xor(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_not(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_build_shift_left(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_logical_shift_right(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_arithmetic_shift_right(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_int_compare(int32_t value0, int32_t value1, int32_t value2, int32_t value3, EmeraldString * value4);
int32_t emerald_llvm_build_alloca(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_build_entry_alloca(int32_t value0, int32_t value1, EmeraldString * value2);
int32_t emerald_llvm_build_load(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_store(int32_t value0, int32_t value1, int32_t value2);
int32_t emerald_llvm_build_gep(int32_t value0, int32_t value1, int32_t value2, EmeraldLlvmListObject * value3, EmeraldString * value4);
int32_t emerald_llvm_build_inbounds_gep(int32_t value0, int32_t value1, int32_t value2, EmeraldLlvmListObject * value3, EmeraldString * value4);
int32_t emerald_llvm_build_global_string_pointer(int32_t value0, EmeraldString * value1, EmeraldString * value2);
int32_t emerald_llvm_build_call(int32_t value0, int32_t value1, int32_t value2, EmeraldLlvmListObject * value3, EmeraldString * value4);
int32_t emerald_llvm_build_phi(int32_t value0, int32_t value1, EmeraldString * value2);
void emerald_llvm_add_incoming(int32_t value0, int32_t value1, int32_t value2);
int32_t emerald_llvm_build_select(int32_t value0, int32_t value1, int32_t value2, int32_t value3, EmeraldString * value4);
int32_t emerald_llvm_build_truncate(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_zero_extend(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_sign_extend(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_pointer_to_int(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_int_to_pointer(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
int32_t emerald_llvm_build_bit_cast(int32_t value0, int32_t value1, int32_t value2, EmeraldString * value3);
#endif

#ifdef __cplusplus
}
#endif

#endif
