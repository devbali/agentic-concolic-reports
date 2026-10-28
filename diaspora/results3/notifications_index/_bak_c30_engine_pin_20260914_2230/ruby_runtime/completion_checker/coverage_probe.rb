# C2 capture (CHECKS.md Part IV): line coverage of a real-mode run.
# JRuby requires the --debug flag for Coverage to see lines.
#
#   CompletionChecker::CoverageProbe.capture_to("real_cov.json", filter: %r{app/}) { ... }
#
# Output: { "path" => [executed line numbers (1-based)] } — only files
# matching `filter`. Diff two of these (real-mode vs corpus union) to find
# blind spots: lines real execution reaches that the corpus never did.
require "json"
require "coverage"

module CompletionChecker
  module CoverageProbe
    def self.capture(filter: nil)
      Coverage.start
      yield
      raw = Coverage.result
      out = {}
      raw.each do |path, lines|
        next if filter && path !~ filter
        executed = []
        lines.each_with_index { |count, i| executed << (i + 1) if count && count > 0 }
        out[path] = executed unless executed.empty?
      end
      out
    end

    def self.capture_to(path, filter: nil, &block)
      result = capture(filter: filter, &block)
      File.write(path, JSON.pretty_generate(result))
      result
    end

    # Diff two saved coverage JSONs: lines in `real` never present in
    # `corpus` — the C2 blind-spot list.
    def self.blind_spots(real_json_path, corpus_json_path)
      real = JSON.parse(File.read(real_json_path))
      corpus = JSON.parse(File.read(corpus_json_path))
      gaps = {}
      real.each do |path, lines|
        seen = corpus[path] || []
        missing = lines - seen
        gaps[path] = missing unless missing.empty?
      end
      gaps
    end
  end
end
