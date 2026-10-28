# frozen_string_literal: true

require_relative "ruby_runtime/path_condition"
require_relative "ruby_runtime/base"
require_relative "ruby_runtime/int"
require_relative "ruby_runtime/string"
require_relative "ruby_runtime/symbolic_func"
require_relative "ruby_runtime/call_interceptor"
require_relative "ruby_runtime/dict"
require "json"

$passed = 0
$failed = 0

def test(name)
  print "  #{name}... "
  begin
    yield
    puts "PASS"
    $passed += 1
  rescue Exception => e # NotImplementedError is a ScriptError, not StandardError
    puts "FAIL: #{e.class}: #{e.message}"
    $failed += 1
  end
end

def assert(condition, msg = "assertion failed")
  raise msg unless condition
end

def assert_equal(expected, actual, msg = nil)
  unless expected == actual
    raise msg || "expected #{expected.inspect}, got #{actual.inspect}"
  end
end

def assert_match(pattern, str, msg = nil)
  unless str.match?(pattern)
    raise msg || "expected #{str.inspect} to match #{pattern.inspect}"
  end
end

# ══════════════════════════════════════════════════════════════════════
# PathCondition
# ══════════════════════════════════════════════════════════════════════

test "PathCondition: construction" do
  pc = PathCondition.new(expr: "(x > 5)", op_name: ">", frame: ["test.rb", 42, "target"])
  assert_equal "(x > 5)", pc.expr
  assert_equal ">", pc.op_name
  assert_equal true, pc.taken
end

test "PathCondition: location" do
  pc = PathCondition.new(expr: "(x > 5)", op_name: ">", frame: ["test.rb", 42, "target"])
  assert_equal "test.rb:42 in target()", pc.location
end

test "PathCondition: to_dict / from_dict roundtrip" do
  pc = PathCondition.new(expr: "(x > 5)", op_name: ">", frame: ["test.rb", 42, "target"], taken: false)
  d = pc.to_dict
  pc2 = PathCondition.from_dict(d)
  assert_equal pc.expr, pc2.expr
  assert_equal pc.op_name, pc2.op_name
  assert_equal false, pc2.taken
end

# ══════════════════════════════════════════════════════════════════════
# SymbolicInt
# ══════════════════════════════════════════════════════════════════════

test "SymbolicInt: construction and name" do
  x = symint("x", 10)
  assert_equal 10, x.value
  assert_equal "x", x.sym_name
  y = SymbolicInt.new(42, name: "y")
  assert_equal 42, y.value
  assert_equal "y", y.sym_name
end

test "SymbolicInt: > records PC" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 10)
  result = x > 5
  assert_equal true, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(x > 5)", pcs[0].expr
  assert_equal true, pcs[0].taken
end

test "SymbolicInt: all 6 comparisons" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 10)
  assert_equal true, x > 5
  assert_equal true, x >= 10
  assert_equal true, x < 20
  assert_equal true, x <= 10
  assert_equal true, x == 10
  assert_equal true, x != 5
  pcs = SymbolicVar.get_path_conditions
  assert_equal 6, pcs.size
  pcs.each { |pc| assert_equal true, pc.taken }
end

test "SymbolicInt: false comparison" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 3)
  r = x > 10
  assert_equal false, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal false, pcs[0].taken
end

test "SymbolicInt: boolean context (zero?) — canonical (x != 0) expr" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 0)
  assert_equal true, x.zero?
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal false, pcs[0].taken # taken = non-zero, as in py __bool__
  assert_match(/!= 0/, pcs[0].expr)
end

test "SymbolicInt: arithmetic raises NotImplementedError (strict parity)" do
  x = symint("x", 10)
  y = symint("y", 3)
  [[:+, y], [:-, y], [:*, 3]].each do |op, rhs|
    begin
      x.send(op, rhs)
      raise "expected NotImplementedError for #{op}"
    rescue NotImplementedError
      # expected — loud failure instead of silent concretization
    end
  end
  begin
    1 + x # reflected — goes through coerce
    raise "expected NotImplementedError for coerce"
  rescue NotImplementedError
    # expected
  end
end

test "SymbolicInt: unary minus preserves symbolic tracking" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 3)
  neg = -x
  assert neg.is_a?(SymbolicInt)
  assert_equal(-3, neg.value)
  assert_equal "(- x)", neg.sym_name
  # Negated value still records a real PC when compared (tracking preserved)
  r = (neg == 0)
  pcs = SymbolicVar.get_path_conditions
  assert_equal false, r
  assert_equal 1, pcs.size
  assert_equal "((- x) == 0)", pcs[0].expr
end
test "SymbolicInt: unary minus on unnamed int uses concrete value" do
  SymbolicVar.clear_path_conditions
  x = SymbolicInt.new(7)
  neg = -x
  assert_equal(-7, neg.value)
  assert(neg.sym_name.nil?, "expected unnamed")
  r = (neg == -7)
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
end

test "SymbolicInt: source location tracked" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 100)
  x == 100
  pc = SymbolicVar.get_path_conditions[0]
  # The source should be a non-empty 3-element array
  assert pc.frame.is_a?(Array)
  assert_equal 3, pc.frame.size
  # At minimum the path is populated (lineno may be 0 in eval context)
  assert pc.frame[0].is_a?(String), "Expected file path string"
end

# ══════════════════════════════════════════════════════════════════════
# SymbolicString
# ══════════════════════════════════════════════════════════════════════

test "SymbolicString: construction" do
  s = symstr("s", "hello")
  assert_equal "hello", s.value
  assert_equal "s", s.sym_name
end

test "SymbolicString: == records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello")
  r = (s == "hello")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal true, pcs[0].taken
end

test "SymbolicString: != records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello")
  r = (s != "world")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal true, pcs[0].taken
end

test "SymbolicString: empty? records (s == '') PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello")
  r = s.empty?
  assert_equal false, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(s == '')", pcs[0].expr
  assert_equal false, pcs[0].taken
end

test "SymbolicString: empty? true when empty string" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "")
  r = s.empty?
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(s == '')", pcs[0].expr
  assert_equal true, pcs[0].taken
end

test "SymbolicString: start_with? records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello world")
  r = s.start_with?("hello")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_match(/PrefixOf/, pcs[0].expr)
end

test "SymbolicString: end_with? records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello world")
  r = s.end_with?("world")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_match(/SuffixOf/, pcs[0].expr)
end

test "SymbolicString: include? records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello world")
  r = s.include?("llo")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_match(/Contains/, pcs[0].expr)
end

test "SymbolicString: substring [] records SubString PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "hello")
  sub = s[0, 3]  # "hel"
  assert sub.is_a?(SymbolicSubstring)
  assert_equal "hel", sub.value
  r = (sub == "hel")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_match(/SubString/, pcs[0].expr)
  assert_match(/StringVal/, pcs[0].expr)
end

test "SymbolicString: double slice chains through parent" do
  SymbolicVar.clear_path_conditions
  s = symstr("s", "abcdef")
  sub1 = s[1, 4]   # "bcde"
  sub2 = sub1[1, 2] # "cd"
  assert_equal "cd", sub2.value
  r = (sub2 == "cd")
  assert_equal true, r
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  # Should reference parent with correct offset
  assert_match(/SubString\(s, 2, 2\)/, pcs[0].expr)
end

# ══════════════════════════════════════════════════════════════════════
# CallInterceptor
# ══════════════════════════════════════════════════════════════════════

test "CallInterceptor: basic interception" do
  # Use a Proc directly
  interceptor = CallInterceptor.new
  dump = interceptor.run(
    ->(x:) { x > 5 ? "big" : "small" },
    { "x" => 3 },
    label: "test",
  )

  assert_equal "test", dump["label"]
  assert_equal 1, dump["symbolic_vars"].size
  assert_equal "x", dump["symbolic_vars"][0]["name"]
  assert_equal 3, dump["symbolic_vars"][0]["value"]
  # One PC: (x > 5) = false
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  assert_equal 1, pcs.size
  assert_equal "(x > 5)", pcs[0]["expr"]
  assert_equal false, pcs[0]["taken"]
end

test "CallInterceptor: two run dumps independent" do
  interceptor = CallInterceptor.new

  dump1 = interceptor.run(
    ->(x:) { x > 0 ? "pos" : "neg" },
    { "x" => 5 },
    label: "run1",
  )
  dump2 = interceptor.run(
    ->(x:) { x > 0 ? "pos" : "neg" },
    { "x" => -1 },
    label: "run2",
  )

  pcs1 = dump1["events"].select { |e| e["type"] == "path_condition" }
  pcs2 = dump2["events"].select { |e| e["type"] == "path_condition" }

  assert_equal true,  pcs1[0]["taken"]
  assert_equal false, pcs2[0]["taken"]
end

test "CallInterceptor: string arguments" do
  interceptor = CallInterceptor.new
  dump = interceptor.run(
    ->(s:) { s == "admin" ? "granted" : "denied" },
    { "s" => "admin" },
    label: "str_test",
  )

  assert_equal "String", dump["symbolic_vars"][0]["sort"]
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  assert_equal 1, pcs.size
  assert_match(/== StringVal/, pcs[0]["expr"])
end

test "CallInterceptor: multiple comparisons" do
  interceptor = CallInterceptor.new
  dump = interceptor.run(
    ->(x:, y:) {
      if x > 0
        y > 5 ? "big" : "small"
      else
        "neg"
      end
    },
    { "x" => 10, "y" => 3 },
    label: "multi",
  )

  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  assert_equal 2, pcs.size  # x > 0 and y > 5
  assert_equal true,  pcs[0]["taken"]
  assert_equal false, pcs[1]["taken"]
end

test "CallInterceptor: wrap_target with class" do
  class TestTarget
    def validate(x)
      x > 10 ? "valid" : "invalid"
    end
  end

  interceptor = CallInterceptor.new
  interceptor.wrap_target(TestTarget, :validate)

  dump = interceptor.run(
    ->(x:) { TestTarget.new.validate(x) },
    { "x" => 15 },
    label: "wrap_test",
  )

  calls = dump["events"].select { |e| e["type"] == "call" }
  assert_equal 1, calls.size
  assert_equal "TestTarget.validate", calls[0]["target"]

  sym_calls = dump["events"].select { |e| e["type"] == "symbolic_call" }
  assert_equal 1, sym_calls.size
  assert_equal "TestTarget.validate", sym_calls[0]["target"]
  # Result names are Z3-sanitized (engine evals `name = Sort('name')`)
  assert_match(/SYM_RESULT_TestTarget_validate/, sym_calls[0]["result_name"])
end

test "CallInterceptor: JSON serializable" do
  interceptor = CallInterceptor.new
  dump = interceptor.run(
    ->(x:) { x > 5 ? 1 : 0 },
    { "x" => 10 },
    label: "json_test",
  )

  json_str = JSON.generate(dump)
  parsed = JSON.parse(json_str)
  assert_equal "json_test", parsed["label"]
  assert_equal 1, parsed["symbolic_vars"].size
end

test "SymbolicFunc: manual wrapping" do
  SymbolicFunc.reset!

  class TestHelper
    def get_role(user_id)
      1  # admin
    end
  end

  obj = TestHelper.new
  symbolic_func!(obj, :get_role)

  result = obj.get_role(42)
  assert result.is_a?(SymbolicInt)
  assert_equal 1, result.value
  assert_match(/SYM_RESULT_/, result.sym_name)

  records = SymbolicFunc.get_call_records
  assert_equal 1, records.size
  assert_equal "TestHelper#get_role", records[0].target_name
end

# ══════════════════════════════════════════════════════════════════════
# SymbolicBool / note / SymbolicList (query-ops runtime additions)
# ══════════════════════════════════════════════════════════════════════

require_relative "ruby_runtime/bool"
require_relative "ruby_runtime/list"

puts "\nSymbolicBool:"

test "SymbolicBool: == records PC" do
  SymbolicVar.clear_path_conditions
  b = SymbolicBool.new(false, name: "flag")
  result = (b == true)
  assert_equal false, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(flag == True)", pcs[0].expr
  assert_equal false, pcs[0].taken
end

test "SymbolicBool: != records PC" do
  SymbolicVar.clear_path_conditions
  b = SymbolicBool.new(true, name: "flag")
  result = (b != false)
  assert_equal true, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal true, pcs[0].taken
end

test "SymbolicBool: ! records PC (canonical (x == True) expr, parity with py __bool__)" do
  SymbolicVar.clear_path_conditions
  b = SymbolicBool.new(false, name: "flag")
  result = !b
  assert_equal true, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(flag == True)", pcs[0].expr
  assert_equal false, pcs[0].taken # taken = underlying value, as in Python
end

test "symbool factory registers var with note" do
  SymbolicFunc.reset!
  b = symbool("nf", false, note: "SELECT 1")
  assert b.is_a?(SymbolicBool)
  vars = SymbolicFunc.save_and_clear_registered_vars
  assert_equal 1, vars.size
  assert_equal "nf", vars[0]["name"]
  assert_equal "Bool", vars[0]["sort"]
  assert_equal "SELECT 1", vars[0]["note"]
end

puts "\nSymbolicList (length-only):"

test "SymbolicList: empty? records canonical length PC (parity with py __bool__)" do
  SymbolicVar.clear_path_conditions
  l = SymbolicList.new(0, name: "rows")
  assert_equal true, l.empty?
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(SYM_LEN_rows != 0)", pcs[0].expr
  assert_equal false, pcs[0].taken # taken = non-empty, as in Python
end

test "SymbolicList: length returns SymbolicInt; compare records PC" do
  SymbolicVar.clear_path_conditions
  l = SymbolicList.new(3, name: "rows")
  len = l.length
  assert len.is_a?(SymbolicInt)
  result = (len > 1)
  assert_equal true, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_match(/SYM_LEN_rows > 1/, pcs[0].expr)
end

test "SymbolicList: element access raises NotImplementedError" do
  l = SymbolicList.new(2, name: "rows")
  [:[], :first, :last, :each, :map].each do |m|
    begin
      m == :[] ? l[0] : l.send(m)
      raise "expected NotImplementedError for #{m}"
    rescue NotImplementedError
      # expected
    end
  end
end

test "SymbolicList: note propagates to length var registration" do
  SymbolicFunc.reset!
  SymbolicList.new(2, name: "rows", note: "SELECT * FROM posts")
  vars = SymbolicFunc.save_and_clear_registered_vars
  assert_equal 1, vars.size
  assert_equal "SYM_LEN_rows", vars[0]["name"]
  # The reason for the spelling (2026-09-14): solver.py transports Z3 terms as
  # PYTHON SOURCE it exec/evals, so a minted name must be a legal Python
  # identifier. `len(X)` is legal Z3 and legal JSON but not legal Python, and
  # the batch-local rename that used to paper over that cost seven multi-hour
  # failures. Assert the PROPERTY, so a future rename cannot regress it.
  assert_match(/\A[A-Za-z_][A-Za-z0-9_]*\z/, vars[0]["name"],
               "a minted var name must be a legal Python identifier")
  assert_equal "SELECT * FROM posts", vars[0]["note"]
end

puts "\nInterceptor (receiver-passing / dump):"

class FakeRel
  def to_sql; "SELECT * FROM posts WHERE id = 1"; end
  def find(id); raise "real body must not run"; end
end

test "declare_target: 3-arity mock receives receiver; note vars in dump" do
  interceptor = CallInterceptor.instance
  interceptor.declare_target(FakeRel, :find, returns: lambda do |receiver, args, name|
    sql = receiver.to_sql
    nf = symbool("#{name}_not_found", false, note: sql)
    raise "concolic: empty result for: #{sql}" if nf == true
    SymbolicList.new(2, name: "rows", note: sql)
  end)

  dump = interceptor.run(->(x:) {
    rows = FakeRel.new.find(1)
    rows.empty?
    x > 5
  }, { "x" => 7 }, label: "recv-test")

  names = dump["symbolic_vars"].map { |v| v["name"] }
  assert names.any? { |n| n.include?("not_found") }, "not_found var in dump: #{names}"
  assert names.include?("SYM_LEN_rows"), "SYM_LEN_rows in dump: #{names}"
  nf_var = dump["symbolic_vars"].find { |v| v["name"].include?("not_found") }
  assert_equal "Bool", nf_var["sort"]
  assert_equal "SELECT * FROM posts WHERE id = 1", nf_var["note"]

  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  assert pcs.any? { |pc| pc["expr"].include?("not_found") }, "not_found PC recorded"
  assert pcs.any? { |pc| pc["expr"].include?("SYM_LEN_rows") }, "length PC recorded"

  JSON.generate(dump)
end

test "run: exception captured in dump error key" do
  interceptor = CallInterceptor.instance
  dump = interceptor.run(->(x:) {
    x > 5
    raise ArgumentError, "boom"
  }, { "x" => 7 }, label: "err-test")
  assert dump["error"], "error key present"
  assert_equal "ArgumentError", dump["error"]["type"]
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  assert_equal 1, pcs.size
end

# ══════════════════════════════════════════════════════════════════════
# Symbolic model instance (make_symbolic_instance)
# ══════════════════════════════════════════════════════════════════════

require_relative "ruby_runtime/object"

puts "\nSymbolic model instance:"

class FakePost
  def initialize
    raise "initialize must never run for symbolic instances"
  end

  def visible_to(user_id)
    # Real app logic branching on attributes (explicit compares — Ruby)
    return true if public == true
    author_id == user_id
  end

  def display_name
    "post-#{guid}"
  end
end

def fake_post_attrs(sql = "SELECT * FROM posts")
  {
    "id"        => symint("post_id", 1, note: sql),
    "author_id" => symint("post_author_id", 7, note: sql),
    "public"    => symbool("post_public", false, note: sql),
    "guid"      => symstr("post_guid", "g-1", note: sql),
  }
end

test "symbolic instance: is_a? real class, initialize skipped" do
  post = make_symbolic_instance(FakePost, fake_post_attrs)
  assert post.is_a?(FakePost)
end

test "symbolic instance: attr reads are symbolic" do
  post = make_symbolic_instance(FakePost, fake_post_attrs)
  assert post.public.is_a?(SymbolicBool)
  assert post.author_id.is_a?(SymbolicInt)
end

test "symbolic instance: real method records PCs" do
  SymbolicVar.clear_path_conditions
  post = make_symbolic_instance(FakePost, fake_post_attrs)
  result = post.visible_to(7)
  assert_equal true, result # public=false, author_id 7 == 7
  pcs = SymbolicVar.get_path_conditions
  exprs = pcs.map(&:expr)
  assert exprs.include?("(post_public == True)"), "public PC recorded: #{exprs}"
  assert exprs.any? { |e| e.include?("post_author_id") }, "author PC recorded: #{exprs}"
  public_pc = pcs.find { |pc| pc.expr == "(post_public == True)" }
  assert_equal false, public_pc.taken
end

test "symbolic instance: predicate reader records PC, returns concrete" do
  SymbolicVar.clear_path_conditions
  post = make_symbolic_instance(FakePost, fake_post_attrs)
  val = post.public?
  assert_equal false, val
  assert_equal FalseClass, val.class # concrete — truthiness-safe
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(post_public == True)", pcs[0].expr
  assert_equal false, pcs[0].taken
end

test "symbolic instance: strict rejects concrete attrs" do
  begin
    make_symbolic_instance(FakePost, { "id" => 1 })
    raise "expected TypeError"
  rescue TypeError
    # expected
  end
  post = make_symbolic_instance(FakePost, { "id" => 1 }, strict: false)
  assert_equal 1, post.id
end

test "symbolic instance: concolic_attrs accessor + note registration" do
  SymbolicFunc.reset!
  post = make_symbolic_instance(FakePost, fake_post_attrs("SELECT 42"))
  assert_equal %w[id author_id public guid].sort, post.concolic_attrs.keys.sort
  vars = SymbolicFunc.save_and_clear_registered_vars
  assert_equal 4, vars.size
  assert vars.all? { |v| v["note"] == "SELECT 42" }, "notes: #{vars.inspect}"
end

# ══════════════════════════════════════════════════════════════════════
# Symbolic string length
# ══════════════════════════════════════════════════════════════════════

puts "\nSymbolic string length:"

test "SymbolicString#length is symbolic; compare records PC" do
  SymbolicVar.clear_path_conditions
  s = symstr("guid", "abcdef")
  ln = s.length
  assert ln.is_a?(SymbolicInt), "length is SymbolicInt, got #{ln.class}"
  result = (ln > 3)
  assert_equal true, result
  pcs = SymbolicVar.get_path_conditions
  assert_equal 1, pcs.size
  assert_equal "(Length(guid) > 3)", pcs[0].expr
  assert_equal true, pcs[0].taken
end

test "SymbolicSubstring#length is concrete (defined with concrete length)" do
  s = symstr("header", "Bearer token")
  sub = s[7, 5]
  SymbolicVar.clear_path_conditions
  assert_equal 5, sub.length
  assert sub.length.is_a?(Integer) && !sub.length.is_a?(SymbolicInt)
  assert_equal 0, SymbolicVar.get_path_conditions.size
end

# ══════════════════════════════════════════════════════════════════════
# SymbolicString#split (symbolic; mirrors py_runtime) + strict raising
# ══════════════════════════════════════════════════════════════════════

puts "\nSymbolicString split / strict:"

test "split: parts[0] and parts[1] record Contains/IndexOf PCs" do
  SymbolicVar.clear_path_conditions
  s = symstr("pair", "key:value")
  parts = s.split(":")

  p0 = parts[0]
  assert_equal "key", p0.value # to_s raises (strict) — use .value
  assert p0.is_a?(SymbolicSubstring)

  p1 = parts[1]
  assert_equal "value", p1.value

  pcs = SymbolicVar.get_path_conditions
  exprs = pcs.map(&:expr)
  assert exprs.any? { |e| e.include?("Contains(") }, "Contains PC: #{exprs}"
  assert exprs.any? { |e| e.include?("IndexOf(") }, "IndexOf PC: #{exprs}"
  assert exprs.any? { |e| e.include?("Not(Contains(") }, "tail Not(Contains) PC: #{exprs}"
end

test "split: unsupported forms raise" do
  s = symstr("s", "a:b")
  begin
    s.split
    raise "expected NotImplementedError (no separator)"
  rescue NotImplementedError
  end
  begin
    s.split("::")
    raise "expected NotImplementedError (multi-char separator)"
  rescue NotImplementedError
  end
  begin
    symstr("m", "a:b:c").split(":")
    raise "expected NotImplementedError (>1 separator)"
  rescue NotImplementedError
  end
end

test "strict: unsupported String methods raise (no silent delegation)" do
  s = symstr("s", "Hello")
  %i[upcase downcase strip gsub sub chars reverse].each do |m|
    begin
      s.send(m)
      raise "expected NotImplementedError for #{m}"
    rescue NotImplementedError
      # expected — was silent delegation before
    end
  end
end

# ══════════════════════════════════════════════════════════════════════
# Parity-audit fixes (A1–A8, B1–B6)
# ══════════════════════════════════════════════════════════════════════

puts "\nParity-audit fixes:"

test "A1: to_i / to_int raise" do
  x = symint("x", 5)
  [%i[to_i], %i[to_int]].each do |(m)|
    begin
      x.send(m)
      raise "expected NotImplementedError for #{m}"
    rescue NotImplementedError
    end
  end
end

test "A2: SymbolicString to_s / to_str are identity (String subclass)" do
  s = symstr("s", "ab")
  assert s.is_a?(String), "SymbolicString must be a String subclass"
  %i[to_s to_str].each do |m|
    assert s.send(m).equal?(s), "SymbolicString##{m} must return self (identity)"
  end
end

test "A3: hash allowed as concrete bucket; eql? raises" do
  # hash is intentionally concretized to the value's hash (documented bucket
  # coercion — Arel's to_sql de-dupes BindParams by hash); eql? remains
  # strict (an untracked comparison could slip through a Hash lookup).
  assert_equal symint("x", 1).hash, 1.hash
  begin; symint("x", 1).eql?(1); raise "int eql?"; rescue NotImplementedError; end
  assert_equal symstr("s", "a").hash, "a".hash
  begin; symstr("s", "a").eql?("a"); raise "str eql?"; rescue NotImplementedError; end
  symbool("b", true).hash # allowed (py defines __hash__)
  begin; symbool("b", true).eql?(true); raise "bool eql?"; rescue NotImplementedError; end
end

test "A4: <=> raises" do
  begin
    symint("x", 5) <=> 3
    raise "expected NotImplementedError"
  rescue NotImplementedError
  end
end

test "A5: zero?/nonzero? record canonical (x != 0)" do
  SymbolicVar.clear_path_conditions
  x = symint("x", 0)
  x.zero?
  x.nonzero?
  pcs = SymbolicVar.get_path_conditions
  assert_equal 2, pcs.size
  pcs.each do |pc|
    assert_equal "(x != 0)", pc.expr
    assert_equal false, pc.taken
  end
end

test "A6: unnamed string expr uses Python repr quoting" do
  SymbolicVar.clear_path_conditions
  s = SymbolicString.new("ab")
  s == "ab"
  assert_equal "('ab' == StringVal('ab'))", SymbolicVar.get_path_conditions[0].expr
end

test "A7: endless range slice -> open-ended substring" do
  s = symstr("header", "Bearer token")
  sub = s[7..]
  assert sub.is_a?(SymbolicSubstring)
  assert_equal "token", sub.value
  assert_equal "SubString(header, 7, Length(header) - 7)", sub.z3_expr
end

test "A8: list count: 0-arg symbolic, with arg raises" do
  l = symlist("rows", 3)
  assert l.count.is_a?(SymbolicInt)
  begin
    l.count(1)
    raise "expected NotImplementedError"
  rescue NotImplementedError
  end
end

test "B1: unnamed symbolic int rhs renders concrete value" do
  SymbolicVar.clear_path_conditions
  x = SymbolicInt.new(5, name: "x")
  y = SymbolicInt.new(3) # unnamed
  x > y
  assert_equal "(x > 3)", SymbolicVar.get_path_conditions[-1].expr
end

test "B2: string compare with non-string raises" do
  s = symstr("s", "ab")
  begin; s == 5; raise "expected raise for =="; rescue NotImplementedError; end
  begin; s != [1]; raise "expected raise for !="; rescue NotImplementedError; end
end

test "B3: symdict registers len var" do
  SymbolicFunc.reset!
  symdict("opts", { "a" => 1 })
  vars = SymbolicFunc.save_and_clear_registered_vars
  found = vars.find { |v| v["name"] == "SYM_LEN_opts" }
  assert found, "SYM_LEN_opts registered: #{vars.inspect}"
  assert_equal "Int", found["sort"]
  assert_equal 1, found["value"]
end

test "B4/B5: to_symbolic nil passthrough; bool -> SymbolicBool" do
  assert to_symbolic(nil, name: "r").nil?, "expected nil passthrough"
  wrapped = to_symbolic(true, name: "r")
  assert wrapped.is_a?(SymbolicBool), "got #{wrapped.class}"
  assert_equal true, wrapped.value
end

test "B5: run bool kwarg becomes SymbolicBool" do
  interceptor = CallInterceptor.instance
  seen = {}
  interceptor.run(->(flag:) { seen[:cls] = flag.class }, { "flag" => true }, label: "boolkw")
  assert_equal SymbolicBool, seen[:cls]
end

test "B6: call events carry per-target name" do
  interceptor = CallInterceptor.instance

  klass_a = Class.new { def alpha(x); x; end; def self.name; "KlassA"; end }
  klass_b = Class.new { def beta(x); x; end;  def self.name; "KlassB"; end }
  interceptor.declare_target(klass_a, :alpha, returns: ->(args, name) { 1 })
  interceptor.declare_target(klass_b, :beta,  returns: ->(args, name) { 2 })

  dump = interceptor.run(->(x:) {
    klass_a.new.alpha(1)
    klass_b.new.beta(2)
  }, { "x" => 1 }, label: "multi-target")

  call_targets = dump["events"].select { |e| e["type"] == "call" }.map { |e| e["target"] }
  assert call_targets.include?("KlassA.alpha"), "targets: #{call_targets}"
  assert call_targets.include?("KlassB.beta"), "targets: #{call_targets}"
end

test "B7: pre-run declared var registers on participation" do
  # Regression (2026-08-18): CallInterceptor#run's reset! clears the
  # registration table, which used to silently drop vars declared before
  # the run (symbolic request params) from the dump's symbolic_vars while
  # their PCs still referenced them. A named scalar now re-registers when
  # it records a PC — participation, not construction time, decides
  # membership.
  interceptor = CallInterceptor.instance

  pre    = symstr("SYM_PARAM_pre", "hello")
  unused = symstr("SYM_PARAM_unused", "x")

  dump1 = interceptor.run(->(x:) { pre == "hello" ? 1 : 0 },
                          { "x" => 1 }, label: "uses_pre")
  names1 = dump1["symbolic_vars"].map { |v| v["name"] }
  assert names1.include?("SYM_PARAM_pre"), "names: #{names1}"
  assert !names1.include?("SYM_PARAM_unused"), "names: #{names1}"
  decl = dump1["symbolic_vars"].find { |v| v["name"] == "SYM_PARAM_pre" }
  assert_equal "String", decl["sort"]
  assert_equal "hello", decl["value"]

  dump2 = interceptor.run(->(x:) { 0 }, { "x" => 1 }, label: "ignores_pre")
  names2 = dump2["symbolic_vars"].map { |v| v["name"] }
  assert !names2.include?("SYM_PARAM_pre"), "names: #{names2}"

  dump3 = interceptor.run(->(x:) { pre == "hello" ? 1 : 0 },
                          { "x" => 1 }, label: "uses_pre_again")
  names3 = dump3["symbolic_vars"].map { |v| v["name"] }
  assert names3.include?("SYM_PARAM_pre"), "names: #{names3}"
end

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════

puts
puts "=" * 60
puts "Results: #{$passed} passed, #{$failed} failed"
puts "=" * 60

exit(1) if $failed > 0