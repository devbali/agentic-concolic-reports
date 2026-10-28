# C1 capture (CHECKS.md Part IV): subscribe to sql.active_record and log
# every statement real execution issues. Ground truth for the statement
# differential — no reference policy involved.
#
#   real = CompletionChecker::StatementLog.capture { <real code> }
#   CompletionChecker::StatementLog.capture_to("real.json") { ... }
#
# For T1 use target_call_probe.rb (the shim-mock contract is about
# TARGET FUNCTIONS, not SQL); this log is T1's supplementary belt for the
# SQL target family where a DB is wired:
#   raise "shim mock issued SQL" unless CompletionChecker::StatementLog.capture { body }.empty?
require "json"

module CompletionChecker
  module StatementLog
    SKIP_NAMES = ["SCHEMA", "TRANSACTION"].freeze

    def self.capture
      unless defined?(ActiveSupport::Notifications)
        raise "StatementLog.capture requires the app booted (ActiveSupport missing)"
      end
      statements = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        payload = args.last
        next if payload[:cached]
        next if SKIP_NAMES.include?(payload[:name].to_s)
        statements << { "sql" => payload[:sql].to_s, "name" => payload[:name].to_s }
      end
      yield
      statements
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription) if subscription
    end

    def self.capture_to(path, &block)
      statements = capture(&block)
      File.write(path, JSON.pretty_generate(statements))
      statements
    end
  end
end
