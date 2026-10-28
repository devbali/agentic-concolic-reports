# people_stream — declared walls (2026-09-09, first corpus)

## W1. `format.all` arm terminates in ActionController::UnknownFormat (6 dumps)

`PeopleController#stream`:

    def stream
      respond_to do |format|
        format.all  { redirect_to person_path(@person) }   # <-- this arm
        format.json { render json: person_stream.stream_posts.map {...} }
      end
    end

`redirect_to` is a DECLARED TARGET (shared boundary, intercepted as
`ActionController::Instrumentation.redirect_to`), so it returns a marker
instead of setting a redirect response. The action then completes with no
response and Rails raises

    ActionController::UnknownFormat: PeopleController#stream is missing a
    template for this request format and variant. request.formats: ["text/html"]

All 6 occurrences are in the `anon_all` scenario. This is a MOCK WALL, not
application behaviour: a real request would redirect (302) and issue no
further SQL.

**Policy impact: none.** A redirect issues no query. Every statement the arm
does issue (the `@person` lookup in the before_action) is recorded BEFORE the
terminal and is in the corpus. The arm adds no statement that the corpus
lacks.

**Why it is declared rather than repaired:** descending `redirect_to` would
change the SHARED boundary for every endpoint (Rule T), to model an arm that
provably contributes no statement. Not worth a project-wide regeneration.

**What a consumer must NOT conclude:** the absence of a redirect-arm terminal
in this corpus is a declared wall, not evidence that the arm reads nothing.
