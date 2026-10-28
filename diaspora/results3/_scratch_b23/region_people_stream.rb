  def person
    return super unless respond_to?(:concolic_attrs)
    rel = Person.where(owner_id: self[:id])
    @__ps_via_user_noted ||= (rel.take; true)
    @__ps_via_user_note ||= begin
      rendered = begin
                   # Rule T4 (concolic_targets.rb `finder_note`): a SINGULAR
                   # association read is a LIMIT 1 read, and the LIMIT is
                   # APPENDED there rather than rendered by Arel. Build the
                   # note the same way so it is byte-identical to the note the
                   # ordinary query boundary already writes for this relation.
                   s = ConcolicTargets.render_relation_sql(rel)
                   s =~ /\sLIMIT\s/ ? s : "#{s} LIMIT 1"
                 rescue Exception # rubocop:disable Lint/RescueException
                   # As in ConcolicTargets.sql_for: note rendering must NEVER
                   # crash the mock, and a symbolic wall raises
                   # NotImplementedError < ScriptError, which `rescue
                   # StandardError` would let escape. B-4's live failure
                   # (NoMethodError in the Arel renderer) is caught here too.
                   nil
                 end
      rendered.to_s.start_with?("SELECT") ? rendered : "User#person (has_one)"
    end
    ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_via_user", @__ps_via_user_note)
  end
