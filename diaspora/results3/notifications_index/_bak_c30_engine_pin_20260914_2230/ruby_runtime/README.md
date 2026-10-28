# ruby_runtime — Ruby Concolic Runtime

## What is this?

A drop-in symbolic runtime that wraps `Integer` and `String` to track **path
conditions** (branch decisions) during execution. The Ruby counterpart of
`py_runtime` — same design, same RunDump JSON schema.

## Usage

### 1. Replace your variables with symbolic types

```ruby
require_relative "path_condition"
require_relative "base"
require_relative "int"
require_relative "string"

# Before:
x = 5
s = "hello"

# After:
x = SymbolicInt.new(5, name: "x")
s = SymbolicString.new("hello", name: "s")
```

### 2. Declare target methods

Target functions mark the **boundary between application logic and external
systems** (DB queries, API calls, JWT verification). Two forms:

#### Form A — body executes, return becomes symbolic

```ruby
interceptor = CallInterceptor.instance
interceptor.declare_target(MyRepository, :query_by_id)
```

The real method body runs, but the return value is wrapped as symbolic.

#### Form B — body skipped, lambda provides the return

For pure declarations where the method body is meaningless. The lambda receives
`(call_args_hash, result_name_string)` and returns a concrete value.

```ruby
interceptor.declare_target(
  ChatRepository, :check_session_access,
  returns: ->(args, name) { 0 }
)

interceptor.declare_target(
  ChatRepository, :get_chat_detail,
  returns: ->(args, name) { args["found"] ? [1, "Int"] : [0, "Int"] }
)
```

For explicit sort control, return a `[value, sort]` array.

### 3. Wrap the call in `interceptor.run()`

```ruby
dump = interceptor.run(
  ->(session_id:, auth_type:, **) { source_method(session_id, auth_type) },
  { session_id: "test", auth_type: "jwt" },
  label: "run-1",
  script: "optional inline source string"
)
```

`dump` is a JSON-serializable Hash that the concolic engine can consume.

### 4. Use the interceptor in RSpec or standalone scripts

```ruby
require_relative "call_interceptor"
require_relative "base"

interceptor = CallInterceptor.instance

# Declare targets
interceptor.declare_target(SomeRepository, :query, returns: ->(args, name) { 0 })

# Define entrypoint as a Proc
entrypoint = ->(user_id:) do
  result = SomeRepository.new.query(user_id)
  if result
    "found"
  else
    "not_found"
  end
end

# Each run: reset state, call run(), collect dump
SymbolicVar.clear_path_conditions
SymbolicFunc.reset!
old_count = interceptor.calls.size

dump = interceptor.run(entrypoint, { user_id: "abc" }, label: "run_x")
```

## The RunDump JSON Schema

Every `interceptor.run()` produces a dict matching the engine's `Run` schema:

```json
{
  "schema_version": "1.0",
  "label": "run-1",
  "symbolic_vars": [
    {"name": "user_id", "sort": "String", "value": "abc"}
  ],
  "events": [
    {"type": "path_condition", "expr": "(result != 0)", "taken": true, ...},
    {"type": "call", "target": "SomeRepository.query", "args": {...}, ...},
    {"type": "symbolic_call", "target": "SomeRepository.query",
     "result_name": "SYM_RESULT_SomeRepository.query_1",
     "result_value": 0, "result_sort": "Int", ...}
  ],
  "symbolic_results": [
    {"name": "SYM_RESULT_SomeRepository.query_1", "sort": "Int", "value": 0}
  ],
  "script": "optional inline source for reproducibility"
}
```

## What works

- **SymbolicInt**: `==`, `!=`, `<`, `>`, `<=`, `>=` record path conditions.
- **SymbolicString**: only `==` and `!=` record path conditions.
- **CallInterceptor**: captures the PC stack at call time and emits a RunDump.
- **`declare_target`**: `returns:` keyword for body-skip lambda mode.
- **`wrap_target`**: deprecated, delegates to `declare_target`.
- **`script` field**: optional source embedded in the dump for reproducibility.

## What doesn't

- **Arithmetic** on `SymbolicInt` returns plain `Integer` (loses symbolic tracking).
  Workaround: declare symbolic vars upfront, use them only in comparisons.
- **String methods** (`.downcase`, `.start_with?`, etc.) are not intercepted.
  Workaround: use only `==`/`!=` comparisons with string literals.
- **Arrays/hashes** are not tracked symbolically. Return `0`/`1` from targets
  to model truthy/falsy branching.

## Running in RSpec

```ruby
require_relative "path/to/call_interceptor"

RSpec.describe "concolic coverage" do
  it "explores all branches" do
    interceptor = CallInterceptor.instance
    interceptor.declare_target(SomeRepository, :query, returns: ->(args, name) { 0 })

    dump = interceptor.run(
      ->(user_id:) { MyService.new.call(user_id) },
      { user_id: "abc" },
      label: "test-1"
    )

    # Write dump to JSON for the CoverageChecker
    File.write("dump_test-1.json", JSON.pretty_generate(dump))
  end
end
```

## Summary

Three steps: import symbolic types → declare targets with `declare_target()` →
wrap call in `run()`. Everything else (PC recording, JSON output) is automatic.