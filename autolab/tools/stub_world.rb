# stub_world.rb -- the fake WORLD a diaspora target config declares against.
#
# Loaded by tools/declaration_probe.rb and by test/test_install.rb. It provides
# the src_new runtime for real, and replaces Rails and the diaspora app with
# auto-vivifying stub modules.
#
# This is the measurement instrument behind manifest.json. It is NOT a grep:
# `ConcolicTargets.install!` really executes, `declare_target` really runs,
# and `MissingKind` / `MissingType` / `valid_type?` are the runtime's own.
# What is faked is only the WORLD the config declares against: Rails and the
# diaspora app are replaced by auto-vivifying stub modules that answer
# `defined?`, `respond_to?`, `method_defined?` and `instance_methods.include?`
# affirmatively and materialise an instance method the moment
# `declare_target` asks for it.
#
# CONSEQUENCE, and it is the honest caveat on every count in this lab: the
# probe measures the MAXIMAL declaration set -- what the config declares when
# every guarded constant and method is present. Against the real app an
# eager-load failure can leave a guard false and one declaration dormant.
# The probe cannot see that; only a JRuby run inside the app can.
#
#   ruby declaration_probe.rb <spec.json>
#     spec = {"lenient": false, "consts": [...],
#             "steps": [{"file": "...", "modules": ["ConcolicTargets"]}, ...]}
#   lenient: true  -- for pre-`kind:` corpora (results3). A declaration missing
#     kind:/type: is RECORDED as needing repair and retried with placeholders so
#     the rest of install! still runs. Placeholders are flagged, never trusted.

# Runs a real ConcolicTargets-style install! against the REAL CallInterceptor
# from src_new, with stub constants standing in for Rails / diaspora app code.

require "json"

# RUBY 2.6 SYNTAX ONLY. JRuby 9.3.0.0 -- the runtime `scripts/diaspora-concolic`
# sets up, and the one a sweep actually runs on -- is Ruby 2.6 compatible, so no
# endless method definitions, no pattern matching, no `Hash#except`.
require "date"    # configs subclass ::Date (ConcolicDate)
require "digest"
require "set"
RT = "/home/dev/project/src_new/runtimes/ruby_runtime"
%w[call_interceptor base int string bool list object dict symbolic_func].each { |f| require "#{RT}/#{f}" }

class AlwaysIncludes < Array
  def include?(_x)
    true
  end
  def member?(_x)
    true
  end
end

module StubSingleton
  def alias_method(new_name, old_name)
    unless (@__autodef ||= {})[old_name.to_sym]
      @__autodef[old_name.to_sym] = true
      define_method(old_name) { |*_a, **_k, &_b| nil }
    end
    super
  end
  def method_defined?(_n)
    true
  end
  def instance_method(n)
    unless (@__autodef ||= {})[n.to_sym]
      @__autodef[n.to_sym] = true
      define_method(n) { |*_a, **_k, &_b| nil }
    end
    super
  end
end

module StubBehaviour
  def alias_method(new_name, old_name)
    unless (@__autodef ||= {})[old_name.to_sym]
      @__autodef[old_name.to_sym] = true
      define_method(old_name) { |*_a, **_k, &_b| nil }
    end
    super
  end
  def __stub__
    true
  end
  def instance_methods(_all = true)
    AlwaysIncludes.new(super)
  end
  def public_instance_methods(_all = true)
    AlwaysIncludes.new(super)
  end
  def private_instance_methods(_all = true)
    AlwaysIncludes.new(super)
  end
  def protected_instance_methods(_all = true)
    AlwaysIncludes.new(super)
  end
  def singleton_methods(_all = true)
    AlwaysIncludes.new
  end

  def const_missing(n)
    m = Module.new
    m.extend(StubBehaviour)
    m.instance_variable_set(:@__stub_name, "#{@__stub_name}::#{n}")
    const_set(n, m)
    m
  end
  def singleton_class
    sc = super
    sc.extend(StubSingleton) unless sc.singleton_class.include?(StubSingleton)
    sc
  end
  def method_defined?(_n)
    true
  end
  def public_method_defined?(_n)
    true
  end
  def private_method_defined?(_n)
    false
  end
  def instance_method(n)
    unless (@__autodef ||= {})[n.to_sym]
      @__autodef[n.to_sym] = true
      define_method(n) { |*_a, **_k, &_b| nil }
    end
    super
  end
  def respond_to_missing?(_n, _p = false)
    true
  end
  def method_missing(n, *_a, **_k, &_b)
    return true if n.to_s.end_with?("?")
    nil
  end
  def table_name
    "stub_table"
  end
  def name
    @__stub_name
  end
  def to_s
    @__stub_name.to_s
  end
  def inspect
    @__stub_name.to_s
  end
end

def stub_class(path)
  parts = path.split("::")
  leaf = parts.pop
  parent = parts.empty? ? Object : stub_const(parts.join("::"))
  return parent.const_get(leaf, false) if parent.const_defined?(leaf, false)
  c = Class.new
  c.extend(StubBehaviour)
  c.instance_variable_set(:@__stub_name, path)
  parent.const_set(leaf, c)
  c
end

def stub_const(path)
  parts = path.split("::")
  parent = Object
  acc = []
  parts.each do |p|
    acc << p
    if parent.const_defined?(p, false)
      parent = parent.const_get(p, false)
    else
      m = Module.new
      m.extend(StubBehaviour)
      m.instance_variable_set(:@__stub_name, acc.join("::"))
      parent.const_set(p, m)
      parent = m
    end
    return parent unless parent.is_a?(Module)
  end
  parent
end

# Safety net for constants referenced but not pre-listed.
class Object
  def self.const_missing(n)
    stub_const(n.to_s)
  end
end

# Constants used as SUPERCLASSES must be Classes, not Modules.
%w[Arel::Visitors::ToSql Arel::Collectors::SQLString ActiveRecord::Base
   ActionController::Base].each { |c| stub_class(c) }

