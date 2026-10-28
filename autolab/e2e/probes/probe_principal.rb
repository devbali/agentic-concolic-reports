#!/usr/bin/env jruby
# frozen_string_literal: true
#
# probe_principal.rb — WHY do the signed-in scaffolded endpoints stop at
# `undefined method 'language' for nil:NilClass`?
#
# The generic driver resolves the principal with
#   User.serialize_from_session(ci_uid, "concolicsalt")   (autolab_dse.rb:390)
# and devise's `serialize_from_session` (devise-4.7.1
# lib/devise/models/authenticatable.rb:236-239) is
#   record = to_adapter.get(key); record if record && record.authenticatable_salt == salt
# so there are exactly three ways it can return nil.  This probe walks the
# chain and prints which one fires, under the SAME core-only target set a
# scaffolded endpoint gets.  It asserts nothing; it prints.
require "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse"

AutolabDSE.boot!("__probe_core_only__")

def show(label, v)
  puts format("  %-28s %-34s %s", label, v.class.to_s, v.inspect.to_s[0, 150])
end

$interceptor.run(lambda do
  uid = symint("SYM_USER_CI_id", 1)
  puts "\n== principal resolution chain, core targets only =="
  show("uid", uid)
  ad = User.to_adapter
  show("User.to_adapter", ad)
  rec = begin
    ad.get(uid)
  rescue Exception => e
    puts "  to_adapter.get RAISED #{e.class}: #{e.message.to_s[0, 160]}"
    puts "    #{Array(e.backtrace).first(3).join("\n    ")}"
    nil
  end
  show("to_adapter.get(uid)", rec)
  if rec
    salt = begin
      rec.authenticatable_salt
    rescue Exception => e
      puts "  authenticatable_salt RAISED #{e.class}: #{e.message.to_s[0, 160]}"
      puts "    #{Array(e.backtrace).first(3).join("\n    ")}"
      :RAISED
    end
    show("record.authenticatable_salt", salt)
    # NB: `salt` is a symbolic string; comparing it to a Symbol raises inside
    # the runtime, so the sentinel is tested by identity, never by `==`.
    unless salt.equal?(:RAISED)
      cmp = begin
        salt == "concolicsalt"
      rescue Exception => e
        "RAISED #{e.class}: #{e.message.to_s[0, 120]}"
      end
      show("salt == 'concolicsalt'", cmp)
      puts "  -> truthiness of that comparison: #{(cmp ? 'TRUTHY' : 'FALSY')}"
      puts "  -> devise keeps the record only if it is truthy " \
           "(authenticatable.rb:238: `record if record && record.authenticatable_salt == salt`)"
      $stdout.flush
    end
  end
  u = begin
    User.serialize_from_session(uid, "concolicsalt")
  rescue Exception => e
    puts "  serialize_from_session RAISED #{e.class}: #{e.message.to_s[0, 160]}"
    nil
  end
  show("serialize_from_session", u)
  puts "\n== what set_locale would then do =="
  begin
    puts "  current_user.language -> #{u.language.inspect[0, 80]}"
  rescue Exception => e
    puts "  RAISES #{e.class}: #{e.message.to_s[0, 160]}"
    puts "    #{Array(e.backtrace).first(4).join("\n    ")}"
  end
  puts "\n== is the salt shim present? =="
  puts "  User ancestors carrying authenticatable_salt: " +
       User.ancestors.select { |m| m.instance_methods(false).include?(:authenticatable_salt) }.inspect
  puts "  FinderMethods#devise_user_first defined? " \
       "#{ActiveRecord::FinderMethods.method_defined?(:devise_user_first)}"
  :ok
end, {}, label: "probe", script: "probe_principal.rb")
puts "\nprobe done"
