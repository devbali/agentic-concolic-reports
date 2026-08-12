# frozen_string_literal: true
#
# run_concolic.rb — comments batch runner.
#
# Drives the REAL diaspora controller->service code for each comments
# entrypoint through the concolic interceptor. Path conditions come only
# from real app branches (CommentService / PostService / User querying /
# Person#owns? / finders) on symbolic query results — nothing is hand-built.
#
# Usage (run from app dir via diaspora-concolic):
#   diaspora-concolic results/comments/run_concolic.rb <entrypoint> [round]
#
#   <entrypoint>: comments_create | comments_index | comments_new | comments_destroy
#   [round]:      0 = defaults (no seeds); 1,2,... = apply seeds from
#                 results/comments/seeds.json[entrypoint][round]
#
# Writes: results/comments/{entrypoint}/dump_{label}.json
#
# The launcher script sets RAILS_ENV=concolic and cds into the app; we're
# loaded from the app dir here.

require "./config/environment"

require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/symbolic_func"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

OUT = "/home/dev/project/reports/diaspora/results/comments"
SEEDS_FILE = File.join(OUT, "seeds.json")

$entry = ARGV[0]
$round = Integer(ARGV[1] || 0)

# ---------------------------------------------------------------- helpers

def load_seeds(entry, round)
  return {} unless File.exist?(SEEDS_FILE)
  all = JSON.parse(File.read(SEEDS_FILE))
  (all[entry] || {})[round.to_s] || {}
end

def current_user
  # CommentService is built with `current_user` in the controller. We emulate
  # the authenticated-user lookup through the real AR FinderMethods#first
  # finder mock, which returns a symbolic User instance (klass.allocate).
  #
  # NOTE: we deliberately use `User.first`, NOT `User.find`. Rails 5.2 defines
  # `find` on ActiveRecord::Core::ClassMethods (fast single-id path via
  # cached find_by_sql), which is NOT the FinderMethods#find that
  # concolic_targets.rb declares — so `User.find` slips through to
  # find_by_sql -> SymbolicList#first and crashes. Reported as a framework
  # gap (see REPORT.md). `first` routes through the working finder mock.
  User.first
end

def write_dump(label, dump)
  dir = File.join(OUT, $entry)
  Dir.mkdir(dir) unless File.directory?(dir)
  File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }.size
  err  = dump["error"]
  puts "[#{$entry}:#{label}] events=#{dump['events'].size} PCs=#{pcs}" +
       (err ? " error=#{err['type']}: #{err['message'][0,100]}" : "")
end

# -------------------------------------------------------------- drivers
#
# Each driver replicates the real CommentsController action body calling the
# real app services. The rescue clauses mirror the controller's owns rescue /
# rescue_from behaviour.

def driver_create(post_id:, text:)
  # CommentsController#create (authenticated):
  #   begin
  #     comment = comment_service.create(params[:post_id], params[:text])
  #   rescue ActiveRecord::RecordNotFound      -> render 404
  service  = CommentService.new(current_user)
  begin
    comment = service.create(post_id.value, text.value)
    comment ? "created" : "error_422"
  rescue ActiveRecord::RecordNotFound
    "not_found_404"
  rescue Diaspora::NonPublic
    # CommentsController#rescue_from Diaspora::NonPublic -> authenticate_user!
    "needs_auth"
  end
end

def driver_index(post_id:)
  # CommentsController#index (no auth):
  #   comments = comment_service.find_for_post(params[:post_id])
  #   (controller then renders CommentPresenter.as_collection(comments))
  service = CommentService.new(nil)
  begin
    comments = service.find_for_post(post_id.value)
    # The real next step in the action is presenter materialisation of the
    # collection (contents out of scope -> NotImplementedError, recorded).
    CommentPresenter.as_collection(comments)
    "index_ok"
  rescue ActiveRecord::RecordNotFound
    "not_found"
  rescue Diaspora::NonPublic
    "needs_auth"
  rescue NotImplementedError => e
    "collection_contents_out_of_scope: #{e.class}"
  end
end

def driver_destroy(id:)
  # CommentsController#destroy (authenticated):
  #   if comment_service.destroy(params[:id]) -> success else error
  service = CommentService.new(current_user)
  begin
    ok = service.destroy(id.value)
    ok ? "destroyed" : "destroy_error"
  rescue ActiveRecord::RecordNotFound
    # CommentsController#rescue_from ActiveRecord::RecordNotFound -> head :not_found
    "not_found"
  rescue NotImplementedError => e
    "impl_error: #{e.class}"
  end
end

def driver_new(post_id:, format: nil)
  # CommentsController#new: only renders the mobile layout; no query, so no
  # symbolic call / path condition branches on query results are possible.
  "new_renders_mobile"
end

DRIVERS = {
  "comments_create"  => ->(d) { driver_create(**d) },
  "comments_index"   => ->(d) { driver_index(**d) },
  "comments_destroy" => ->(d) { driver_destroy(**d) },
  "comments_new"     => ->(d) { driver_new(**d) },
}

PARAMS = {
  "comments_create"  => { "post_id" => "5", "text" => "a symbolic comment" },
  "comments_index"   => { "post_id" => "5" },
  "comments_destroy" => { "id" => "42" },
  "comments_new"     => { "post_id" => "5" },
}

# ---------------------------------------------------------------- run

def run_entry(entry, round)
  driver = DRIVERS.fetch(entry)
  params = PARAMS.fetch(entry)
  ConcolicTargets.seed_overrides = load_seeds(entry, round)

  label = "#{entry}_r#{round}"
  dump  = $interceptor.run(driver, params, label: label,
                           script: File.basename(__FILE__))
  write_dump(label, dump)
end

run_entry($entry, $round)