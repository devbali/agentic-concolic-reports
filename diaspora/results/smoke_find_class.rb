# frozen_string_literal: true
#
# smoke_find_class.rb — temporary smoke test for the new Core::ClassMethods
# single-id finder targets (find / find_by / find_by!). NOT a batch runner.
#
# Run:  diaspora-concolic /abs/path/smoke_find_class.rb
#
# Exercises the real class-level form the app uses (Comment.find(1),
# Comment.find_by(id: 1), Comment.find_by!(id: 1)) and confirms they now
# return a symbolic single record instead of crashing on SymbolicList#first.

require "./config/environment"

require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/symbolic_func"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

def report(label, dump)
  ok = !dump["error"]
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }.size
  calls = dump["events"].select { |e| e["type"] == "symbolic_call" }
  targets = calls.map { |c| c["target"] }.uniq
  err = dump["error"]
  puts "== #{label}: #{ok ? 'OK' : 'ERROR'} | PCs=#{pcs} | targets=#{targets.inspect}" \
       + (err ? " | #{err['type']}: #{err['message'][0,90]}" : "")
end

# --- find (raise_on_missing) found branch ---
src_find = ->(id:) {
  begin
    c = Comment.find(id.value)
    c.class.name
  rescue ActiveRecord::RecordNotFound
    "not_found"
  end
}
report("find_found", $interceptor.run(src_find, { "id" => 1 }, label: "find_found"))

# --- find not-found branch (seeded) ---
nf_name = "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found"
ConcolicTargets.seed_overrides = { nf_name => true }
report("find_not_found", $interceptor.run(src_find, { "id" => 1 }, label: "find_not_found",
      script: "smoke: seed #{nf_name}=true"))
ConcolicTargets.seed_overrides = {}

# --- find_by (returns nil, not raises) ---
src_find_by = ->(id:) {
  c = Comment.find_by(id: id.value)
  c.nil? ? "nil" : c.class.name
}
report("find_by_nil", $interceptor.run(src_find_by, { "id" => 1 }, label: "find_by_nil"))

# --- find_by! (raises on missing) found branch ---
src_find_by_bang = ->(id:) {
  begin
    c = Comment.find_by!(id: id.value)
    c.class.name
  rescue ActiveRecord::RecordNotFound
    "not_found"
  end
}
report("find_by_bang_found", $interceptor.run(src_find_by_bang, { "id" => 1 }, label: "find_by_bang_found"))

puts "\nDONE"
