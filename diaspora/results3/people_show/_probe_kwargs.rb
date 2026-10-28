#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_kwargs.rb — verify PeopleShowFindByKwargs prepend + finder_sql merge.
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
PeopleTargets.install!($interceptor)          # prepends PeopleShowFindByKwargs
PeopleShowSymParams.install!($interceptor)

puts "MRO check: FinderMethods.ancestors.first(4) = #{ActiveRecord::FinderMethods.ancestors.first(4).map(&:name).inspect}"
puts "PeopleShowFindByKwargs in FinderMethods.ancestors? #{ActiveRecord::FinderMethods.ancestors.include?(PeopleShowFindByKwargs)}"
puts "Relation.ancestors (first 12):"
ActiveRecord::Relation.ancestors.first(12).each_with_index { |m, i| puts "  #{i}: #{m.name} (#{'PSFBK' if m == PeopleShowFindByKwargs})" }
puts "Relation includes FinderMethods? #{ActiveRecord::Relation.ancestors.include?(ActiveRecord::FinderMethods)}"
puts "Relation#find_by owner: #{ActiveRecord::Relation.instance_method(:find_by).owner rescue 'N/A'}"
puts "Position in chain of FinderMethods: idx=#{ActiveRecord::Relation.ancestors.index(ActiveRecord::FinderMethods).inspect}"
puts "Position in chain of PSFBK: idx=#{ActiveRecord::Relation.ancestors.index(PeopleShowFindByKwargs).inspect}"

ConcolicTargets.seed_overrides = {}
user = PeopleTargets.signed_in_user("KW")

dump = $interceptor.run(
  -> {
    person = ConcolicTargets.symbolic_instance(Person, "KW_PERSON", "probe person")
    person.define_singleton_method(:id) { 7 }
    # direct relation find_by with kwargs
    c1 = Contact.includes(person: :profile).find_by(user_id: 1, person_id: person.id)
    puts "contact_for result: #{c1.class}"
    # block_for path
    b1 = user.blocks.find_by(person_id: person.id)
    puts "block_for result: #{b1.class}"
    :ok
  },
  {}, label: "probe_kwargs", script: "_probe_kwargs.rb"
)
$interceptor.instance_variable_get(:@all_calls).clear

(File.exist?("dump_probe_kwargs.json") && File.delete("dump_probe_kwargs.json"))
File.write("dump_probe_kwargs.json", JSON.pretty_generate(dump))
(dump["events"] || []).select { |e| e["type"] == "symbolic_call" }.each do |e|
  puts format("  %-45s | %s", e["target"], (e["note"] || "")[0, 160])
end
puts "PROBE DONE"