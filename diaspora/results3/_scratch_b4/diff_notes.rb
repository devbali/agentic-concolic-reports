#!/usr/bin/env jruby
# frozen_string_literal: true
# diff_notes.rb — differential: does the B-4 patch move any note that the
# PRE-patch canonical already rendered successfully?
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
ActiveRecord::Base.establish_connection(:concolic)

DIR = "/home/dev/project/reports/diaspora"
def load_renderer(const, path)
  lines = File.readlines(path)
  a = lines.index { |l| l =~ /^  def render_relation_sql\(rel\)/ }
  b = lines.index { |l| l =~ /^  def model_class\(receiver\)/ }
  foot = lines.join[/^class ConcolicSymbolicToSql < Arel::Visitors::ToSql.*?\nend\n/m]
  eval(foot) if foot && !Object.const_defined?(:ConcolicSymbolicToSql)
  m = Module.new
  Object.const_set(const, m)
  m.module_eval("module_function\n" + lines[a...(b - 1)].join)
  m
end
AFTER  = load_renderer(:AfterR,  "#{DIR}/concolic_targets.rb")
BEFORE = load_renderer(:BeforeR, "#{DIR}/concolic_targets.rb.bak_pre_b4_20260915")

s_id   = symint("SYM_PERSON_PO_id", 7)
s_guid = symstr("SYM_POST_guid", "g-1")

CASES = {
  "concrete: Notification.where(recipient_id: 5)"      => -> { Notification.where(recipient_id: 5) },
  "symbolic bind: Notification.where(recipient_id: S)" => -> { Notification.where(recipient_id: s_id) },
  "concrete join+limit: Contact.where(user_id: 1).limit(3)" => -> { Contact.where(user_id: 1).limit(3) },
  "concrete STI: Reshare.where(root_guid: 'g')"        => -> { Reshare.where(root_guid: "g") },
  "symbolic STI: Reshare.where(root_guid: S)"          => -> { Reshare.where(root_guid: s_guid) },
  "STI + symbolic int: Reshare.where(author_id: S)"    => -> { Reshare.where(author_id: s_id) },
  "raw-arel Casted: Post.where(Post.arel_table[:public].eq(true))" =>
    -> { Post.where(Post.arel_table[:public].eq(true)) },
  "assoc scope: User#person (concrete owner)"          => -> { u = User.new; u.id = 7; u.association(:person).scope },
  "Person.where(owner_id: S)"                          => -> { Person.where(owner_id: s_id) },
  "order/offset: Post.order(:id).offset(2).limit(4)"   => -> { Post.order(:id).offset(2).limit(4) },
  "IN list: Post.where(id: [1,2,3])"                   => -> { Post.where(id: [1, 2, 3]) },
  "NOT: Post.where.not(author_id: 3)"                  => -> { Post.where.not(author_id: 3) },
}

same = moved = fixed = 0
CASES.each do |label, mk|
  r = ->(m) { begin; m.render_relation_sql(mk.call); rescue Exception => e; "!!#{e.class}"; end }
  b = r.call(BEFORE); a = r.call(AFTER)
  if b == a
    same += 1;  puts "SAME   #{label}"
  elsif b.start_with?("!!")
    fixed += 1; puts "FIXED  #{label}\n         before: #{b}\n         after : #{a}"
  else
    moved += 1; puts "MOVED  #{label}\n         before: #{b}\n         after : #{a}"
  end
end
puts "\n#{same} byte-identical, #{fixed} crash->statement, #{moved} MOVED"
