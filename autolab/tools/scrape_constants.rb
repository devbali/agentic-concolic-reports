# scrape_constants.rb -- every CONSTANT PATH a config file references in CODE
# (Ripper, so strings and comments are excluded), minus the ones this Ruby
# already defines. declaration_probe.rb pre-creates these as stubs so that the
# config's `if defined?(Stream::Aspect)` guards are TRUE -- `defined?` does not
# trigger `const_missing`, so without the pre-pass the probe silently
# under-counts every guarded declaration.
#
#   ruby scrape_constants.rb <file.rb> [more.rb ...]   -> JSON [names]

require "ripper"; require "json"
def unp(n)
  return nil unless n.is_a?(Array)
  case n[0]
  when :var_ref, :const_ref, :top_const_ref then unp(n[1])
  when :@const then n[1]
  when :const_path_ref
    a = unp(n[1]); b = unp(n[2]); (a && b) ? "#{a}::#{b}" : nil
  else nil
  end
end
def walk(n, out)
  return unless n.is_a?(Array)
  if [:var_ref, :const_path_ref, :top_const_ref].include?(n[0])
    v = unp(n); out << v if v
  end
  n.each { |c| walk(c, out) }
end
out = []
ARGV.each { |f| walk(Ripper.sexp(File.read(f)), out) }
names = out.compact.uniq.select { |n| n =~ /\A[A-Z]/ }
# A constant the config CREATES AT INSTALL TIME (`Object.const_set(:X, ...)`)
# must NOT be pre-stubbed: the creation is guarded by `unless defined?(::X)`,
# and a stub would make that guard TRUE and silently skip the declarations
# inside it. (Measured: pre-stubbing `ConcolicThroughLoadProbe` cost
# comments_index one TARGET_FUNCTION.)
created = ARGV.flat_map { |f| File.read(f).scan(/const_set\(\s*:([A-Z][A-Za-z0-9_]*)/).flatten }.uniq
keep = names.reject do |n|
  top = n.split("::").first
  created.include?(top) || (Object.const_defined?(top) rescue false)
end
# include intermediate namespaces
extra = []
keep.each { |n| p2 = n.split("::"); (1...p2.size).each { |i| extra << p2[0,i].join("::") } }
puts JSON.generate((keep + extra).uniq.sort)
