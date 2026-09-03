#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _t1_inspect.rb — variant_b T1 pre-flight. Boots the SAME environment
# run_dse.rb boots (all targets declared as normal), then for a candidate
# list of (klass, method) pairs prints:
#   - original.source_location
#   - the literal source text (best-effort line-range finder)
#   - original.parameters
# to a log so fixtures can be built accurately. Does NOT invoke anything.
# Read-only inspection; writes no dumps.

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false

# Capture ORIGINAL unbound methods BEFORE declare_target patches them.
CANDIDATES = [
  [ActionController::Metal, :status=],
  [ActionController::Redirecting, :redirect_to],
  [ActionDispatch::Routing::UrlFor, :url_for],
  [DeviseController, :assert_is_devise_resource!],
  [ActiveRecord::Associations::SingularAssociation, :writer],
  [ActionController::Metal, :head],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target],
  [ActionController::Rendering, :_set_rendered_content_type],
  [DeviseController, :devise_mapping],
  [ActiveRecord::Base, :to_param],
  [ActionController::Instrumentation, :redirect_to],
  # design-family spot checks (informational only)
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::Relation, :exists?],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Relation, :update_all],
  [ActiveRecord::Persistence, :save],
  [ActiveRecord::Querying, :find_by_sql],
  [Sidekiq::Client, :push],
  [User, :blocks],
  [ActiveRecord::Calculations, :pluck],
].compact

# IMPORTANT: do NOT call ConcolicTargets.install!/NotificationsIndexTargets.install!
# here — that monkey-patches these very classes via declare_target, and
# instance_method() below would then return the INTERCEPTOR WRAPPER, not the
# true original body. Inspect the pristine classes as loaded by Rails boot.
$interceptor = CallInterceptor.instance

def find_end_line(lines, start_idx)
  # start_idx is 0-based index of the `def` line. Track keyword/end balance.
  depth = 0
  opens = /\b(def|do|if|unless|case|begin|class|module|while|until)\b/
  # module-level `if`/`unless` used as statement MODIFIERS don't open a block;
  # heuristic: only count opens when the line does NOT end with 'end' inline
  # and isn't a one-line modifier form (trailing if/unless/while/until).
  i = start_idx
  while i < lines.length
    line = lines[i]
    stripped = line.strip
    # crude: count 'end' keywords vs block-openers, ignoring modifier forms
    is_modifier = stripped =~ /\S.*\s(if|unless|while|until)\s+\S.*[^;]$/ && !(stripped =~ /^(if|unless|while|until|case|def|class|module|begin)\b/)
    opens_here = 0
    ends_here = 0
    stripped.scan(opens) { opens_here += 1 } unless is_modifier && i != start_idx
    stripped.scan(/\bend\b/) { ends_here += 1 }
    # ternary/lambda `do |x| ... end` on one line handled by balance too
    depth += opens_here
    depth -= ends_here
    if i > start_idx && depth <= 0
      return i
    end
    i += 1
  end
  start_idx
end

out = []
CANDIDATES.each do |klass, meth|
  begin
    um = klass.instance_method(meth)
    loc = um.source_location
    out << "=== #{klass}##{meth} ==="
    out << "source_location: #{loc.inspect}"
    out << "arity: #{um.arity}  parameters: #{um.parameters.inspect}"
    if loc
      file, sline = loc
      begin
        lines = File.readlines(file)
        eline = find_end_line(lines, sline - 1)
        out << "computed body range: #{sline}..#{eline + 1} (#{eline - (sline - 1) + 1} lines)"
        out << lines[(sline - 1)..eline].join
      rescue StandardError => e
        out << "(could not read source: #{e.class}: #{e.message})"
      end
    end
    out << ""
  rescue StandardError => e
    out << "=== #{klass}##{meth} === FAILED: #{e.class}: #{e.message}"
    out << ""
  end
end

File.write("/home/dev/project/reports/diaspora/results3/_experiment/variant_b/_t1_inspect.log", out.join("\n"))
warn "[t1_inspect] wrote _t1_inspect.log (#{out.length} lines)"
