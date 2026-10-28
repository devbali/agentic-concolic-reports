# frozen_string_literal: true

require_relative "path_condition"
require_relative "base"
require_relative "int"
require_relative "string"
require_relative "bool"
require_relative "symbolic_func"
require "json"

# CallInterceptor — Ruby runtime target call interceptor.
#
# Records every call to a target method during symbolic execution,
# along with the path conditions that led there. Produces RunDump
# JSON dicts that the concolic engine can consume.
#
# The CallInterceptor is a singleton. Use CallInterceptor.instance.
#
# Usage:
#   interceptor = CallInterceptor.instance
#
#   # Option 1: declare a target — body executes, return becomes symbolic
#   interceptor.declare_target(MyClass, :my_method)
#
#   # Option 2: declare with a returns lambda — body is SKIPPED
#   #   The lambda receives (call_args_hash, result_name_string) and
#   #   returns the concrete value (or [value, sort] for explicit sort).
#   interceptor.declare_target(CheckSessionAccess, :call,
#     returns: ->(args, name) { 0 })
#
#   # Option 3: run a Proc directly
#   dump = interceptor.run(->(x) { ... }, { x: 5 }, label: "test")
#
#   # The dump is a JSON-serializable Hash

class CallInterceptor
  # Sorts a mock may declare via the `[value, sort]` return form.
  SORT_NAME_SET = [:Int, :Bool, :String, :Real,
                   "Int", "Bool", "String", "Real"].freeze

  # ------------------------------------------------------------------
  # TargetCall — one intercepted invocation
  # ------------------------------------------------------------------
  class TargetCall
    attr_reader :run_label, :args, :call_site, :pc_snapshot, :target_name

    def initialize(run_label:, args:, call_site:, pc_snapshot:, target_name: "")
      @run_label   = run_label
      @args        = args
      @call_site   = call_site
      @pc_snapshot = pc_snapshot
      @target_name = target_name # which target this call hit (multi-target safe)
    end
  end

  # ------------------------------------------------------------------
  # Singleton
  # ------------------------------------------------------------------

  @instance = nil

  def self.instance
    @instance ||= new
  end

  # ------------------------------------------------------------------
  # Initialize
  # ------------------------------------------------------------------

  attr_reader :calls

  def initialize
    @all_calls          = []
    @current_run_label  = nil
    @target_name        = ""
  end

  def calls
    @all_calls.dup
  end

  def calls_for_run(label)
    @all_calls.select { |c| c.run_label == label }
  end

  # ------------------------------------------------------------------
  # declare_target — decorate a method so its calls are intercepted
  # ------------------------------------------------------------------

  # Two forms:
  #
  #   1. declare_target(klass, method)
  #      Body executes, return becomes symbolic.
  #
  #   2. declare_target(klass, method, returns: ->(args, name) { ... })
  #      Body is SKIPPED.  The lambda receives (call_args_hash,
  #      result_name) and returns concrete value (or [value, sort]
  #      array for explicit sort control).
  #
  # @param klass  [Class|Module]
  # @param method [Symbol]
  # @param returns [Proc, nil]  Optional lambda value-supplier
  def declare_target(klass, method, returns: nil)
    klass_name = klass.name || "Anonymous"
    @target_name = "#{klass_name}.#{method}"

    original = klass.instance_method(method)
    interceptor = self
    value_fn = returns

    klass.define_method(method) do |*splat_args, **kwargs, &block|
      # Snapshot PC stack
      raw_pcs = SymbolicVar.get_path_conditions
      pc_snap = raw_pcs.map { |pc| pc.to_dict }

      loc = interceptor.send(:caller_location)

      # Build concrete args
      params = original.parameters
      call_args = {}
      params.each_with_index do |p, i|
        type = p[0]
        name = p[1]
        idx = i
        if name
          val = idx < splat_args.length ? splat_args[idx] : kwargs[name]
          call_args[name.to_s] = to_native(val)
        end
      end

      interceptor.instance_variable_get(:@all_calls) << TargetCall.new(
        run_label:   interceptor.instance_variable_get(:@current_run_label),
        args:        call_args,
        call_site:   "#{loc[0]}:#{loc[1]} in #{loc[2]}()",
        pc_snapshot: pc_snap,
        target_name: "#{klass_name}.#{method}",
      )

      if value_fn
        # --- Body-skip mode ---
        func_name = "#{klass_name}.#{method}"
        idx = SymbolicFunc.next_call_idx(func_name)
        # Z3-safe result name (engine evals `name = Sort('name')`)
        result_name = "SYM_RESULT_#{func_name}_#{idx}".gsub(/[^A-Za-z0-9_]/, "_")

        # Mock lambdas may take (args, result_name) [legacy] or
        # (receiver, args, result_name) [needed for e.g. receiver.to_sql].
        raw_result = if value_fn.arity == 2
                       value_fn.call(call_args, result_name)
                     else
                       value_fn.call(self, call_args, result_name)
                     end

        # `[value, sort]` is a declaration form, not a shape any 2-element
        # Array should fall into: a mock returning two rows (reachable in
        # every batch since the 0/1/many cardinality rule, B-7) was being
        # read as a value plus a sort, silently dropping the second row
        # (conversations_index, 2026-08-29). Require the second element to
        # actually name a sort.
        if raw_result.is_a?(Array) && raw_result.length == 2 &&
           SORT_NAME_SET.include?(raw_result[1])
          concrete_result = raw_result[0]
          result_sort     = raw_result[1]
        else
          concrete_result = raw_result
          result_sort     = sort_of(to_native(concrete_result))
        end

        src = caller_frame_skip(["call_interceptor.rb"])
        SymbolicFunc.push_record(
          SymbolicCallRecord.new(
            target_name:  func_name,
            args:         call_args,
            result_name:  result_name,
            result_value: to_native(concrete_result),
            result_sort:  result_sort,
            source:       src,
            note:         interceptor.class.extract_note(concrete_result),
          )
        )

        # If the mock already returned a symbolic value (or an arbitrary
        # object such as a symbolic model instance), pass it through
        # unchanged — only convert plain natives.
        if concrete_result.is_a?(SymbolicVar) ||
           !(concrete_result.is_a?(Integer) || concrete_result.is_a?(String) ||
             concrete_result.is_a?(Float) || concrete_result == true ||
             concrete_result == false || concrete_result.is_a?(Array) ||
             concrete_result.is_a?(Hash) || concrete_result.nil?)
          concrete_result
        else
          to_symbolic(concrete_result, name: result_name)
        end
      else
        # --- Body-execute mode ---
        # Avoid the JRuby kwargs gotcha: an empty **kwargs is passed as a
        # spurious trailing positional arg when the target method has no
        # keyword params. Only splat kwargs when they are actually present.
        result = if kwargs.empty?
                   original.bind(self).call(*splat_args, &block)
                 else
                   original.bind(self).call(*splat_args, **kwargs, &block)
                 end

        concrete = to_native(result)
        func_name = "#{klass_name}.#{method}"
        idx = SymbolicFunc.next_call_idx(func_name)
        result_name = "SYM_RESULT_#{func_name}_#{idx}".gsub(/[^A-Za-z0-9_]/, "_")
        result_sort = sort_of(concrete)

        src = caller_frame_skip(["call_interceptor.rb"])
        SymbolicFunc.push_record(
          SymbolicCallRecord.new(
            target_name:  func_name,
            args:         call_args,
            result_name:  result_name,
            result_value: concrete,
            result_sort:  result_sort,
            source:       src,
            note:         interceptor.class.extract_note(result),
          )
        )

        to_symbolic(concrete, name: result_name)
      end
    end
  end

  # Extract a SQL/context note from a value returned by a mock (or a real
  # method body). Mirrors SymbolicVar#note: symbolic factories set it, and
  # symbolic_model instances carry #concolic_note (see concolic_targets.rb).
  # Returns nil when the value has no note — the symbolic_call event then
  # omits the key (matches the pre-note behavior).
  # A mock that returns a FALSY value (a finder that found nothing, a
  # predicate that is false) cannot carry a note on its result — Ruby has no
  # falsy object to hang one on — so the statement the mock stands for was
  # lost: 3 551 note-less events across 2 960 dumps on comments_index, and
  # the extracted policy silently omitted the endpoint's own access-control
  # reads (adversary round 5, M-9, 2026-08-29). A mock may therefore publish
  # its note out of band, immediately before returning, via
  #
  #     CompletionChecker = nil  # (no dependency)
  #     Thread.current[:concolic_pending_note] = "SELECT ..."
  #
  # which this reads exactly once. A note on the returned value still wins;
  # the side channel is always cleared, so it can never leak into the next
  # call.
  def self.extract_note(value)
    pending = Thread.current[:concolic_pending_note]
    Thread.current[:concolic_pending_note] = nil

    from_value =
      if value.nil?
        nil
      elsif value.respond_to?(:note) && value.note
        value.note
      elsif value.respond_to?(:concolic_note) && value.concolic_note
        value.concolic_note
      end

    from_value || pending
  end

  # ------------------------------------------------------------------
  # wrap_target — DEPRECATED, use declare_target instead
  # ------------------------------------------------------------------

  def wrap_target(*args)
    warn "[DEPRECATION] wrap_target is deprecated. Use declare_target instead."
    if args.length == 2
      klass, method = args
      declare_target(klass, method)
    elsif args.length == 3
      value_fn, klass, method = args
      declare_target(klass, method, returns: value_fn)
    else
      raise ArgumentError, "wrap_target takes 2 or 3 arguments"
    end
  end

  # ------------------------------------------------------------------
  # run — execute source with symbolic values, return RunDump
  # ------------------------------------------------------------------

  # @param source [Proc|Method]  The function to run (receives kwargs)
  # @param concrete_values [Hash<String, Object>]  var name → concrete value
  # @param label [String, nil]
  # @param script [String, nil]  Optional inline source that generated this
  #   run.  Embedded in the dump for reproducibility.
  # @return [Hash]  RunDump (JSON-serializable)
  def run(source, concrete_values, label: nil, script: nil)
    SymbolicVar.clear_path_conditions
    SymbolicFunc.reset!
    old_count = @all_calls.size
    @current_run_label = label

    # Build kwargs as symbolic types (bools → SymbolicBool, mirroring py)
    kwargs = {}
    concrete_values.each do |name, val|
      kwargs[name.to_sym] = if val.is_a?(String)
                              SymbolicString.new(val, name: name.to_s)
                            elsif val == true || val == false
                              SymbolicBool.new(val, name: name.to_s)
                            else
                              SymbolicInt.new(val, name: name.to_s)
                            end
    end

    # Execute (capture errors into the dump — PCs recorded before the
    # crash are still emitted; mirrors py_runtime behaviour)
    error_info = nil
    begin
      if source.is_a?(Proc) || source.respond_to?(:call)
        source.call(**kwargs)
      end
    rescue Exception => e
      error_info = {
        "type"      => e.class.name,
        "message"   => e.message,
        "traceback" => (e.backtrace || []).first(20).join("\n"),
      }
    end

    # Collect PCs
    all_pcs = SymbolicVar.save_and_clear
    all_pc_dicts = all_pcs.map { |pc| pc_to_dict(pc) }

    # Collect symbolic call records
    sym_call_records = SymbolicFunc.save_and_clear

    symbolic_results = sym_call_records.map do |rec|
      {
        "name"  => rec.result_name,
        "sort"  => rec.result_sort,
        "value" => rec.result_value,
      }
    end

    run_calls = @all_calls[old_count..]

    # Merge events
    events = []
    pc_idx = 0
    sym_idx = 0

    (run_calls || []).each do |call|
      call_prefix = call.pc_snapshot
      # Emit PCs before this call
      while pc_idx < call_prefix.size
        pc = call_prefix[pc_idx]
        events << {
          "type"     => "path_condition",
          "expr"     => pc["expr"],
          "taken"    => pc["taken"],
          "file"     => pc["file"],
          "lineno"   => pc["lineno"],
          "function" => pc["function"],
        }
        pc_idx += 1
      end

      # Emit call event
      parts = call.call_site.split(" in ")
      loc_part = parts[0]
      func_part = parts[1]&.sub(/\(\)$/, "") || ""
      file, lineno_str = loc_part.split(":")

      events << {
        "type"     => "call",
        "target"   => (call.target_name.empty? ? @target_name : call.target_name),
        "args"     => call.args,
        "file"     => file,
        "lineno"   => lineno_str.to_i,
        "function" => func_part,
      }

      # Emit symbolic_call event
      if sym_idx < sym_call_records.size
        rec = sym_call_records[sym_idx]
        ev = {
          "type"         => "symbolic_call",
          "target"       => rec.target_name,
          "args"         => rec.args,
          "result_name"  => rec.result_name,
          "result_value" => rec.result_value,
          "result_sort"  => rec.result_sort,
          "file"         => rec.source[0],
          "lineno"       => rec.source[1],
          "function"     => rec.source[2],
        }
        ev["note"] = rec.note if rec.note
        events << ev
        sym_idx += 1
      end
    end

    # Emit remaining PCs
    while pc_idx < all_pc_dicts.size
      pc = all_pc_dicts[pc_idx]
      events << {
        "type"     => "path_condition",
        "expr"     => pc["expr"],
        "taken"    => pc["taken"],
        "file"     => pc["file"],
        "lineno"   => pc["lineno"],
        "function" => pc["function"],
      }
      pc_idx += 1
    end

    registered_vars = SymbolicFunc.respond_to?(:save_and_clear_registered_vars) ? SymbolicFunc.save_and_clear_registered_vars : []

    make_run_dump(label, concrete_values, events,
                  symbolic_results: symbolic_results, script: script,
                  registered_vars: registered_vars, error: error_info)
  end

  private

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  def pc_to_dict(pc)
    {
      "expr"     => pc.expr,
      "taken"    => pc.taken,
      "file"     => pc.frame[0],
      "lineno"   => pc.frame[1],
      "function" => pc.frame[2],
    }
  end

  def caller_location
    caller_locations.each do |loc|
      bn = File.basename(loc.path)
      unless bn == "call_interceptor.rb"
        return [loc.path, loc.lineno, loc.label]
      end
    end
    ["<unknown>", 0, "<unknown>"]
  end

  def make_run_dump(label, concrete_values, events, symbolic_results: [], script: nil, registered_vars: [], error: nil)
    svars = concrete_values.map do |name, val|
      sort = case val
             when String  then "String"
             when TrueClass, FalseClass then "Bool"
             when Float   then "Real"
             else "Int"
             end
      { "name" => name.to_s, "sort" => sort, "value" => val }
    end

    # Vars declared inside mocks / source via factories (symint/symbool/...)
    # with register_var — deduped by name, first declaration wins.
    seen = svars.map { |v| v["name"] }.to_a
    registered_vars.each do |v|
      next if seen.include?(v["name"])
      svars << v
      seen << v["name"]
    end

    dump = {
      "schema_version" => "1.0",
      "label"          => label,
      "symbolic_vars"  => svars,
      "events"         => events,
    }
    dump["symbolic_results"] = symbolic_results unless symbolic_results.empty?
    dump["script"] = script if script
    dump["error"] = error if error
    dump
  end
end
