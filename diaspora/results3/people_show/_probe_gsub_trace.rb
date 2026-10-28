#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_gsub_trace.rb — trace gsub block behavior on plain String.
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

rx = DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX
msg = "x diaspora://alice@localhost/post/postguid100000001 y"
puts "regex inspect: #{rx.inspect[0,120]}"

# replicate diaspora_links exactly with tracing
out = msg.gsub(rx) { |match_str|
  guid = Regexp.last_match(3)
  warn "GSUB BLOCK RAN: match=#{match_str.inspect} guid=#{guid.inspect} lm2=#{Regexp.last_match(2).inspect}"
  if Regexp.last_match(2) == "post"
    warn "  calling Post.exists?"
    r = Post.exists?(guid: guid)
    warn "  exists? => #{r.inspect}"
  end
  match_str
}
puts "final: #{out.inspect}"