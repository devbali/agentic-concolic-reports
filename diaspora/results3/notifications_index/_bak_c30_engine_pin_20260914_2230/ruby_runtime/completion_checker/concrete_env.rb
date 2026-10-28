# CONCRETE CHECKER fixture environment (the RUNBOOK gap-1 harness).
require "tmpdir"
# Establishes a REAL database (sqlite3 via the bundled JDBC adapter — no
# server needed) and loads the app schema, so target functions genuinely
# execute during a concrete run. Fixture ROWS are seeded with raw INSERTs
# through the live connection (fixtures are data, not code-under-test —
# raw seeding deliberately avoids running app callbacks, which are part
# of WRITE paths, not the read endpoint being checked).
#
#   require_relative ".../concrete_env"
#   CompletionChecker::ConcreteEnv.setup!(db: "/tmp/concrete.sqlite3")
#   CompletionChecker::ConcreteEnv.insert("people", id: 1, guid: "g", ...)
module CompletionChecker
  module ConcreteEnv
    def self.setup!(db:, schema: File.expand_path("db/schema.rb", Dir.pwd))
      require "active_record"
      File.delete(db) if db != ":memory:" && File.exist?(db)
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db)
      # schema.rb carries mysql-isms the JDBC sqlite3 adapter passes
      # through verbatim (ENGINE=/CHARSET table options, collation:) —
      # load a transformed copy with them stripped. Purely dialect
      # scaffolding; tables/columns/indexes are untouched.
      src = File.read(schema)
      src = src.gsub(/, options: "[^"]*"/, "")
               .gsub(/, collation: "[^"]*"/, "")
      # sqlite adapter caps index names at 62 chars; shorten with a stable
      # hash suffix (names are dialect scaffolding, not app behavior)
      src = src.gsub(/name: "([^"]{63,})"/) do
        long = Regexp.last_match(1)
        %(name: "#{long[0, 54]}_#{long.sum.to_s(16)}")
      end
      tmp = File.join(File.dirname(db == ":memory:" ? Dir.tmpdir : db),
                      "_concrete_schema.rb")
      File.write(tmp, src)
      verbose = ActiveRecord::Migration.verbose
      ActiveRecord::Migration.verbose = false
      load tmp
      ActiveRecord::Migration.verbose = verbose
      ActiveRecord::Base.connection.tables.size
    end

    # Booleans must be written in the SAME representation the adapter READS.
    # This rig writes fixtures with raw INSERT while the app queries through
    # ActiveRecord, so a hardcoded 1/0 silently mismatched the adapter's
    # quoting and every `WHERE public = 't'` arm returned no rows — the real
    # cause of the long-standing "JDBC boolean artefact", which had left the
    # signed-in public-post branch unexercised on EVERY batch (found by the
    # comments_index adversary, 2026-08-28). Delegate to the adapter.
    def self.quote(v)
      c = ActiveRecord::Base.connection
      case v
      when nil then "NULL"
      when true, false then (v ? c.quoted_true : c.quoted_false)
      when Numeric then v.to_s
      else c.quote(v.to_s)
      end
    end

    def self.insert(table, **cols)
      now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
      c = ActiveRecord::Base.connection
      all = c.columns(table).map(&:name)
      cols = { "created_at" => now, "updated_at" => now }
               .select { |k, _| all.include?(k) }
               .merge(cols.transform_keys(&:to_s))
      sql = "INSERT INTO #{table} (#{cols.keys.join(', ')}) " \
            "VALUES (#{cols.values.map { |v| quote(v) }.join(', ')})"
      c.execute(sql)
      cols["id"]
    end
  end
end
