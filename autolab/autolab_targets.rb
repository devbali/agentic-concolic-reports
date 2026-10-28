# frozen_string_literal: true
#
# autolab_targets.rb -- the auto lab's target-function loader.
#
# A sweep drives an endpoint like this, from inside the diaspora app, under
# JRuby (`scripts/diaspora-concolic`):
#
#     require "./config/environment"
#     require "/home/dev/project/reports/autolab/autolab_targets.rb"
#     report = Autolab::Targets.install!("comments_index", interceptor: $interceptor)
#
# and gets back a report saying exactly what was declared, by which layer.
#
# WHAT IT LOADS, IN ORDER
# -----------------------
#   1. the src_new ruby runtime (by ABSOLUTE path -- `scripts/diaspora-concolic`
#      still exports a vestigial RUBY_RUNTIME pointing at the OLD `src/`, which
#      nothing here reads)
#   2. targets/core.rb                 -> ConcolicTargets.install!
#   3. targets/endpoints/<endpoint>.rb -> each of its modules, in registry order
#   4. targets/shared_shims.rb         -> only the groups the endpoint opts into
#
# Steps 2 and 3 reproduce `results4/<endpoint>/run_dse.rb` exactly, file for
# file and module for module, so a gold endpoint driven through this loader
# declares what it declared when its dumps were made. Step 4 adds nothing to a
# gold endpoint (their `shared_shim_groups` is empty) and is where a NEW
# endpoint picks up the app-wide shim tail without copying it.
#
# ONE ENDPOINT PER PROCESS
# ------------------------
# A sweep must fork a process per endpoint, the way each results4 `run_dse.rb`
# does. `install!` is NOT IDEMPOTENT, and this lab measured where:
# `targets/endpoints/comments_index.rb:881` creates `ConcolicThroughLoadProbe`
# under `unless defined?(::ConcolicThroughLoadProbe)` and DECLARES ITS TARGET
# INSIDE THAT GUARD, so a second install in the same process silently declares
# 104 targets instead of 105. It is the only site of that shape in the gold
# corpus (checked across all three files), and it never showed up before
# because every batch ran in its own process.
# This loader cannot fix it -- the guard is in a verified batch file -- but it
# DETECTS it: a repeat install of the same endpoint whose declared set differs
# from the first warns on stderr and sets `repeat_install_drift` in the report.
#
# WHY THE ORDER IS CORE-THEN-LOCAL AND NOT THE OTHER WAY
# ------------------------------------------------------
# It has to be. `declare_target` installs a wrapper with `define_method`, so a
# later declaration WRAPS the earlier one rather than replacing it; the local
# layer can only win by going last. That mechanism is lossy -- see D5 in the
# README -- which is why this loader REPORTS every double declaration instead
# of leaving it to be discovered in a dump.

require "json"

module Autolab
  module Targets
    ROOT     = File.expand_path(__dir__)
    RUNTIME  = "/home/dev/project/src_new/runtimes/ruby_runtime"
    REGISTRY = File.join(ROOT, "targets", "registry.json")
    MANIFEST = File.join(ROOT, "inventory", "manifest.json")

    class UnknownEndpoint < ArgumentError; end

    module_function

    def registry
      @registry ||= JSON.parse(File.read(REGISTRY))
    end

    def manifest
      @manifest ||= JSON.parse(File.read(MANIFEST))
    end

    def endpoints
      registry["endpoints"].keys.sort
    end

    # Load the runtime. Idempotent; safe if the runner already required it.
    def require_runtime!
      %w[call_interceptor base int string bool list object dict symbolic_func].each do |f|
        require File.join(RUNTIME, f)
      end
    end

    # The target names the endpoint's OWN override file declares. Read from the
    # manifest so `shared_shims` can be told what not to touch before anything
    # has run.
    def local_targets(endpoint)
      manifest["declarations"]
        .select { |d| d["endpoint"] == endpoint && d["layer"] == "local" }
        .map { |d| d["target"] }
        .uniq
    end

    # @param endpoint [String]
    # @param interceptor [CallInterceptor]
    # @param shared_shim_groups [Array<String>, nil] override the registry
    # @return [Hash] what each layer did
    def install!(endpoint, interceptor: nil, shared_shim_groups: nil)
      require_runtime!
      interceptor ||= CallInterceptor.instance

      spec = registry["endpoints"][endpoint]
      unless spec
        raise UnknownEndpoint,
              "autolab has no override file for endpoint #{endpoint.inspect}. " \
              "Registered: #{endpoints.inspect}. An endpoint mined from " \
              "results3 but not yet migrated to kind:/type: is in " \
              "inventory/candidates.json, NOT here -- see README.md."
      end

      report = { "endpoint" => endpoint, "layers" => [] }

      # 1. core
      require File.join(ROOT, registry["core"]["file"])
      registry["core"]["modules"].each do |m|
        before = declared_names(interceptor)
        Object.const_get(m).install!(interceptor)
        report["layers"] << layer_report("core", m, before, interceptor)
      end

      # 2. endpoint-local
      require File.join(ROOT, spec["file"])
      spec["modules"].each do |m|
        before = declared_names(interceptor)
        Object.const_get(m).install!(interceptor)
        report["layers"] << layer_report("local", m, before, interceptor)
      end

      # 3. shared shim groups the endpoint opted into
      groups = shared_shim_groups || spec["shared_shim_groups"] || []
      require File.join(ROOT, "targets", "shared_shims.rb")
      report["shared_shims"] =
        AutolabSharedShims.install!(interceptor, groups: groups,
                                                 skip: declared_names(interceptor))

      names = declared_names(interceptor).sort
      report["declared_total"] = names.size
      report["double_declared"] = double_declared(endpoint)

      # Repeat-install drift. See "ONE ENDPOINT PER PROCESS" above.
      @first_install ||= {}
      if @first_install.key?(endpoint) && @first_install[endpoint] != names
        lost = @first_install[endpoint] - names
        gained = names - @first_install[endpoint]
        report["repeat_install_drift"] = { "lost" => lost, "gained" => gained }
        warn "[autolab] REPEAT INSTALL of #{endpoint} in this process declared a " \
             "DIFFERENT set: lost #{lost.inspect}, gained #{gained.inspect}. " \
             "install! is not idempotent -- drive one endpoint per process."
      else
        @first_install[endpoint] ||= names
        report["repeat_install_drift"] = nil
      end
      report
    end

    def declared_names(interceptor)
      (interceptor.instance_variable_get(:@declarations) || {}).keys
    end

    def layer_report(layer, mod, before, interceptor)
      after = declared_names(interceptor)
      { "layer" => layer, "module" => mod,
        "new" => (after - before).sort,
        "declared_after" => after.size }
    end

    # Targets that MORE THAN ONE layer declares for this endpoint, i.e. the
    # ones exposed to D5 (see README). Read from the manifest rather than
    # inferred at run time: `@declarations` keeps one entry per target, so a
    # redeclaration leaves no trace in the interceptor's own state, and the
    # only honest way to see it without monkeypatching the runtime during a
    # real sweep is to consult the measurement that already counted the calls.
    #
    # It is a REPORT, not a failure. Both gold endpoints have some, by design.
    def double_declared(endpoint)
      counts = Hash.new(0)
      manifest["declarations"].each do |d|
        next unless d["endpoint"] == endpoint
        counts[d["target"]] += 1
      end
      counts.select { |_t, n| n > 1 }.keys.sort
    end
  end
end
