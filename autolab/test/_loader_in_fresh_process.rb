# frozen_string_literal: true
#
# Helper for test/test_install.rb. Drives Autolab::Targets.install! for ONE
# endpoint in a FRESH process -- which is how a sweep must run it, because
# install! is not idempotent (see autolab_targets.rb, "ONE ENDPOINT PER
# PROCESS"). Prints the report as JSON on stdout.
#
#   ruby test/_loader_in_fresh_process.rb <endpoint> [repeats]
require "json"
require_relative "../tools/stub_world"

LAB = File.expand_path("..", __dir__)
reg = JSON.parse(File.read(File.join(LAB, "targets", "registry.json")))
ep = ARGV[0]
repeats = (ARGV[1] || "1").to_i

files = [File.join(LAB, reg["core"]["file"]),
         File.join(LAB, reg["endpoints"][ep]["file"])]
consts = JSON.parse(`ruby #{File.join(LAB, "tools", "scrape_constants.rb")} #{files.join(" ")}`)
files.each { |f| load f }
consts.each { |c| stub_const(c) rescue nil }
if Object.const_defined?(:Rails) && Rails.respond_to?(:__stub__)
  Rails.define_singleton_method(:root) { "/nonexistent-autolab-rails-root" }
  Rails.define_singleton_method(:application) { nil }
end

require_relative "../autolab_targets"
reports = (1..repeats).map { Autolab::Targets.install!(ep, interceptor: CallInterceptor.new) }
puts JSON.generate(reports)
