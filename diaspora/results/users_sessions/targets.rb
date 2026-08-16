# frozen_string_literal: true
#
# Per-batch concolic targets — `users_sessions`.
#
# Installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration REPLACES an earlier one (last-one-wins):
#
#   ConcolicTargets.install!(interceptor)        # shared generic AR interception
#   UsersSessionsTargets.install!(interceptor)   # this file — batch-local fixes
#   UsersSessionsTargets.decorate_user!(u)       # per-instance fixes (see §0)
#
# ---------------------------------------------------------------------------
# THE CENTRAL TECHNIQUE IN THIS FILE: boundary-decided booleans
# ---------------------------------------------------------------------------
# 14 of this batch's 20 entrypoints were VACUOUS (0 path conditions). The single
# dominant cause was NOT a wall but the Ruby truthiness gap (src/TODO.txt):
#
#     if current_user.confirm_email(params[:token])
#     if current_user.update_attributes(...)
#     if @user.sign_up
#
# Every one of these mocks returned a value that is TRUTHY IN RUBY no matter
# what it wraps — either a literal `true` (concolic_targets.rb:508, :1191) or a
# `SymbolicBool`, which is a non-nil object and therefore truthy even when it
# wraps `false`. So the app always took the success branch and recorded NO path
# condition. Making the value merely *seedable* is not enough: DSE would emit
# the flip, the mock would honour it, and the app would still go left.
#
# `to_symbolic` (src/ruby_runtime/symbolic_func.rb:149-155) documents the way
# out, and the shared file already uses it for boolean column readers
# (concolic_targets.rb:237-241, `post.public?`):
#
#     "nil means 'absent' — pass through unchanged. Absence must be decided
#      (and PC-recorded) AT THE MOCK BOUNDARY, never silently converted into a
#      symbolic value."
#
# So `flag` below records the path condition on a seedable SymbolicBool inside
# the mock and then returns a value whose RUBY TRUTHINESS matches the decision:
# `true` (re-wrapped by the interceptor into a truthy SymbolicBool) or `nil`
# (passed through unchanged, falsy). The branch is recorded once, at the
# boundary, and the app then really diverges. src/TODO.txt sanctions exactly
# this ("boolean-returning mocks may also branch inside the mock with an
# explicit compare and return a concrete true/false").
#
# HONESTY NOTE, per the addendum's most important rule: `flag` is used ONLY on
# methods whose callers in this batch actually branch on the result. A `flag`
# on a method whose return value is discarded would manufacture a phantom
# branch — two paths through code that has no `if`. That is why `save` is
# deliberately NOT converted (§7).

module UsersSessionsTargets
  module_function

  # Boundary-decided boolean. Records `(<var> == True)` on a seedable
  # SymbolicBool and returns a Ruby-truthy/falsy value matching it.
  # Returns `true` or `nil` — see the header for why not `false`.
  def flag(var, default, note)
    b = symbool(var, ConcolicTargets.seed_for(var, default), note: note)
    (b == true) ? true : nil
  end

  # =====================================================================
  # §0. Per-INSTANCE fixes for the symbolic current_user.
  #
  # These cannot be `declare_target`s. `ConcolicTargets.symbolic_instance`
  # (concolic_targets.rb:229) installs a SINGLETON reader for every DB column,
  # and singleton methods beat any `define_method` on the class — so a
  # declare_target on `User#language` would never fire on a symbolic user.
  # The runner calls this right after building the symbolic user.
  # =====================================================================
  def decorate_user!(u)
    # --- W1. The i18n wall that blocked 13 of 20 entrypoints. ------------
    # ApplicationController#set_locale (a before_action, i.e. BEFORE any action
    # code) does `I18n.locale = current_user.language`; i18n's
    # enforce_available_locales! then evaluates `locale != false`, i.e.
    # SymbolicString#!=(FalseClass) -> NotImplementedError.
    #
    # Set LANG_MODE=symbolic to keep `language` a (tolerant) SymbolicString
    # instead — see §12 for the subclass and REPORT.md for the measurement.
    if ENV["LANG_MODE"] == "symbolic" && defined?(TolerantSymbolicString)
      v = "SYM_USER_language"
      seed = ConcolicTargets.seed_for(v, "en")
      lang = TolerantSymbolicString.new(seed, name: v, note: "users.language")
      # symstr's factory side effect, replicated so the var shows up in the dump.
      SymbolicFunc.register_var(name: v, sort: "String", value: seed,
                                note: "users.language") if defined?(SymbolicFunc)
      u.define_singleton_method(:language) { lang }
    else
      # `language` is a locale tag consumed only by i18n plumbing; no app
      # branch in this batch reads it. Concretising swallows no branch.
      u.define_singleton_method(:language) { "en" }
    end

    # --- W2. Same wall, second before_action. ----------------------------
    # set_grammatical_gender does `current_user.gender.to_s.tr(...)`;
    # SymbolicString#to_s is unimplemented by design. gender only selects an
    # inflection token — no app branch reads it.
    u.define_singleton_method(:gender) { "" }

    # --- W3. CarrierWave mounted uploaders shadowed by column readers. ---
    # `export` / `exported_photos_file` are both DB columns AND mounted
    # uploaders, so symbolic_instance's generic column reader wins and
    # users#download_profile's `current_user.export.url` hits SymbolicString.
    # Stub exposing #url only (pure data, no SQL, no branch).
    upload = Object.new
    def upload.url; "http://example.com/concolic_export.zip"; end
    u.define_singleton_method(:export) { upload }
    u.define_singleton_method(:exported_photos_file) { upload }
    u
  end

  # =====================================================================
  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # -------------------------------------------------------------------
    # §1. User#valid_password? -> boundary-decided flag.
    #     THE MOST SECURITY-RELEVANT BRANCH IN THIS BATCH.
    #
    # `Devise::Models::DatabaseAuthenticatable#valid_password?` (devise-4.7.1
    # models/database_authenticatable.rb:67-69) is exactly
    #     Devise::Encryptor.compare(self.class, encrypted_password, password)
    # — no SQL, no other declared target: the smallest SQL-free leaf that
    # encloses the `BCrypt::Errors::InvalidHash` raise. `encrypted_password` is
    # a SymbolicString, so `BCrypt::Password.new(hashed)` rejects it and the run
    # dies. Observed in BOTH users_destroy and sessions_create.
    #
    # Unlocks:
    #   * users#destroy   — the wrong-password fork (`flash users.destroy.wrong_password`)
    #   * sessions#create — the authentication fork, via
    #     Warden::Strategies::DatabaseAuthenticatable#valid?/_run!
    #
    # DECLARED COST (measured, reported in REPORT.md): the real body's early-out
    # `return false if hashed_password.blank?` lives one level down inside
    # `Devise::Encryptor.compare`, and it is where the pre-existing
    # `(SYM_RESULT_..._encrypted_password == '')` PC came from. That PC is
    # REPLACED by `(SYM_RESULT_User_valid_password__N_ok == True)` — the same
    # decision (does this password authenticate?) relocated to the mock
    # boundary, but now with BOTH sides explorable instead of one side fatal.
    # It is not swallowed; it is moved. We deliberately do NOT hand-replicate
    # the blank? guard inside the mock to keep both PCs — that would be
    # re-implementing gem logic in the harness.
    # -------------------------------------------------------------------
    if defined?(User) && User.method_defined?(:valid_password?)
      interceptor.declare_target(User, :valid_password?, returns: lambda do |_r, _a, name|
        flag("#{name}_ok", true, "User#valid_password? (Devise::Encryptor.compare)")
      end)
    end

    # -------------------------------------------------------------------
    # §2. ActiveRecord::Base#update_attributes -> boundary-decided flag.
    #
    # concolic_targets.rb:508 declares save/save!/update/update!/... on
    # ActiveRecord::Base returning `symbool(..., true)` with the literal `true`
    # HARD-CODED — no `seed_for`. That is the inert-mock pattern the addendum
    # warns about: DSE emits the flip, runs the child, and the mock ignores it.
    #
    # It also never fired for this batch's callers. In Rails 5.2
    # `update_attributes` is `alias update_attributes update`
    # (activerecord-5.2.4.3/lib/active_record/persistence.rb:432) — an alias
    # binds the ORIGINAL BODY, so `define_method(:update)` does not intercept
    # it. The alias's body ran for real and called `save`, whose SymbolicBool
    # is truthy, so:
    #     users#update                  change_language: `if @user.update_attributes(user_data)`
    #     users#update_privacy_settings `if current_user.update_attributes(strip_exif:)`
    # both took the success branch every time and recorded nothing.
    #
    # Declared on ActiveRecord::Base (not Persistence) for the same
    # MRO reason the shared §8 block documents. Both call sites branch on the
    # result, so no phantom branch is created.
    # -------------------------------------------------------------------
    base = ActiveRecord::Base
    %i[update_attributes update_attributes!].each do |m|
      next unless base.method_defined?(m) || base.private_method_defined?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        flag("#{name}_ok", true, "#{receiver.class.name}##{m} args=#{args.inspect}")
      end)
    end

    # -------------------------------------------------------------------
    # §3. User#confirm_email -> boundary-decided flag.
    #
    # concolic_targets.rb:1191 returns a literal `true`. users#confirm_email is
    #     if    current_user.confirm_email(params[:token])   -> notice
    #     elsif current_user.unconfirmed_email.present?      -> error
    # so the literal pinned it to the first arm forever: 0 PCs, vacuous.
    #
    # Legal leaf: user.rb:232-236 is `return false if token.blank? || token !=
    # confirm_email_token` / assign / `save` — no SQL of its own, and the `if`
    # that produces our path condition is in the CONTROLLER, not in this body,
    # so mocking does not swallow the branch it guards.
    # -------------------------------------------------------------------
    if defined?(User) && User.method_defined?(:confirm_email)
      interceptor.declare_target(User, :confirm_email, returns: lambda do |_r, args, name|
        flag("#{name}_ok", true, "User#confirm_email token=#{args.inspect}")
      end)
    end

    # -------------------------------------------------------------------
    # §4. User#sign_up -> boundary-decided flag (registrations#create fork).
    #
    # user.rb:570 is `AppConfig.settings.captcha.enable? ? save_with_captcha :
    # save`. Its result is branched on by the controller
    # (`if @user.sign_up` -> success vs. `render "new"` with errors), and the
    # `save` underneath is ITSELF already a declared mock, so nothing real is
    # hidden: the captcha selection is a concrete config read, not a symbolic
    # branch. This is the one place we mock a method that calls another target,
    # and only because that target issues no SQL either.
    # -------------------------------------------------------------------
    if defined?(User) && User.method_defined?(:sign_up)
      interceptor.declare_target(User, :sign_up, returns: lambda do |_r, _a, name|
        flag("#{name}_ok", true, "User#sign_up")
      end)
    end

    # -------------------------------------------------------------------
    # §5. Schema gap: `unconfirmed_email` / `confirm_email_token`.
    #
    # NOT a symbolic-runtime wall and NOT an app bug — db/concolic.sqlite3's
    # `users` table has 39 columns and is missing these two, although db/schema.rb
    # declares them (schema.rb:587-588). Consequences observed:
    #   * registrations#create -> User.build -> setup -> self.valid? ->
    #     `validate :unconfirmed_email_quasiuniqueness` (user.rb:499) ->
    #     NoMethodError: undefined method `unconfirmed_email' — the sole reason
    #     that entrypoint produced an error dump with 0 PCs.
    #   * users#confirm_email's `elsif current_user.unconfirmed_email.present?`
    #     arm would raise the moment §3 made the first arm flippable.
    #
    # Fixed batch-locally rather than by editing the shared app DB. These cannot
    # be declare_targets: `declare_target` calls `klass.instance_method(method)`
    # first (call_interceptor.rb:103) and the methods do not exist at all.
    # Defined here with the SAME naming and seeding scheme symbolic_instance
    # would have used had the column been present, so the vars are seedable by
    # DSE and prefix-stable (no call ordinal).
    # -------------------------------------------------------------------
    if defined?(User)
      %w[unconfirmed_email confirm_email_token].each do |col|
        next if User.column_names.include?(col)
        ivar = :"@concolic_#{col}"
        var  = "SYM_USER_#{col}"
        note = "users.#{col} (column absent from db/concolic.sqlite3)"
        # TolerantSymbolicString (§12), not plain symstr: Devise's
        # `downcase_keys` / `strip_whitespace` before_validations run
        # `send(:unconfirmed_email).try(:downcase)` because
        # config.case_insensitive_keys / strip_whitespace_keys list it
        # (config/initializers/devise.rb:66,71), and plain SymbolicString
        # raises NotImplementedError on both.
        User.send(:define_method, col) do
          unless instance_variable_defined?(ivar)
            seed = ConcolicTargets.seed_for(var, "")
            v = TolerantSymbolicString.new(seed, name: var, note: note)
            SymbolicFunc.register_var(name: var, sort: "String", value: seed, note: note)
            instance_variable_set(ivar, v)
          end
          instance_variable_get(ivar)
        end
        User.send(:define_method, "#{col}=") { |v| instance_variable_set(ivar, v) }
        User.send(:define_method, "will_save_change_to_#{col}?") { false }
      end
    end

    # -------------------------------------------------------------------
    # §6. User.authentication_token (CLASS method) — the JVM-OOM guard.
    #
    # THIS IS THE BUG THAT KILLED A WHOLE BATCH PROCESS (343s, then
    # java.lang.OutOfMemoryError). user/authentication_token.rb:20-24:
    #
    #     loop do
    #       token = Devise.friendly_token(30)
    #       break token unless User.exists?(authentication_token: token)
    #     end
    #
    # `FinderMethods#exists?` is a declared target returning a SymbolicBool,
    # which is ALWAYS truthy (src/TODO.txt) — so `break … unless` NEVER fires
    # and the loop spins forever, allocating tokens until the JVM dies.
    #
    # Guard = a HARD INTEGER BOUND, not a symbolic one: at most MAX_PROBES
    # iterations, then return unconditionally. Termination does not depend on
    # any symbolic value, so it cannot regress.
    #
    # The probe is kept REAL (`User.exists?` still runs through the declared
    # target, so the uniqueness SELECT is still issued and recorded), and its
    # result is boundary-decided so the retry branch is flippable. The previous
    # runner-local guard no-op'd `reset_authentication_token!` wholesale, which
    # hid that SELECT entirely; guarding the generator instead lets
    # `reset_authentication_token!` run FOR REAL.
    #
    # `ensure_authentication_token!` is untouched and still runs for real —
    # that is where the flippable `authentication_token.blank?` PC comes from
    # (users#auth_token). Reached also from SessionsController's
    # before/after_action :reset_authentication_token.
    #
    # HONEST UNDER-APPROXIMATION: the real loop retries unboundedly. Seeding
    # "token collides" twice returns the colliding token instead of looping,
    # so the >2-collision path is not modelled. Forced by the truthiness gap.
    # -------------------------------------------------------------------
    max_probes = 2
    if defined?(User) && User.respond_to?(:authentication_token)
      interceptor.declare_target(User.singleton_class, :authentication_token,
                                 returns: lambda do |_r, _a, name|
        token = nil
        max_probes.times do |i|
          token = Devise.friendly_token(30)
          collides =
            begin
              flag("#{name}_collides_#{i}", false,
                   "User.exists?(authentication_token: …) uniqueness probe #{i}")
            rescue StandardError => e
              warn "[users_sessions] token probe #{i}: #{e.class}: #{e.message.to_s[0, 80]}"
              nil
            end
          break unless collides
        end
        token || Devise.friendly_token(30)
      end)
    end

    # -------------------------------------------------------------------
    # §7. DELIBERATELY NOT CONVERTED: ActiveRecord::Base#save.
    #
    # `save` is the other literal-`true` persistence mock, and converting it to
    # a `flag` would be the single biggest raw-PC win available. It is refused
    # on purpose. In this batch `save`'s result is DISCARDED at every call site
    # that a flag would touch:
    #   users#getting_started_completed  `user.save`               (ignored)
    #   users#export / export_photos     queue_export -> `update`  (ignored)
    #   reset_authentication_token!      `save(validate: false)`   (ignored)
    # Recording a PC there manufactures a phantom branch: two "paths" through
    # code containing no `if`, inflating PCs/nodes while covering nothing. The
    # one real `save` branch in this batch (users#change_email's `if @user.save`)
    # is unreachable with this entrypoint's params (`user_data[:language]` wins
    # the `update_user` elsif chain first).
    #
    # Consequence reported honestly instead: users#getting_started_completed and
    # the discarded-`save` sites stay at 0 PCs, and they are 0-PC because the
    # ACTION HAS NO CONDITIONAL — not because a wall blocks them.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # §8. DeviseController#devise_mapping -> the REAL Devise mapping.
    #     Highest-value fix for any Devise-touching batch.
    #
    # concolic_targets.rb:848-869 substitutes a bare `Object` stub because in a
    # controller-test rig `Devise.mappings` looks unregistered. It is not — it
    # is populated once the route set is evaluated. The stub answers only nine
    # hand-picked methods, so every Devise action NoMethodErrors on the tenth
    # (`authentication_keys`, `new_with_session`, `to`, `strategies` for a real
    # scope …) before reaching app code.
    #
    # `Devise.mappings[:user]` is a pure in-memory Hash lookup: no SQL, no
    # declared target beneath it, nothing hidden. Returning the real mapping is
    # strictly MORE faithful than the stub — `resource_class`, `resource_name`
    # and `require_no_authentication`'s `no_input_strategies` all become the
    # values production would see.
    # -------------------------------------------------------------------
    if defined?(DeviseController)
      begin
        Rails.application.routes.routes # force route-set evaluation
      rescue StandardError
        nil
      end
      mapping = begin
        defined?(Devise) ? (Devise.mappings[:user] || Devise.mappings.values.first) : nil
      rescue StandardError
        nil
      end
      if mapping
        interceptor.declare_target(DeviseController, :devise_mapping,
                                   returns: ->(_r, _a, _n) { mapping })
        warn "[users_sessions] devise_mapping -> real #{mapping.class}(#{mapping.name})"
      else
        warn "[users_sessions] devise_mapping: Devise.mappings EMPTY — keeping shared stub"
      end
    end

    # -------------------------------------------------------------------
    # §9. User#blocks -> real Relation. (Was runner-local; moved here.)
    #
    # concolic_targets.rb:546 returns a length-only SymbolicList, which the
    # streams/posts batches need (`Post.blocked_people` does `blocks.map`) but
    # which has none of the Relation methods this batch calls:
    #   users#privacy_settings  `current_user.blocks.includes(:person)`
    #   users#getting_started   -> User::Querying#block_for -> `blocks.find_by(person_id:)`
    # `Block.all` routes those into the declared FinderMethods targets, so the
    # queries stay REAL. Exactly the override the photos batch needed and the
    # reason per-batch target files exist.
    #
    # Caveat: drops the association's `WHERE blocks.user_id = <user>` scope, so
    # that query's rendered SQL is unscoped.
    # -------------------------------------------------------------------
    interceptor.declare_target(User, :blocks, returns: ->(_r, _a, _n) { Block.all })

    # -------------------------------------------------------------------
    # §10. NullRelation short-circuit. (Adopted verbatim from photos §4.)
    #
    # PersonPresenter#current_user_person_contact returns `Contact.none`. The
    # shared symbolic mocks make `Contact.none.present?` TRUE, so the app enters
    # a branch UNREACHABLE in production and dies with `NoMethodError: id for
    # Contact::ActiveRecord_Relation`. A NullRelation is DEFINED to be empty and
    # issues no SQL, so returning the concrete empty result hides no query.
    # Reached here through users#getting_started's PersonPresenter#as_json.
    # -------------------------------------------------------------------
    rel = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    if null_rel
      %i[to_a to_ary records].each do |m|
        interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
          next [] if receiver.is_a?(null_rel)
          vn  = "#{name}_rows"
          rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row",
                                     ct.sql_for(receiver, args))
          SymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                           note: ct.sql_for(receiver, args), representative: rep)
        end)
      end

      {empty?: true, any?: false, one?: false, many?: false}.each do |m, null_val|
        interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
          next null_val if receiver.is_a?(null_rel)
          vn = "#{name}_#{m.to_s.delete('?')}"
          symbool(vn, ct.seed_for(vn, m == :empty? ? false : true),
                  note: ct.sql_for(receiver, args))
        end)
      end
    end

    # -------------------------------------------------------------------
    # §11. Asset-path stub. (Adopted verbatim from photos §5.)
    #
    # ENVIRONMENT wall, not a symbolic-runtime one. AvatarPresenter's CLASS BODY
    # evaluates `ActionController::Base.helpers.image_path("user/default.png")`,
    # driving Sprockets through manifest.js -> `require underscore`; the minimal
    # rig has no compiled assets, so Sprockets::FileNotFound is raised WHILE THE
    # CLASS BODY IS STILL EXECUTING and AvatarPresenter is left half-defined.
    # Every LATER run in the same JVM then dies differently:
    # `NoMethodError: undefined method 'base_hash' for #<Profile>`.
    # Observed here as 1 Sprockets::FileNotFound + 7 base_hash NoMethodErrors
    # across users#getting_started's 8 dumps — order-dependent and misleading.
    # -------------------------------------------------------------------
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[users_sessions] asset stub: #{e.class}: #{e.message.to_s[0, 60]}"
    end

    # -------------------------------------------------------------------
    # §14. NOT ADDED: crypto leaf stubs for registrations#create.
    #
    # Once §12's downcase/strip tolerance let registrations#create past its
    # SymbolicString#downcase wall, its SECOND DSE path started ABORTING THE
    # WHOLE JVM: `SIGSEGV ... The crash happened outside the Java Virtual
    # Machine in native code`, with the native stack naming
    #     com.kenai.jffi.Foreign.getZeroTerminatedByteArray
    #     org.jruby.ext.ffi.jffi.FFIUtil.getString(Ruby, long)
    # — an FFI binding reading a C string back from a native pointer.
    #
    # Two candidate leaves were mocked and MEASURED, and neither prevented the
    # abort, so both were removed rather than left in as decoration:
    #   * OpenSSL::PKey::RSA.generate  (User#setup -> generate_keys, 4096-bit)
    #   * Devise::Encryptor.digest     (bcrypt is FFI-based on JRuby)
    # The remaining suspect is a real query reaching the FFI sqlite driver with
    # a SymbolicString bind value, which no batch-local mock can fix without
    # suppressing the query itself.
    #
    # CONTAINED INSTEAD: run_dse.rb caps registrations_create at 1 execution and
    # explores it LAST. Reported as capped/not-drained with 3 missing branches —
    # never as complete. See REPORT.md.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # §12. TolerantSymbolicString — batch-local SUBCLASS, no src/ change.
    #
    # `SymbolicString#check_string_operand!` (src/ruby_runtime/string.rb:384)
    # raises NotImplementedError whenever `==` / `!=` is given a non-String
    # operand. i18n's `enforce_available_locales!` opens with
    #
    #     if locale != false && config.enforce_available_locales
    #
    # — `locale != false` is a TYPE TEST, not a value comparison, and it is the
    # first thing `I18n.locale=` does. Since ApplicationController#set_locale is
    # a before_action, this fired before ANY action code and was the single
    # wall behind 13 of this batch's 20 vacuous entrypoints.
    #
    # The fix needs no src/ change: subclass and answer the type test directly.
    # This is SOUND rather than a concretisation — a string-sorted symbolic
    # value can never be equal to `false` under ANY assignment, so
    # `sym != false` is a tautology and `sym == false` is unsatisfiable. There
    # is no branch to record: emitting a PC here would be the fabrication, not
    # the omission. Value comparisons against real strings still record PCs
    # exactly as the base class does.
    # -------------------------------------------------------------------
    unless defined?(TolerantSymbolicString)
      ::Object.const_set(:TolerantSymbolicString, Class.new(SymbolicString) do
        def ==(other)
          return false unless other.is_a?(String) || other.is_a?(SymbolicString)
          super
        end

        def !=(other)
          return true unless other.is_a?(String) || other.is_a?(SymbolicString)
          super
        end

        # Case/whitespace normalisation — identity, tracking preserved.
        #
        # Devise's `downcase_keys` and `strip_whitespace` before_validations
        # run `send(k).try(:downcase)` / `.try(:strip)` over
        # case_insensitive_keys / strip_whitespace_keys, which diaspora
        # configures as %i(email unconfirmed_email username)
        # (config/initializers/devise.rb:66,71). SymbolicString lists both in
        # its UNSUPPORTED table (string.rb:353) and raises — this was the sole
        # remaining wall in registrations#create.
        #
        # HONEST APPROXIMATION: the SMT string theory the engine targets has no
        # case-folding or trim operator, so there is no sound symbolic result to
        # return. Returning the receiver unchanged restricts the modelled input
        # space to values that are ALREADY lowercase and stripped, rather than
        # concretising the value (which would kill tracking outright and lose
        # the `(SYM_USER_unconfirmed_email == '')` branch that users#confirm_email
        # depends on). No branch in this batch tests case or padding.
        def downcase; self; end
        def strip;    self; end
        def downcase!; nil; end
        def strip!;    nil; end

        # §12b. Regex predicates — PORTED from results/services_admin/targets.rb
        # §2b (see also photos §6d, the same port).
        #
        # ActiveModel's format validator does `record.errors.add(...) if
        # value.to_s !~ regexp` (validations/format.rb:9), and `=~` / `match` /
        # `match?` are all in the runtime's UNSUPPORTED table (string.rb:335) —
        # strings track only `==`/`!=` by design. `registrations#create`
        # validates `unconfirmed_email` (§5) that way, which was the last
        # NotImplementedError in this batch.
        #
        # There is no app method to mock here: the caller is framework code, so
        # the README's "smallest SQL-free enclosing unit" rule has nothing to
        # bite on. Fix the VALUE instead.
        #
        # A regex match is not expressible in the `(VAR op LITERAL)` PC grammar,
        # so the predicate is abstracted as a FRESH seedable boolean, recorded
        # at the predicate boundary (the sanctioned boundary-decided pattern,
        # src/TODO.txt) and answered concretely so the app branches for real.
        #
        # SOUNDNESS CAVEAT, stated plainly: the fresh boolean is INDEPENDENT of
        # the string's concrete value. Its DEFAULT is the true concrete answer
        # (`value =~ re`), so an unflipped run is exact. When DSE flips it, the
        # path explored is one that some string could take, but the witness in
        # that dump no longer satisfies the regex. The path is reachable; the
        # witness is not a model of it. Over-approximation — false positives,
        # never false negatives.
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

    # -------------------------------------------------------------------
    # §13. ConcolicDate — date/datetime typed-column gap. (photos §6a.)
    #
    # `symbolic_instance` maps every non-integer/boolean column to a
    # SymbolicString, so `profiles.birthday` (a `date` column) has no #year and
    # PeopleHelper#birthday_format dies with
    # `NoMethodError: undefined method 'year' for <SymStr assoc_profile_birthday>`
    # — all 8 of users#getting_started's dumps, via
    # PersonPresenter#as_json -> ProfilePresenter.
    #
    # birthday_format itself must NOT be mocked: its body IS the branch
    # (`if bday.year <= 1004`). Instead the VALUE gains the method — a real
    # ::Date subclass (so `Date === obj` and I18n.l still work) whose #year is a
    # seedable SymbolicInt, turning the crash into a flippable PC. Same
    # subclass-not-src-change technique as §12.
    # -------------------------------------------------------------------
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    unless ConcolicTargets.respond_to?(:symbolic_instance_without_dates)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_dates, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_dates(klass, base_name, sql)
          klass.columns_hash.each do |col, meta|
            next unless %i[date datetime].include?(meta.type)
            vn = "#{base_name}_#{col}_year"
            d = ConcolicDate.new(1990, 1, 1)
            d.sym_year = symint(vn, seed_for(vn, 1990), note: sql)
            obj.define_singleton_method(col) { d }
            obj.concolic_attrs[col] = d if obj.respond_to?(:concolic_attrs)
          end
          obj
        end
      end
    end

    # -------------------------------------------------------------------
    # §15. DiasporaFederation::Discovery::Discovery#fetch_and_save -> nil.
    #      THE registrations#create JVM ABORT — diagnosed and closed.
    #
    # §14 recorded this crash as unexplained and contained it by capping the
    # entrypoint at one execution. Crash-isolated DSE
    # (run_registrations_isolated.rb + drive_registrations.py) then attributed
    # it precisely: ALL FOUR poisoned seed sets share exactly one assignment,
    #
    #     SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found = true
    #
    # and that var is `Person.by_account_identifier` (person.rb:331,
    # `find_by(diaspora_handle:)`), reached from
    # User#send_welcome_message -> share_with. Its caller is
    # `Person.find_or_fetch_by_identifier`, whose not-found arm is
    # person.rb:325:
    #
    #     DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
    #     by_account_identifier(diaspora_id)
    #
    # i.e. a REAL webfinger over HttpClient -> libcurl -> JRuby's FFI. That is
    # the same native path `search_links_reports_profiles` hit on links#resolve
    # and documented with the same signature (SIGSEGV outside the JVM, jffi
    # frames, `munmap_chunk(): invalid pointer`; here the crash report carries
    # org.jruby.ext.ffi.AutoPointer locals and RIP=0x32). It was never a crypto
    # leaf — which is why §14's two crypto mocks measured no effect.
    #
    # This is that batch's §2 mock, ported verbatim. Legality (unchanged): the
    # body is `validate_diaspora_id` plus a `save_person_after_webfinger`
    # callback trigger — no SQL of its own and no other declared target
    # beneath it. Crucially `find_or_fetch_by_identifier` calls
    # `by_account_identifier` AGAIN afterwards, so the real
    # `find_by(diaspora_handle:)` query and its seedable `_not_found` var
    # SURVIVE the mock: the branch is preserved, only the network is removed.
    # -------------------------------------------------------------------
    if defined?(DiasporaFederation::Discovery::Discovery)
      interceptor.declare_target(
        DiasporaFederation::Discovery::Discovery, :fetch_and_save,
        returns: ->(_r, _a, _n) { nil }
      )
      warn "[users_sessions] Discovery#fetch_and_save -> nil (§15)"
    end

    warn "[users_sessions] UsersSessionsTargets installed"
  end
end
