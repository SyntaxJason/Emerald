#include "runtime/emerald_runtime.h"

#include <stdint.h>
#include <string.h>

static int emerald_string_matches(EmeraldString *value, const char *expected) {
    size_t length = strlen(expected);
    return value != NULL && value->length == length && memcmp(value->bytes, expected, length) == 0;
}

int main(void) {
    hyperalloc_flow_init();

    EmeraldString *source = emerald_string_from_cstr("4-2-2");
    EmeraldString *needle = emerald_string_from_cstr("-");
    EmeraldString *empty = emerald_string_from_cstr("");
    EmeraldString *replaced = emerald_string_replace(source, needle, empty);
    EmeraldString *slice_source = emerald_string_from_cstr("x42y");
    EmeraldString *slice = emerald_string_substring(slice_source, 1, 3);
    EmeraldString *index_source = emerald_string_from_cstr("x-42");
    int32_t index = emerald_string_index_of(index_source, needle);
    EmeraldString *split_source = emerald_string_from_cstr("4::2");
    EmeraldString *delimiter = emerald_string_from_cstr("::");
    EmeraldList *parts = emerald_string_split(split_source, delimiter);
    EmeraldString *trim_source = emerald_string_from_cstr("  42 \n");
    EmeraldString *trimmed = emerald_string_trim(trim_source);
    EmeraldString *case_source = emerald_string_from_cstr("AbC");
    EmeraldString *lower = emerald_string_to_lower(case_source);
    EmeraldString *upper = emerald_string_to_upper(case_source);
    EmeraldString *number_source = emerald_string_from_cstr("-42");
    int32_t number = emerald_string_to_int(number_source);
    int32_t digit = emerald_string_char_at(trimmed, 0);
    int32_t letter = emerald_string_char_at(case_source, 0);
    int32_t whitespace = emerald_string_char_at(trim_source, 0);
    EmeraldString *digit_text = emerald_char_to_string(digit);
    char *arguments[] = {"runtime-smoke", "emerald-selfhost", "42", NULL};
    emerald_process_set_args(3, arguments);
    EmeraldList *process_args = emerald_process_args();
    int result = emerald_string_matches(replaced, "422")
        && emerald_string_matches(slice, "42")
        && index == 1
        && emerald_list_length(parts) == 2
        && emerald_string_matches((EmeraldString *) emerald_list_get(parts, 0), "4")
        && emerald_string_matches((EmeraldString *) emerald_list_get(parts, 1), "2")
        && emerald_string_matches(trimmed, "42")
        && emerald_string_matches(lower, "abc")
        && emerald_string_matches(upper, "ABC")
        && number == -42
        && emerald_char_is_digit(digit)
        && emerald_char_is_letter(letter)
        && emerald_char_is_whitespace(whitespace)
        && emerald_string_matches(digit_text, "4")
        && emerald_list_length(process_args) == 2
        && emerald_string_matches((EmeraldString *) emerald_list_get(process_args, 0), "emerald-selfhost")
        && emerald_string_matches((EmeraldString *) emerald_list_get(process_args, 1), "42") ? 0 : 1;

    hyperalloc_flow_root_release(process_args);
    hyperalloc_flow_root_release(digit_text);
    hyperalloc_flow_root_release(number_source);
    hyperalloc_flow_root_release(upper);
    hyperalloc_flow_root_release(lower);
    hyperalloc_flow_root_release(case_source);
    hyperalloc_flow_root_release(trimmed);
    hyperalloc_flow_root_release(trim_source);
    hyperalloc_flow_root_release(parts);
    hyperalloc_flow_root_release(delimiter);
    hyperalloc_flow_root_release(split_source);
    hyperalloc_flow_root_release(index_source);
    hyperalloc_flow_root_release(slice);
    hyperalloc_flow_root_release(slice_source);
    hyperalloc_flow_root_release(replaced);
    hyperalloc_flow_root_release(empty);
    hyperalloc_flow_root_release(needle);
    hyperalloc_flow_root_release(source);
    hyperalloc_flow_shutdown();
    return result;
}
