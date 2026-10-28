#!/usr/bin/env jruby
# frozen_string_literal: true
#
# probe_fixes.rb — does each PROPOSED fix actually work, under the same
# core-only target set a scaffolded endpoint gets?  Nothing here is applied
# to the library; every fix is simulated in-process and measured.
#
#   FIX A  install the `authenticatable_salt` leaf shim (the one
#          targets/endpoints/comments_index.rb:2050 installs for the ONE gold
#          endpoint) and re-run the principal chain.
#   FIX B  make the devise_mapping stub's `to` return ::User instead of the
#          stub itself, and check that the five methods the six devise
#          endpoints died on are then all present.
require "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse"

AutolabDSE.boot!("__probe_core_only__")

def show(label, v)
  puts format("  %-34s %-30s %s", label, v.class.to_s, v.inspect.to_s[0, 120])
  $stdout.flush
end

puts "\n================ FIX B: devise_mapping.to ================"
if defined?(DeviseController)
  ctrl = DeviseController.allocate
  stub = begin
    ctrl.send(:devise_mapping)
  rescue Exception => e
    puts "  devise_mapping raised #{e.class}: #{e.message.to_s[0, 120]}"
    nil
  end
  show("devise_mapping", stub)
  if stub
    show("devise_mapping.to (current)", (begin
                                           stub.to
                                         rescue Exception => e
                                           "RAISED #{e.class}"
                                         end))
    puts "  stub.equal?(stub.to) -> #{stub.equal?(stub.to) rescue 'n/a'}"
  end
end
puts "\n  the five methods the six devise endpoints died on, asked of ::User:"
%i[authentication_keys new_with_session new reset_password_by_token
   send_reset_password_instructions].each do |m|
  puts format("    ::User.respond_to?(:%-32s) -> %s", m, (User.respond_to?(m) rescue "n/a"))
end
puts "  Devise.mappings keys: #{(Devise.mappings.keys.inspect rescue 'n/a')}"
puts "  Devise.mappings[:user].to: #{(Devise.mappings[:user].to.inspect rescue 'n/a')}"

puts "\n================ FIX A: authenticatable_salt shim ================"
puts "  BEFORE: User ancestors defining authenticatable_salt: " \
     "#{User.ancestors.select { |m| m.instance_methods(false).include?(:authenticatable_salt) }.inspect}"

salt_shim = Module.new do
  def authenticatable_salt
    if defined?(ConcreteSymbolicString)
      ConcreteSymbolicString.build("concolicsalt", name: nil,
        note: "User#authenticatable_salt leaf (encrypted_password[0,29] slice)")
    else
      "concolicsalt"
    end
  end
end
User.prepend(salt_shim)
puts "  AFTER : User ancestors defining authenticatable_salt: " \
     "#{User.ancestors.select { |m| m.instance_methods(false).include?(:authenticatable_salt) }.inspect}"

$interceptor.run(lambda do
  uid = symint("SYM_USER_CI_id", 1)
  u = begin
    User.serialize_from_session(uid, "concolicsalt")
  rescue Exception => e
    puts "  serialize_from_session RAISED #{e.class}: #{e.message.to_s[0, 160]}"
    nil
  end
  show("serialize_from_session", u)
  if u
    %i[language gender person].each do |m|
      v = begin
        u.send(m)
      rescue Exception => e
        "RAISED #{e.class}: #{e.message.to_s[0, 100]}"
      end
      show("current_user.#{m}", v)
    end
  end
  :ok
end, {}, label: "probe_fixes", script: "probe_fixes.rb")

puts "\nprobe_fixes done"
