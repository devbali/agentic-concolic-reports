# frozen_string_literal: true
#
# Per-entrypoint concolic targets — results2/notifications_index ONLY.
#
# Ported (trimmed to what notifications#index actually needs) from
# ../../results/notifications_tags/targets.rb §5a/§5b/§5c — the wall-closing
# infrastructure that took notifications#index from "crashes 3/3" to
# "runs clean, 0 PCs" in the source batch. Everything below is UNCHANGED
# logic from that file; #update/#read_all-only pieces (§1 Tag load, §2
# persistence overrides, §6 Post.blocked_people) are dropped — this
# directory drives notifications#index exclusively, per results2/README.md's
# "one dir per entrypoint" layout.
#
# Installs AFTER `ConcolicTargets.install!` (see run_dse.rb).
#
#   ConcolicTargets.install!(interceptor)     # shared generic AR interception
#   NotificationsIndexTargets.install!(interceptor)  # this file
#
# Wall-fixing discipline (main README): every mock here wraps the SMALLEST
# enclosing method whose real body contains NO SQL and calls NO other
# declared target. Producing queries still run for real.

module NotificationsIndexTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # -----------------------------------------------------------------
    # 5a. Coercible + quotable symbolic integer.
    #
    # Closes the WillPaginate wall: `will_paginate/collection.rb:109
    # total_entries=` does `number.to_i`, and src/ruby_runtime/int.rb:30
    # raises NotImplementedError on `SymbolicInt#to_i` by design (it is an
    # implicit-concretization channel). `#to_i` here is EXPLICIT and returns
    # the concrete `value`; `#to_int` is deliberately left raising, so
    # implicit coercion (Array#[], string *, etc.) is still caught.
    # -----------------------------------------------------------------
    unless defined?(ConcolicIntValue)
      ::Object.const_set(:ConcolicIntValue, Class.new(SymbolicInt) do
        def to_i
          value
        end

        def value_for_database
          value
        end

        def quoted_id
          value
        end

        def next
          ConcolicIntValue.new(value + 1,
                               name: (sym_name ? "(#{sym_name} + 1)" : nil),
                               note: note)
        end
        alias_method :succ, :next
      end)
    end

    # -----------------------------------------------------------------
    # 5b. Iterable symbolic list.
    #
    # notifications#index needs `each`/`map`/`group_by` on query results:
    #   `types.each_with_object(current_user.unread_notifications.group_by(&:type))`
    #   `notification_list.map {|note| NotificationSerializer.new(note, ...) }`
    # The shared collection mock already attaches `representative:` and
    # #first/#last/#[0] honour it — yielding that same representative once is
    # the Gate 1b "one sampled row" semantics those readers already implement.
    #
    # DO NOT `include Enumerable` HERE (measured regression in the source
    # batch: shadows the PC-recording SymbolicList#any?/#empty?/#first).
    # -----------------------------------------------------------------
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end

        def map
          return to_enum(:map) unless block_given?
          (@representative && concrete_length != 0) ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    rel = ActiveRecord::Relation

    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_rows"
        sql = ct.sql_for(receiver, args)
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: sql, representative: rep)
      end)
    end

    # 5b-ii. `to_ary` must return a TRUE Array — `pager.replace(result)`
    # (notifications_controller.rb:41) reaches `Array#replace`
    # (WillPaginate::Collection < Array); `to_ary` is Ruby's IMPLICIT
    # conversion protocol and the interpreter type-checks the result, so a
    # SymbolicList (or even a bare Array, which `to_symbolic` would re-wrap)
    # fails. `SampledRowsArray` is a real `::Array` subclass that also
    # includes `SymbolicVar` so it survives the interceptor's post-processing
    # AND satisfies `to_ary`'s type check.
    unless defined?(SampledRowsArray)
      ::Object.const_set(:SampledRowsArray, Class.new(::Array) do
        include SymbolicVar
        attr_reader :note, :representative

        def self.build(len, rep, name:, note:)
          a = new(len) { rep }
          a.instance_variable_set(:@sym_name, name)
          a.instance_variable_set(:@note, note)
          a.instance_variable_set(:@representative, rep)
          a
        end
      end)
    end

    interceptor.declare_target(rel, :to_ary, returns: lambda do |receiver, args, name|
      vn  = "#{name}_rows"
      sql = ct.sql_for(receiver, args)
      len = ct.seed_for("len(#{vn})", 1).to_i
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      SampledRowsArray.build(len, rep, name: vn, note: sql)
    end)

    # 5b-iii. Relation#count -> ConcolicIntValue (the WillPaginate producer).
    calc = ActiveRecord::Calculations
    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn = "#{name}_count"
      ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn,
                           note: ct.sql_for(receiver, args))
    end)

    # -----------------------------------------------------------------
    # 5c. Date-shaped symbolic value + column wiring.
    #
    # `symbolic_instance` maps every non-integer/boolean column to
    # SymbolicString, so the `datetime` column `notifications.updated_at` has
    # no #strftime and notifications#index dies at
    #   `@group_days = @notifications.group_by {|note| note.updated_at.strftime(..) }`
    # -----------------------------------------------------------------
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # 5c-wiring + 5a-wiring: batch-local WRAPPER around the shared
    # `symbolic_instance`. After the generic build, rewrite the attrs hash the
    # singleton readers close over: date/datetime -> ConcolicDate; integer/
    # bigint -> ConcolicIntValue (same var name/seed/note, now quotable).
    unless ConcolicTargets.respond_to?(:symbolic_instance_without_ni_values)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_ni_values, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_ni_values(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          klass.columns_hash.each do |col, meta|
            case meta.type
            when :date, :datetime
              vn = "#{base_name}_#{col}_year"
              d = ConcolicDate.new(1990, 1, 1)
              d.sym_year = symint(vn, seed_for(vn, 1990), note: sql)
              attrs[col] = d
              obj.define_singleton_method(col) { d }
            when :integer, :bigint
              old = attrs[col]
              next unless old.is_a?(SymbolicInt)
              nv = ConcolicIntValue.new(old.value, name: old.sym_name, note: old.note)
              attrs[col] = nv
              obj.define_singleton_method(col) { nv }
            end
          end
          obj
        end
      end
    end

    warn "[notifications_index] NotificationsIndexTargets installed"
  end
end
