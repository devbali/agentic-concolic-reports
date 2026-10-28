#!/usr/bin/env ruby
# SHIM EXTRACTOR (Ruby-runtime-specific step of the completion engine).
# Mechanically extracts the shim-mocked functions from batch runner code —
# the AUTHORITATIVE shim list is derived from the code that installs the
# shims, never hand-maintained. The engine (completion_checker.py) calls
# this, then demands a test per extracted shim.
#
#   ruby shim_extractor.rb <file.rb> [<file.rb> ...] > shims.json
#
# Extraction patterns (static, deterministic):
#   receiver.define_singleton_method(:meth) { ... }   -> kind: singleton
#   SomeModule with def meth / define_method(:meth),
#     later `Owner.prepend(SomeModule)`               -> kind: prepend
#   Owner.prepend(Module.new do ... end) with dynamic
#     define_method(:"interp#{olated}")               -> kind: dynamic
#     (unextractable name — the engine requires a manual entry or waiver)
#
# Value-class definitions on Concolic*/Symbolic*/Sampled* constants are
# runtime plumbing, not shims over app code — tagged kind: value_class so
# the engine can require only a waiver, not a test.
require "json"

files = ARGV
abort "usage: shim_extractor.rb <file.rb>..." if files.empty?

shims = []
rep_factory_sites = {}   # "basename:line" => true  (see the Rule S note below)

files.each do |path|
  src = File.read(path)
  lines = src.lines

  # module definitions with their instance methods (for prepend resolution)
  modules = {}  # name -> [methods]
  src.scan(/^\s*module\s+([A-Z]\w+)(.*?)^\s*end\s*$/m) do |name, body|
    meths = body.scan(/^\s*def\s+([a-z_0-9?!]+)/).flatten +
            body.scan(/define_method\(:([a-z_0-9?!]+)\)/).flatten
    modules[name] = meths.uniq
  end
  # Module.new assigned to a local: local = Module.new do ... end
  src.scan(/(\w+)\s*=\s*Module\.new do(.*?)^\s*end\s*$/m) do |name, body|
    meths = body.scan(/^\s*def\s+([a-z_0-9?!]+)/).flatten +
            body.scan(/define_method\(:([a-z_0-9?!]+)\)/).flatten
    dynamic = body.scan(/define_method\(:"[^"]*#\{/).size
    modules[name] = meths.uniq
    modules["#{name}__dynamic"] = dynamic
  end

  # Mark the body of each rep-factory method (`def symbolic_instance` &c) by
  # INDENTATION: from the `def` line to the first line at the same or lower
  # indentation whose content is exactly `end`. Singleton methods defined on
  # the representative object inside that body are the runtime's own rep
  # plumbing (attribute readers/writers, Ruby object protocol, and decision
  # readers whose whole content is a recorded PC) — not shims over app code.
  lines.each_with_index do |l0, j|
    # any method that BUILDS a representative object: the batch names vary
    # (`symbolic_instance`, `conversation`, `person_rep`…), so match a def
    # whose body defines singleton methods on a local receiver. Precision
    # comes from the RUNNER's protocol test, not from this list.
    next unless l0 =~ /^(\s*)def\s+[a-z_]\w*\b/
    ind = $1.length
    ((j + 1)...lines.size).each do |k|
      rep_factory_sites["#{File.basename(path)}:#{k + 1}"] = true
      lk = lines[k]
      break if lk =~ /^(\s*)end\s*$/ && $1.length <= ind
    end
  end

  lines.each_with_index do |line, i|
    next if line.strip.start_with?("#")
    # singleton shims
    line.scan(/(\S+)\.define_singleton_method\(:([a-z_0-9?!]+)\)/) do |recv, meth|
      shims << { "owner" => recv, "method" => meth, "kind" => "singleton",
                 "file" => File.basename(path), "line" => i + 1 }
    end
    # prepends
    line.scan(/([\w:.\[\]()]+)\.prepend\((\w+)\)/) do |owner, mod|
      meths = modules[mod] || []
      dyn = modules["#{mod}__dynamic"].to_i
      meths.each do |m|
        shims << { "owner" => owner, "method" => m, "kind" => "prepend",
                   "module" => mod, "file" => File.basename(path), "line" => i + 1 }
      end
      if dyn > 0 || meths.empty?
        shims << { "owner" => owner, "method" => "DYNAMIC", "kind" => "dynamic",
                   "module" => mod, "file" => File.basename(path), "line" => i + 1,
                   "note" => "dynamically-named define_method — engine requires manual entry or waiver" }
      end
    end
  end
end

# Classify what is NOT a shim over application code (Bali 2026-08-27,
# DISCIPLINE Rule S): these are the symbolic runtime's own machinery. The
# classification is STRUCTURAL — the defining site, not a per-batch text —
# so a batch cannot talk its way out of a shim test.
#
#   value_class      methods on the runtime's symbolic value classes
#   rep_plumbing     methods defined on a symbolic REPRESENTATIVE object,
#                    i.e. inside the rep factory (`def symbolic_instance` and
#                    friends): attribute readers/writers, Ruby object
#                    protocol, and the seeded decision readers whose entire
#                    content is a recorded PC. They have no real app body to
#                    run against; their evidence is the attribute vars and
#                    the decision PCs themselves.
shims.each do |s|
  if s["owner"] =~ /Concolic|Symbolic|Sampled|::Object/ || s["module"].to_s =~ /Concolic|Symbolic/
    s["kind"] = "value_class"
  elsif s["kind"] == "singleton" && rep_factory_sites["#{s["file"]}:#{s["line"]}"]
    s["kind"] = "rep_plumbing"
  end
end

puts JSON.pretty_generate(shims)
