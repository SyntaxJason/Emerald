#!/usr/bin/env bash
# Run inside the capped selfhost sandbox; COMPILER can be any bootstrap stage.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPILER="$1"
OUTPUT="$2"
mkdir -p "$OUTPUT"
check() {
    local name="$1" expected="$2"
    timeout 60 "$COMPILER" build "$ROOT/tests/selfhost/language_features/$name.ems" -o "$OUTPUT/$name" --emit-ir > "$OUTPUT/$name.build.log" 2>&1
    timeout 15 "$OUTPUT/$name" > "$OUTPUT/$name.actual" 2> "$OUTPUT/$name.stderr"
    printf '%s\n' "$expected" > "$OUTPUT/$name.expected"
    diff -u "$OUTPUT/$name.expected" "$OUTPUT/$name.actual"
}
check float '2'
check inline_loop $'1999999000000\n5999997'
check math $'2\n0\n-0\n1e-20\n1e+20\ntrue\n1024\n3.5\n-3\n-2\n-3\n0\n1\n0\n0\n2\n1\n4000000000\n5'
check float_remainder $'1.5\n-1.5'
check float_format $'0.1\n0.30000000000000004\n0.3333333333333333\n100\n2.5e-07\n10000000000000000\n0.1|'
check read_lines $'4\na|b||c\n0\n0'
check integer_edges $'0\n-9223372036854775808\n-1\n-1\n1\n-2\n-2\n9223372030926249001'
check empty_string_builtins $'true\ntrue\n9\nword\ntrue\nwordvalue\n2\nw'
check int '4000000000'
check map '42'
check lambda 'Ada'
check long_concat 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
check llvm_numbers $'i64 4000000000\ni64 -9223372036854775808'
check numbers $'4000000000\n9223372036854775807\n-9223372036854775808\n4000000000\n4000000000\n-5000000000\n5\n62.5\n-2\n3.5\n3\ntrue\n2.5\n-3.75\n2'
check collections $'200\n8000000000\nfalse\n8000000000\nfalse\n-5000000000\n199\n4000000199\nkey0\n4000000000\ntrue\n7000000000\nwide-key'
# Root chains built by tail appends must build in linear time (timeout guarded).
check deep_linked_list $'44999850000\n44999850000'
check callbacks $'Ada\nGrace\nhello Ada\nhello Grace\ntrue\nfalse\ncaptured: Ada\ntrue\nfalse\n6000000000\ncaptured: '
check virtual_dispatch $'I say generic\nI say Woof\nI say Yip\nI say generic\n1\n2\n<Bird>\n1000'
check custom_ilist $'3\n43\ntrue\n2\n7\n129\n12'
check typed_lists $'4000000007\n0\n5\n9\ntrue\nfalse\n7\nm\ntrue\ntrue\ncd'
check data_class_scalars $'true\nfalse\ntrue\nfalse\nLetter { value: q, count: 3 }'
# Codegen shape: IR is built against the target data layout (no
# under-aligned i64 accesses), definitions are module-internal and raw generic
# templates are not emitted.
grep -Fq 'target datalayout' "$OUTPUT/typed_lists.ll"
if grep -Eq 'i64 .*, align 4$' "$OUTPUT/typed_lists.ll"; then echo "Under-aligned i64 access in typed_lists.ll"; exit 1; fi
grep -Fq 'define internal' "$OUTPUT/virtual_dispatch.ll"
if grep -Fq 'ArrayList<T>' "$OUTPUT/custom_ilist.ll"; then echo "Raw generic template emitted in custom_ilist.ll"; exit 1; fi
check hash_collections $'334\n1998\nfalse\n0\n3\n999\n1\n1\n0\n2\n1\n1\n2\nv5\ntrue\nfalse\ntrue\nfalse\n0'
check comparators_time $'-1\n1\n0\n1\n-1\n2023-11-14T23:13:20+01:00\n1969-12-31T23:59:59+00:00\n2000-02-29T00:00:00+00:00\ntrue\ntrue\ntrue\ntrue\n0'
check text_builder $'60008\n60008\nab0ab1\n60009\ntrue\n0\na-b-c\n4\n-1\nababab\n0\nx |\n  x|\ntrue\nfalse\n-1\n1\n0\n-1\n65\nB'
check deque_heap $'100\nf49\nb49\n0\n40\nf19\ns0\ns1\n999\n9\n8\ntrue\n9\n3\n1'
check_example() {
    local name="$1" expected="$2"
    timeout 60 "$COMPILER" build "$ROOT/examples/$name.ems" -o "$OUTPUT/$name" --emit-ir > "$OUTPUT/$name.build.log" 2>&1
    timeout 15 "$OUTPUT/$name" > "$OUTPUT/$name.actual" 2> "$OUTPUT/$name.stderr"
    printf '%s\n' "$expected" > "$OUTPUT/$name.expected"
    diff -u "$OUTPUT/$name.expected" "$OUTPUT/$name.actual"
}
check_example 41_stdlib_functional_foundation $'lambda\nemerald\nstdlib\nlambda-id\ntrue\ntrue\n-1\n7\nnew\nstart\ntrue\nanswer\n42'
check_example 43_stdlib_collections $'Ada\nGrace\nLinus\nGrace\nAda\nGrace\nLinus\n36\n0\n2\nAda\n36\nAda36\nGrace85\ntrue\nfalse\ntrue\ncompiler\ntrue\ntrue'
for name in overflow_add overflow_sub overflow_mul overflow_div overflow_neg zero_div invalid_int invalid_int_space overflow_float; do
    timeout 60 "$COMPILER" build "$ROOT/tests/selfhost/language_features/$name.ems" -o "$OUTPUT/$name" > "$OUTPUT/$name.build.log" 2>&1
    set +e
    timeout 15 "$OUTPUT/$name" > "$OUTPUT/$name.actual" 2> "$OUTPUT/$name.stderr"
    rc=$?
    set -e
    [[ "$rc" == 1 ]] || { echo "Expected numeric failure for $name, got $rc"; exit 1; }
    grep -Fq 'Emerald numeric error:' "$OUTPUT/$name.stderr"
done
timeout 60 "$COMPILER" build "$ROOT/tests/selfhost/language_features/list_bounds.ems" -o "$OUTPUT/list_bounds" > "$OUTPUT/list_bounds.build.log" 2>&1
set +e
timeout 15 "$OUTPUT/list_bounds" > "$OUTPUT/list_bounds.actual" 2> "$OUTPUT/list_bounds.stderr"
rc=$?
set -e
[[ "$rc" != 0 && "$rc" != 124 ]] || { echo "Expected List bounds panic, got $rc"; exit 1; }
[[ "$(cat "$OUTPUT/list_bounds.actual")" == 7 ]] || { echo "Output before List bounds panic was not flushed"; exit 1; }
grep -Eq 'index 1 (is )?out of bounds for length 1' "$OUTPUT/list_bounds.stderr"
for name in invalid_literal invalid_lambda reassigned_capture invalid_generic invalid_lambda_return invalid_index; do
    set +e
    timeout 60 "$COMPILER" build "$ROOT/tests/selfhost/language_features/$name.ems" -o "$OUTPUT/$name" > "$OUTPUT/$name.build.log" 2>&1
    rc=$?
    set -e
    [[ "$rc" == 1 ]] || { echo "Expected clean compile failure for $name, got $rc"; exit 1; }
done
grep -Fq 'Int overflow' "$OUTPUT/invalid_literal.build.log"
grep -Fq 'Invalid lambda parameter count' "$OUTPUT/invalid_lambda.build.log"
grep -Fq 'Lambda capture must not be reassigned' "$OUTPUT/reassigned_capture.build.log"
grep -Fq 'Index expressions are not supported' "$OUTPUT/invalid_index.build.log"
echo 'language-features-tests-ok'
