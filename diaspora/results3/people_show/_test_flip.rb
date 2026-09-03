# unit test: load flip_seed from run_dse.rb and probe expr/want combos
src = File.read("run_dse.rb")
# extract flip_seed + helpers by eval-ing the file up to flip_seed def... simpler: 
# define parse_literal/other_value/flip_seed by evaluating the relevant region
region = src[/^def parse_literal.*?^end/m] + "\n" + src[/^def other_value.*?^end/m] + "\n" + src[/^def flip_seed.*?^end/m]
eval(region)

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
