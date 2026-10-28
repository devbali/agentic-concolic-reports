#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_bio_exists3.rb — trace diaspora_links execution.
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)

puts "MessageRenderer#diaspora_links? " +
     (Diaspora::MessageRenderer.method_defined?(:diaspora_links) ? "YES" : "no")
puts "Processor#diaspora_links source: " +
     Diaspora::MessageRenderer::Processor.instance_method(:diaspora_links).source_location.inspect
puts "Processor#normalize source: " +
     Diaspora::MessageRenderer::Processor.instance_method(:normalize).source_location.inspect
puts "Processor#diaspora_links? " +
     (Diaspora::MessageRenderer::Processor.method_defined?(:diaspora_links) ? "YES" : "no")
puts "Processor#normalize? " +
     (Diaspora::MessageRenderer::Processor.method_defined?(:normalize) ? "YES" : "no")

# Check block dispatch: which methods does instance_exec resolve?
renderer = Diaspora::MessageRenderer.new("x diaspora://alice@localhost/post/postguid100000001 y")
# monkeypatch Post.exists? to print a trace marker
class << Post
  alias_method :_orig_exists, :exists?
  def exists?(*a, **k)
    warn "!!! Post.exists? CALLED args=#{a.inspect} kwargs=#{k.inspect}"
    _orig_exists(*a, **k)
  end
end
d = $interceptor.run(
  -> {
    out = renderer.plain_text_for_json
    puts "rendered: #{out.inspect}"
    :ok
  },
  {}, label: "probe_bio_exists3", script: "_probe_bio_exists3.rb"
)
puts "error=#{d["error"].inspect}"
(d["events"] || []).each_with_index do |e, i|
  puts "#{i}: type=#{e["type"]} tgt=#{e["target"].to_s[0,58]} note=#{e["note"].to_s[0,90]}"
end