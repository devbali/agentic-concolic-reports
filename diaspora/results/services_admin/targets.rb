# frozen_string_literal: true
#
# Per-batch concolic targets — `services_admin`.
#
# Installed AFTER ConcolicTargets.install!. `declare_target` uses define_method,
# so a later declaration REPLACES an earlier one (last-one-wins), which is how
# the overrides below re-point the shared count target without editing
# `reports/diaspora/concolic_targets.rb` (shared by all 13 batches).
#
#   ConcolicTargets.install!(interceptor)      # shared generic AR interception
#   ServicesAdminTargets.install!(interceptor) # this file
#
# Discipline (README wall-fixing rules): every mock here either
#   (a) wraps a SQL-free leaf that calls no other declared target, or
#   (b) RE-ISSUES the declared target beneath it (§1), so no query is hidden, or
#   (c) changes only the SHAPE / VALUE-CLASS of what a shared mock returns
#       (§2, §3, §4) — same query, same var name, same seed wiring.
# No mock swallows the branch it guards. §1 exists precisely to CREATE a branch
# the runtime could not previously record.
#
# NOTHING under src/ is modified. Where the previous round said "this needs a
# src/ruby_runtime change", §2 closes it with a batch-local SUBCLASS of the
# runtime's own symbolic class instead (the pattern proven in
# results/photos/targets.rb §6).

module ServicesAdminTargets
  module_function

  # =====================================================================
  # 1. THE ADMIN AUTHORIZATION GATE — the headline fix.
  #
  # PROBLEM (previous round, all 7 admin_* entrypoints):
  #   before_action :redirect_unless_admin            admin/admin_controller.rb:6
  #   def redirect_unless_admin                       application_controller.rb:110
  #     return if current_user.admin?
  #     redirect_to stream_url, notice: "you need to be an admin to do that"
  #   end
  #   User#admin? -> Role.is_admin?(person) -> Role.exists?(person_id:, name:)
  #
  # `Role.exists?` is DESIGN target #3 and returns a SymbolicBool, which is then
  # consumed by a BARE truthiness test (`return if ...`). Every non-nil,
  # non-false Ruby object is truthy and `if obj` calls no method, so:
  #   * no path condition was ever recorded for the gate, and
  #   * the gate was PINNED OPEN — with the role query answering `false`
  #     ("not an admin") all 33 runs still executed the admin-only action
  #     bodies, and `redirect_to stream_url` was unreachable under any seeding.
  #
  # FIX — the `col?` predicate-reader pattern from
  # `ConcolicTargets.symbolic_instance` (concolic_targets.rb:237): record the
  # PC at the predicate boundary and hand the app a CONCRETE truth value.
  #
  # Why this is NOT "mocking away the branch", and NOT the old `admin?` stub:
  #   * the old runner did `user.define_singleton_method(:admin?) { true }` —
  #     hand-replicated app logic that bypassed Role.is_admin? and its SQL
  #     entirely, and hid the defect. This mock does the opposite: it RE-ISSUES
  #     `Role.exists?` / `Role.moderators.exists?` from inside the lambda, so
  #     the real query still fires through declared target #3 and still appears
  #     in the dump with its SQL note. Nothing is hidden beneath the mock.
  #   * `Role.is_admin?`'s own body IS that one query — there is no `if` in it
  #     to swallow. The `if` lives in redirect_unless_admin, which is NOT
  #     mocked and now branches for real.
  #   * the PC is recorded on the exists? var, which the shared mock already
  #     feeds through `seed_for`, so DSE's flip actually drives the gate.
  #
  # RETURN-VALUE TRICK (non-obvious, and load-bearing):
  #   CallInterceptor re-wraps a mock's `true`/`false` return via to_symbolic
  #   (call_interceptor.rb:174-182) into a SymbolicBool — which would re-open
  #   the very truthiness gap we are closing. `nil` is passed through unchanged
  #   (to_symbolic(nil) => nil) and is FALSY in Ruby. So the mock returns `true`
  #   for the positive case (wrapped, still truthy) and `nil` for the negative
  #   case (falsy). Both branches then become real Ruby control flow.
  # =====================================================================
  def recording_role_predicate(interceptor, role_class, method, op_label, &query)
    return unless role_class.respond_to?(method)

    interceptor.declare_target(role_class.singleton_class, method, returns: lambda do |_recv, args, _name|
      person = args["person"]
      raw = begin
        query.call(person)
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn "[services_admin] #{op_label} query failed: #{e.class}: #{e.message.to_s[0, 80]}"
        nil
      end

      val = raw.respond_to?(:value) ? !!raw.value : !!raw
      if raw.respond_to?(:sym_name) && raw.sym_name
        # Record the branch at the predicate boundary, on the SEEDABLE var the
        # exists? mock minted, so DSE's single-branch flip closes it.
        raw.send(:record!, "(#{raw.sym_name} == True)", op_label, taken: val)
      end
      [val ? true : nil, "Bool"]
    end)
  end

  # =====================================================================
  # 2. ConcolicArithInt — arithmetic-capable SymbolicInt (batch-local subclass).
  #
  # `SymbolicInt` raises NotImplementedError for +, -, to_i, to_f, next, ...
  # (int.rb:57-66) to stop silent concretization. That produced THREE of this
  # batch's walls:
  #
  #   a) `InvitationCode#add_invites!` (invitation_code.rb:19)
  #      `self.update_attributes(count: self.count+100)`   -> SymbolicInt#+
  #   b) `AdminsController#percent_change` (admins_controller.rb:95)
  #      `((today-yesterday) / yesterday.to_f)*100`        -> SymbolicInt#-
  #   c) `current_user.services << service` (services_controller.rb:24)
  #      CollectionAssociation#set_owner_attributes does
  #      `record[fk] = owner["id"]`, and AR reads it back through
  #      ActiveModel::Type::Integer#cast_value -> value.to_i -> SymbolicInt#to_i
  #
  # The runtime's classes are ordinary Ruby classes with public readers, so a
  # batch-local SUBCLASS closes all three without touching src/. Each op returns
  # a new instance carrying a DERIVED sym_name — exactly the shape of
  # `SymbolicInt#-@` (int.rb:79), which already chooses a sound symbolic result
  # over raising. Tracking is preserved, not concretized.
  #
  # Honest limits, reported rather than hidden:
  #   * a derived name like `(SYM_x + 100)` is not a bare identifier, so
  #     run_dse.rb's flip_seed cannot invert a PC written in terms of it. Such
  #     PCs are counted in `unflippable_pcs`, never silently dropped.
  #   * derived vars are NOT registered with SymbolicFunc (mirroring `-@`), so
  #     they are not declared in the dump's symbolic_vars.
  #   * `to_i`/`to_int` DO concretize. That is the point at (c): AR's integer
  #     type-cast needs an Integer and there is nothing symbolic to preserve on
  #     the other side of it. Scoped to this batch only.
  #   * an op whose result is not an Integer (e.g. Int / Float in
  #     percent_change) returns the plain Ruby result: the runtime has no
  #     symbolic Real, so tracking ends at the Int -> Float boundary.
  #
  # `zero?` / `positive?` / `negative?` additionally RECORD a path condition
  # before returning their concrete answer — the same predicate-reader pattern
  # as §1, turning three more bare-truthiness sites into real branches.
  # =====================================================================
  def define_arith_int!
    return if defined?(::ConcolicArithInt)

    ::Object.const_set(:ConcolicArithInt, Class.new(SymbolicInt) do
      def derive(res, expr)
        return res unless res.is_a?(Integer)

        ::ConcolicArithInt.new(res, name: expr, note: note)
      end

      def combine(other, op)
        ov  = other.is_a?(SymbolicVar) ? other.value : other
        res = value.send(op, ov)
        rhs = other.respond_to?(:sym_name) && other.sym_name ? other.sym_name : ov.inspect
        derive(res, sym_name ? "(#{sym_name} #{op} #{rhs})" : nil)
      end

      %i[+ - * / % ** div modulo remainder & | ^ << >>].each do |op|
        define_method(op) { |other| combine(other, op) }
      end

      %i[abs round floor ceil truncate].each do |op|
        define_method(op) do |*a|
          derive(value.send(op, *a), sym_name ? "(#{op} #{sym_name})" : nil)
        end
      end

      def next
        combine(1, :+)
      end
      alias_method :succ, :next

      def pred
        combine(1, :-)
      end

      # Deliberate concretization boundary — see the header comment (c).
      def to_i
        value
      end
      alias_method :to_int, :to_i

      def to_f
        value.to_f
      end

      def to_r
        value.to_r
      end

      def coerce(other)
        [other, value]
      end

      # Predicate readers: record the branch, answer concretely (as §1 does).
      def zero?
        res = value.zero?
        record!("(#{sym_name || value} == 0)", "zero?", taken: res)
        res
      end

      def positive?
        res = value.positive?
        record!("(#{sym_name || value} > 0)", "positive?", taken: res)
        res
      end

      def negative?
        res = value.negative?
        record!("(#{sym_name || value} < 0)", "negative?", taken: res)
        res
      end

      # Not branch-shaped in Z3 terms; concrete, no PC. Not used by this batch,
      # present so a stray call is not a wall.
      def odd?
        value.odd?
      end

      def even?
        value.even?
      end

      def integer?
        true
      end
    end)
  end

  # =====================================================================
  # 2b. ConcolicRegexString — regex-predicate-capable SymbolicString.
  #
  # WALL (services_invite, 12 of 18 dumps): `Profile#build_image_url`
  # (profile.rb:170) is
  #     return nil if url.blank? || url.match(/user\/default/)
  #     return url if url.match(%r{^https?://})
  # and `SymbolicString#match` raises (string.rb:334) — the runtime tracks only
  # `==`/`!=` on strings by design.
  #
  # build_image_url CANNOT be mocked: its body IS the branch (this is the
  # regression the photos batch documented). So fix the VALUE instead, with the
  # same batch-local-subclass technique as §2.
  #
  # A regex match is not expressible in the `(VAR op LITERAL)` PC grammar this
  # rig uses, so the predicate is abstracted as a FRESH seedable boolean —
  # exactly the concolic_engine's "untracked" notion — recorded at the
  # predicate boundary and answered concretely, so the app branches for real.
  #
  # SOUNDNESS CAVEAT, stated plainly:
  #   the fresh boolean is INDEPENDENT of the string's concrete value. Its
  #   DEFAULT is the true concrete answer (`value =~ re`), so an unflipped run
  #   is exact. When DSE flips it, the path explored is one that some URL could
  #   take, but the concrete witness in that dump (the string's seeded value)
  #   no longer satisfies the regex. The path is reachable; the witness is not
  #   a model of it. No other mock in this batch has this property.
  # =====================================================================
  def define_regex_string!
    return if defined?(::ConcolicRegexString)

    ::Object.const_set(:ConcolicRegexString, Class.new(SymbolicString) do
      def as_regexp(re)
        re.is_a?(Regexp) ? re : Regexp.new(Regexp.escape(re.to_s))
      end

      def regex_predicate(re, label)
        rx   = as_regexp(re)
        slug = rx.source.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 40]
        slug = "re" if slug.nil? || slug.empty?
        vn   = "#{sym_name || 'str'}_match_#{slug}"
        sym  = symbool(vn, ConcolicTargets.seed_for(vn, !(value =~ rx).nil?), note: note)
        ans  = sym.value
        sym.send(:record!, "(#{vn} == True)", label, taken: ans)
        ans
      end

      def match(re, *_a)
        return nil unless regex_predicate(re, "match")

        value.match(as_regexp(re)) || true
      end

      def match?(re, *_a)
        regex_predicate(re, "match?")
      end

      def =~(re)
        regex_predicate(re, "=~") ? ((value =~ as_regexp(re)) || 0) : nil
      end
    end)
  end

  def arith_int(name, val, note: nil)
    SymbolicFunc.register_var(name: name, sort: "Int", value: val, note: note) if defined?(SymbolicFunc)
    ::ConcolicArithInt.new(val, name: name, note: note)
  end

  # =====================================================================
  # 3. STI-aware symbolic instances + arithmetic integer columns.
  #
  # PROBLEM (services_invite): `Service.where(uid: ...).first` routes through
  # the shared finder_mock, which allocates the BASE `Service`. Base
  # `Service#provider` is a bare `attr_accessor` (service.rb:8), so it is nil on
  # an allocated record and `service.provider.camelize`
  # (services_controller.rb:55) raises `NoMethodError: undefined method
  # 'camelize' for nil`. In production that row is ALWAYS an STI subclass
  # (`services.type` is NOT NULL, schema.rb:494) whose `provider` returns a real
  # constant ("twitter" / "tumblr" / "wordpress").
  #
  # FIX: wrap the shared `ConcolicTargets.symbolic_instance` (the shared FILE is
  # untouched — this is a runtime alias, the same technique photos/targets.rb §6a
  # uses). When the requested class is the BASE of an STI hierarchy — it has an
  # inheritance column and descends directly from ActiveRecord, which is exactly
  # the negation of AR's own `finder_needs_type_condition?` test — allocate a
  # concrete SUBCLASS instead and pin the `type` column to that subclass's name
  # so the record is internally consistent. Which subclass is SEEDABLE via
  # `<base_name>_type`; the default is the first subclass by name.
  #
  # This is not a hidden query: same finder mock, same SQL note, same
  # `_not_found` PC. Only the allocated Ruby class changes — and base `Service`
  # is never a real row, so a subclass is the strictly better approximation.
  #
  # The wrapper also re-wraps every integer column as a ConcolicArithInt (§2),
  # which is what unblocks `InvitationCode#count + 100` and the AR foreign-key
  # type-cast. Doing it in the wrapper covers EVERY producer at once (the
  # finder mocks, W3 find_target, the DESIGN #4 representative row, and the
  # runner's own symbolic current_user) instead of re-declaring each target.
  #
  # Honest limits:
  #   * nothing branches on `type`, so DSE never flips it; only the default
  #     subclass is explored unless seeded by hand.
  #   * the resolution is generic, so any STI base (Post, Notification, ...)
  #     would also resolve to a subclass. No entrypoint in this batch builds
  #     such an instance, so nothing else is affected here — but the choice is
  #     batch-local for exactly that reason.
  # =====================================================================
  def sti_class_for(klass, base_name)
    ic = klass.inheritance_column
    return [klass, nil] unless klass.columns_hash.key?(ic)
    return [klass, nil] unless klass.descends_from_active_record?

    subs = klass.descendants
                .reject { |d| d.respond_to?(:abstract_class?) && d.abstract_class? }
                .select(&:name)
                .sort_by(&:name)
    return [klass, nil] if subs.empty?

    var  = "#{base_name}_#{ic}"
    want = ConcolicTargets.seed_for(var, subs.first.name)
    [subs.find { |d| d.name == want } || subs.first, ic]
  rescue Exception # rubocop:disable Lint/RescueException
    [klass, nil]
  end

  def install_symbolic_instance_wrapper!
    return if ConcolicTargets.respond_to?(:symbolic_instance_plain)

    class << ConcolicTargets
      alias_method :symbolic_instance_plain, :symbolic_instance

      def symbolic_instance(klass, base_name, sql)
        resolved, ic = ServicesAdminTargets.sti_class_for(klass, base_name)
        obj = symbolic_instance_plain(resolved, base_name, sql)

        if obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          # Pin `type` to the class we actually allocated. The column readers
          # close over this same Hash, so writing here updates them too.
          attrs[ic] = symstr("#{base_name}_#{ic}", resolved.name, note: sql) if ic
          # Give every integer column arithmetic (§2) and every string column
          # regex predicates (§2b). Same names, values and notes — only the
          # value CLASS changes, so seeding and registration are untouched.
          attrs.each do |col, v|
            if v.is_a?(SymbolicInt) && !v.is_a?(::ConcolicArithInt)
              attrs[col] = ::ConcolicArithInt.new(v.value, name: v.sym_name, note: v.note)
            elsif v.instance_of?(SymbolicString)
              attrs[col] = ::ConcolicRegexString.new(v.value, name: v.sym_name, note: v.note)
            end
          end
        end
        obj
      end
    end
  end

  # =====================================================================
  # 4. Grouped `Calculations#count` returns a Hash-shaped result.
  #
  # PROBLEM (admin_stats): AR's `.group(x).count` returns a Hash
  # {group_key => count}, but DESIGN mock #5 returns a scalar SymbolicInt for
  # EVERY count. `admins_controller.rb:83` then does
  # `@posts_per_day.values.max.to_f` -> `NoMethodError: undefined method
  # 'values'`. That is a SHAPE BUG in the mock, not an app outcome.
  #
  # FIX: when the receiving relation is grouped (`receiver.group_values.any?`),
  # return a one-entry group-key => count result — the direct analogue of
  # DESIGN #4's "one representative row" for collections. The count stays
  # SYMBOLIC and seedable; it is deliberately not concretized.
  #
  # A plain Hash return cannot be used: CallInterceptor converts Hash results
  # into a SymbolicDict (call_interceptor.rb:177), which has no #values. The
  # tiny value object below is passed through unchanged and carries #note so
  # the symbolic_call event still shows the SQL.
  # =====================================================================
  # NOTE — deliberately NOT `include Enumerable`.
  #
  # The notifications_tags batch found that including Enumerable in a symbolic
  # subclass silently DESTROYS path conditions: a module included into a
  # subclass is inserted BEFORE the superclass in the ancestor chain, so
  # `Enumerable#any?` / `#none?` / `#count` shadow the PC-recording
  # `SymbolicList` versions (8 PCs -> 4 on an otherwise green run).
  #
  # GroupedCount's superclass is Object, not a symbolic class, so it had nothing
  # to shadow — measured at 2972 PCs across the batch both with and without the
  # include (see REPORT §3.3). It is removed anyway as a guard: this class is a
  # deliberately thin, explicit delegation to a Hash, and every method it needs
  # is named here rather than inherited.
  class GroupedCount
    attr_reader :note

    def initialize(hash, note)
      @h = hash
      @note = note
    end

    def each(&blk); @h.each(&blk); end
    def map(&blk);  @h.map(&blk);  end
    def values;     @h.values;    end
    def keys;       @h.keys;      end
    def [](k);      @h[k];        end
    def size;       @h.size;      end
    def length;     @h.length;    end
    def count;      @h.size;      end
    def empty?;     @h.empty?;    end
    def to_a;       @h.to_a;      end
    def to_h;       @h;           end
    def to_s;       @h.to_s;      end
    def inspect;    "<GroupedCount #{@h.inspect}>"; end
  end

  # =====================================================================

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    define_arith_int!
    define_regex_string!

    # --- load the STI subclasses so Service.descendants is populated -----
    if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
      Dir.glob(File.join(Rails.root, "app/models/services/*.rb")).sort.each do |f|
        begin
          require_relative f
        rescue LoadError, StandardError => e
          warn "[services_admin] could not load #{f}: #{e.class} #{e.message.to_s[0, 80]}"
        end
      end
    end

    install_symbolic_instance_wrapper!

    # ---------------------------------------------------------------------
    # 1a. Gate predicates (see §1). Each RE-ISSUES the real query.
    #
    # NOTE: `defined?(Role)` is NOT usable here — Rails 5.2 autoloads via
    # const_missing and `defined?` does not trigger it, so the guard silently
    # skipped every declaration on the first attempt (smoke run: gate still
    # unrecorded). Force the constant to load instead.
    # ---------------------------------------------------------------------
    role = begin
      ::Object.const_get(:Role)
    rescue NameError => e
      warn "[services_admin] Role not loadable, gate targets skipped: #{e.class}"
      nil
    end

    if role
      recording_role_predicate(interceptor, role, :is_admin?, "Role.is_admin?") do |person|
        role.exists?(person_id: person && person.id, name: "admin")
      end
      recording_role_predicate(interceptor, role, :moderator?, "Role.moderator?") do |person|
        role.moderators.exists?(person_id: person && person.id)
      end
      recording_role_predicate(interceptor, role, :moderator_only?, "Role.moderator_only?") do |person|
        role.exists?(person_id: person && person.id, name: "moderator")
      end
      recording_role_predicate(interceptor, role, :spotlight?, "Role.spotlight?") do |person|
        role.exists?(person_id: person && person.id, name: "spotlight")
      end
    end

    # ---------------------------------------------------------------------
    # 1b. Make `redirect_to` ENFORCE the halt it stands for.
    #
    # Without this, §1a records the gate branch but the gate still does not
    # gate: the shared Y3/X1 targets make redirect_to a pure marker that never
    # sets a response, so `performed?` stays false and
    # AbstractController::Callbacks' terminator
    # (`result_lambda.call; controller.performed?`, callbacks.rb:34) does NOT
    # halt the before_action chain — the admin-only action body would run
    # anyway. Reporting "both sides of the gate are now reachable" while the
    # non-admin side still executes the admin body would be a half-fix.
    #
    # Setting @_response_body directly is what makes `performed?` true
    # (metal.rb:184) WITHOUT touching @_response, which is nil in this rig.
    # Every other aspect of the shared terminal-marker behaviour is preserved.
    # This also makes the app's other guard clauses (abort_if_already_authorized,
    # abort_if_read_only_access, validate_user) halt as they do in production.
    # ---------------------------------------------------------------------
    mark_performed = lambda do |receiver, _args, _n|
      begin
        receiver.instance_variable_set(:@_response_body, ["<concolic redirect>"])
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end
      :redirect_reached
    end
    if defined?(ActionController::Redirecting)
      interceptor.declare_target(ActionController::Redirecting, :redirect_to, returns: mark_performed)
    end
    if defined?(ActionController::Instrumentation) &&
       ActionController::Instrumentation.instance_methods.include?(:redirect_to)
      interceptor.declare_target(ActionController::Instrumentation, :redirect_to, returns: mark_performed)
    end

    # ---------------------------------------------------------------------
    # 1c. Same halt semantics for an explicit `render`.
    #
    # Found by the run that added 1b: `ServicesController#redirect_to_origin`
    # (services_controller.rb:66) ends in `render(text: "<script>…</script>")`
    # when there is no omniauth origin, and it is called from the
    # `abort_if_already_authorized` BEFORE_ACTION. With the shared render
    # marker not setting a response, the chain did not halt and
    # `ServicesController#create` ran anyway — producing 16 of the 32
    # services_invite paths along an execution that cannot happen in
    # production (the app had already responded). Those are infeasible paths,
    # not coverage.
    #
    # "Render is terminal" (README decision A) means we stop modelling the
    # VIEW; the controller's own halt is app control flow and must be
    # preserved. render_to_string / render_to_body do NOT respond and are left
    # as-is. The shared mock's @_response fix-up is kept.
    # ---------------------------------------------------------------------
    if defined?(ActionController::Rendering)
      interceptor.declare_target(ActionController::Rendering, :render, returns: lambda do |receiver, _args, _n|
        unless receiver.instance_variable_get(:@_response)
          reply = receiver.respond_to?(:reply) ? receiver.reply : nil
          receiver.instance_variable_set(:@_response, reply) if reply
        end
        begin
          receiver.instance_variable_set(:@_response_body, ["<concolic render>"])
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        :render_reached
      end)
    end

    # ---------------------------------------------------------------------
    # 4a. Calculations#count / #sum and Relation#size -> ConcolicArithInt,
    #     with the grouped-count shape fix (§4). Same var names, same
    #     seed_for wiring, same SQL notes as the shared DESIGN #5 mock.
    # ---------------------------------------------------------------------
    calc = ActiveRecord::Calculations
    rel  = ActiveRecord::Relation

    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn   = "#{name}_count"
      note = ct.sql_for(receiver, args)
      grouped = begin
        receiver.respond_to?(:group_values) && !receiver.group_values.empty?
      rescue Exception # rubocop:disable Lint/RescueException
        false
      end
      cnt = ServicesAdminTargets.arith_int(vn, ct.seed_for(vn, 1), note: note)
      grouped ? GroupedCount.new({"concolic_group_1" => cnt}, note) : cnt
    end)

    interceptor.declare_target(calc, :sum, returns: lambda do |receiver, args, name|
      vn = "#{name}_sum"
      ServicesAdminTargets.arith_int(vn, ct.seed_for(vn, 0), note: ct.sql_for(receiver, args))
    end)

    interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
      vn = "#{name}_size"
      ServicesAdminTargets.arith_int(vn, ct.seed_for(vn, 1), note: ct.sql_for(receiver, args))
    end)

    # ---------------------------------------------------------------------
    # 5. DELIBERATELY NOT MOCKED — the refusals, recorded explicitly.
    #
    # (a) `InvitationCode#add_invites!` (invitation_code.rb:19). Its body is
    #     `self.update_attributes(count: self.count+100)`, and
    #     update_attributes/update IS declared persistence target #8. Mocking
    #     add_invites! would hide a declared target beneath a mock — the exact
    #     invariant the README's wall-fixing rules forbid. §2 fixes the VALUE's
    #     arithmetic instead, which leaves the persistence call visible and
    #     firing.
    #
    # (b) `AdminsController#percent_change` (admins_controller.rb:94). A mock
    #     returning 0.0 would have been a legal SQL-free leaf, but with §2 the
    #     real body executes, so no mock is needed. Removed in favour of
    #     running the app's own arithmetic.
    #
    # (c) The unguarded nil at admins_controller.rb:37,
    #     `InvitationCode.find_by_token(params[:invite_code_id]).add_invites!`.
    #     An unknown invite token yields nil and the controller calls
    #     `.add_invites!` on it -> 500 instead of a 404. That is a REAL APP
    #     DEFECT found by this experiment and is deliberately left in place.
    #
    # (d) `ApplicationController#redirect_unless_admin`. It is the `if`.
    #     Mocking it would delete the branch §1 exists to create.
    #
    # (e) `Service#provider` (-> a concrete "twitter"). Legal, but §3 subsumes
    #     it and is strictly more faithful: the record becomes a real
    #     Services::* instance, so provider / post_opts / MAX_CHARACTERS all
    #     behave as production would instead of one method being special-cased.
    # ---------------------------------------------------------------------

    warn "[services_admin] ServicesAdminTargets installed"
  end
end
