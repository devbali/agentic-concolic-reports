# frozen_string_literal: true
#
# shared_shims.rb -- SHIM mocks lifted OUT of a batch-local override file and
# into the auto lab's shared layer.
#
# WHY THIS FILE EXISTS
# --------------------
# The user's ruling for this lab: TARGET_FUNCTION declarations are the app-wide
# boundary and belong in the core; SHIM declarations get triaged, and the
# genuinely app-wide ones join them. `targets/core.rb` already carries 38
# app-wide shims. This file carries the ones that were still trapped in a
# single batch's `targets.rb` even though nothing about them is specific to
# that endpoint.
#
# WHAT MAY BE LIFTED HERE, AND WHAT MAY NOT
# -----------------------------------------
# A declaration is lifted only when its mock body is SELF-CONTAINED: no call
# into a batch-local helper (`AspectMembershipsTargets.finder_note`,
# `CommentsTargets.poly_klass`, ...) and no dependence on a prepend the batch
# installs. That is not fussiness -- a note helper is a NOTE SHAPE, and under
# Rule T a note-shape change in a shared file restarts every endpoint that has
# already been closed against the old shape.
#
# Declarations that are app-wide in SUBSTANCE but not yet liftable in FORM are
# recorded in ../inventory/partition.json with tier "core-eligible" and the
# exact blocker. That file, not this one, is the backlog.
#
# THE D5 HAZARD, AND WHY THIS FILE TAKES A SKIP LIST
# --------------------------------------------------
# `declare_target` installs via `define_method`, so a SECOND declaration for
# the same (class, method) does not replace the first -- it WRAPS it, and
# `declare_target` then reads `klass.instance_method(method).parameters` off
# the FIRST mock's wrapper, whose signature is `|*splat_args, **kwargs, &block|`.
# Every named argument the second mock wanted comes back nil. That defect is
# named D5 in the corpus and is measured at
# `targets/endpoints/aspect_memberships_create.rb:1072`.
#
# So this file never declares a target the endpoint is going to declare
# itself. `install!` takes `skip:` -- the set of target names the endpoint's
# own override will claim -- and the loader computes it from the manifest.
# For the two gold endpoints the skip list plus the empty default group set
# makes this file a measured no-op; `test/test_install.rb` asserts that.
#
# GROUPS
# ------
# `install!(interceptor, groups: [...], skip: [...])`. Nothing installs unless
# its group is named, so adding a group here can never silently change an
# endpoint that has already been closed.

require "json"

module AutolabSharedShims
  module_function

  # Group -> the target names it declares. The loader reads this to decide
  # what to skip and the test suite reads it to prove coverage.
  GROUPS = {
    # Federation DELIVERY. `Dispatcher.defer_dispatch` builds a
    # `Diaspora::Federation::Dispatcher` and hands it to Sidekiq (and
    # `Sidekiq::Client#push` is already a core shim); `User#deliver_profile_update`
    # is a one-line delegation to it. Neither issues SQL on this path: they are
    # walls -- the runtime cannot model the federation entity graph -- not
    # accesses, so SHIM is right for both.
    #
    # KNOWN COST, carried over verbatim from the batch that wrote them:
    # `deliver_profile_update` reads `self.profile`, an association load that
    # WOULD be an access; shimming the outer method elides it. The alternative
    # (letting it run) drags the whole federation entity validation chain in,
    # which is a documented wall on every batch.
    #
    # WHY APP-WIDE: nothing in either body, or in the reasoning above, mentions
    # aspect memberships. Any endpoint that writes a shareable or touches a
    # profile reaches them. They sat in one batch's file because that batch was
    # the first write endpoint in the corpus, not because they are local to it.
    "federation_delivery" => [
      "Diaspora::Federation::Dispatcher.defer_dispatch",
      "User#deliver_profile_update",
    ].freeze,
  }.freeze

  # @param interceptor [CallInterceptor]
  # @param groups [Array<String>] which GROUPS to install. Default: none.
  # @param skip [Array<String>] target names the endpoint declares itself.
  # @return [Hash] {installed: [...], skipped: [...], unavailable: [...]}
  def install!(interceptor = CallInterceptor.instance, groups: [], skip: [])
    groups = Array(groups).map(&:to_s)
    unknown = groups - GROUPS.keys
    unless unknown.empty?
      raise ArgumentError,
            "AutolabSharedShims: unknown group(s) #{unknown.inspect}; " \
            "known groups are #{GROUPS.keys.inspect}"
    end
    skip = Array(skip).each_with_object({}) { |t, h| h[t.to_s] = true }
    report = { installed: [], skipped: [], unavailable: [] }

    if groups.include?("federation_delivery")
      # type: str? -- the real defer_dispatch returns perform_async's job id;
      # this mock records null.
      t = "Diaspora::Federation::Dispatcher.defer_dispatch"
      if skip[t]
        report[:skipped] << t
      elsif !defined?(Diaspora::Federation::Dispatcher)
        report[:unavailable] << t
      else
        interceptor.declare_target(Diaspora::Federation::Dispatcher.singleton_class,
                                   :defer_dispatch,
                                   kind: CallInterceptor::SHIM, type: "str?",
                                   returns: ->(_r, _a, _n) { nil })
        report[:installed] << t
      end

      # type: str? -- delegates to defer_dispatch (a job id); this mock records null.
      t = "User#deliver_profile_update"
      if skip[t]
        report[:skipped] << t
      elsif !(defined?(User) && User.method_defined?(:deliver_profile_update))
        report[:unavailable] << t
      else
        interceptor.declare_target(User, :deliver_profile_update,
                                   kind: CallInterceptor::SHIM, type: "str?",
                                   returns: ->(_r, _a, _n) { nil })
        report[:installed] << t
      end
    end

    report
  end
end
