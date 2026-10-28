#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_remote.rb — debug remote? seed computation for anon+local.
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
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)

puts "seed_overrides = #{ConcolicTargets.seed_overrides.inspect}"
sym = PeopleShowSymParams.symbolic_username("alice@localhost")
puts "sym class=#{sym.class} name=#{sym.sym_name.inspect} value=#{sym.value.inspect}"
puts "downcase=#{sym.downcase.class}"

# Simulate the remote? lambda:
h = sym
s = h.respond_to?(:value) ? h.value.to_s : h.to_s
default = (!s.empty? && s !~ /@localhost/) rescue false
puts "host-derived default for symbolic username: #{default.inspect} (s=#{s.inspect})"

# The symbolic person's diaspora_handle:
person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON", "SELECT * FROM people")
dh = person.diaspora_handle
puts "person.diaspora_handle class=#{dh.class} value=#{dh.respond_to?(:value) ? dh.value.inspect : dh.inspect}"
s2 = dh.respond_to?(:value) ? dh.value.to_s : dh.to_s
default2 = (!s2.empty? && s2 !~ /@localhost/) rescue false
puts "host-derived default for person handle: #{default2.inspect} (s=#{s2.inspect})"

vn = "Person_remote"
puts "seed_for(remote, default2) = #{ConcolicTargets.seed_for(vn, default2).inspect}"