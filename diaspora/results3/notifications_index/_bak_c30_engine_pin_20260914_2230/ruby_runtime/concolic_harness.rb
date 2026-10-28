# frozen_string_literal: true
#
# Diaspora concolic harness — loads the REAL Rails app and provides a stubbed
# DB connection so the real model/service/controller query pipeline runs
# against the intercepted SQL target (ConcolicAdapter#execute).
#
# Usage (from the diaspora app dir, RAILS_ENV=concolic):
#   require "config/environment"
#   require "/home/dev/project/src/ruby_runtime/concolic_harness"
#   harness = ConcolicHarness.new
#   harness.declare_sql_target { |sql, name| ... returns [value, sort] or nil }
#   dump = harness.run(->(id:) { ... }, {id: 1}, label: "x")
#
require "config/environment"

require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/symbolic_func"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"

module ConcolicHarness
  # Stub adapter: select_all builds an ActiveRecord::Result whose rows come
  # from the intercepted execute target. The target returns either:
  #   [rows_array, "Result"]   -> rows are hashes of column=>value
  #   [nil_or_empty, "Result"] -> empty result (no rows)
  #   [int, "Int"]             -> scalar (for counts/existence)
  class Adapter < ActiveRecord::ConnectionAdapters::AbstractAdapter
    attr_accessor :target_proc

    def initialize
      super(nil)
      @target_proc = nil
    end

    # The concolic target — declare_target intercepts this.
    def execute(sql, name = nil)
      raise NotImplementedError, "stub — declare_target intercepts"
    end

    def select_all(arel, name = nil, binds = [], preparable: nil)
      sql = arel.is_a?(String) ? arel : arel.to_sql
      result = execute(sql, name) # intercepted -> symbolic value

      # The target returns a symbolic value. We convert:
      # - a SymbolicList / Array of row-hashes -> ActiveRecord::Result
      # - a SymbolicInt 1 -> single generic row
      # - 0 / empty -> empty result
      if defined?(SymbolicList) && result.is_a?(SymbolicList)
        rows = result.items.map do |item|
          if defined?(SymbolicDict) && item.is_a?(SymbolicDict)
            item.items.transform_keys(&:to_s)
          elsif item.is_a?(Hash)
            item.transform_keys(&:to_s)
          else
            item
          end
        end
      else
        rows = result.is_a?(Array) ? result : []
      end
      cols = rows.empty? ? ["id"] : rows.first.keys
      # Coerce row values to native (unwrap any remaining SymbolicInt/String)
      native_rows = rows.map { |r| r.is_a?(Hash) ? r.map { |k, v| [k, to_native(v)] }.to_h : r }
      ActiveRecord::Result.new(cols, native_rows.map { |r| r.is_a?(Hash) ? cols.map { |c| r[c] } : [r] })
    end

    def exec_query(sql, name = nil, binds = [], prepare: false)
      select_all(sql, name)
    end

    def quote_column_name(n); "`#{n}`"; end
    def quote_table_name(n); "`#{n}`"; end
    def quote(v)
      case v
      when String then "'#{v}'"
      when true then "1"
      when false then "0"
      else v.to_s
      end
    end
    def quote_true; "1"; end
    def quote_false; "0"; end
    def columns(table); []; end
    def data_source_exists?(n); true; end
    def data_sources; []; end
    def primary_key(t); "id"; end
    def indexes(t); []; end
    def foreign_keys(t); []; end
    def table_exists?(n); true; end
    def schema_cache; @sc ||= ActiveRecord::ConnectionAdapters::SchemaCache.new(self); end
    def supports_statement_cache?; false; end
    def supports_migrations?; false; end
    def supports_primary_key?; false; end
    def supports_ddl_transactions?; false; end
  end

  class << self
    def interceptor
      @interceptor ||= CallInterceptor.instance
    end

    # Install the stub connection into ActiveRecord.
    def install!
      pool = ActiveRecord::Base.connection_pool
      adapter = Adapter.new
      pool.define_singleton_method(:connection) { adapter }
      adapter
    end

    # Declare the SQL target. The block receives (sql_string, result_name)
    # and returns [value, sort] (e.g. [1, "Int"] or [[{id:1}], "Result"]).
    def declare_sql_target(&block)
      interceptor.declare_target(Adapter, :execute, returns: block)
    end

    def run(proc, concrete_values, label:)
      interceptor.run(proc, concrete_values, label: label)
    end
  end
end