# frozen_string_literal: true

# _test_compose.rb — MRI unit tests for dse_compose.rb
# Run: ruby /path/to/_test_compose.rb

require_relative "dse_compose"

$failures = 0

def check(desc, got, want)
  if got == want
    puts "ok   #{desc}"
  else
    $failures += 1
    puts "FAIL #{desc}\n     got:  #{got.inspect}\n     want: #{want.inspect}"
  end
end

# --- 2-way composition on distinct vars -----------------------------------
flippable = [
  [{ "SYM_PERSON_via_user_diaspora_handle" => ".@b" }, 3],   # dot-T
  [{ "len(SYM_RESULT_ActiveRecord__Relation_to_a_1_rows)" => 1 }, 5], # rows>0
]
out = DseCompose.compose_children({}, flippable, cap: 6)
check("2 distinct vars compose into one child",
      out.map { |c, k| [c, k] },
      [[{ "SYM_PERSON_via_user_diaspora_handle" => ".@b",
          "len(SYM_RESULT_ActiveRecord__Relation_to_a_1_rows)" => 1 }, 6]])

# --- same-var flips are skipped (last-wins no-op) --------------------------
flippable2 = [
  [{ "H" => "" }, 1],     # blank-T
  [{ "H" => ".@b" }, 4],  # dot-T on SAME var
]
out2 = DseCompose.compose_children({}, flippable2, cap: 6)
check("same-var flips produce no 2-way children", out2, [])

# --- 3-way pairwise-distinct ----------------------------------------------
flippable3 = [
  [{ "A" => 1 }, 1],
  [{ "B" => 2 }, 2],
  [{ "C" => 3 }, 3],
]
out3 = DseCompose.compose_children({}, flippable3, cap: 6)
check("3-way composition present",
      out3.any? { |c, k| c == { "A" => 1, "B" => 2, "C" => 3 } && k == 4 },
      true)

# --- parent seeds inherited -------------------------------------------------
out4 = DseCompose.compose_children({ "PARENT" => 99, "A" => 0 }, flippable3, cap: 6)
check("parent seeds inherited and not clobbered by distinct-var flips",
      out4.all? { |c, _k| c["PARENT"] == 99 },
      true)

# --- dedup: same composed seed from different pair order -------------------
flippable5 = [
  [{ "X" => 1 }, 1],
  [{ "Y" => 2 }, 2],
  [{ "Z" => 3 }, 3],
]
out5 = DseCompose.compose_children({}, flippable5, cap: 6)
keys5 = out5.map { |c, _k| JSON.generate(c.sort.to_h) }
check("no duplicate composed seeds", keys5.uniq.size, keys5.size)

# --- cap respected: 2-way capped at cap, 3-way capped at cap*2 total -------
flippable6 = (1..8).map { |i| [{ "V#{i}" => i }, i] }
out6 = DseCompose.compose_children({}, flippable6, cap: 4)
check("cap bounds children (≤ 8 for cap=4)", out6.size <= 8, true)

# --- min_k is max(pc index)+1 ----------------------------------------------
flippable7 = [
  [{ "A" => 1 }, 2],
  [{ "B" => 2 }, 7],
]
out7 = DseCompose.compose_children({}, flippable7, cap: 6)
check("min_k = max index + 1", out7.map { |_c, k| k }, [8])

puts $failures.zero? ? "\nALL PASS" : "\n#{$failures} FAILURES"
exit($failures.zero? ? 0 : 1)