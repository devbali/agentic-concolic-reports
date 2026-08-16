# frozen_string_literal: true
#
# Per-batch concolic targets — `oidc_federation_nodeinfo`.
#
# This batch is unusual: it hits ZERO walls. All 22 dumps of the previous round,
# across all 7 entrypoints, had no `error` key — so there is nothing here to fix
# in the wall-mock sense, and this file deliberately adds NO crash mocks and NO
# app-method mocks at all.
#
# It exists for exactly ONE reason: `webfinger` was permanently incomplete for a
# REPRESENTATIONAL reason, not an unexplored branch. §1 removes that
# representation defect with a batch-local SUBCLASS of the runtime's own
# `SymbolicString` — no app method is replaced, no query is hidden, and nothing
# under src/ is touched.
#
# Installed AFTER the shared targets (declare_target / alias_method are
# last-one-wins):
#
#   ConcolicTargets.install!(interceptor)
#   OidcFederationNodeinfoTargets.install!(interceptor)

module OidcFederationNodeinfoTargets
  module_function

  def install!(_interceptor = CallInterceptor.instance)
    # ---------------------------------------------------------------------
    # 1. Marker-free symbolic split — closes `webfinger`'s two permanently
    #    missing branches AT THE SOURCE, by observation rather than by
    #    assumption.
    #
    # THE PROBLEM (a representation defect, not an app branch)
    # -------------------------------------------------------
    # `Person#username` (app/models/person.rb:270) is
    #
    #     @username ||= diaspora_handle.split("@")[0]
    #
    # and `webfinger` reaches it through `person.profile_url` / `person.atom_url`.
    # `SymbolicString`'s split accessor (src/ruby_runtime/string.rb:256-298)
    # records three STRUCTURAL MARKERS as PathConditions with `taken: true`
    # HARD-CODED:
    #
    #     Contains(StringVal('@'), <suffix>)        # separator found
    #     IndexOf(<suffix>, StringVal('@')) == n    # ...at this offset
    #     Not(Contains(StringVal('@'), <suffix>))   # no separator
    #
    # They are ASSERTIONS ABOUT A CONCRETE VALUE, not evaluated decisions. The
    # program never takes their other side, so strict per-node coverage demands
    # a `taken: false` observation that CANNOT EXIST — on any entrypoint that
    # splits a symbolic string. In `webfinger` that was 2 unclosable missing
    # branches (one per `guid` prefix), i.e. `complete=false` forever.
    #
    # Flipping does not help: the DSE *does* generate a handle containing '@',
    # but that run records the syntactically DIFFERENT node
    # `Contains(StringVal('@'), …)`, which is also only ever `taken: true`.
    # Path signatures compare as strings, so the two never unify. Relatedly
    # `IndexOf(…) == 0` was this batch's only unflippable PC shape — its LHS is
    # a function application, not a bare variable.
    #
    # (Aside, worth raising but NOT worked around here: the marker's arguments
    # are reversed. Z3's `Contains(a, b)` is "a contains b", so
    # `Contains(StringVal('@'), handle)` asserts that "@" contains the handle.
    # That is why the checker's witness for the missing side was
    # `diaspora_handle = ""`. Fixing the direction would not make the node
    # two-sided — `taken: true` is still hard-coded — so it changes nothing
    # about completeness here.)
    #
    # THE FIX — subclass, do not mock
    # -------------------------------
    # The runtime's symbolic classes are ordinary Ruby classes with public
    # readers, so a batch-local subclass can change behaviour without touching
    # shared code. `MarkerFreeSplitAccessor#[]` reproduces the shared
    # accessor's logic EXACTLY — same offsets, same bounds errors, same
    # `SymbolicSubstring` results with the same `SubString(parent, start, len)`
    # z3 expressions — minus the three `record!` calls.
    #
    # What this preserves that a mock would have destroyed:
    #
    #   * `Person#username` still RUNS. Its real body is executed, so if it
    #     ever grew a conditional that branch would still be observed. (The
    #     `Profile#build_image_url` trap from the photos batch: a mock that
    #     swallows the branch it guards is a regression, not a fix.)
    #   * The symbolic DEPENDENCY survives. `username` is still
    #     `SubString(<handle>, 0, …)` of the very same variable, so any future
    #     branch on a username is solved together with the handle's
    #     constraints. An earlier attempt here — mocking `Person#username` to
    #     return a fresh `symstr` — worked, but silently dropped that
    #     dependency. This does not.
    #   * No query is hidden and no app method is replaced: `declare_target` is
    #     not used at all in this file.
    #
    # What it removes is ONLY the three unobservable assertions. Nothing that
    # was ever a decision stops being recorded.
    #
    # TRAP (recorded because it cost a run): do not compute anything from a
    # symbolic string with `.to_s`. `SymbolicString#to_s` is IDENTITY
    # (src/ruby_runtime/string.rb:65-76 — it returns `self` so interpolation
    # keeps tracking alive), so `handle.to_s.split("@")` re-enters the SYMBOLIC
    # split. Use `.value` for the concrete string.
    # ---------------------------------------------------------------------
    unless defined?(MarkerFreeSplitAccessor)
      ::Object.const_set(:MarkerFreeSplitAccessor, Class.new(SymbolicString::SplitAccessor) do
        # Byte-for-byte the shared SplitAccessor#[] (string.rb:256-298) with the
        # three `record!` marker pushes removed.
        def [](idx)
          raise NotImplementedError, "split result negative index not supported" if idx.negative?

          if idx >= @concrete_parts.length
            raise IndexError,
                  "split result index #{idx} out of range (len=#{@concrete_parts.length})"
          end

          abs_offset = 0
          idx.times do |i|
            pos = @concrete.index(@sep, abs_offset)
            raise IndexError, "split result index #{idx} out of range at step #{i}" if pos.nil?

            abs_offset = pos + @sep.length
          end

          next_sep = @concrete.index(@sep, abs_offset)
          length   = next_sep.nil? ? -1 : (next_sep - abs_offset)

          SymbolicSubstring.new(@concrete_parts[idx],
                                parent_expr: @parent.z3_expr,
                                start:       abs_offset,
                                length:      length)
        end

        # The shared accessor exposes only #[]; Person#name uses `.first`.
        def first
          self[0]
        end

        def last
          self[@concrete_parts.length - 1]
        end
      end)
    end

    unless defined?(MarkerFreeSymbolicString)
      ::Object.const_set(:MarkerFreeSymbolicString, Class.new(SymbolicString) do
        def split(sep = nil, limit = nil)
          # `super` re-runs the shared validation (nil separator / limit /
          # multi-char separator / more than one occurrence all still raise
          # NotImplementedError exactly as before) and records nothing — the
          # markers live in the accessor's #[], not in #split.
          super
          MarkerFreeSplitAccessor.new(self, sep.to_s, value, value.split(sep.to_s, -1))
        end
      end)
    end

    # 1-wiring: route symbolic string columns through the subclass.
    #
    # Batch-local WRAPPER around the shared `ConcolicTargets.symbolic_instance`
    # (the shared file itself is untouched). After the generic build, every
    # plain-`SymbolicString` column value is re-wrapped as a
    # `MarkerFreeSymbolicString` carrying the SAME name, seeded value and note,
    # so seeding/flipping behave identically. The shared builder's column
    # readers, `#[]`, `#read_attribute` and `#attributes` all read the same
    # `concolic_attrs` hash, so mutating it in place is sufficient.
    #
    # `SymbolicSubstring` (a SymbolicString subclass) is deliberately skipped —
    # `instance_of?`, not `is_a?`.
    unless ConcolicTargets.respond_to?(:symbolic_instance_with_split_markers)
      class << ConcolicTargets
        alias_method :symbolic_instance_with_split_markers, :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_with_split_markers(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)

          attrs = obj.concolic_attrs
          attrs.each do |col, val|
            next unless val.instance_of?(SymbolicString)

            attrs[col] = MarkerFreeSymbolicString.new(val.value,
                                                      name: val.sym_name,
                                                      note: val.note)
          end
          obj
        end
      end
    end

    # ---------------------------------------------------------------------
    # 2. DELIBERATELY NOT MOCKED — everything else.
    #
    # Zero dumps in this batch carry an `error` key, so there is no wall to
    # close, and a mock added anyway could only lose information.
    #
    #   * `WebfingerController#webfinger` / `#host_meta`,
    #     `NodeInfoController#document`, `ReceiveController#public|private`,
    #     `TokenEndpointController#create` and
    #     `AuthorizationsController#create` all reach a terminal render/head
    #     with the SHARED targets alone.
    #
    #   * `host_meta`, `node_info_show` and `federation_receive_public` are
    #     VACUOUS (0 path conditions) because they contain no data-dependent
    #     branch — not because anything crashed. No mock can fix that; one that
    #     manufactured a branch there would be fabrication. See REPORT §5.
    #
    #   * `initializers/diaspora_federation.rb:100`
    #     (`person.present? && person.owner_id.present?`) is invisible because
    #     of the documented Ruby truthiness gap (src/TODO.txt): `blank?`
    #     reduces to `!self` on a SymbolicInt, so there is no hook point.
    #     Mocking `present?` would INVENT the branch rather than observe it.
    # ---------------------------------------------------------------------

    warn "[oidc_federation_nodeinfo] OidcFederationNodeinfoTargets installed"
  end
end
