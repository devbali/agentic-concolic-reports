# Exercises the EXACT note-construction clause the repaired boundary now runs,
# with the renderer stubbed to return what render_relation_sql is MEASURED to
# return on this relation in the corpus (and, in the negative arms, to fail).
TARGET = 'SELECT "people".* FROM "people" WHERE "people"."owner_id" = ' \
         '$$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id) LIMIT 1'

def build_note(renderer)
  rendered = begin
               s = renderer.call
               s =~ /\sLIMIT\s/ ? s : "#{s} LIMIT 1"
             rescue Exception # rubocop:disable Lint/RescueException
               nil
             end
  rendered.to_s.start_with?("SELECT") ? rendered : "User#person (has_one)"
end

arms = {
  "renderer OK (corpus-measured output, no LIMIT)" =>
    -> { 'SELECT "people".* FROM "people" WHERE "people"."owner_id" = $$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id)' },
  "renderer OK (already carries LIMIT)" =>
    -> { TARGET },
  "renderer raises NoMethodError (B-4 shape)" =>
    -> { raise NoMethodError, "undefined method `value' for #<Arel::Nod" },
  "renderer raises NotImplementedError (symbolic wall)" =>
    -> { raise NotImplementedError, "SymbolicInt#to_i" },
  "renderer returns '(no arel)' prose" =>
    -> { "ActiveRecord::Relation (no arel)" },
}
arms.each do |label, r|
  n = build_note(r)
  flag = (n == TARGET) ? "== TARGET STATEMENT" :
         (n == "User#person (has_one)" ? "== OLD PROSE (byte-identical fallback)" : "!! UNEXPECTED")
  puts format("%-52s %s\n%-52s   %p", label, flag, "", n)
end
