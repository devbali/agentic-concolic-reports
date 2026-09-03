# Agent-provided shim test bodies for notifications_index — keys ENUMERATED
# BY THE ENGINE (shim_extractor output); a key missing here is a NO-TEST red,
# EXCEPT for the runtime rep machinery (kind `rep_plumbing` / `value_class`),
# which the runner itself resolves to the PROTOCOL verdict: those are the
# symbolic runtime's OWN rep accessors, not mocks over application code.
#
# RULE S (2026-08-27): waivers are abolished. Every shim below RUNS. Where a
# shim could not run as-is, the minimal mocks it needs are named and justified
# in its entry: fixture ROWS in a real sqlite DB (data, not code-under-test),
# a constructed receiver, or a provisioned config value. No app logic is
# stubbed anywhere in this file.
#
# Two shim classes cannot satisfy "zero targets" by construction and say so in
# their entry (flagged for the coordinator): a DELEGATING WRAPPER whose body's
# `super` IS a declared target (`Relation#pluck`, `CollectionAssociation#size`,
# `OrmAdapter#get`). For those the zero-target set excludes exactly the targets
# the body itself calls, and nothing else.

# NOTE on keys: the asset-path and Gon shim modules were hoisted to NAMED
# constants (targets.rb `AssetPathShim` / `GonPreloadsShim`) so a test can
# install and exercise them without calling `install!` (which declares
# targets). The extractor then sees `X.prepend(<constant>)` and names the key
# `<owner>.DYNAMIC` — hence the DYNAMIC keys below; the bodies they test are
# exactly the ones `install!` prepends.

# --- MINIMAL FIXTURE DB (Rule S: "make it runnable with the minimal mocks the
#     test needs"). Real sqlite + the app schema through the project's own
#     concrete_env helper, then ROWS via the app's own AR.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(
  db: "/home/dev/project/reports/diaspora/results3/notifications_index/shim_tests.sqlite3")
CompletionChecker::ConcreteEnv.insert("users", id: 9, username: "shimtester",
  email: "shim@example.org", encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
  language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CompletionChecker::ConcreteEnv.insert("people", id: 1, guid: "shimguid",
  diaspora_handle: "shim@localhost", serialized_public_key: "K", owner_id: 9,
  closed_account: 0, fetch_status: 0)
CompletionChecker::ConcreteEnv.insert("profiles", id: 11, person_id: 1,
  first_name: "Shim", last_name: "Tester", searchable: 1, nsfw: 0, public_details: 0)
CompletionChecker::ConcreteEnv.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
CompletionChecker::ConcreteEnv.insert("aspects", id: 951, user_id: 9, name: "Work", order_id: 2)
SHIM_DB_USER = User.find(9)

# the symbolic runtime (rep constructor) and the batch's own shim modules.
# `install!` is NEVER called here: no target is declared in this process.
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/results3/notifications_index/concolic_targets.rb"
require "/home/dev/project/reports/diaspora/results3/notifications_index/targets.rb"

# The session-user rep the devise_user_first target builds, decorated by the
# batch's OWN named method (targets.rb `decorate_session_user!`, hoisted out of
# the target's return lambda in cycle 2 so a test can reach those bodies).
SHIM_SESSION_USER = ConcolicTargets.symbolic_instance(User, "SHIMTEST_session_user", "shim test")
NotifDeviseUserNaming.decorate_session_user!(SHIM_SESSION_USER)

# Throwaway receivers carrying the batch's OWN named shim modules (also hoisted
# out of `install!`). Prepending them here is exactly what `install!` does —
# the module body under test is byte-identical.
# The runtime's concrete-string wrapper is created inside
# `ConcolicTargets.install!` (which a shim test may never call, since it
# declares targets). Create the same class here — runtime plumbing, byte
# identical to the one the batch installs.
unless defined?(ConcreteSymbolicString)
  ::Object.const_set(:ConcreteSymbolicString, Class.new(::String) do
    include SymbolicVar
    attr_reader :note
    def self.build(v, name: nil, note: nil)
      s = new(v.to_s)
      s.instance_variable_set(:@sym_name, name)
      s.instance_variable_set(:@note, note)
      s
    end
  end)
end

SHIM_ASSET_HOST = Object.new
SHIM_GON_HOST   = Object.new
SHIM_ASSET_HOST.singleton_class.prepend(NotificationsIndexTargets::AssetPathShim)
# B-2's escape-segment shim is installed on the REAL owner (exactly what
# `install!` does) so its own body runs: its `super` is the real percent
# encoder, which is not a target.
ActionDispatch::Journey::Router::Utils.singleton_class.prepend(EscapeSegmentShim)
SHIM_GON_HOST.singleton_class.prepend(NotificationsIndexTargets::GonPreloadsShim)

AR_TARGETS = [
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :last],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :sum],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Relation, :to_ary],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
]

SHIM_TESTS = {
  # --- RULE S: the shared kwargs re-pack prepend (`ConcolicKwargsToPositional`,
  #     prepended at FILE scope to both `ActiveRecord::Base.singleton_class` and
  #     `ActiveRecord::Relation`, so it is installed in this process too). Its
  #     body stashes the finder conditions in a thread-local — the interceptor's
  #     param binding drops them — re-packs kwargs positionally and calls
  #     `super`. Run for real against fixture rows, both arms (kwargs form and
  #     positional-hash form) plus the `ensure` restore.
  #     TARGET SET (delegating wrapper, flagged): `super` IS the finder target.
  "ActiveRecord::Base.singleton_class.DYNAMIC" => {
    targets: AR_TARGETS - [[ActiveRecord::FinderMethods, :find_by],
                           [ActiveRecord::FinderMethods, :exists?],
                           [ActiveRecord::Relation, :records],
                           [ActiveRecord::Relation, :to_a]],
    coverage_of: [ConcolicKwargsToPositional, :find_by, :instance],
    fixture: -> {
      Thread.current[:concolic_finder_conds] = nil
      got = User.find_by(id: SHIM_DB_USER.id)                 # kwargs arm
      raise "find_by(kwargs): #{got.inspect}" unless got && got.id == SHIM_DB_USER.id
      got2 = User.find_by({username: "shimtester"})           # positional-hash arm
      raise "find_by(hash): #{got2.inspect}" unless got2 && got2.id == SHIM_DB_USER.id
      User.find_by(id: -1)                                    # no-row arm
      raise "thread-local not restored" unless Thread.current[:concolic_finder_conds].nil?
    } },

  # --- RULE S / runner `real_class:` (2026-08-28): the symbolic rep's own
  #     COLUMN READERS. Each states the class the representative stands for;
  #     the runner verifies against the REAL class that the method is a column
  #     (the AR attribute protocol), so this is a checkable fact, not prose.
  #     `type` / `mentions_container_type` / `commentable_type` additionally
  #     carry this batch's documented type DECISIONS (targets.rb §5f) and
  #     `guid` a render-safe ConcreteSymbolicString — all three are columns of
  #     the class named here.
  "obj.type"                    => { real_class: "Notification" },
  "obj.mentions_container_type" => { real_class: "Mention" },
  "obj.commentable_type"        => { real_class: "Comment" },
  "obj.guid"                    => { real_class: "Post" },
  "obj.language"                => { real_class: "User" },
  "obj.image_url"               => { real_class: "Profile" },
  "obj.hidden_shareables"       => { real_class: "User" },
  # base Post does NOT define post_location (only StatusMessage/Reshare do),
  # and this reader is defined ONLY on base-Post reps — the real class does
  # not define it at all, which is the rep's own machinery.
  "obj.post_location"           => { real_class: "Post" },

  # --- REAL app-code shim: Person.name_from_attrs replaces the removed
  #     Person#name TARGET mock. Pure string logic, zero targets, one
  #     conditional — both arms probed.
  "Person.singleton_class.name_from_attrs" => {
    targets: AR_TARGETS,
    coverage_of: [Person, :name_from_attrs, :singleton],
    fixture: -> {
      Person.name_from_attrs("Alice", " A ", "alice@localhost")   # non-blank branch
      Person.name_from_attrs("", "", "alice@localhost")           # blank -> handle branch
    } },

  # --- asset-path provisioning prepend (one body, prepended to BOTH the
  #     helper proxy and ActionView::Base). Static "/assets/<src>", no `super`,
  #     so nothing of sprockets runs and no target can be reached.
  "helper_proxy.singleton_class.DYNAMIC" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_ASSET_HOST, :compute_asset_path, :singleton],
    fixture: -> {
      got = SHIM_ASSET_HOST.compute_asset_path("application.js")
      raise "compute_asset_path: #{got.inspect}" unless got == "/assets/application.js"
      SHIM_ASSET_HOST.compute_asset_path("x.css", {})
    } },
  "ActionView::Base.DYNAMIC" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_ASSET_HOST, :compute_asset_path, :singleton],
    fixture: -> {
      got = SHIM_ASSET_HOST.compute_asset_path("application.css")
      raise "compute_asset_path: #{got.inspect}" unless got == "/assets/application.css"
    } },

  # --- class-level Gon.preloads memo, both arms (fresh -> {}, memo hit).
  "::Gon.singleton_class.DYNAMIC" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_GON_HOST, :preloads, :singleton],
    fixture: -> {
      SHIM_GON_HOST.instance_variable_set(:@concolic_preloads, nil)
      first = SHIM_GON_HOST.preloads
      raise "preloads: #{first.inspect}" unless first == {}
      first[:contacts] = [1]
      raise "memo lost" unless SHIM_GON_HOST.preloads[:contacts] == [1]
    } },

  # --- the three session-user singletons (real bodies in targets.rb's
  #     `decorate_session_user!`). Zero targets: two boolean literals and one
  #     that only BUILDS a relation (no materialization, no statement).
  "u.persisted?" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SESSION_USER, :persisted?, :singleton],
    fixture: -> { raise "persisted? false" unless SHIM_SESSION_USER.persisted? == true } },
  "u.new_record?" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SESSION_USER, :new_record?, :singleton],
    fixture: -> { raise "new_record? true" unless SHIM_SESSION_USER.new_record? == false } },
  "u.unread_notifications" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SESSION_USER, :unread_notifications, :singleton],
    fixture: -> {
      rel = SHIM_SESSION_USER.unread_notifications
      raise "not a relation: #{rel.class}" unless rel.is_a?(ActiveRecord::Relation)
      raise "wrong model: #{rel.klass}" unless rel.klass == Notification
      # never render SQL here: the rep's id is a SymbolicInt and Arel would
      # call #to_i on it (a ScriptError the runner cannot catch). Read the
      # predicate COLUMNS off the where clause instead.
      cols = rel.where_clause.send(:predicates).map { |pr|
        (pr.respond_to?(:left) && pr.left.respond_to?(:name)) ? pr.left.name.to_s : nil
      }.compact
      raise "scope lost recipient_id: #{cols.inspect}" unless cols.include?("recipient_id")
      raise "scope lost unread: #{cols.inspect}" unless cols.include?("unread")
    } },

  # --- Devise's authenticatable_salt on a REAL user row: the real body is the
  #     `encrypted_password[0,29]` slice; zero targets.
  "User.authenticatable_salt" => {
    targets: AR_TARGETS,
    coverage_of: [User, :authenticatable_salt, :instance],
    fixture: -> {
      got  = SHIM_DB_USER.authenticatable_salt
      want = SHIM_DB_USER.encrypted_password[0, 29]
      raise "salt: #{got.inspect} != #{want.inspect}" unless got == want
    } },

  # --- DELEGATING WRAPPER (flagged for the coordinator): the shim's own arms
  #     delegate — `count_records` IS `Calculations#count`, and reaching the
  #     `loaded?` arm needs the association loaded (`CollectionProxy#load_target`
  #     -> `Relation#records`/`#to_a`). A zero-target run of this body does not
  #     exist; the excluded targets are exactly the ones it calls itself.
  "ActiveRecord::Associations::CollectionAssociation.size" => {
    targets: AR_TARGETS - [[ActiveRecord::Calculations, :count],
                           [ActiveRecord::Associations::CollectionProxy, :load_target],
                           [ActiveRecord::Relation, :records],
                           [ActiveRecord::Relation, :to_a]],
    coverage_of: [ActiveRecord::Associations::CollectionAssociation, :size, :instance],
    fixture: -> {
      assoc = SHIM_DB_USER.association(:aspects)
      assoc.reset
      assoc.size                                  # unloaded, empty target
      assoc.load_target
      assoc.size                                  # loaded? arm
      User.new.association(:aspects).size         # find_target? false arm
      a2 = SHIM_DB_USER.association(:aspects)
      a2.reset
      a2.target = [Aspect.new(name: "unsaved")]   # non-empty in-memory target
      a2.size
      # the `group_values` and `distinct_value` arms: the app defines no
      # grouped or DISTINCT has_many, so the only way to reach them is to give
      # a real association object a scope that carries them. MOCK: the scope
      # object only (a relation built by AR itself) — no app logic replaced.
      a3 = SHIM_DB_USER.association(:aspects)
      a3.reset
      a3.define_singleton_method(:association_scope) { Aspect.where(user_id: 9).group(:user_id) }
      a3.size                                     # group_values arm
      a4 = SHIM_DB_USER.association(:aspects)
      a4.reset
      a4.define_singleton_method(:association_scope) { Aspect.where(user_id: 9).distinct }
      a4.size                                     # distinct arm
    } },

  # --- DELEGATING WRAPPER (flagged): body is "stash the projection; super",
  #     and `super` IS `Calculations#pluck` — the target it exists to feed.
  "ActiveRecord::Relation.pluck" => {
    # `Relation#records`/`#to_a` are excluded too: the LOADED arm of the real
    # body is `records.pluck(...)`, i.e. it calls that target itself.
    targets: AR_TARGETS - [[ActiveRecord::Calculations, :pluck],
                           [ActiveRecord::Relation, :records],
                           [ActiveRecord::Relation, :to_a]],
    coverage_of: [ActiveRecord::Relation, :pluck, :instance],
    fixture: -> {
      Aspect.where(user_id: SHIM_DB_USER.id).pluck(:id, :name)   # unloaded arm
      Aspect.where(user_id: -1).pluck(:id)                        # empty result
      Aspect.where(user_id: SHIM_DB_USER.id).load.pluck(:name)    # loaded arm
      Aspect.includes(:user).where(users: {id: SHIM_DB_USER.id})
            .references(:users).pluck("users.username")           # has_include? arm
      Thread.current[:ni_pluck_cols] = nil
    } },

  # --- DELEGATING WRAPPER (flagged): `OrmAdapterGetNaming#get` is byte-faithful
  #     to orm_adapter-0.5.0's `#get` with ONE change — the `.first` is the
  #     `devise_user_first` ALIAS, so the session lookup mints its own note.
  #     The finder IS the call it exists to make (and resolves through
  #     `Relation#records`/`#to_a`).
  "OrmAdapter::ActiveRecord.DYNAMIC" => {
    targets: AR_TARGETS - [[ActiveRecord::FinderMethods, :first],
                           [ActiveRecord::Relation, :records],
                           [ActiveRecord::Relation, :to_a]],
    coverage_of: [OrmAdapter::ActiveRecord, :get, :instance],
    fixture: -> {
      got = User.to_adapter.get(SHIM_DB_USER.id)
      raise "orm_adapter get returned #{got.inspect}" unless got && got.id == SHIM_DB_USER.id
    } },

  # --- BOUNDARY HARVEST B-2: the escape-segment leaf is a SHIM now (it was a
  #     target minting a junk note on every route generation). The REAL body
  #     runs (`super` is `Journey::Router::Utils.escape_segment`, pure percent
  #     encoding — not a target), so this is a zero-target test at full
  #     coverage of the shim body: both arms (a plain String and a symbolic
  #     value carrying `#value`).
  "ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment" => {
    targets: AR_TARGETS,
    coverage_of: [EscapeSegmentShim, :escape_segment, :instance],
    fixture: -> {
      got = ActionDispatch::Journey::Router::Utils.escape_segment("a b/c")
      raise "escape: #{got.inspect}" unless got.to_s.include?("%20")
      sym = SymbolicString.new("x y", name: "SHIMTEST_seg")
      got2 = ActionDispatch::Journey::Router::Utils.escape_segment(sym)
      raise "escape sym: #{got2.inspect}" unless got2.to_s.include?("%20")
    } },

}
