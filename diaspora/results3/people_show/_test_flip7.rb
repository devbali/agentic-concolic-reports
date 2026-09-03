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
def flip_seed(expr, want_taken)
  s = expr.to_s.strip

  # `diaspora_handle.split('@')[0]` (Person#username -> #atom_url, reached
  # from layout_helper.rb's current_user_atom_tag on EVERY html render, now
  # real -- results3's render-boundary removal) records via
  # SymbolicString::SplitAccessor#[] (string.rb:279/288): idx=0 with no
  # separator match records `Not(Contains(StringVal(sep), VAR))` taken:true
  # (our default seed, no literal '@'); WITH a match it records the
  # DIFFERENT text `Contains(StringVal(sep), VAR)` taken:true instead (not
  # simply the same expr with taken:false -- string.rb's split_no_more vs
  # split_contains are separate record! call sites emitting separate expr
  # text). Only idx=0 (offset 0) is handled here -- `suffix_expr(0)` reduces
  # to the bare parent var, which is the only index this app's `[0]` calls
  # ever produce; a nonzero-offset SymbolicSubstring shape is out of scope
  # (never exercised on this endpoint).
  if (m = /\AContains\(StringVal\('(.*)'\), ([A-Za-z_][A-Za-z0-9_]*)\)\z/m.match(s))
    sep, var = m[1], m[2]
    return want_taken ? { var => "x#{sep}y" } : { var => "no-separator-here" }
  end
  if (m = /\ANot\(Contains\(StringVal\('(.*)'\), ([A-Za-z_][A-Za-z0-9_]*)\)\)\z/m.match(s))
    sep, var = m[1], m[2]
    return want_taken ? { var => "no-separator-here" } : { var => "x#{sep}y" }
  end

  # --- anon_mobile unflippables (results3/people_show, H1 mobile campaign) ---
  # The mobile render (show.mobile.haml -> stream -> people_helper
  # local_or_remote_person_path + ActiveSupport blank? checks) records FIVE
  # new PC shapes on the handle var(s) that the classic handlers above cannot
  # parse. All are concrete-value-derived (string.rb SubString/IndexOf), so
  # the only lever is SYNTHESIZING a parent-var seed that changes the derived
  # concrete value. Prefix-replay drift is accepted (path-signature dedup
  # bounds it):
  #
  #   1. `IndexOf(H, '@') == 1`  (219x taken:true, unflippable: the seed
  #      "x@y" always puts '@' at index 1) -> seed '@' at a DIFFERENT index.
  #   2. `Contains('.', H[0,1])` (72x false)  -> seed dot-leading H.
  #   3. `Contains('.', H[0,Len-0])` (72x false) -> seed H with/without dot.
  #   4. `(SubString(H,0,Len-0) == '')` / `(SubString(H,0,1) == '')` (blank?
  #      BLANK_RE) -> seed empty/non-empty.

  # 1. IndexOf(VAR, StringVal('sep')) == N
  if (m = /\AIndexOf\(([A-Za-z_][A-Za-z0-9_]*), StringVal\('(.*)'\)\) == (\d+)\z/m.match(s))
    var, sep, n = m[1], m[2], m[3].to_i
    if want_taken
      return { var => ("a" * n) + sep + "z" }
    else
      return { var => ("a" * (n + 1)) + sep + "z" }
    end
  end

  # 2. Contains(StringVal('.'), SubString(VAR, 0, 1)) -- username[0] == sep
  #    EMPIRICAL (734-run corpus): k in SubString(H,0,k) = length of
  #    split('@')[0] (username). k=1 -> '@' at position 1. T-side:
  #    username "." -> H = ".@b". F-side: username "a" -> H = "a@b".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 1\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".@b" } : { var => "a@b" }
  end

  # 2b. Contains(StringVal('.'), SubString(VAR, 0, 2)) -- username[0..1]
  #    k=2 -> '@' at position 2. T-side: username ".a" -> H = ".a@b".
  #    F-side: username "aa" -> H = "aa@b".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 2\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".a@b" } : { var => "aa@b" }
  end

  # 2c. Contains(StringVal('.'), SubString(VAR, 0, 3)) -- username[0..2]
  #    k=3 -> '@' at position 3. T-side: username "a.b" -> H = "a.b@c".
  #    F-side: username "abc" -> H = "abc@d".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 3\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => "a.b@c" } : { var => "abc@d" }
  end

  # 3. Contains(StringVal('.'), SubString(VAR, 0, Length(VAR) - 0)) -- H.include?(sep)
  #    EMPIRICAL: the Length-0 form fires on the WHOLE handle as username
  #    (no-'@' / NOTC arm). ".a.b" (no @, dot) records T; the default
  #    "..._v" (no @, no dot) records F. Seeds: T -> ".a.b"; F -> "ab".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, Length\2 - 0\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".a.b" } : { var => "ab" }
  end

  # 4a. (SubString(VAR, 0, Length(VAR) - 0) == '') -- H == ''
  if (m = /\A\(SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, Length\(\1\) - 0\) == ''\)\z/m.match(s))
    var = m[1]
    return want_taken ? { var => "" } : { var => "x@y" }
  end

  # 4b. (SubString(VAR, 0, 1) == '') -- H[0] == ''
  if (m = /\A\(SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 1\) == ''\)\z/m.match(s))
    var = m[1]
    return want_taken ? { var => "" } : { var => "x@y" }
  end

  if (m = /\A\(len\((.+)\) (<=|>=|==|!=|<|>) (-?\d+)\)\z/m.match(s))
    var, op, n = m[1], m[2], m[3].to_i
    len =
      case op
      when "<"  then want_taken ? n - 1 : n
      when "<=" then want_taken ? n     : n + 1
      when ">"  then want_taken ? n + 1 : n
      when ">=" then want_taken ? n     : n - 1
      when "==" then want_taken ? n     : n + 1
      when "!=" then want_taken ? n + 1 : n
      else return nil
      end
    len = 0 if len.negative?
    return { "len(#{var})" => len }
  end

  if (m = /\A\(len\((.+)\) != 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 1 : 0) }
  end
  if (m = /\A\(len\((.+)\) == 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 0 : 1) }
  end

  if (m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (<=|>=|<|>) (-?\d+)\)\z/m.match(s))
    var, op, n = m[1], m[2], m[3].to_i
    value =
      case op
      when "<=" then want_taken ? n : n + 1
      when "<"  then want_taken ? n - 1 : n
      when ">=" then want_taken ? n : n - 1
      when ">"  then want_taken ? n + 1 : n
      end
    return { var => value }
  end

  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip

  parsed = parse_literal(lit)
  return nil if parsed.nil?

  equal_wanted = (op == "==") ? want_taken : !want_taken
  value = equal_wanted ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

cases = [
  ["Contains(StringVal('.'), SubString(H, 0, 1))", true, ".@b"],
  ["Contains(StringVal('.'), SubString(H, 0, 1))", false, "a@b"],
  ["Contains(StringVal('.'), SubString(H, 0, 2))", true, ".a@b"],
  ["Contains(StringVal('.'), SubString(H, 0, 2))", false, "aa@b"],
  ["Contains(StringVal('.'), SubString(H, 0, 3))", true, "a.b@c"],
  ["Contains(StringVal('.'), SubString(H, 0, 3))", false, "abc@d"],
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
