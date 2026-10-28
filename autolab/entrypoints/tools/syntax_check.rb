# frozen_string_literal: true
#
# syntax_check.rb — parse every generated runner in ONE JRuby process.
#
# `jruby -c` per file costs a JVM start (~3 s); 161 of those is ten minutes.
# JRuby.parse does the same parse in-process, so the whole scaffold checks in
# a few seconds. Parsing only: it proves the files are syntactically valid
# Ruby, NOT that they run.
#
#   jruby tools/syntax_check.rb <file-or-glob> [...]

require "jruby"

paths = ARGV.flat_map { |a| File.directory?(a) ? Dir.glob(File.join(a, "**", "*.rb")) : Dir.glob(a) }
paths = paths.uniq.sort
abort("usage: syntax_check.rb <file|dir|glob> ...") if paths.empty?

ok = 0
fails = []
paths.each do |f|
  begin
    JRuby.parse(File.read(f), f)
    ok += 1
  rescue SyntaxError, StandardError => e
    fails << [f, "#{e.class}: #{e.message.to_s[0, 300]}"]
  end
end

fails.each { |f, msg| puts "FAIL #{f}\n     #{msg}" }
puts "parsed OK: #{ok} / #{paths.length}   failures: #{fails.length}"
exit(fails.empty? ? 0 : 1)
