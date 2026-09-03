# frozen_string_literal: true

require "json"

# dse_compose.rb — pure-Ruby MULTI-VAR SEED COMPOSITION for prefix-directed
# DSE (people_show results3 future-work #1).
#
# The classic prefix-directed loop emits ONE child per flipped PC (child =
# parent seeds + one flip). Reaching a multi-var conjunction (e.g. blank-T ×
# dot-T; via_user_handle dot-T × posts rows>0; guid=='' × stream) requires
# several flips to LAND IN ONE RUN, and chaining them one-per-level is depth-
# limited by PC ordering: flipping PC_k changes the path, so the sibling PC
# needed for the next flip may never re-appear at an index ≥ min_k.
#
# This module adds a composition step: from an observed run's flippable PCs
# (the same [(flip_hash, pc_index), ...] list the single-flip loop uses), also
# synthesize children that merge TWO (and up to THREE) flips whose targets are
# DISTINCT variables into one seed set. That jumps the co-flip depth by 2–3
# per level, targeting exactly the missing dot×guid×stream×branch-B
# conjunctions (STRUCTURAL_GAPS blockers #1/#5). Same-var merges are
# last-wins no-ops and are skipped. 3-way composes only from 2-way-distinct
# triples (pairwise distinct keys).
#
# Pure Ruby (no Rails/jruby deps) so it is unit-testable under MRI.
#
# Returns [[child_seeds_hash, min_k], ...], bounded per call by `cap`
# (2-way: first `cap`; 3-way: next `cap`, so ≤ 2*cap children per call).

module DseCompose
  # @param parent_seeds [Hash] seeds inherited from the parent run
  # @param flippable    [Array<[Hash, Integer]>] (flip_seed_hash, pc_index)
  # @param cap          [Integer] per-way budget
  # @return [Array<[Hash, Integer]>] composed children (deduped)
  def self.compose_children(parent_seeds, flippable, cap: 6)
    out = []
    seen = {}

    # --- 2-way composition -------------------------------------------
    flippable.each_with_index do |(fa, ka), ia|
      break if out.size >= cap
      flippable[(ia + 1)..].each do |(fb, kb)|
        break if out.size >= cap
        next if (fa.keys & fb.keys).any?
        child = parent_seeds.merge(fa).merge(fb)
        key = JSON.generate(child.sort.to_h)
        next if seen[key]
        seen[key] = true
        out << [child, [ka, kb].max + 1]
      end
    end

    # --- 3-way composition (pairwise-distinct keys, budget beyond 2-way) ---
    n = flippable.size
    (0...n).each do |ia|
      break if out.size >= cap * 2
      fa, ka = flippable[ia]
      (ia + 1...n).each do |ib|
        break if out.size >= cap * 2
        fb, kb = flippable[ib]
        next if (fa.keys & fb.keys).any?
        (ib + 1...n).each do |ic|
          break if out.size >= cap * 2
          fc, kc = flippable[ic]
          next if (fa.keys & fc.keys).any? || (fb.keys & fc.keys).any?
          child = parent_seeds.merge(fa).merge(fb).merge(fc)
          key = JSON.generate(child.sort.to_h)
          next if seen[key]
          seen[key] = true
          out << [child, [ka, kb, kc].max + 1]
        end
      end
    end

    out
  end
end