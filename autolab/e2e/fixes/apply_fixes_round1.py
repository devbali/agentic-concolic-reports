#!/usr/bin/env python3
"""apply_fixes_round1.py — the round-1 repairs, applied atomically.

Each fix below names the evidence that motivated it and the blast radius it
was chosen to have.  Run with --check to see what would change; --apply to
change it.  Every edited file is backed up next to itself first.

FIX-1  autolab_dse.rb — install the `authenticatable_salt` leaf shim so the
       SYMBOLIC PRINCIPAL actually resolves.
       EVIDENCE (e2e/probes/probe_principal.out, executed):
         to_adapter.get(uid)         -> a symbolic User               (ok)
         record.authenticatable_salt -> SymbolicSubstring of the symbolic
                                        encrypted_password column,
                                        concrete "SYM_RESULT_ActiveRecord__Find"
         salt == "concolicsalt"      -> concrete false
         serialize_from_session      -> nil
         current_user.language       -> NoMethodError (nil:NilClass)
       The driver at autolab_dse.rb:390 resolves the principal with
       `User.serialize_from_session(ci_uid, "concolicsalt")`, i.e. it already
       assumes the shim that makes that salt compare true.  That shim exists
       only in `targets/endpoints/comments_index.rb` (one gold endpoint), so
       every core-only signed-in endpoint resolves to nil.
       BLAST RADIUS chosen deliberately: the shim is installed BY THE DRIVER
       and ONLY when the endpoint has no target override (tier == candidate),
       so neither gold endpoint's target layer is touched, the shared target
       library is not touched, and `declare_target`'s D5 wrapping hazard
       cannot fire (this is a `prepend`, not a declaration).

FIX-2  targets/core.rb — the devise_mapping stub's `to` returns ::User.
       EVIDENCE: all six devise endpoints stop with a NoMethodError on a
       plain `#<Object>` receiver, and every missing name is a User CLASS
       method that Devise reaches through `mapping.to`:
         sessions_new            authentication_keys
         registrations_new       new_with_session
         devise_passwords_new    new
         devise_passwords_create send_reset_password_instructions
         devise_passwords_edit   reset_password_by_token
         devise_passwords_update reset_password_by_token / new
       core.rb:1998 has `def dev_stub.to(*_); self; end`, so `mapping.to`
       hands back the stub instead of the model class.
       BLAST RADIUS: the stub object's method table only.  No declaration is
       added or removed (the table stays at 86 names), no note shape changes,
       and only the 6 endpoints that CALL devise_mapping can observe it.
"""
from __future__ import annotations

import shutil
import sys

DRIVER = "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb"
CORE = "/home/dev/project/reports/autolab/targets/core.rb"

FIX1_ANCHOR = '''    ep = (reg["endpoints"] || {})[endpoint_id]
    if ep.nil?'''

FIX1_NEW = '''    ep = (reg["endpoints"] || {})[endpoint_id]
    if ep.nil?
      install_candidate_principal_plumbing!'''

FIX1_METHOD = '''  # -----------------------------------------------------------------------
  # candidate-tier principal plumbing  (e2e fix round 1, 2026-09-26)
  # -----------------------------------------------------------------------
  #
  # WHY THIS EXISTS, MEASURED (reports/autolab/e2e/probes/probe_principal.out):
  #
  #   User.to_adapter.get(uid)      -> a symbolic User            [ok]
  #   record.authenticatable_salt   -> SymbolicSubstring of the SYMBOLIC
  #                                    encrypted_password column, concrete
  #                                    value "SYM_RESULT_ActiveRecord__Find"
  #   salt == "concolicsalt"        -> concrete false
  #   User.serialize_from_session   -> nil
  #   current_user.language         -> NoMethodError: nil:NilClass
  #
  # `run_one` resolves the principal through the REAL Devise path
  # (`User.serialize_from_session(uid, "concolicsalt")`, below) precisely so
  # that the two statements a real signed-in request issues are recorded
  # rather than swallowed — but devise-4.7.1
  # `lib/devise/models/authenticatable.rb:236-239` keeps the record only if
  # `record.authenticatable_salt == salt`, and against a symbolic
  # `encrypted_password` that compare is always false.  The gold endpoint
  # `comments_index` carries a leaf shim for exactly this
  # (`targets/endpoints/comments_index.rb`, the "(a) salt leaf shim" block);
  # the shared core does not, so every CORE-ONLY signed-in endpoint resolved
  # its principal to nil and died in `set_locale` before the action ran.
  # Measured blast radius before the fix: 113 of the 114 signed-in endpoints.
  #
  # IT IS INSTALLED HERE, NOT IN THE TARGET LIBRARY, AND ONLY FOR
  # candidate-tier endpoints:
  #   * it is a `prepend`, not a `declare_target`, so the declaration table
  #     is unchanged (86 names) and the D5 double-declaration wrap cannot
  #     fire;
  #   * an endpoint WITH an override installs its own (comments_index does),
  #     and this never runs for one, so no closed endpoint's evidence moves;
  #   * it is runner-local plumbing of the same kind `run_one` already does
  #     for `authenticate_user!`.
  def install_candidate_principal_plumbing!
    return unless defined?(::User)

    unless ::User.instance_variable_get(:@autolab_candidate_salt_shim)
      shim = Module.new do
        def authenticatable_salt
          if defined?(::ConcreteSymbolicString)
            ::ConcreteSymbolicString.build(
              "concolicsalt", name: nil,
              note: "User#authenticatable_salt leaf (encrypted_password[0,29] slice)")
          else
            "concolicsalt"
          end
        end
      end
      ::User.prepend(shim)
      ::User.instance_variable_set(:@autolab_candidate_salt_shim, true)
      warn "[autolab] candidate principal plumbing: authenticatable_salt leaf " \\
           "shim installed (see install_candidate_principal_plumbing!)"
    end

    # -------------------------------------------------------------------
    # FIX-3: principal-column pins (users.language, profiles.gender)
    # -------------------------------------------------------------------
    # MEASURED (e2e/fixtrial, admin_pods_index, run auth_json_dse0001, with
    # FIX-1 in place and nothing else): once the principal resolves, the very
    # next wall is
    #   NotImplementedError: SymbolicString comparison (!=) with non-string
    #     (FalseClass) is not supported
    #   src_new/runtimes/ruby_runtime/string.rb:413 check_string_operand!
    # reached from `I18n.locale = current_user.language`
    # (app/controllers/application_controller.rb:102 set_locale) through
    # i18n's `enforce_available_locales!`.
    #
    # BOTH gold batches carry exactly this pin and both record the same
    # rationale: targets/endpoints/aspect_memberships_create.rb:408-441
    # ("Principal-column domains for the before_action chain ... this is NOT
    # new modelling -- it is the SAME two columns, on the SAME devise
    # principal, reached by the SAME two ApplicationController callbacks"),
    # ported there from results3/comments_index. The two callbacks live in
    # ApplicationController, so every signed-in diaspora endpoint runs them;
    # that is why the pin is app-wide rather than endpoint-specific.
    #
    # users.language keeps the measured THREE-ARM domain, so a candidate
    # endpoint agrees with the gold ones rather than inventing a narrower
    # world:
    #   "pl" available AND inflected -> set_grammatical_gender runs and reads
    #        the principal's profile
    #   "xx" syntactically fine, NOT in I18n.available_locales -> I18n.locale=
    #        raises I18n::InvalidLocale before the action body
    #   "en" available, not inflected -> the callback does nothing
    # The two compares that select the arm ARE the decision and are recorded
    # as path conditions on the column's own variable before it is
    # concretised.
    #
    # profiles.gender is a PIN LEDGER entry, pinned "male", for the reason the
    # gold batch gives: both arms of the `gender.empty?` compare reach only
    # in-memory I18n inflector lookups -- no statement, no association -- and
    # `String#tr` on a SymbolicString returns a bare subclass allocation with
    # no @value, which turns the callback into a wall instead of a decision.

    # -------------------------------------------------------------------
    # FIX-9: Gate 1b's representative must be reachable
    # -------------------------------------------------------------------
    # `SymbolicList#each` / `#map` are in the runtime's LIST_STUBS and raise
    # (`src_new/runtimes/ruby_runtime/list.rb:285-311`, "contents out of
    # scope"), so the representative row core.rb's `records` mock attaches
    # "so SQL-free display/serialisation iteration completes" could not be
    # reached by anything. MEASURED as the wall on every endpoint that
    # materialises a relation, once FIX-1/3/4/7 let one be materialised.
    #
    # `targets/endpoints/comments_index.rb:780-860` already defines the class
    # core.rb:1482 looks for; it lives in ONE endpoint's layer. This is the
    # MINIMAL version of it, installed only when that one is absent.
    #
    # NO `include Enumerable`, verbatim from that file's reasoning: a module
    # included into a SUBCLASS is inserted BEFORE the superclass, so
    # `Enumerable#any?`/`#none?`/`#count`/`#first` would SHADOW the
    # `SymbolicList` implementations that RECORD `(len(X) != 0)` -- silently
    # dropping path conditions on a run that still looks green (that batch
    # measured 8 PCs falling to 4). It would also re-enable `#include?` and
    # `#to_a`, which the runtime raises on by design.
    #
    # `each` AND `map` both record the same canonical compare the runtime's
    # own `any?`/`none?` record (list.rb:163-172), because a JSON render
    # reaches a collection through `map` and never compares its length
    # otherwise (comments_index D9).
    unless defined?(::IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        def each
          return to_enum(:each) unless block_given?
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "each", taken: nonempty)
          yield @representative if nonempty && @representative
          self
        end

        def map
          return to_enum(:map) unless block_given?
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "map", taken: nonempty)
          (nonempty && @representative) ? [yield(@representative)] : []
        end
        alias_method :collect, :map

        # Ruby's own `[].first` is nil and so is AR's; every OTHER rep-less
        # access still raises loudly. Same carve-out comments_index makes.
        def first(*args)
          return nil if args.empty? && @representative.nil? && concrete_length.zero?
          super
        end
      end)
      warn "[autolab] candidate principal plumbing: IterableSymbolicList defined"
    end

    return unless defined?(::ConcolicTargets)
    unless ::ConcolicTargets.instance_variable_get(:@autolab_candidate_pins)
      pins = Module.new do
        def symbolic_instance(klass, base_name, sql)
          obj = super
          attrs = (obj.respond_to?(:concolic_attrs) ? obj.concolic_attrs : nil)
          return obj unless attrs.is_a?(Hash)
          if klass.name == "User" && attrs["language"].respond_to?(:value)
            lang = attrs["language"]
            attrs["language"] = if lang == "pl"
                                  "pl"
                                elsif lang == "xx"
                                  "xx"
                                else
                                  "en"
                                end
            obj.define_singleton_method(:language) { attrs["language"] }
          end
          if klass.name == "Profile" && attrs["gender"].respond_to?(:value)
            attrs["gender"] = "male"
            obj.define_singleton_method(:gender) { attrs["gender"] }
          end
          obj
        end
      end
      ::ConcolicTargets.singleton_class.prepend(pins)
      ::ConcolicTargets.instance_variable_set(:@autolab_candidate_pins, true)
      warn "[autolab] candidate principal plumbing: users.language 3-arm " \
           "domain + profiles.gender pin installed"
    end

    # -------------------------------------------------------------------
    # FIX-4: name the devise session lookup, and stop branching on it
    # -------------------------------------------------------------------
    # Two problems the gold batches already solved and a candidate endpoint
    # inherits neither of:
    #
    # (a) NAMING. The ONE `.first` inside OrmAdapter::ActiveRecord#get takes
    #     the shared `first_1` ordinal, so the endpoint's OWN first finder
    #     becomes `first_2` and every note/var name shifts by one.
    # (b) A DECISION THAT IS NOT THE ENDPOINT'S. `finder_mock` records a
    #     `<name>_not_found` path condition, so half the exploration budget
    #     goes on "the session failed to resolve" -- MEASURED in the trial:
    #     of 3 runs on admin_pods_index, run 2 took the `not_found == true`
    #     seed and died at `set_locale` with a nil principal again. Devise's
    #     middleware 401s a request whose session does not resolve BEFORE the
    #     controller runs, so that arm is auth plumbing, not endpoint logic.
    #
    # The fix is the one both gold batches carry verbatim
    # (targets/endpoints/aspect_memberships_create.rb:1205-1253,
    #  targets/endpoints/comments_index.rb:2012-2060): a call-site-stable
    # alias declared as its OWN target_function, whose mock mints the users
    # SELECT note but pins the record found and persisted. THE STATEMENT IS
    # STILL RECORDED -- only the not_found DECISION is suppressed.
    return unless defined?(::OrmAdapter::ActiveRecord) && defined?(::ActiveRecord::FinderMethods)
    fm = ::ActiveRecord::FinderMethods
    unless fm.method_defined?(:devise_user_first)
      fm.send(:alias_method, :devise_user_first, :first)
    end
    unless ::ConcolicTargets.instance_variable_get(:@autolab_candidate_devise_first)
      $interceptor.declare_target(
        fm, :devise_user_first,
        kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>",
        returns: lambda do |receiver, args, name|
          ct = ::ConcolicTargets
          u = ct.symbolic_instance(ct.model_class(receiver), name,
                                   ct.sql_for(receiver, args))
          if u.respond_to?(:define_singleton_method)
            u.define_singleton_method(:persisted?)  { true }
            u.define_singleton_method(:new_record?) { false }
          end
          u
        end)
      ::OrmAdapter::ActiveRecord.prepend(OrmAdapterGetNaming) unless
        ::OrmAdapter::ActiveRecord < OrmAdapterGetNaming
      ::ConcolicTargets.instance_variable_set(:@autolab_candidate_devise_first, true)
      warn "[autolab] candidate principal plumbing: devise_user_first " \
           "declared; OrmAdapter#get routed to it"
    end
  end

  # Byte-faithful to orm_adapter-0.5.0's OrmAdapter::ActiveRecord#get, with
  # the one `.first` renamed. Same module both gold batches install.
  module OrmAdapterGetNaming
    def get(id)
      klass.where(klass.primary_key => wrap_key(id)).devise_user_first
    end
  end

'''

# ---------------------------------------------------------------------------
# FIX-5 / FIX-6, both in the driver's terminal policy
# ---------------------------------------------------------------------------

FIX5_OLD = """      rescue Exception => e # rubocop:disable Lint/RescueException
        handled = begin
          ctrl.send(:rescue_with_handler, e)
        rescue Exception
          nil
        end
        unless handled"""

FIX5_NEW = """      rescue Exception => e # rubocop:disable Lint/RescueException
        # E2E FIX-5. `rescue_with_handler` returns the EXCEPTION when a
        # handler ran (activesupport-5.2.4.3 rescuable.rb:88-100) and nil
        # when none matched -- but the old code also collapsed a handler that
        # ITSELF RAISED into the same nil, so the recorded terminal named the
        # ORIGINAL exception with no trace of the failure that actually
        # stopped the run. MEASURED: `comments_index` and `likes_index` each
        # recorded `Diaspora::NonPublic` as their outcome, while what really
        # happened is that the matching handler
        # (app/controllers/comments_controller.rb:16 `rescue_from
        # Diaspora::NonPublic { authenticate_user! }`) raised inside itself.
        # The three cases are now told apart and all three are recorded.
        handler_error = nil
        handled = begin
          ctrl.send(:rescue_with_handler, e)
        rescue Exception => he # rubocop:disable Lint/RescueException
          handler_error = he
          nil
        end
        unless handled"""

FIX5_OLD2 = """          terminal_box[:value] = terminal_record(e)
          next :app_error_500"""

FIX5_NEW2 = """          terminal_box[:value] = terminal_record(e)
          terminal_box[:value]["handler"] =
            if handler_error
              { "status" => "rescue_from handler RAISED",
                "handler_exception" => terminal_record(handler_error) }
            else
              { "status" => "no rescue_from handler matched " \\
                             "#{e.class} on #{ctrl.class}" }
            end
          next :app_error_500"""

FIX6_OLD = """      ctrl.singleton_class.define_method(:current_user) { nil }
      ctrl.singleton_class.define_method(:user_signed_in?) { false }
    end"""

FIX6_NEW = """      ctrl.singleton_class.define_method(:current_user) { nil }
      ctrl.singleton_class.define_method(:user_signed_in?) { false }
      # E2E FIX-6. The signed-in branch above already stubs
      # `authenticate_user!` because \"devise's authenticate_user! -> warden,
      # which the controller-test rig has no middleware for\". The ANONYMOUS
      # branch did not, and the app reaches it anyway -- from a `rescue_from`
      # handler (comments_controller.rb:16, likes_controller.rb:15) and from
      # Devise's own sessions controller. What got recorded was
      # `Devise::MissingWarden`, a RIG artifact, in the place where the
      # endpoint's outcome belongs. MEASURED on sessions_create,
      # sessions_destroy, comments_index and likes_index.
      #
      # The real app THROWS :warden here and its middleware turns that into a
      # redirect to sign-in. The rig has no middleware, so the honest thing
      # is a NAMED outcome saying exactly that, which is what this raises.
      ctrl.singleton_class.define_method(:authenticate_user!) do
        raise AutolabDSE::AuthenticationRequired,
              "authenticate_user! was called on an ANONYMOUS request " \\
              "(directly or from a rescue_from handler); the real app " \\
              "throws :warden here and its middleware redirects to sign-in"
      end
    end

    # e2e FIX-6, second half. `authenticate_user!` is not the only way into
    # Warden: `Devise::SessionsController#create` calls
    # `warden.authenticate!` DIRECTLY, and devise's accessor
    # (devise-4.7.1/lib/devise/controllers/helpers.rb:142-144) is
    # `request.env['warden'] or raise MissingWarden`. The rig dispatches the
    # action directly and has no Warden middleware, so `request.env` never
    # carries one. MEASURED: `sessions_create` and `sessions_destroy` both
    # recorded `Devise::MissingWarden` as their ENDPOINT OUTCOME, which reads
    # like an application fault and is not one -- it is the rig saying it
    # cannot model this endpoint at all, because this endpoint IS Warden
    # authentication.
    #
    # Stubbed in BOTH scenarios, because the accessor is reached from both.
    ctrl.singleton_class.define_method(:warden) do
      raise AutolabDSE::AuthenticationRequired,
            "the action asked for the Warden proxy " \\
            "(devise/controllers/helpers.rb:142). The rig dispatches the " \\
            "action directly and installs no Warden middleware, so there is " \\
            "none. This endpoint cannot be driven without one."
    end"""

FIX6_CLASS_OLD = """module AutolabDSE
  RUNTIME  = \"/home/dev/project/src_new/runtimes/ruby_runtime\""""

FIX6_CLASS_NEW = """module AutolabDSE
  # E2E FIX-6: a NAMED outcome for \"the app asked an anonymous request to
  # authenticate\". Without it the rig's missing Warden middleware surfaced
  # as `Devise::MissingWarden`, which reads like an application fault and is
  # not one.
  class AuthenticationRequired < StandardError; end

  RUNTIME  = \"/home/dev/project/src_new/runtimes/ruby_runtime\""""


FIX2_OLD = '      def dev_stub.to(*_); self; end'
FIX2_NEW = '''      # e2e fix round 1 (2026-09-26). WAS `self`, which handed Devise the
      # STUB where it expects the MODEL CLASS: `mapping.to` is how Devise
      # reaches the resource class, e.g.
      # devise-4.7.1/lib/devise/parameter_sanitizer.rb:158
      # (`extract_auth_keys` -> `mapping.to.authentication_keys`).  All six
      # endpoints that call devise_mapping stopped with a NoMethodError on a
      # bare `#<Object>` receiver, and every missing name --
      # authentication_keys, new_with_session, new, reset_password_by_token,
      # send_reset_password_instructions -- is a User class method.  Falls
      # back to the old behaviour when User is not defined, so nothing that
      # boots without the model changes.
      def dev_stub.to(*_); defined?(::User) ? ::User : self; end'''



# ---------------------------------------------------------------------------
# FIX-7  targets/core.rb calls a runtime method that was DELETED
# ---------------------------------------------------------------------------
# MEASURED (e2e/fixtrial v2, admin_pods_index, runs 1, 2 and 4, with FIX-1/3/4
# in place):
#   NoMethodError: undefined method `len_var_name' for SymbolicVar:Module
#   reports/autolab/targets/core.rb:1395:in `block in install!'
#
# `SymbolicVar.len_var_name` was deleted from the runtime
# (`src_new/runtimes/ruby_runtime/base.rb:33`, DESIGN_IR §4.1.1c change 3 /
# §4.1.1e / §5.3 — "a length is the `length` OPERATOR ... nothing replaces
# this method: there is no name to mint"), and
# `runtimes/ruby_runtime/tests/test_name_boundary_seed.rb:116` asserts the
# deletion. Two sites in core.rb still call it, both only to build a SEED KEY:
#
#   core.rb:1395  Relation#to_a / #to_ary / #records  -> SymbolicList
#   core.rb:1483  the id-projection list mock         -> list_class
#
# So EVERY endpoint that materialises a relation raises. The shakedown never
# saw it because 113 of 161 endpoints died at `set_locale` first and the rest
# stopped before any relation was materialised — the defect was CONCEALED by
# the shallowness, not absent.
#
# The fix mints the key locally instead of reviving the runtime method. The
# spelling is the one this file's own name boundary already documents and
# accepts (`SYM_LEN_PREFIX` / `length_var?`, core.rb:98-124), so seed files
# keyed either way still reach it.

FIX7_HELPER_OLD = """  # True when `var_name` names a container's cardinality, in either spelling.
  def length_var?(var_name)"""

FIX7_HELPER_NEW = """  # The SEED KEY for a container's cardinality.
  #
  # e2e fix round 1 (2026-09-26). Both call sites used to say
  # `SymbolicVar.len_var_name(vn)`, but that method was DELETED from the
  # runtime (src_new/runtimes/ruby_runtime/base.rb:33, DESIGN_IR §4.1.1c
  # change 3 / §5.3 -- a length is the `length` OPERATOR, it registers no
  # symbol, and `tests/test_name_boundary_seed.rb:116` asserts the deletion).
  # Every relation materialisation therefore raised NoMethodError. A length
  # still needs no VARIABLE; what these sites need is a SEED key, and that is
  # this library's own business, so it is minted here in the spelling
  # `length_var?` below already accepts.
  def len_seed_key(var_name)
    "#{SYM_LEN_PREFIX}#{var_name}"
  end

  # True when `var_name` names a container's cardinality, in either spelling.
  def length_var?(var_name)"""

FIX7_SITE1_OLD = """        SymbolicList.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,"""
FIX7_SITE1_NEW = """        SymbolicList.new(seed_for(len_seed_key(vn), 1), name: vn,"""

FIX7_SITE2_OLD = """        list_class.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,"""
FIX7_SITE2_NEW = """        list_class.new(seed_for(len_seed_key(vn), 1), name: vn,"""



# ---------------------------------------------------------------------------
# FIX-9  Gate 1b's representative cannot be iterated, so `records` is a wall
# ---------------------------------------------------------------------------
# MEASURED (e2e/fixtrial with FIX-1/3/4/7, admin_pods_index, runs 1, 2 and 4):
#   NotImplementedError: SymbolicList#each is not supported (contents out of
#     scope). Only #empty?, #any?, #none?, #length/#size, #!, #first, #last,
#     #[] ... are tracked.
#   src_new/runtimes/ruby_runtime/list.rb:305:in `block in each'
#
# core.rb:1386-1389 says the `to_a`/`to_ary`/`records` mock attaches "a single
# representative model row so SQL-free display/serialisation iteration
# COMPLETES (sampled-content)" -- but it builds a plain `SymbolicList`, whose
# `each`/`map` are in `LIST_STUBS` and raise by design. So the representative
# exists and nothing can reach it.
#
# The library already anticipates the answer: core.rb:1482 (the id-projection
# mock) reads `defined?(IterableSymbolicList) ? IterableSymbolicList :
# SymbolicList` INSIDE its returns lambda. The class it looks for exists only
# in ONE endpoint's layer -- targets/endpoints/comments_index.rb:780-860 --
# so for the 159 core-only endpoints the lookup always misses, and the
# `records` mock 87 lines earlier does not even make it.
#
# TWO PARTS:
#   (a) core.rb:1395 takes the SAME `list_class` lookup as core.rb:1482, so
#       the two list mocks stop disagreeing;
#   (b) the driver defines a MINIMAL `IterableSymbolicList` for candidate
#       endpoints, `unless defined?`, so comments_index's richer version
#       (which carries a second representative, M-13) still wins where it is
#       installed.
#
# The minimal version is comments_index's `each`/`map` and nothing else, with
# its two load-bearing decisions kept verbatim:
#   * NO `include Enumerable` -- a module included into a SUBCLASS goes BEFORE
#     the superclass, so `Enumerable#any?`/`#none?` would SHADOW the
#     SymbolicList versions that RECORD `(len(X) != 0)`, silently dropping
#     path conditions on a run that still looks green (measured on the
#     notifications_tags batch: 8 PCs -> 4);
#   * `each` and `map` BOTH record that same canonical compare, because a
#     JSON render reaches the list through `map` and never compares the
#     length otherwise (comments_index D9, adversary round 2).

FIX9_CORE_OLD = """      interceptor.declare_target(rel, m, kind: CallInterceptor::TARGET_FUNCTION, type: "[?]", returns: lambda do |receiver, args, name|
        vn = "#{name}_rows"
        rep = symbolic_instance(model_class(receiver), "#{name}_row", sql_for(receiver, args))
        SymbolicList.new(seed_for(len_seed_key(vn), 1), name: vn,
                       note: sql_for(receiver, args), representative: rep)
      end)"""

FIX9_CORE_NEW = """      interceptor.declare_target(rel, m, kind: CallInterceptor::TARGET_FUNCTION, type: "[?]", returns: lambda do |receiver, args, name|
        vn = "#{name}_rows"
        rep = symbolic_instance(model_class(receiver), "#{name}_row", sql_for(receiver, args))
        # e2e fix round 1 (2026-09-26): the SAME `list_class` lookup the
        # id-projection mock 87 lines below already does. Gate 1b's comment
        # above says the representative is attached "so SQL-free display /
        # serialisation iteration COMPLETES", and a plain SymbolicList's
        # `each`/`map` are in LIST_STUBS and raise -- so without this the
        # representative existed and nothing could reach it. MEASURED:
        # `SymbolicList#each is not supported` at list.rb:305 was the wall on
        # every endpoint that materialises a relation.
        list_class = defined?(IterableSymbolicList) ? IterableSymbolicList : SymbolicList
        list_class.new(seed_for(len_seed_key(vn), 1), name: vn,
                       note: sql_for(receiver, args), representative: rep)
      end)"""



# ---------------------------------------------------------------------------
# FIX-13  a HANDLED exception is invisible, so a rendered error page reads as
#         "the endpoint ran to completion"
# ---------------------------------------------------------------------------
# MEASURED.  `api_openid_connect_clients_create` writes a dump with NO
# `concolic_terminal`, 0 path conditions, 0 target-function reach and exactly
# four events:
#
#   call / symbolic_call  ActionController::Metal#status=
#   call / symbolic_call  ActionController::Rendering#_set_rendered_content_type
#
# The action is
#
#   def create
#     registrar = OpenIDConnect::Client::Registrar.new(request.url, params)
#     client = Api::OpenidConnect::OAuthApplication.register! registrar
#     render json: client.as_json(root: false)
#   end
#
# which neither sets a status nor touches the content type on its success
# path.  `ClientsController` carries FOUR `rescue_from` handlers
# (clients_controller.rb:8-23), every one of which renders a 400 JSON error —
# and `status=` is what a handler does.  So the action raised, a handler
# rendered an error page, and because the driver only records UNRESCUED
# exceptions the dump says nothing at all about it.  The endpoint reads as
# "ran to completion" in every summary.
#
# A HANDLED EXCEPTION IS STILL WHERE EXECUTION STOPPED.  It is a different
# fact from an unrescued one — the application chose this path and a real
# request would get the same 400 — so it is recorded SEPARATELY (as
# `concolic_handled`, a list, since a run can handle more than one) rather
# than folded into `concolic_terminal`, which keeps meaning exactly what it
# meant before.

FIX13_OLD = """        unless handled"""

FIX13_NEW = """        if handled
          # e2e FIX-13: record the handled exception too. Without it a
          # rendered error page is indistinguishable from the action
          # completing — see this script's header for the measurement.
          rec = terminal_record(e)
          rec["handler"] = { "status" => "rescue_from handler HANDLED it",
                             "controller" => ctrl.class.to_s }
          (terminal_box[:handled] ||= []) << rec
        end
        unless handled"""

FIX13_DUMP_OLD = """    dump["concolic_terminal"] = terminal_box[:value] if terminal_box[:value]"""

FIX13_DUMP_NEW = """    dump["concolic_terminal"] = terminal_box[:value] if terminal_box[:value]
    # e2e FIX-13. A SEPARATE key: `concolic_terminal` keeps meaning "the run
    # ended at an exception nothing rescued", and this one means "the
    # application raised and chose a handler". Both are outcomes; only the
    # first one stops the run.
    dump["concolic_handled"] = terminal_box[:handled] if terminal_box[:handled]"""

FIX13_RESET_OLD = """    ConcolicTargets.seed_overrides = seeds
    terminal_box[:value] = nil"""

FIX13_RESET_NEW = """    ConcolicTargets.seed_overrides = seeds
    terminal_box[:value] = nil
    terminal_box[:handled] = nil   # e2e FIX-13: per-run, like :value"""

FIX13_ROW_OLD = """        "terminal" => dump["concolic_terminal"],
        "run_error" => dump["error"]"""

FIX13_ROW_NEW = """        "terminal" => dump["concolic_terminal"],
        "handled" => dump["concolic_handled"],
        "run_error" => dump["error"]"""


def patch(path, edits, apply):
    s = open(path).read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            print(f"  !! anchor appears {n} times in {path}: {old[:60]!r}")
            return False
        s = s.replace(old, new)
    if apply:
        shutil.copy(path, path + ".bak_e2e_round1")
        open(path, "w").write(s)
        print(f"  patched {path} (backup at {path}.bak_e2e_round1)")
    else:
        print(f"  would patch {path}")
    return True


def main():
    apply = "--apply" in sys.argv
    ok = True
    print("FIX-1/3/4 driver principal plumbing; FIX-5/6 terminal policy")
    ok &= patch(DRIVER, [(FIX1_ANCHOR, FIX1_NEW),
                         ("  def install_module!(name)",
                          FIX1_METHOD + "  def install_module!(name)"),
                         (FIX6_CLASS_OLD, FIX6_CLASS_NEW),
                         (FIX5_OLD, FIX5_NEW),
                         (FIX13_OLD, FIX13_NEW),
                         (FIX5_OLD2, FIX5_NEW2),
                         (FIX6_OLD, FIX6_NEW),
                         (FIX13_RESET_OLD, FIX13_RESET_NEW),
                         (FIX13_DUMP_OLD, FIX13_DUMP_NEW),
                         (FIX13_ROW_OLD, FIX13_ROW_NEW)], apply)
    print("FIX-2 devise_mapping stub `to`; FIX-7 deleted len_var_name")
    ok &= patch(CORE, [(FIX2_OLD, FIX2_NEW),
                       (FIX7_HELPER_OLD, FIX7_HELPER_NEW),
                       (FIX7_SITE1_OLD, FIX7_SITE1_NEW),
                       (FIX7_SITE2_OLD, FIX7_SITE2_NEW),
                       (FIX9_CORE_OLD, FIX9_CORE_NEW)], apply)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
