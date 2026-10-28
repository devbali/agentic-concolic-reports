#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_rc1.rb — does RAILS_ENV=concolic_mod actually activate
# lazy_columns' default_scope on Profile in THIS harness?
require "./config/environment"

puts "RAILS_ENV                     = #{ENV['RAILS_ENV'].inspect}"
puts "Rails.env                     = #{Rails.env.inspect}"
puts "Rails.env.include?('mod')     = #{Rails.env.include?('mod')}"
puts "Profile loaded before conn?   = #{Object.const_defined?(:Profile)}"

ActiveRecord::Base.establish_connection(:concolic)
puts "connection established"

puts "Profile.table_exists?         = #{Profile.table_exists?}"
puts "Profile.all.to_sql            = #{Profile.all.to_sql}"
puts "Profile.default_scopes.size   = #{Profile.default_scopes.size}"
puts "Profile.where(person_id: 1).to_sql ="
puts "  #{Profile.where(person_id: 1).to_sql}"
puts "Person.first.class rescue     = (skipped)"
puts "Profile.column_names.size     = #{Profile.column_names.size}"
puts "has lazy accessor for :bio?   = #{Profile.instance_methods(false).include?(:bio)}"
