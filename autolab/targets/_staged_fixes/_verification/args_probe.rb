# frozen_string_literal: true
#
# args_probe.rb — WHAT SHAPE DO THE ARGS ARRIVE IN?
#
# `update`, `update_attribute` and `touch` are intercepted BEFORE their body
# runs, so the columns they write are in ARGS, not on the receiver. Which key
# holds them depends on how many times the target was declared: `declare_target`
# names args from `klass.instance_method(m).parameters`, and after a SECOND
# declaration "the method" is the first mock's wrapper, whose signature is
# `|*splat_args, **kwargs, &block|` (the D5 defect in ../../README.md).
#
# This prints the raw args hash under BOTH stacks so the renderer's extraction
# is written against a measurement, not a guess.
#
# ENV: TARGETS=core|override, TARGETS_DIR

require "./config/environment"
%w[call_interceptor base int string bool list].each do |f|
  require "/home/dev/project/src_new/runtimes/ruby_runtime/#{f}"
end
require "fileutils"

HERE = File.dirname(File.expand_path(__FILE__))
TDIR = ENV["TARGETS_DIR"] || "/home/dev/project/reports/autolab/targets"
STACK = ENV["TARGETS"] || "core"
DB = File.join(HERE, "out", "args_#{Process.pid}.sqlite3")
FileUtils.cp(File.join(Rails.root, "db", "concolic.sqlite3"), DB)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
conn = ActiveRecord::Base.connection
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts people users].each { |t| conn.execute("DELETE FROM #{t}") rescue nil }
conn.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'a','a@e','x','#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,created_at,updated_at) VALUES (2,'g','b@o','k','#{now}','#{now}')")
conn.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")
R1 = Contact.find(50)
R2 = Contact.find(50)
R3 = Contact.find(50)

require File.join(TDIR, "core.rb")
IC = CallInterceptor.instance
ConcolicTargets.install!(IC)
if STACK == "override"
  require File.join(TDIR, "endpoints/aspect_memberships_create.rb")
  AspectMembershipsTargets.install!(IC)
  AmDeviseUserNaming.install!(IC) if defined?(AmDeviseUserNaming)
end

# Wrap the renderer so the ARGS it was handed are printed alongside the note
# it produced. Nothing is changed: the original is called straight through.
module ArgsSpy
  def dml_note(receiver, op, args = nil)
    n = super
    puts format("  op=%-18s args=%-70s\n     -> %s",
                op.to_s, args.inspect[0, 70], n.inspect[0, 150])
    n
  end
end
ConcolicTargets.singleton_class.prepend(ArgsSpy)

puts "== TARGETS=#{STACK}  dir=#{TDIR}"
R1.update(receiving: true)
R2.update_attribute(:sharing, true)
R3.touch
R3.touch(:receiving)
puts "== done"
