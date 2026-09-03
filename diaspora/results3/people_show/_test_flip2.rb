# Self-contained unit test: pure functions copied from run_dse.rb
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
$(sed -n '/^def flip_seed/,/^end$/p' run_dse.rb | head -n -1)
