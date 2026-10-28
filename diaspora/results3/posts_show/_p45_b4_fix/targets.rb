# frozen_string_literal: true
#
# Per-batch concolic targets — `posts`.
#
# Installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration REPLACES an earlier one (last-one-wins).
# In body-skip mode the captured `original` is never invoked, so re-declaring an
# already-instrumented method produces exactly one TargetCall + one
# SymbolicCallRecord — no double counting, no ordinal drift.
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   PostsTargets.install!(interceptor)      # this file — batch-local wall fixes
#
# THE TWO WALLS THIS BATCH HITS
# -----------------------------
#   1. NotImplementedError: SymbolicList#each   — 1536 of 1540 reshares_create
#      dumps, at PostInteractionPresenter#as_api (post_interaction_presenter.rb:29,
#      `collection.includes(author: :profile).map { ... }`).
#   2. NotImplementedError: Calculations#pluck  — status_messages_create, at
#      StatusMessage#people_allowed_to_be_mentioned (status_message.rb:121).
#
# NEITHER is fixed by mocking the enclosing app method:
#   * `as_api`'s body fires `Relation#records` (a declared target) — mocking it
#     would hide the symbolic query chain.
#   * `people_allowed_to_be_mentioned`'s body IS the branch (`if public?`), so
#     mocking it is the exact regression the addendum warns about.
#
# Both are fixed at the MOCK BOUNDARY instead — which is where src/ruby_runtime
# says they belong. list.rb's header states the design explicitly:
#
#     "Iteration (each/map/reject/select/find) STAYS unimplemented — iteration is
#      handled by caller-wrapping at the mocked boundary, never executed against
#      the list."
#
# So `SymbolicList#each` raising is NOT a src/ bug to patch; the missing piece is
# the caller-side wrapper the design calls for, and a wrapper is exactly what a
# batch-local target file is allowed to provide. Nothing under src/ is modified.

module PostsTargets
  module_function

  # =====================================================================
  # IterableSymbolicList — the "caller-wrapping at the mocked boundary"
  # that src/ruby_runtime/list.rb's design mandates, implemented as a
  # runner-local SUBCLASS so that src/ is untouched.
  #
  # Semantics (a faithful extension of the Gate 1b representative model):
  #
  #   len == 0  ->  iterate zero times
  #   len != 0  ->  iterate EXACTLY ONCE over the single representative row
  #
  # and record the canonical `(len(X) != 0)` path condition on entry, with
  # taken = non-empty. That expression is identical to the one #empty? / #any?
  # already emit, so it path-signature-matches, and `len(X)` is already a
  # seedable key (the collection mock builds the length via
  # seed_for("len(NAME)", ...) — concolic_targets.rb:452). The DSE runner's
  # flip_seed already understands `(len(NAME) != 0)`, so iterate-vs-skip
  # becomes a genuinely flippable branch instead of a crash.
  #
  # HONEST LIMITS (unchanged from the base class, restated because iteration
  # makes them observable):
  #   * ONE representative row is modeled, not N. A list seeded len=3 still
  #     yields once. Distinct-row branching is not modeled.
  #   * A non-empty list with NO representative still raises loudly rather
  #     than silently yielding nothing — an unmodelable iteration must stay a
  #     visible wall, not become a silent empty loop.
  #
  # `include Enumerable` was tried first and REJECTED: Enumerable sits between
  # this class and SymbolicList in the ancestor chain, so it also shadows the
  # tracked API (first / count / include? / any? / none?), and re-binding those
  # back through a wrapper made every one of their path conditions report
  # `targets.rb` as its source frame instead of the app line. Iteration methods
  # are therefore delegated EXPLICITLY to a materialised row array, leaving
  # everything SymbolicList already tracked completely untouched and
  # byte-identical.
  #
  # `to_ary` is deliberately NOT among them and keeps raising: it is Ruby's
  # IMPLICIT array-conversion protocol, and defining it would silently change
  # destructuring / splat / puts behaviour at call sites that never asked to
  # iterate. `to_a` (explicit) is provided.
  # =====================================================================
  class IterableSymbolicList < SymbolicList
    def each(&blk)
      return to_enum(:each) unless blk
      __rows.each(&blk)
      self
    end

    ITERATION_OPS = %i[
      map collect flat_map collect_concat
      select filter find_all reject filter_map
      find detect find_index each_with_index each_with_object each_entry
      sort_by group_by partition min_by max_by
      sum reduce inject tally zip take drop to_a
    ].freeze

    ITERATION_OPS.each do |m|
      define_method(m) do |*args, &blk|
        __rows.public_send(m, *args, &blk)
      end
    end

    private

    # Materialise the modeled contents. Records the canonical emptiness PC
    # exactly once per iteration site, then returns either [] or the single
    # representative row.
    def __rows
      nonempty = !concrete_length.zero?
      record!("(#{symbolic_len} != 0)", "each", taken: nonempty)
      return [] unless nonempty

      if representative.nil?
        raise NotImplementedError,
              "IterableSymbolicList#each: list #{self} is non-empty but carries no " \
              "representative row, so its contents cannot be modeled. " \
              "(Wall kept visible on purpose — see results/posts/targets.rb.)"
      end
      [representative]
    end

    public

    # acts_as_api serialisation of a collection. Iteration-shaped, same
    # one-rep semantics.
    def as_api_response(*args)
      __rows.map { |r| r.respond_to?(:as_api_response) ? r.as_api_response(*args) : r }
    end

    # results3 NEW (mission item 2 — mark_user_notifications real descent).
    # `PostService#mark_mention_notifications_read` does `mention_ids.concat
    # (mentions_in_comments_for_post(post_id).pluck(:id))` where `mention_ids`
    # is THIS class (from the `.ids` mock, targets.rb §2). Real Array#concat
    # mutates the receiver in place and returns it; IterableSymbolicList
    # models one representative row and cannot grow a second, distinct one,
    # so `concat` is a documented, harmless simplification: return self
    # unchanged (the representative-sampling semantics already treat "1
    # mention_id" and "1 mention_id plus more" as the same modeled shape —
    # what matters for coverage is that `.any?`/`.each` keep working
    # afterward, which they do since self is untouched). Was previously an
    # unconditional-raise stub (list.rb LIST_STUBS).
    def concat(*_others)
      self
    end
  end

  # =====================================================================
  # SuccIntValue — SymbolicInt plus #next / #succ.
  #
  # `User#update_or_create_participation!` (social_actions.rb:56) does
  # `participation.update!(count: participation.count.next)`. `count` is an
  # INTEGER COLUMN on a symbolic model instance, so it is a SymbolicInt, and
  # SymbolicInt lists :next/:succ among its raising arithmetic stubs
  # (int.rb:55-66).
  #
  # `+1` is exactly as soundly expressible in Z3 as the unary minus that
  # SymbolicInt#-@ (int.rb:78-80) ALREADY models symbolically rather than
  # raising — so this follows an existing runtime precedent rather than
  # inventing semantics. The naming convention matches -@'s: the result is a
  # named symbolic value whose name is the arithmetic expression.
  #
  # Scope note: only #next/#succ are added. The rest of SymbolicInt's
  # arithmetic (+ - * / ...) still raises, because those take an operand whose
  # own symbolic expression would have to be composed — a bigger change than
  # this batch needs, and the documented core design constraint.
  # =====================================================================
  class SuccIntValue < SymbolicInt
    def next
      SuccIntValue.new(value + 1,
                       name: sym_name ? "(#{sym_name} + 1)" : nil, note: note)
    end
    alias succ next
  end

  # Swap every plain SymbolicInt attribute of a symbolic model instance for a
  # SuccIntValue. Mutates the `attrs` Hash that `symbolic_instance`'s column
  # readers close over (`obj.define_singleton_method(col) { attrs[col] }`), so
  # the readers observe the swap. Booleans are SymbolicBool (a separate class,
  # not a SymbolicInt subclass) and their predicate readers capture the value
  # object directly, so they are untouched by construction.
  def upgrade_ints!(obj)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    attrs.keys.each do |col|
      v = attrs[col]
      next unless v.instance_of?(SymbolicInt)
      attrs[col] = SuccIntValue.new(v.value, name: v.sym_name, note: v.note)
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # Batch-local SUBCLASS adding the one string operation this batch's last wall
  # needs. Same discipline as search_links_reports_profiles §3: implemented ONLY
  # where the answer is EXACT for the concrete witness, and raises loudly
  # otherwise. It never concretizes and never invents a Z3 term.
  #
  # THE WALL: `Diaspora::Mentionable.filter_people` (mentionable.rb:59-72) does
  #     mentioned_ppl = people_from_string(msg_text)
  #     msg_text.to_s.gsub(REGEX) {|m| ... }
  # reached from StatusMessage#filter_mentions (status_message.rb:127) on
  # status_messages#create. `gsub` is in the runtime's UNSUPPORTED table
  # (string.rb:325).
  #
  # `filter_people` CANNOT be mocked: its body calls `people_from_string`, which
  # is itself a declared target (§5), so mocking it would hide that symbolic
  # query chain — the README invariant. `filter_mentions` is worse: its body IS
  # the branch (`return if people_allowed_to_be_mentioned == :all`). So fix the
  # VALUE.
  #
  # EXACTNESS: REGEX is the mention syntax /@\{(?:([^\}]+?); )?([^\} ]+)\}/.
  # When the witness contains no mention, `gsub(REGEX)` provably returns an
  # equal string, so returning SELF is exact and preserves sym_name, note and
  # the whole constraint history. When the witness DOES contain one, the result
  # depends on the string's contents — which SymbolicString does not model — so
  # it raises, exactly as it does today. This is therefore strictly no worse
  # than the status quo: it can only turn a crash into a faithful no-op.
  # ConcreteSymbolicString — RESTORED BATCH-LOCALLY, 2026-09-10 (drive).
  #
  # THE DEFECT IT REPAIRS. `targets.rb` uses `ConcreteSymbolicString` in three
  # places, and the 2026-09-09 Rule-T re-sync deleted its DEFINITION while
  # ADDING one of those uses. The re-sync made this batch's
  # `concolic_targets.rb` a verbatim copy of the shared boundary, which has
  # never defined the class (`grep -c` = 0 there and in this batch), whereas
  # the archived `concolic_targets.rb.pre_ruleT_resync` defines it at line 479.
  # The use it added is the W3b `to_param` wall mock (:666 below), whose own
  # comment says it fires on `post_url @post` / `post_path` in
  # `PostPresenter#url` — the metas render of the HTML format.
  #
  # MEASURED COST, on the corpus the re-sync produced: 100 % of html runs that
  # get past the finder die in the view with
  # `ActionView::Template::Error: uninitialized constant
  # PostsTargets::ConcreteSymbolicString` — auth_html 2 061 of 2 237 sampled,
  # anon_html 1 433 of 2 239 (the rest are RecordNotFound / NonPublic, which
  # terminate earlier), and ZERO html runs in either arm reach the end of the
  # action. The json arms are unaffected.
  #
  # WHY DEFINE IT HERE AND NOT GUARD THE USES. The mock genuinely needs the
  # class: a bare Ruby `String` returned from a `declare_target` mock is NOT
  # exempt from the interceptor's `to_symbolic` return wrapping (only `nil` and
  # already-`SymbolicVar`-tagged values are), so a "concrete" return is
  # silently RE-WRAPPED into a `SymbolicString` whose UNSUPPORTED-op stubs
  # (scan/gsub/strip/...) then fire downstream. A real `::String` subclass that
  # also includes `SymbolicVar` is native for every string op AND recognised by
  # the interceptor as already-symbolic. Guarding the uses with
  # `if defined?(...)` would only move the failure. Body is BYTE-IDENTICAL to
  # comments_index/concolic_targets.rb:1411-1423 and to
  # notifications_index's, which is where it was first found — on that
  # endpoint's HTML render path.
  #
  # It is defined HERE, in the batch's own `targets.rb`, and NOT in this
  # batch's copy of the shared boundary: DISCIPLINE Rule T1 keeps batch-local
  # shims here so the boundary copy stays diffable against upstream, and T3
  # forbids an agent editing the boundary. That the SHARED boundary lacks a
  # class two batches carry privately is RAISED, not fixed here.
  def define_concrete_symbolic_string!
    return if defined?(::ConcreteSymbolicString)

    ::Object.const_set(:ConcreteSymbolicString, Class.new(::String) do
      include SymbolicVar
      attr_reader :note

      def self.build(str, name:, note:)
        s = new(str)
        s.instance_variable_set(:@sym_name, name)
        s.instance_variable_set(:@note, note)
        s
      end
    end)
  end

  # PcVisibleConcreteString — a render-safe string that STAYS PC-VISIBLE.
  # ------------------------------------------------------------------------
  # WHY IT EXISTS (2026-09-10 drive, §46). Three of this endpoint's SQL-free
  # display mocks return a value that Rails' HTML-escape path then walks
  # (`tag_option` -> `unwrapped_html_escape` -> `Multibyte::Unicode.tidy_bytes`
  # -> `String#scrub`). `SymbolicString#scrub` is UNSUPPORTED by design, so
  # every html run in the corpus terminated there. `ConcreteSymbolicString`
  # (a real ::String that also `include`s SymbolicVar) is the established fix
  # and it renders — but a plain ::String's `==` records NOTHING, so wrapping
  # would DELETE whatever comparisons the corpus was recording on those
  # values. That is the D1 direction ("a mock may replace execution, never
  # evidence") and it is avoidable at zero cost.
  #
  # This subclass is notifications_index's `TypeLinkedString` instrument
  # (targets.rb:853, "NOT a new pin ... these columns stay PC-VISIBLE and
  # pc_visibility_audit --gate can still see any compare the app makes"),
  # reused verbatim in mechanism: a ::String subclass whose `==` / `!=`
  # RECORD the path condition against the value's own sym_name and then
  # return a concrete Ruby bool. Render-safe for every string op AND
  # strictly evidence-preserving: every `(name == StringVal(...))` the corpus
  # recorded through the SymbolicString is still recorded through this.
  def define_pc_visible_concrete_string!
    return if defined?(::PcVisibleConcreteString)

    define_concrete_symbolic_string!
    ::Object.const_set(:PcVisibleConcreteString, Class.new(::ConcreteSymbolicString) do
      # NOTE the explicit ::String bindings below. `to_s` returns SELF on this
      # class (see below), so `to_s == other` inside `==` would re-enter this
      # method forever; the comparison is therefore taken from ::String
      # directly, which is the concrete byte comparison these mean.
      def ==(other)
        return super unless sym_name && other.is_a?(::String) && !other.respond_to?(:sym_name)
        rhs = ::String.new(other.to_s)
        result = ::String.instance_method(:==).bind(self).call(rhs)
        record!("(#{sym_name} == #{z3_str_val(rhs)})", "==", taken: result)
        result
      end

      def !=(other)
        return super unless sym_name && other.is_a?(::String) && !other.respond_to?(:sym_name)
        rhs = ::String.new(other.to_s)
        result = !::String.instance_method(:==).bind(self).call(rhs)
        record!("(#{sym_name} != #{z3_str_val(rhs)})", "!=", taken: result)
        result
      end

      # `empty?`, recorded in the EXACT shape SymbolicString#empty? uses
      # (src/ruby_runtime/string.rb:212-217, `"(#{z3_expr} == '')"` — note:
      # NOT `StringVal('')`, which is what `==` renders). Byte-identical to
      # the expression the corpus already carries for this value, so the
      # decision the pre-W7 html runs recorded stays the SAME expression and
      # is closable rather than orphaned.
      #
      # This is why the carrier is chosen PER SITE (W7): the emptiness of the
      # RENDERED POST TEXT is a decision over app data, and the app really
      # branches on it (ActiveSupport tidy_bytes, unicode.rb:227). The other
      # two W7 sites return a value the MOCK invented — a constant that no app
      # datum controls — so recording `== ''` there would mint a decision that
      # is False by construction, i.e. a fake unreachable side needing a fake
      # pin. Those two therefore use plain ConcreteSymbolicString and record
      # nothing, and that non-recording is DECLARED rather than pinned.
      def empty?
        return super unless sym_name
        result = ::String.instance_method(:empty?).bind(self).call
        record!("(#{sym_name} == '')", "empty?", taken: result)
        result
      end

      # `to_s` / `to_str` return SELF, mirroring SymbolicString (string.rb:74-80).
      # MEASURED necessity, not defensiveness: Rails'
      # `unwrapped_html_escape` (output_safety.rb:38) does `s = s.to_s` BEFORE
      # `tidy_bytes`, and ::String#to_s on a SUBCLASS returns a fresh plain
      # String — so without this the identity is stripped one frame before the
      # `empty?` the corpus records, and the first attempt at this fix recorded
      # nothing at all.
      def to_s
        self
      end

      def to_str
        self
      end
    end)
  end

  def define_substitutable_string!
    return if defined?(::SubstitutableSymbolicString)

    ::Object.const_set(:SubstitutableSymbolicString, Class.new(SymbolicString) do
      def gsub(pattern, *rest, &_blk)
        rx = pattern.is_a?(Regexp) ? pattern : Regexp.new(Regexp.escape(pattern.to_s))
        return self if rest.empty? && !(value =~ rx)

        raise NotImplementedError,
              "SubstitutableSymbolicString#gsub(#{pattern.inspect}): witness " \
              "#{value.inspect} matches the pattern, so the result depends on " \
              "string contents the runtime does not model. Only the provably- " \
              "identity case (no match, no replacement argument) is supported."
      end
    end)
  end

  # Swap the `text` column of a symbolic model instance for a
  # SubstitutableSymbolicString. Mutates the same `attrs` Hash the column
  # readers close over, and installs NO new singleton — re-installing one here
  # would shadow app readers that take an argument (measured in the photos
  # batch: a blanket string upgrade that re-installed readers broke
  # `Profile#image_url(size)` across 46 dumps).
  #
  # Deliberately narrow: `text` is the only string this batch substitutes over.
  def upgrade_text!(obj)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    v = attrs["text"]
    if v.instance_of?(SymbolicString)
      attrs["text"] = ::SubstitutableSymbolicString.new(v.value, name: v.sym_name, note: v.note)
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # results3 NEW (found live): `PostPresenter#tags` -> `@post.tags.map(&:name)`
  # -> `.join(", ")` (comma_separated_tags), on-path for the now-real
  # show.html.haml meta-tags render. `Tag#name` is a plain `:string` column,
  # generically dispatched by symbolic_instance to a raw `symstr` — and
  # `SymbolicString#to_s`/`#to_str` are IDENTITY (string.rb:70-76, by
  # design: str()/interpolation must not silently concretize), so `.join`
  # cannot flatten it to a native String, and the un-concretized value
  # reaches Rails' HTML-escape path (`tag_option` -> `tidy_bytes` ->
  # `#scrub`, UNSUPPORTED by design). `Tag#name` itself is not branched on
  # anywhere in this endpoint (its only use is display), so — same
  # reasoning as X6i/X6l/X6h — a ConcreteSymbolicString (a genuine ::String
  # subclass, native for every op, still interceptor-recognized as
  # already-symbolic) is the correct, narrow fix: real string ops downstream
  # (join/scrub/html_safe) all work, and the query that produced the row
  # (the tags/taggings JOIN) keeps its real, already-captured SQL note.
  def upgrade_tag_name!(obj, base_name, sql)
    return obj unless defined?(::ActsAsTaggableOn::Tag) && obj.is_a?(::ActsAsTaggableOn::Tag)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    v = attrs["name"]
    if v.instance_of?(SymbolicString)
      attrs["name"] = ConcreteSymbolicString.build(v.value, name: v.sym_name, note: sql)
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # NOTE: the text-identity shim (has_mention-driven concrete `text`) and
  # the federation network-I/O wall for the people_from_string real descent
  # (mission item 4) are wired directly in `install!` below (§3a/§3b),
  # matching results3/comments_index's inline-alias style — not here, to
  # avoid two independent symbolic_instance wrapper chains fighting over
  # the same `attrs["text"]` key.

  # =====================================================================
  # results3 NEW — ConcolicDate. Ported verbatim from
  # results3/people_show/targets.rb (same problem: a `:date`/`:datetime`
  # column falls through symbolic_instance's generic type dispatch into a
  # bare SymbolicString, which crashes on `.to_time`/`.iso8601` etc.).
  # PostPresenter#metas_attributes (called from the now-real
  # show.html.haml render — concolic_targets.rb header MOCK LEDGER, render
  # family removal) calls `published_time_iso8601`/`modified_time_iso8601`
  # -> `created_at.to_time.iso8601` / `updated_at.to_time.iso8601`
  # unconditionally. A real `::Date` subclass whose `#year` reader is
  # swapped for a symbolic int (so `.year` compares still record a PC) but
  # every OTHER Date method (`to_time`, `iso8601`, ...) runs for real
  # against the underlying concrete 1990-01-01 — no wall, no
  # concretization of anything actually branched on.
  # =====================================================================
  def define_concolic_date!
    return if defined?(::ConcolicDate)
    ::Object.const_set(:ConcolicDate, Class.new(::Date) do
      attr_writer :sym_year
      def year
        @sym_year || super
      end

      # results3 FIX (found live): ActiveSupport's `Date#to_time`
      # (activesupport core_ext/date/conversions.rb) is Ruby, not C — it
      # calls the PUBLIC `year`/`mon`/`mday` reader methods explicitly
      # (`Time.local(year, mon, mday, ...)`), unlike Date's built-in
      # strftime/iso8601 (C-level, reads internal @ajd directly, never
      # calls #year — unaffected). So `#year` returning a SymbolicInt
      # crashes `to_time` (`SymbolicInt#to_int` unsupported) even though
      # `#iso8601`/`#to_s`/`#strftime` all work fine already.
      # PostPresenter#published_time_iso8601/#modified_time_iso8601 call
      # `created_at.to_time.iso8601` — only #to_time itself needs the real
      # concrete value; bypass the symbolic year for JUST this one method
      # by delegating to a genuine ::Date (not self) built from the fixed
      # concrete witness (1990-01-01, the only date this class ever models).
      def to_time(*args)
        ::Date.new(1990, 1, 1).to_time(*args)
      end
    end)
  end

  def upgrade_dates!(obj, base_name, sql)
    return obj unless obj.respond_to?(:concolic_attrs)
    klass = obj.class
    return obj unless klass.respond_to?(:columns_hash)
    attrs = obj.concolic_attrs
    klass.columns_hash.each do |col, meta|
      next unless %i[date datetime].include?(meta.type)
      vn = "#{base_name}_#{col}_year"
      d = ::ConcolicDate.new(1990, 1, 1)
      d.sym_year = symint(vn, ConcolicTargets.seed_for(vn, 1990), note: sql)
      attrs[col] = d
      obj.define_singleton_method(col) { d }
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # ---------------------------------------------------------------------

  def install!(interceptor = CallInterceptor.instance)
    define_substitutable_string!
    define_concrete_symbolic_string!
    define_pc_visible_concrete_string!
    # --- DIAGNOSTIC ONLY, ENV-GATED (PSH_SCRUB_DIAG=1), 2026-09-10 drive. ---
    # §42 named `Person#name` as the string that reaches Rails' HTML-escape
    # path. The wrap installed for it (§43) proved to be a NO-OP: the post-wrap
    # dump is byte-identical to the pre-wrap one (135 events, 330 symbolic vars,
    # no Person var minted in EITHER), so `Person#name` was never re-wrapped and
    # is not the crashing string. This prepend NAMES the actual object instead
    # of inferring it from the last CALL event. It is off unless the env var is
    # set, so no corpus run is affected.
    if ENV["PSH_SCRUB_DIAG"] == "1" && defined?(::SymbolicString)
      ::SymbolicString.prepend(Module.new do
        # NON-FATAL under the diagnostic: return the CONCRETE witness so the
        # render continues and ONE run enumerates EVERY string that reaches
        # Rails' HTML-escape path, instead of one run per failure point.
        # Diagnostic only — these dumps are never corpus evidence.
        def scrub(*args, &blk)
          nm = respond_to?(:sym_name) ? sym_name : nil
          vl = respond_to?(:value) ? value : nil
          warn("[SCRUB-DIAG] sym_name=#{nm.inspect} value=#{vl.inspect} " \
               "class=#{self.class} site=#{caller[3, 4].join(' <- ')}")
          String(vl).scrub(*args, &blk)
        end
      end)
    end
    ct  = ConcolicTargets
    rel = ActiveRecord::Relation
    calc = ActiveRecord::Calculations
    cproxy = defined?(ActiveRecord::Associations::CollectionProxy) ?
               ActiveRecord::Associations::CollectionProxy : nil
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    # -------------------------------------------------------------------
    # 0. Batch-local wrapper around ConcolicTargets.symbolic_instance.
    #
    # The shared file stays untouched; only the live method object is
    # re-pointed, and only inside this process. `module_function` gives
    # ConcolicTargets a SINGLETON copy of symbolic_instance, and the shared
    # mocks call it bare with `self == ConcolicTargets`, so they resolve to
    # that singleton — re-aliasing it therefore covers the shared mocks'
    # internal calls too, not just my own.
    # -------------------------------------------------------------------
    define_concolic_date!
    unless ct.respond_to?(:__posts_orig_symbolic_instance)
      ct.singleton_class.send(:alias_method,
                              :__posts_orig_symbolic_instance, :symbolic_instance)
      ct.singleton_class.send(:define_method, :symbolic_instance) do |klass, base_name, sql|
        # results3 FIX (found live, render family now executes for real):
        # every stored post is an STI subclass (StatusMessage or Reshare) —
        # ActiveRecord never persists a bare `Post` row, so `klass == Post`
        # here (from EvilQuery/find_public!'s `@class = Post`) is an
        # under-specified representative. `PostPresenter#tags`/`#images`/
        # `#comma_separated_tags` (called from the now-real show.html.haml
        # meta-tags render) hit `@post.tags` — `acts_as_taggable_on :tags`
        # lives on StatusMessage (status_message.rb:15), not bare Post, so a
        # bare-Post representative raises NoMethodError. StatusMessage is
        # the representative choice (matches PostPresenter#tags' own
        # `@post.is_a?(Reshare) ? ... : @post.tags` branching — the
        # non-Reshare case IS StatusMessage in practice); Reshare-shaped
        # posts are not modeled by this representative (documented residual,
        # same "one representative row" limit as IterableSymbolicList).
        klass = StatusMessage if klass == Post && defined?(StatusMessage)
        PostsTargets.upgrade_tag_name!(
          PostsTargets.upgrade_dates!(
            PostsTargets.upgrade_text!(
              PostsTargets.upgrade_ints!(__posts_orig_symbolic_instance(klass, base_name, sql))),
            base_name, sql),
          base_name, sql)
      end
    end

    # -------------------------------------------------------------------
    # 0b. STI type-dispatch: found-post representative is a real StatusMessage,
    # not bare Post. Ported technique from results3/notifications_index's §5f
    # `build_representative` (same problem: a representative built off the STI
    # BASE class lacks every subclass-only method the now-real render pipeline
    # calls).
    #
    # `Post` is an STI base (post.rb, `type` column) with leaf subclasses
    # `StatusMessage`/`Reshare`. Every finder path on posts#show (design-#1
    # `finder_mock`, reused by ALL of PostsShowFinderNaming's evilq_*/
    # findpublic_* dedicated targets, and the rows_mock/pluck/ids reps above)
    # calls `symbolic_instance(model_class(receiver), name, sql)` where
    # `model_class(receiver)` resolves to plain `Post` (the class the finder
    # query relation was built on) — so the representative object is a BARE
    # `Post`, which lacks `acts_as_taggable_on :tags` (only declared on
    # `StatusMessage`/`Comment`, status_message.rb:15) and other subclass-only
    # methods. FOUND LIVE: `PostPresenter#tags` (`@post.tags`, called from the
    # now-real show.html.haml -> metas_attributes -> og:article:tag) crashed
    # `NoMethodError: undefined method 'tags'` on every dump reaching render.
    #
    # Fix at `ConcolicTargets.model_class` (batch-local alias, same wrapping
    # technique as symbolic_instance above): map bare `Post` -> `StatusMessage`
    # everywhere a representative is built. `StatusMessage < Post` inherits
    # everything the base class has plus `tags`/`tag_list` — strictly more
    # capable, never less. Deliberate, documented representative-element
    # choice (Gate 1b "one sampled row" methodology, same class of
    # approximation as IterableSymbolicList's single row): the Reshare-shaped
    # branches (`@post.is_a?(Reshare)`, `@post.absolute_root`) are therefore
    # NEVER explored by this rerun — reported in REPORT.md, not silently
    # papered over. Only Post itself is remapped; any OTHER receiver class
    # (Person, Notification, Block, ...) passes through unchanged.
    # -------------------------------------------------------------------
    unless ct.respond_to?(:__posts_orig_model_class)
      ct.singleton_class.send(:alias_method, :__posts_orig_model_class, :model_class)
      ct.singleton_class.send(:define_method, :model_class) do |receiver|
        klass = __posts_orig_model_class(receiver)
        klass == Post ? StatusMessage : klass
      end
    end

    # -------------------------------------------------------------------
    # 1. Collection materialization -> ITERABLE symbolic list.
    #
    # Same contract as the shared §C mock (concolic_targets.rb:449-453): same
    # var names (`<name>_rows`, `len(<name>_rows)`), same seed_for key, same
    # note (rendered SQL), same symbolic_instance representative. The ONLY
    # difference is the class, which adds the caller-side iteration wrapper.
    #
    # This does NOT swallow a branch: the query still runs through the declared
    # target, the length is still symbolic and seedable, and #empty?/#any?
    # still record. It only replaces a crash with an execution.
    #
    # NullRelation short-circuit: `PostInteractionPresenter#participations`
    # returns `@post.participations.none` when there is no current_user. A
    # NullRelation is DEFINED to be empty and issues no SQL, so there is no
    # query to preserve and no declared target beneath it. Without this,
    # iteration would fabricate a representative row for a relation that can
    # never have one — an unsound over-approximation that only became
    # observable once #each stopped raising.
    # -------------------------------------------------------------------
    rows_mock = lambda do |receiver, args, name|
      # results3 FIX (found live, render family now executes for real):
      # returning a bare `[]` here gets passed through the interceptor's
      # to_symbolic wrapping (a plain Array is not already-SymbolicVar-
      # tagged), producing a bare, non-iterable SymbolicList with NO
      # representative and note=nil — the exact "bare Array -> to_symbolic
      # re-wrap" bug class the file-header MOCK LEDGER documents for X6f.
      # `PostInteractionPresenter#participations` -> `@post.participations
      # .none` (NullRelation, no current_user) -> `.includes(...).map{...}`
      # then crashed on `SymbolicList#each`. Return a genuine EMPTY
      # IterableSymbolicList instead — concrete_length 0 needs no
      # representative and #each/#map correctly return [] without raising.
      next IterableSymbolicList.new(0, name: "#{name}_rows", note: "NullRelation (empty by definition, no SQL)",
                                    representative: nil) if null_rel && receiver.is_a?(null_rel)

      vn  = "#{name}_rows"
      sql = ct.sql_for(receiver, args)
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1),
                               name: vn, note: sql, representative: rep)
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    # ...AND on CollectionProxy, which OVERRIDES Relation#records.
    #
    # `ActiveRecord::Associations::CollectionProxy#records` (collection_proxy.rb
    # :1003) is `load_target` — its own method, so a target declared on
    # ActiveRecord::Relation never fires for it. `Relation::Delegation` sends
    # `each`/`map` to `records` (delegation.rb:71), so `@post.reshares.map` in
    # BasePresenter.as_collection (base_presenter.rb:14) went through the
    # UNMOCKED association path and produced a plain, non-iterable SymbolicList
    # — 259 of the dumps in the first overlay run still died on
    # `SymbolicList#each` for exactly this reason.
    #
    # Routing the association load through the same mock also makes it a
    # RECORDED symbolic query with rendered SQL, instead of letting
    # `load_target` wander into the statement cache.
    if cproxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cproxy.method_defined?(m) || cproxy.private_method_defined?(m)
        interceptor.declare_target(cproxy, m, returns: rows_mock)
      end
    end

    # -------------------------------------------------------------------
    # 2. Calculations#pluck / #ids -> iterable symbolic list.
    #
    # The shared file declares these `UNSUPPORTED` (concolic_targets.rb:469),
    # i.e. an unconditional raise. Replacing a raise with a symbolic value can
    # only reveal branches, never swallow one — and the branch this batch cares
    # about (`if public?` inside people_allowed_to_be_mentioned) lives in the
    # app body, which is untouched. The query is still recorded via sql_for.
    #
    # Element type is resolved from the plucked column so `pluck(:person_id)`
    # yields a SymbolicInt rep rather than a string. Multi-column pluck (rows
    # of arrays) is NOT modeled — it falls back to a single scalar rep, which
    # is wrong-shaped; no call site in this batch uses it, and it stays
    # reported rather than silently right-looking.
    # -------------------------------------------------------------------
    pluck_rep = lambda do |receiver, args, name, sql|
      col = args.values.compact.flatten.first if args.is_a?(Hash)
      col = col.to_s if col
      meta = begin
        k = ct.model_class(receiver)
        (col && k.respond_to?(:columns_hash)) ? k.columns_hash[col] : nil
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end
      vn = "#{name}_val"
      case meta && meta.type
      when :integer, :bigint then symint(vn, ct.seed_for(vn, 1), note: sql)
      when :boolean          then symbool(vn, ct.seed_for(vn, false), note: sql)
      else                        symstr(vn, ct.seed_for(vn, "#{vn}_v"), note: sql)
      end
    end

    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      vn  = "#{name}_plucked"
      sql = ct.sql_for(receiver, args)
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: sql,
                               representative: pluck_rep.call(receiver, args, name, sql))
    end)

    interceptor.declare_target(calc, :ids, returns: lambda do |receiver, args, name|
      vn  = "#{name}_ids"
      sql = ct.sql_for(receiver, args)
      rv  = "#{name}_id"
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: sql,
                               representative: symint(rv, ct.seed_for(rv, 1), note: sql))
    end)

    # -------------------------------------------------------------------
    # 3. Diaspora::Mentionable.people_from_string — REMOVED for results3
    #    (mission item 4; see concolic_targets.rb's file-header MOCK LEDGER).
    #    The shared X6f shape-override mock is gone; the real body now runs:
    #        identifiers = msg_text.to_s.scan(REGEX)...
    #        identifiers.compact.uniq.map { |id| find_or_fetch_person_by_identifier(id) }.compact
    #    Two things it needs, supplied below:
    #    (a) a TEXT IDENTITY SHIM so `.scan` works — `text` is UNSUPPORTED on
    #        SymbolicString by design (contents out of scope). Pin it to a
    #        concrete witness driven by a seeded boolean (same technique as
    #        results3/comments_index §4, itself ported from results3/
    #        notifications_index §5g/§5h): with mentions, a literal
    #        "@{...}"-shaped string that REGEX matches; without, plain text.
    #    (b) a NETWORK-I/O WALL on `fetch_and_save` (coordinator directive:
    #        network I/O must never fire) — only reachable if the local
    #        `find_by(diaspora_handle:)` (real, Patch-2-fixed target) misses.
    #    A THIRD thing (below, §3b) is PostsShowMentionLookupNaming: the real
    #    body is called from TWO independent call sites on this endpoint
    #    (PostPresenter#build_text -> @post.message -> mentioned_people, and
    #    PostPresenter#build_mentioned_people_json -> mentioned_people
    #    directly) — exactly comments_index's CommentsMentionLookupNaming
    #    problem (shared `find_by` ordinal moving target across call sites,
    #    and shifting post.rb's UNTOUCHED find_by_1/find_by_2 like_for/
    #    reshare_for ordinals whenever has_mention flips). Ported/adapted.
    # -------------------------------------------------------------------

    # (a) Text-identity shim. Layers on top of whatever symbolic_instance
    # wiring already exists (upgrade_ints!/upgrade_text! below) — aliasing
    # AGAIN here, called last, so it composes rather than replaces.
    unless ct.respond_to?(:symbolic_instance_without_mention_text_shim)
      class << ct
        alias_method :symbolic_instance_without_mention_text_shim, :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_mention_text_shim(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          if attrs.key?("text")
            hm_name = "#{base_name}_text_has_mention"
            has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
            # W10 (2026-09-10 drive, §46.9) — the text is EMPTYABLE.
            #
            # Before this the shim offered exactly TWO non-empty constants, so
            # `text.empty?` was False by construction and the corpus's own
            # `(SYM_RESULT_Anonymous_process_N == '')` decision — recorded by
            # ActiveSupport's escape path, unicode.rb:227 — could never be
            # observed True. That is a MODELLING gap, not an app fact: a real
            # diaspora StatusMessage can carry blank text (a photo-only post),
            # `posts.text` is nullable, and `Post#message` renders it. Pinning
            # the True side would have declared a mock's arbitrary constant as
            # if it were a property of the program. Widening the model closes
            # the branch instead, which is the direction the discipline asks
            # for: a mock may replace execution, never evidence.
            #
            # BOTH comparisons are evaluated UNCONDITIONALLY (no early exit) —
            # notifications' §5f correction: a companion compare left
            # unevaluated makes a cube demanding it unsatisfiable by any run.
            te_name = "#{base_name}_text_empty"
            text_empty = symbool(te_name, seed_for(te_name, false), note: sql)
            is_empty   = (text_empty == true)
            is_mention = (has_mention == true)
            attrs["text"] =
              if is_empty
                ""
              elsif is_mention
                "hello @{Concolic Mention; concolic_mention@example.org} welcome"
              else
                "hello world, a concolic message with no mentions"
              end
          end
          obj
        end
      end
    end

    # (b) Network-I/O wall.
    if defined?(DiasporaFederation::Discovery::Discovery) &&
       DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # -------------------------------------------------------------------
    # 4. ActsAsApi::Collection#as_api_response -> iterable list.
    #
    # Byte-identical to the shared X3 mock (concolic_targets.rb:920-932) except
    # for the class: it built a plain `symlist`, which raises the moment anything
    # downstream iterates the serialized collection. Length is made seedable
    # here too — X3 hard-coded 1, which is the "permanently inert var" trap the
    # addendum calls out.
    # -------------------------------------------------------------------
    if defined?(ActsAsApi::Collection)
      interceptor.declare_target(
        ActsAsApi::Collection, :as_api_response,
        returns: lambda do |receiver, _args, name|
          note = "ActsAsApi::Collection#as_api_response"
          klass = begin
            ct.model_class(receiver)
          rescue StandardError
            # results3 FIX (found live: build_mentioned_people_json's real
            # body now runs — X6k removed, MOCK LEDGER — so `receiver` can
            # genuinely be an EMPTY real Array when people_from_string finds
            # no mentions; `receiver.first` is then nil and `.class` was
            # NilClass, which Class#allocate cannot instantiate
            # (TypeError: allocator undefined for NilClass). Fall back to
            # Post for a non-Array-with-content receiver too, not just a
            # bare rescue.
            (receiver.is_a?(Array) && receiver.first) ? receiver.first.class : Post
          end
          rep = ct.symbolic_instance(klass, "#{name}_row", note)
          IterableSymbolicList.new(ct.seed_for("len(#{name})", 1),
                                   name: name, note: note, representative: rep)
        end
      )
    end

    warn "[posts] PostsTargets installed"

    # W3b (moved here from concolic_targets.rb by the Rule T re-sync,
    # 2026-09-09). ADJUDICATION: `ActiveRecord::Base#to_param` was declared in
    # this batch's private copy of the SHARED boundary and in no other batch
    # and not upstream — a Rule T divergence. It is a WALL MOCK, not
    # policy-bearing: Rails 5.2's body is literally `id && id.to_s`
    # (activerecord/lib/active_record/integration.rb:49-52), it issues NO SQL,
    # and `persisted?` is not a declared target anywhere, so mocking it
    # forecloses nothing. It exists only because SymbolicInt#to_s is
    # unsupported by design. Batch-local wall mocks belong HERE; the shared
    # boundary copy stays verbatim so it can be diffed against upstream.
    # Reached via `post_url @post`/`post_path` in PostPresenter#url (metas
    # render, html format) and Journey route generation.
    if ActiveRecord::Base.instance_methods.include?(:to_param)
      interceptor.declare_target(ActiveRecord::Base, :to_param, returns: lambda do |receiver, _args, name|
        id = receiver.respond_to?(:id) ? receiver.id : nil
        v = id.respond_to?(:value) ? id.value.to_s : id.to_s
        ConcreteSymbolicString.build(v, name: name, note: "ActiveRecord::Integration#to_param")
      end)
    end

    # -------------------------------------------------------------------
    # W7. THE HTML RENDER ARM — the three strings that reach Rails' escape
    # path, re-declared BATCH-LOCALLY so the boundary copy stays diffable
    # (Rule T1). `PostsTargets.install!` runs AFTER `ConcolicTargets.install!`
    # (run_dse.rb:76-77), so these override the boundary's own declarations.
    #
    # NOT INFERRED FROM THE LAST CALL EVENT. §42 named `Person#name` from the
    # dump's last CALL before the crash and wrapped it (§43); the post-wrap
    # dump is byte-identical to the pre-wrap one (135 events, 330 symbolic
    # vars, no Person var in EITHER), i.e. that wrap is a measured NO-OP and
    # `Person#name` was never the crashing string. The actual objects were
    # NAMED by a diagnostic prepend on `SymbolicString#scrub` (PSH_SCRUB_DIAG,
    # install! above) that prints `sym_name` and returns the concrete witness,
    # so ONE run enumerates EVERY string that reaches the escape path instead
    # of one run per failure point. It found exactly four values in three
    # families, and with them non-fatal the html run COMPLETED (error=None):
    #
    #   SYM_RESULT_Anonymous_process_2            MessageRenderer::Processor.process
    #   SYM_RESULT_Anonymous_process_3            (same target, 3rd call)
    #   SYM_RESULT_Diaspora__MessageRenderer_title_3  MessageRenderer#title
    #   SYM_RESULT_Photo_url_5_url                Photo#url
    #
    # All three are ALREADY declared SQL-free display targets on the boundary
    # (X6h, X6l, W5). Nothing here mocks anything new; each returns the SAME
    # value under the SAME name and note, in a render-safe carrier that keeps
    # its `==`/`!=` PC-visible. No statement is skipped and no comparison is
    # lost — the change is the CARRIER, not the value.
    # -------------------------------------------------------------------
    if defined?(Diaspora::MessageRenderer::Processor) &&
       Diaspora::MessageRenderer::Processor.respond_to?(:process)
      interceptor.declare_target(
        Diaspora::MessageRenderer::Processor.singleton_class, :process,
        returns: lambda do |_r, args, name|
          m = args["message"]
          v = m.respond_to?(:value) ? m.value : String(m)
          PcVisibleConcreteString.build(v.to_s, name: name,
                                        note: "Diaspora::MessageRenderer::Processor.process")
        end
      )
    end

    # X6l / W5 — plain ConcreteSymbolicString, NOT the PC-visible subclass.
    # Both return a value the MOCK invents (a constant title; a URL assembled
    # from the variable's own NAME), so no app datum controls it and every
    # comparison over it would be decided by the mock rather than by the
    # program. Recording them would mint permanently-one-sided expressions and
    # then require pins whose argument is about this file rather than about
    # the app. DECLARED GAP instead: the real `MessageRenderer#title` extracts
    # a heading from the post text and the real `Photo#url` is built from the
    # photo row, and NEITHER dependency is modelled here. Neither compare
    # appears anywhere in the corpus, so nothing is lost by not recording it.
    if defined?(Diaspora::MessageRenderer) &&
       Diaspora::MessageRenderer.instance_methods.include?(:title)
      interceptor.declare_target(
        Diaspora::MessageRenderer, :title,
        returns: lambda do |_r, _args, name|
          ConcreteSymbolicString.build("Concolic title", name: name,
                                       note: "Diaspora::MessageRenderer#title")
        end
      )
    end

    if defined?(Photo) &&
       (Photo.instance_methods.include?(:url) || Photo.private_instance_methods.include?(:url))
      interceptor.declare_target(Photo, :url, returns: lambda do |_receiver, _args, name|
        ConcreteSymbolicString.build("/uploads/#{name}_thumb.jpg",
                                     name: "#{name}_url", note: "Photo#url")
      end)
    end

    # -------------------------------------------------------------------
    # W11. CollectionProxy#size — the wall the W10 empty-text arm exposed.
    #
    # `ConcolicTargets` declares `size` on ActiveRecord::RELATION
    # (concolic_targets.rb:558), but `CollectionProxy` OVERRIDES `size`
    # (collection_proxy.rb:783 -> collection_association.rb:218), so that
    # declaration never fires on an association and the real body runs:
    #
    #   unsaved_records = target.select(&:new_record?)
    #   unsaved_records.size + count_records      # Integer + SymbolicInt
    #
    # `Integer#+` reflects onto `SymbolicInt#coerce`, which the runtime
    # refuses BY DESIGN ("reflected arithmetic would lose symbolic
    # tracking"). MEASURED, not inferred: with W10's empty text seeded,
    # `posts_helper.rb:17` takes the `post.photos.size` arm of
    # `post_page_title` and the run dies exactly there.
    #
    # This arm is REAL and the corpus has never driven it: a blank-text
    # StatusMessage renders `posts.show.photos_by` and reads `photos`.
    # `unsaved_records` is always [] in this rig (nothing is built unsaved),
    # so `size == count_records`, and returning the same seeded SymbolicInt
    # the Relation mock returns — under the same COUNT(*) note — is faithful
    # AND keeps the value symbolic instead of concretising it.
    # -------------------------------------------------------------------
    if cproxy && cproxy.instance_methods.include?(:size)
      interceptor.declare_target(cproxy, :size, returns: lambda do |receiver, args, name|
        vn = "#{name}_size"
        note = ct.sql_for(receiver, args)
        begin
          note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
        rescue StandardError
          nil # projection rewrite must never crash the mock (M-family rule)
        end
        symint(vn, ct.seed_for(vn, 1), note: note)
      end)
    end

    # -------------------------------------------------------------------
    # W8. Person.name_from_attrs — SHIM MOCK, replacing the X6i `Person#name`
    # TARGET mock now disabled in ./concolic_targets.rb (drive §46, D1).
    #
    # Real body (person.rb:254-256) is PURE string logic —
    #   first_name.blank? && last_name.blank? ? diaspora_handle
    #                                         : "#{first.strip} #{last.strip}".strip
    # — reaching ZERO target functions, and its output is DISPLAY data (the
    # presenter's `name` field and the `og:article:author` meta), never a
    # query argument. The only wall it clears is `SymbolicString#strip` on the
    # symbolic first/last-name columns. `Person#name` itself now runs FOR
    # REAL, so its `self.profile` read mints the profile-load evidence the
    # mocked version swallowed.
    #
    # A SINGLETON STUB, not an interceptor target: the return is a plain Ruby
    # String, display-only, and declaring a target here would re-introduce
    # exactly the note-less event D1 objects to. Byte-identical in mechanism
    # to comments_index/targets.rb §7.
    # -------------------------------------------------------------------
    if defined?(Person) && Person.respond_to?(:name_from_attrs)
      Person.define_singleton_method(:name_from_attrs) do |_first, _last, _handle|
        "Concolic Person Name"
      end
    end

  end
end

# =============================================================================
# PostsShowFinderNaming — CALL-SITE-STABLE finder naming (results2/posts_show
# completion pass, 2026-08-18). See COMPLETION_BRIEF.md + this dir's REPORT.md
# final ADDENDUM for why the generic per-run call-ordinal
# (`SYM_RESULT_<func>_<idx>`, minted in call_interceptor.rb:140) is UNSOUND
# here: `EvilQuery::VisibleShareableById#post!` (lib/evil_query.rb:102-105)
#
#     querent_has_visibility.first || querent_is_author.first || public_post.first
#
# makes up to 3 `.first` attempts, AND `PostService#find!` is invoked up to
# 3 TIMES per auth request:
#   1. PostsController#show's own `post_service.find!(params[:id])`
#   2. PostPresenter#with_initial_interactions (post_presenter.rb:27)
#      -> LikeService#find_for_post (like_service.rb:23-24) -> post_service.find!
#   3. PostPresenter#with_initial_interactions (post_presenter.rb:28)
#      -> ReshareService#find_for_post (reshare_service.rb:14-15) -> post_service.find!
# (`with_initial_interactions` only runs in the html format branch of
# PostsController#show; all three, when they fire at all, fire in this
# fixed textual order because Ruby evaluates a hash literal's values
# left-to-right and `likes:` precedes `reshares:`.) The shared
# `ActiveRecord::FinderMethods#first` counter mixes ALL of these calls
# (across BOTH scenarios, since anon's `find_public!` also ends in `.first`)
# into one moving-target ordinal — proven unsound in the prior attempt.
#
# FIX: tag every invocation with its (context x attempt) identity via a
# thread-local + one DEDICATED declared target per combo, ported from
# results2/conversations_index/targets.rb's `convidx_conv_lookup` pattern:
# alias a NEW method name off `.first` (its aliased body is irrelevant —
# `declare_target`'s body-skip mode never calls it, see call_interceptor.rb
# :135-149; what matters is `func_name = "#{klass_name}.#{method}"` is
# computed from the METHOD NAME PASSED TO declare_target, giving each alias
# its own `SymbolicFunc.next_call_idx` counter), then declare_target it
# separately. Each combo can fire at most once per request (short-circuit /
# single call site), so its dedicated counter is ALWAYS "_1" when it fires.
#
# CONTEXTS (who is calling PostService#find!/#find_public!, tagged via
# Thread.current[:posts_show_ctx], default "act" when unset):
#   act     — PostsController#show's own lookup
#   like    — LikeService#find_for_post
#   reshare — ReshareService#find_for_post
#
# ATTEMPTS inside EvilQuery::VisibleShareableById#post! (auth only), tried in
# this fixed `||` short-circuit order (evil_query.rb:109-122):
#   vis    — querent_has_visibility.first  (JOIN share_visibilities, user_id)
#   author — querent_is_author.first       (author_id = querent.person.id)
#   public — public_post.first             (public = true)
#
# Anon uses PostService#find_public! (post_service.rb:51-56) instead — ONE
# call, no attempt chain, but STILL invoked up to 3x per request (the same
# act/like/reshare contexts), so it gets 3 dedicated targets
# (findpublic_act/like/reshare) too. This is a deliberate departure from the
# brief's suggested single shared `findpublic_lookup` name: this pass uses
# the fully-explicit per-context form (matching the evilq_* shape exactly)
# instead of relying on a positional-ordinal argument ("a lone counter's
# _1/_2/_3 stay stable because these three contexts always fire in the same
# relative order") — that argument is very likely true here (verified: nothing
# else in this request path shares `.first` on a Post relation with
# find_public!), but per-context targets make the 1:1 mapping true BY
# CONSTRUCTION rather than by an argument about execution order, which is a
# strictly stronger guarantee for the same implementation cost. See REPORT.md.
#
# `find_by_1` (post.rb:143 `like_for`), `find_by_2` (post.rb:138
# `reshare_for`) and `assoc_profile_nsfw` (post.rb:161-162 `Post#nsfw`) are
# UNTOUCHED: they go through the separate `find_by`/predicate-reader
# boundaries, fire exactly once per request from PostPresenter#as_json's
# unconditional `build_interactions_json`/`non_directly_retrieved_attributes`
# (not from the act/like/reshare re-invocation chain), and were already
# verified single-decision in the prior (ordinal-era) investigation.
#
# NOTE on `source_location`: the runtime's `caller_frame`/`caller_frame_skip`
# walk (base.rb:76-84, call_interceptor.rb:403-411) only skips files under
# `ruby_runtime/` plus a fixed basename list — `concolic_targets.rb` (where
# `finder_mock`'s `if not_found == true` compare actually executes) is NOT
# in that list, so every finder-related PathCondition's recorded source is
# `concolic_targets.rb`'s `finder_mock` line, IDENTICAL across all 12
# dedicated targets (this was equally true, and equally uninformative, in
# the old shared-`first` scheme — the old REPORT.md's mapping was likewise
# derived from `target_name`/SQL-note pattern matching, not the `source`
# field). Attempt/context identity here is instead unambiguous BY
# CONSTRUCTION: `target_name` (e.g. "ActiveRecord::Relation.evilq_act_vis")
# is a literal, invariant string baked into the declared target itself —
# there is no runtime path by which e.g. an "author" attempt could ever
# produce a symbolic_call whose target_name says "vis". The mapping table in
# REPORT.md cross-checks this against each name's rendered SQL note (which
# DOES vary correctly per attempt: vis's note contains a `share_visibilities`
# JOIN, author's contains `author_id =`, public's contains `public` = TRUE,
# findpublic's contains the `id`/`guid` post_key column) as an independent
# proof that the target-name-encoded identity matches the real query shape.
# =============================================================================
module PostsShowFinderNaming
  CONTEXTS = %w[act like reshare].freeze
  ATTEMPTS = %w[vis author public].freeze

  def self.install!(interceptor = CallInterceptor.instance)
    ct  = ConcolicTargets
    rel = ActiveRecord::Relation

    # EvilQuery and LikeService are not in the shared concolic_targets.rb's
    # eager_files list (post_service/reshare_service are; evil_query/
    # like_service are not) — force-load them so the classes exist before we
    # prepend onto them below. Rescued: a missing file is reported, not fatal.
    %w[lib/evil_query app/services/like_service].each do |rel_path|
      path = File.join(Rails.root, "#{rel_path}.rb")
      next unless File.exist?(path)
      begin
        require_relative path
      rescue LoadError, StandardError => e
        warn "[posts_show naming] could not load #{path}: #{e.class} #{e.message[0, 80]}"
      end
    end

    unless defined?(EvilQuery::VisibleShareableById) && defined?(LikeService) &&
           defined?(ReshareService) && defined?(PostService)
      warn "[posts_show naming] one or more target classes undefined after load — " \
           "naming layer NOT installed (see REPORT.md)"
      return
    end

    # -- 1. Dedicated (context x attempt) targets for EvilQuery's chain, plus
    #       dedicated per-context targets for anon's find_public! ----------
    CONTEXTS.each do |ctx|
      ATTEMPTS.each do |attempt|
        name = :"evilq_#{ctx}_#{attempt}"
        rel.send(:alias_method, name, :first) unless rel.method_defined?(name)
        interceptor.declare_target(rel, name, returns: ct.finder_mock(raise_on_missing: false))
      end

      fname = :"findpublic_#{ctx}"
      rel.send(:alias_method, fname, :first) unless rel.method_defined?(fname)
      interceptor.declare_target(rel, fname, returns: ct.finder_mock(raise_on_missing: false))
    end

    # -- 2. EvilQuery::VisibleShareableById — tag + route the 3 attempts ----
    EvilQuery::VisibleShareableById.prepend(EvilQueryAttemptRouting) unless
      EvilQuery::VisibleShareableById < EvilQueryAttemptRouting

    # -- 3. PostService#find_public! — context-routed replacement ----------
    PostService.prepend(FindPublicRouting) unless PostService < FindPublicRouting

    # -- 4. LikeService / ReshareService — tag context around find_for_post -
    LikeService.prepend(LikeServiceContextTag) unless LikeService < LikeServiceContextTag
    ReshareService.prepend(ReshareServiceContextTag) unless ReshareService < ReshareServiceContextTag

    warn "[posts_show] PostsShowFinderNaming installed"
  end

  def self.current_ctx
    Thread.current[:posts_show_ctx] || "act"
  end

  # Runner calls this so a leaked context from a crashed prior run can never
  # bleed into the next run_one call (defense in depth; LikeServiceContextTag/
  # ReshareServiceContextTag already restore via ensure on the happy path).
  def self.reset_ctx!
    Thread.current[:posts_show_ctx] = nil
  end

  def self.with_ctx(tag)
    prev = Thread.current[:posts_show_ctx]
    Thread.current[:posts_show_ctx] = tag
    yield
  ensure
    Thread.current[:posts_show_ctx] = prev
  end

  # Tag the relation `super` just built with a singleton `#first` that routes
  # to this (ctx, attempt)'s dedicated target instead of the generic `.first`
  # `post!` (evil_query.rb:104) will call on it. Does NOT change what query
  # the relation represents — only what `.first` boundary records it under.
  def self.route_first(rel, attempt)
    target = :"evilq_#{current_ctx}_#{attempt}"
    rel.define_singleton_method(:first) { |*a| public_send(target, *a) }
    rel
  end

  module EvilQueryAttemptRouting
    def querent_has_visibility
      PostsShowFinderNaming.route_first(super, "vis")
    end

    def querent_is_author
      PostsShowFinderNaming.route_first(super, "author")
    end

    def public_post
      PostsShowFinderNaming.route_first(super, "public")
    end
    protected :querent_has_visibility, :querent_is_author, :public_post
  end

  module FindPublicRouting
    # Faithful re-implementation of PostService#find_public! (post_service.rb
    # :51-56) — identical raise conditions/messages/query. The ONLY change is
    # which `.first`-boundary the finder call is recorded under. No `super`:
    # find_public!'s body is one line (build relation, call `.first`) with no
    # separate protected method to override the way EvilQuery's 3 attempts
    # have, so the whole (unchanged) body is reproduced here instead.
    def find_public!(id_or_guid)
      tag = :"findpublic_#{PostsShowFinderNaming.current_ctx}"
      Post.where(post_key(id_or_guid) => id_or_guid).public_send(tag).tap do |post|
        raise ActiveRecord::RecordNotFound, "could not find a post with id #{id_or_guid}" unless post
        raise Diaspora::NonPublic unless post.public?
      end
    end
    private :find_public!
  end

  module LikeServiceContextTag
    def find_for_post(post_id)
      PostsShowFinderNaming.with_ctx("like") { super }
    end
  end

  module ReshareServiceContextTag
    def find_for_post(post_id)
      PostsShowFinderNaming.with_ctx("reshare") { super }
    end
  end
end

# =============================================================================
# PostsShowMentionLookupNaming — CALL-SITE-STABLE finder naming for the local
# Person lookup inside Diaspora::Mentionable.people_from_string (results3
# completion pass, mission item 4). Ported technique from
# results3/comments_index/targets.rb's `CommentsMentionLookupNaming` (same
# root cause, same cure), which itself ported PostsShowFinderNaming's own
# (context x attempt) dedicated-alias pattern above.
#
# THE PROBLEM: `PostPresenter#non_directly_retrieved_attributes` computes
# `@post.mentioned_people` in TWO independent places (app/presenters/
# post_presenter.rb) —
#
#   text:             build_text -> @post.message.plain_text_for_json
#                        -> Post#message (MentionsContainer) ->
#                           MessageRenderer.new(text, mentioned_people: mentioned_people)
#                        -> calls #mentioned_people INTERNALLY (call site "msg")
#   mentioned_people:  build_mentioned_people_json -> @post.mentioned_people
#                        .as_api_response(:backbone)   (call site "json")
#
# — and `MentionsContainer#mentioned_people` (persisted? always false on a
# symbolic_instance record, @new_record forced true — concolic_targets.rb's
# symbolic_instance, nil-@attributes section) always calls
# `Diaspora::Mentionable.people_from_string(text)`, which
# (lib/diaspora/mentionable.rb:88-90) calls `Person.find_or_fetch_by_identifier`
# (app/models/person.rb:318-328):
#
#   def self.find_or_fetch_by_identifier(diaspora_id)
#     person = by_account_identifier(diaspora_id)                      # ATTEMPT "first"
#     return person if person.present? && person.profile.present?
#     DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save  # WALLED (targets.rb §3b)
#     by_account_identifier(diaspora_id)                                # ATTEMPT "retry"
#   end
#   def self.by_account_identifier(diaspora_id)
#     find_by(diaspora_handle: diaspora_id.strip.downcase)
#   end
#
# Both call sites (msg, json) reach this SAME `find_by` on the SAME shared
# `ActiveRecord::Core::ClassMethods.find_by` counter (`SYM_RESULT_
# ActiveRecord__Core__ClassMethods_find_by_<idx>`, minted per-run in
# call_interceptor.rb:140) — and each site can call it up to TWICE (first +
# retry). The counter mixes up to 4 semantically DIFFERENT decisions under
# one moving-target ordinal, whose identity shifts across runs depending on
# which sites retried — the main README's "per-run call ordinal" failure
# mode. Fix: one DEDICATED declared target per (site x attempt) combo, so
# each is ALWAYS "_1" when it fires, by construction.
#
# CALL SITES (tagged via Thread.current[:posts_show_mention_ctx], default
# "json" when unset — matches CommentsMentionLookupNaming's convention):
#   msg  — Post#message's internal `mentioned_people:` kwarg build (via
#          PostPresenter#build_text)
#   json — PostPresenter#build_mentioned_people_json's own direct call
#
# ATTEMPTS inside Person.find_or_fetch_by_identifier, in this fixed order:
#   first — the initial by_account_identifier(diaspora_id) call
#   retry — the POST-fetch_and_save by_account_identifier(diaspora_id) call
#
# NEITHER PostPresenter's methods NOR Person.find_or_fetch_by_identifier's
# BODY changes — both prepends below are FAITHFUL reimplementations of the
# real, unchanged bodies (same technique as PostsShowFinderNaming's
# FindPublicRouting reproducing find_public! verbatim, and comments_index's
# PersonFindOrFetchNaming): the only change is which declared target
# boundary each `find_by` call is recorded under. build_text/
# build_mentioned_people_json are wrapped via `prepend`+`super` instead of
# reproducing the whole `non_directly_retrieved_attributes` Hash literal
# (unlike CommentPresenter#as_json, PostPresenter's Hash has many unrelated
# fields — wrapping just the two relevant private methods is smaller
# surface and cannot drift from the real body of anything else in that Hash).
# =============================================================================
module PostsShowMentionLookupNaming
  SITES    = %w[msg json].freeze
  ATTEMPTS = %w[first retry].freeze

  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    unless defined?(PostPresenter) && defined?(Person) &&
           Person.respond_to?(:find_or_fetch_by_identifier)
      warn "[posts_show mention naming] PostPresenter/Person.find_or_fetch_by_identifier " \
           "undefined — naming layer NOT installed"
      return
    end

    core = ActiveRecord::Core::ClassMethods

    # -- 1. Dedicated (site x attempt) targets, aliased off the SAME
    #       Core::ClassMethods#find_by the shared design-#2 mock already
    #       declares — identical returns: lambda (finder_mock(raise_on_missing:
    #       false)), so note fidelity (Phase A Patch 2's class_finder_sql,
    #       honest kwargs fallback included) is unchanged; only the counter
    #       identity differs. --------------------------------------------
    SITES.each do |site|
      ATTEMPTS.each do |attempt|
        name = :"mention_lookup_#{site}_#{attempt}"
        core.send(:alias_method, name, :find_by) unless core.method_defined?(name)
        interceptor.declare_target(core, name, returns: ct.finder_mock(raise_on_missing: false))
      end
    end

    # -- 2. Person.find_or_fetch_by_identifier — context-routed replacement,
    #       faithful to app/models/person.rb:318-328. ---------------------
    Person.singleton_class.prepend(PersonFindOrFetchNaming) unless
      Person.singleton_class < PersonFindOrFetchNaming

    # -- 3. PostPresenter#build_text / #build_mentioned_people_json — tag
    #       "msg" / "json" respectively around the two independent call
    #       sites into #mentioned_people. Both are PRIVATE methods on
    #       PostPresenter; prepend+super leaves their (unchanged) bodies
    #       untouched. -------------------------------------------------
    PostPresenter.prepend(PostPresenterMentionContextTag) unless
      PostPresenter < PostPresenterMentionContextTag

    warn "[posts_show mention naming] PostsShowMentionLookupNaming installed"
  end

  def self.current_ctx
    Thread.current[:posts_show_mention_ctx] || "json"
  end

  # Runner calls this so a leaked context from a crashed prior run can never
  # bleed into the next run_one call (defense in depth; with_ctx already
  # restores via ensure on the happy path).
  def self.reset_ctx!
    Thread.current[:posts_show_mention_ctx] = nil
  end

  def self.with_ctx(tag)
    prev = Thread.current[:posts_show_mention_ctx]
    Thread.current[:posts_show_mention_ctx] = tag
    yield
  ensure
    Thread.current[:posts_show_mention_ctx] = prev
  end

  module PersonFindOrFetchNaming
    def find_or_fetch_by_identifier(diaspora_id)
      site = PostsShowMentionLookupNaming.current_ctx
      handle = diaspora_id.strip.downcase

      first_target = :"mention_lookup_#{site}_first"
      person = public_send(first_target, diaspora_handle: handle)
      return person if person.present? && person.profile.present?

      logger.info "webfingering #{diaspora_id}, it is not known or needs updating"
      DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save

      retry_target = :"mention_lookup_#{site}_retry"
      public_send(retry_target, diaspora_handle: handle)
    end
  end

  module PostPresenterMentionContextTag
    def build_text
      PostsShowMentionLookupNaming.with_ctx("msg") { super }
    end

    def build_mentioned_people_json
      PostsShowMentionLookupNaming.with_ctx("json") { super }
    end
  end
end
