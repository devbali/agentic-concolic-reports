# frozen_string_literal: true
# Mirror test for SymbolicList representative-element (Gate 1b).
# Run: ruby -I src/ruby_runtime src/ruby_runtime/test_list_rep.rb
require_relative "list"
require_relative "object"

failures = 0
def check(cond, msg)
  unless cond
    puts "FAIL: #{msg}"
    $failures = ($failures || 0) + 1
  end
end

# --- With a representative -------------------------------------------------
rep = symint("rep_x", 7)
l = symlist("x", 3, representative: rep)

check(l.first.equal?(rep), "first returns the representative")
check(l.last.equal?(rep), "last returns the representative")
check(l[0].equal?(rep), "[0] returns the representative")

# include? (membership) is NOT implemented by design — no Z3 PC support for
# membership — so it raises, even with a rep. Use element access l[0] == x.
begin
  l.include?(rep)
  check(false, "include? should raise (membership out of scope)")
rescue NotImplementedError
  check(true, "include? raises (membership out of scope)")
end

# each/map are NOT implemented (even with a rep) — contents out of scope;
# the representative only serves element access (first/[0]/include?).
%i[each map reject select find].each do |m|
  begin
    l.public_send(m) { |_| nil }
    check(false, "#{m} should raise (iteration out of scope)")
  rescue NotImplementedError
    check(true, "#{m} still raises (iteration out of scope)")
  end
end

# [i] for i > 0 raises (only one rep modeled).
begin
  l[1]
  check(false, "[1] should raise")
rescue NotImplementedError
  check(true, "[1] raises (single rep)")
end

# --- Back-compat: no representative -> element ops still raise -------------
empty = symlist("y", 0)
begin
  empty.first
  check(false, "back-compat: first should raise without rep")
rescue NotImplementedError
  check(true, "back-compat: first raises without rep")
end
begin
  empty.include?(1)
  check(false, "back-compat: include? should raise without rep")
rescue NotImplementedError
  check(true, "back-compat: include? raises without rep")
end
begin
  empty[0]
  check(false, "back-compat: [0] should raise without rep")
rescue NotImplementedError
  check(true, "back-compat: [0] raises without rep")
end
# rep-less lists still raise for each/map (back-compat).
%i[each map].each do |m|
  begin
    empty.public_send(m) { |_| nil }
    check(false, "back-compat: #{m} should raise without rep")
  rescue NotImplementedError
    check(true, "back-compat: #{m} raises without rep")
  end
end

# With a rep, iteration also still raises — the rep is element-access only.
begin
  l.each { |_| nil }
  check(false, "each with rep should raise (iteration out of scope)")
rescue NotImplementedError
  check(true, "each with rep raises (iteration out of scope)")
end

# --- Length/emptiness still symbolic (unchanged) ---------------------------
check(l.length.value == 3, "length still symbolic (value 3)")
check(l.empty? == false, "empty? still works")
check(l.concrete_length == 3, "concrete_length intact")

# --- Symfactory round-trip -------------------------------------------------
l2 = symlist("z", 2, representative: symint("zr", 9))
check(l2.first.value == 9, "symlist factory passes representative")

if ($failures || 0) == 0
  puts "ruby list rep OK (all checks passed)"
else
  puts "ruby list rep: #{$failures} FAILURES"
  exit 1
end
