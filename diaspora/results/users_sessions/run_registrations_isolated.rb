# frozen_string_literal: true
#
# run_registrations_isolated.rb — crash-isolated prefix-directed DSE for
# `registrations#create`, the one entrypoint in this batch that could not be
# explored in-process.
#
# WHY THIS EXISTS
# ---------------
# registrations#create's SECOND DSE path aborts the whole JVM:
#
#   SIGSEGV ... The crash happened outside the Java Virtual Machine in native code
#     com.kenai.jffi.Foreign.getZeroTerminatedByteArray
#     org.jruby.ext.ffi.jffi.FFIUtil.getString(Ruby, long)
#
# It is outside the JVM, so `rescue Exception` cannot catch it and the process
# dies taking the worklist with it. run_dse.rb contained the damage by capping
# the entrypoint at ONE execution (RUNS_CAP), which is why it is the batch's
# only `coverage_complete: false`.
#
# THE FIX: move the worklist OUT of the process.
# All DSE state (stack, seen-seeds, seen-paths, poisoned seeds, counters) lives
# in <WORK_DIR>/state.json and is fsynced after EVERY execution. Before each
# execution the seed about to run is written to <WORK_DIR>/current_seed.json.
# So when the JVM aborts, the supervising driver knows exactly which seed set
# killed it, marks that ONE seed poisoned, and restarts — the search continues
# instead of stopping. Nothing is silently dropped: poisoned seeds are recorded
# with their crash signature and reported in the summary.
#
# This process re-boots Rails only when it is restarted after a crash, so a
# clean batch costs one boot, not one boot per execution.
#
# Neither src/, the shared concolic_targets.rb, nor the app is modified.
# run_dse.rb is not modified either — its helper prefix (requires, targets
# install, StubWarden, drive, symbolic_user, flip_seed, the EP table) is loaded
# verbatim below, so this file cannot drift from it.
#
# Usage (via the driver, which supervises restarts):
#   python3 reports/diaspora/results/users_sessions/drive_registrations.py
#
# Env:
#   WORK_DIR       required — directory holding state.json / current_seed.json
#   OUT_DIR        where dump_*.json are written (default: ./registrations_create)
#   EP_NAME        entrypoint to explore (default: registrations_create)
#   PROC_MAX_RUNS  executions this process may perform before exiting cleanly
#                  (default 0 = drain the worklist)
#   MAX_RUNS       overall cap across all processes (default 400)

require "json"
require "set"
require "fileutils"

RUN_DSE = "/home/dev/project/reports/diaspora/results/users_sessions/run_dse.rb"

# Load run_dse.rb's helper prefix — everything BEFORE its main loop. The split
# marker is the first line of that loop and occurs exactly once. Passing the
# real path to eval keeps __FILE__ (and therefore RESULTS) correct.
src    = File.read(RUN_DSE)
marker = %r{^only = \(ENV\["ONLY"\]}
raise "run_dse.rb main-loop marker not found" unless src =~ marker
eval(src.split(marker).first, TOPLEVEL_BINDING, RUN_DSE) # rubocop:disable Security/Eval

WORK     = ENV.fetch("WORK_DIR")
EP_NAME  = ENV.fetch("EP_NAME", "registrations_create")
OUT      = ENV["OUT_DIR"] || File.join(RESULTS, EP_NAME)
PROC_MAX = (ENV["PROC_MAX_RUNS"] || 0).to_i
HARD_MAX = (ENV["MAX_RUNS"] || 400).to_i

FileUtils.mkdir_p(WORK)
FileUtils.mkdir_p(OUT)

STATE_PATH   = File.join(WORK, "state.json")
CURRENT_PATH = File.join(WORK, "current_seed.json")

DEFAULT_STATE = {
  "stack"       => [{}],
  "seen_seeds"  => [],
  "seen_paths"  => [],
  "poisoned"    => [],
  "runs"        => 0,
  "written"     => 0,
  "errors"      => {},
  "unflippable" => {},
  "boots"       => 0
}.freeze

def load_state
  return Marshal.load(Marshal.dump(DEFAULT_STATE)) unless File.exist?(STATE_PATH)
  JSON.parse(File.read(STATE_PATH))
rescue JSON::ParserError
  # A crash mid-write can truncate the file; fall back to the .bak snapshot.
  bak = "#{STATE_PATH}.bak"
  raise unless File.exist?(bak)
  warn "[isolated] state.json unreadable, recovering from .bak"
  JSON.parse(File.read(bak))
end

# Atomic + durable: write to a temp file, fsync, rename. The previous good
# state is kept as .bak so a crash during the rename window is recoverable.
def save_state(st)
  FileUtils.cp(STATE_PATH, "#{STATE_PATH}.bak") if File.exist?(STATE_PATH)
  tmp = "#{STATE_PATH}.tmp"
  File.open(tmp, "w") do |f|
    f.write(JSON.generate(st))
    f.flush
    f.fsync
  end
  File.rename(tmp, STATE_PATH)
end

def write_current(seed, label)
  File.open(CURRENT_PATH, "w") do |f|
    f.write(JSON.generate("seed" => seed, "label" => label))
    f.flush
    f.fsync
  end
end

state = load_state
state["boots"] += 1
save_state(state)

body = EP.fetch(EP_NAME)
seen_seeds = Set.new(state["seen_seeds"])
seen_paths = Set.new(state["seen_paths"])
poisoned   = Set.new(state["poisoned"].map { |p| p["key"] })

puts "[isolated] boot ##{state['boots']} ep=#{EP_NAME} stack=#{state['stack'].size} " \
     "runs=#{state['runs']} written=#{state['written']} poisoned=#{poisoned.size}"

this_proc = 0
stop = "worklist_drained"

until state["stack"].empty?
  if state["runs"] >= HARD_MAX
    stop = "max_runs"
    break
  end
  if PROC_MAX.positive? && this_proc >= PROC_MAX
    stop = "proc_max_runs"
    break
  end

  seeds = state["stack"].pop
  key   = digest(JSON.generate(seeds.sort.to_h))
  next if seen_seeds.include?(key) || poisoned.include?(key)

  seen_seeds << key
  state["seen_seeds"] = seen_seeds.to_a
  state["runs"] += 1
  this_proc += 1
  label = format("dse%04d", state["runs"])

  # Persist BEFORE running: if the next line aborts the JVM, the driver reads
  # current_seed.json to attribute the crash to exactly this seed set.
  write_current(seeds, label)
  save_state(state)

  begin
    $interceptor.instance_variable_set(:@all_calls, [])
    ConcolicTargets.seed_overrides = seeds
    user = symbolic_user
    dump = $interceptor.run(-> { body.call(user) }, {}, label: label,
                            script: "run_registrations_isolated.rb")
  rescue Exception => e # rubocop:disable Lint/RescueException
    state["errors"]["harness:#{e.class}"] = (state["errors"]["harness:#{e.class}"] || 0) + 1
    puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
    save_state(state)
    next
  end

  if dump["error"]
    k = "run:#{dump['error']['type']}"
    state["errors"][k] = (state["errors"][k] || 0) + 1
  end

  pcs = path_conditions(dump)
  sig = digest(sig_of(pcs))

  unless seen_paths.include?(sig)
    seen_paths << sig
    state["seen_paths"] = seen_paths.to_a
    state["written"] += 1
    File.write(File.join(OUT, "dump_#{label}.json"), JSON.pretty_generate(dump))
    puts format("  [%s] NEW path pcs=%d stack=%d %s", label, pcs.size,
                state["stack"].size,
                dump["error"] ? "error=#{dump['error']['type']}" : "")
  end

  pcs.each do |expr, taken|
    fl = flip_seed(expr, !taken)
    if fl.nil?
      state["unflippable"][expr] = (state["unflippable"][expr] || 0) + 1
      next
    end
    child = seeds.merge(fl)
    ckey  = digest(JSON.generate(child.sort.to_h))
    next if seen_seeds.include?(ckey) || poisoned.include?(ckey)
    state["stack"].push(child)
  end

  save_state(state)
end

state["stop_reason"]        = stop
state["worklist_exhausted"] = state["stack"].empty?
save_state(state)
File.delete(CURRENT_PATH) if File.exist?(CURRENT_PATH)

puts "[isolated] exit stop=#{stop} drained=#{state['worklist_exhausted']} " \
     "runs=#{state['runs']} written=#{state['written']} stack=#{state['stack'].size}"
