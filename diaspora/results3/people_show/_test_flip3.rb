#!/usr/bin/env ruby
# Self-contained unit test for flip_seed (pure functions; run with plain ruby)
def parse_literal(lit)
  case lit
  when "True"  then true
  when "False" then false
  when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1)
  when /\A'(.*)'\z/m then Regexp.last_match(1)
  when /\A"(.*)"\z/m then Regexp.last_match(1)
  when /\A-?\d+\z/   then lit.to_i
  end
end

def other_value(parsed)
  case parsed
  when true, false then !parsed
  when Integer     then parsed + 1
  when String      then parsed.empty? ? "concolic_other" : ""
  end
end

cases = [
  ["Contains(StringVal('.'), SubString(H, 0, 1))", true, ".@b"],
  ["Contains(StringVal('.'), SubString(H, 0, 1))", false, "a.b"],
  ["Contains(StringVal('.'), SubString(H, 0, 2))", true, ".a.b"],
  ["Contains(StringVal('.'), SubString(H, 0, 2))", false, "aa.b"],
  ["Contains(StringVal('.'), SubString(H, 0, 3))", true, "a.b@c"],
  ["Contains(StringVal('.'), SubString(H, 0, 3))", false, "ab.c@d"],
  ["Contains(StringVal('.'), SubString(H, 0, Length(H) - 0))", true, ".a.b"],
  ["Contains(StringVal('.'), SubString(H, 0, Length(H) - 0))", false, "ab"],
  ["IndexOf(H, StringVal('@')) == 2", true, "aa@z"],
  ["IndexOf(H, StringVal('@')) == 1", false, "aa@z"],
]

ok = 0
cases.each do |expr, want, expect_seed|
  seed = flip_seed(expr, want)
  got = seed && seed["H"]
  mark = (got == expect_seed) ? "OK " : "FAIL"
  ok += 1 if got == expect_seed
  puts "#{mark} flip_seed(#{expr[0,60]}, #{want}) => #{got.inspect} (want #{expect_seed.inspect})"
end
puts "#{ok}/#{cases.size} passed"