# extract_sites.rb -- count and read `declare_target` CALL SITES with Ripper.
#
# WHY NOT grep. This corpus writes `declare_target` across line continuations
# and inside heredoc-sized comment blocks, and it MENTIONS the word in prose.
# A single-line `grep -c declare_target` over the four results4 files returns
# 67/67/22/15; the real site counts are 59/59/10/14. Ripper parses the file,
# so a site is a site and a comment is a comment.
#
# A SITE IS NOT A DECLARATION. `%i[find take! first!].each { |m| declare_target(fm, m, ...) }`
# is ONE site and THREE declarations. For declarations, use declaration_probe.rb.
#
#   ruby extract_sites.rb <file.rb>      -> JSON {file, count, sites:[...]}

# Ripper-based extractor for declare_target call sites.
# Handles line continuations, multi-line lambdas, nested calls.
require "ripper"
require "json"

def walk(node, out, src_lines)
  return unless node.is_a?(Array)
  if node[0] == :method_add_arg || node[0] == :command || node[0] == :command_call || node[0] == :method_add_block
    # find the identifier
  end
  # Generic: look for calls whose method name is declare_target
  name, args, line = nil, nil, nil
  case node[0]
  when :command   # declare_target a, b, kind: x   (no parens)
    id = node[1]
    if id.is_a?(Array) && (id[0] == :@ident || id[0] == :@const)
      name = id[1]; line = id[2][0]; args = node[2]
    end
  when :method_add_arg  # declare_target(...)
    fcall = node[1]; arglist = node[2]
    if fcall.is_a?(Array) && (fcall[0] == :fcall || fcall[0] == :call)
      id = fcall[0] == :fcall ? fcall[1] : fcall[3]
      if id.is_a?(Array) && (id[0] == :@ident)
        name = id[1]; line = id[2][0]; args = arglist
      end
    end
  when :command_call # recv.declare_target a, b
    id = node[3]
    if id.is_a?(Array) && id[0] == :@ident
      name = id[1]; line = id[2][0]; args = node[4]
    end
  end
  if name == "declare_target"
    out << parse_call(args, line, src_lines)
  end
  node.each { |c| walk(c, out, src_lines) }
end

def unparse(node)
  # best-effort textual reconstruction of simple nodes
  return nil unless node.is_a?(Array)
  case node[0]
  when :var_ref, :vcall then unparse(node[1])
  when :@const, :@ident, :@ivar, :@gvar, :@kw then node[1]
  when :@tstring_content then node[1]
  when :@label then node[1].sub(/:\z/, "")
  when :@int then node[1]
  when :symbol_literal then ":" + (unparse(node[1]) || "?")
  when :symbol then unparse(node[1])
  when :dyna_symbol then ":" + (node[1].is_a?(Array) ? node[1].map { |p| unparse(p) }.compact.join : "?")
  when :string_literal
    parts = node[1]
    return nil unless parts.is_a?(Array) && parts[0] == :string_content
    s = parts[1..].map { |p| unparse(p) }
    return nil if s.any?(&:nil?)
    s.join
  when :const_path_ref then [unparse(node[1]), unparse(node[2])].compact.join("::")
  when :top_const_ref then "::" + unparse(node[1]).to_s
  when :call
    r = unparse(node[1]); m = unparse(node[3])
    (r && m) ? "#{r}.#{m}" : nil
  when :method_add_arg
    unparse(node[1])
  when :fcall then unparse(node[1])
  else nil
  end
end

def parse_call(args, line, src_lines)
  pos = []
  pos_literal = []
  kw = {}
  list = nil
  if args.is_a?(Array)
    case args[0]
    when :arg_paren then list = args[1]
    when :args_add_block then list = args
    else list = args
    end
  end
  if list.is_a?(Array) && list[0] == :args_add_block
    positional = list[1] || []
    positional.each do |a|
      if a.is_a?(Array) && a[0] == :bare_assoc_hash
        (a[1] || []).each do |assoc|
          next unless assoc.is_a?(Array) && assoc[0] == :assoc_new
          k = unparse(assoc[1]).to_s.sub(/\A:/, "").sub(/:\z/, "")
          kw[k] = unparse(assoc[2])
          kw[k + "__raw"] = raw_kind(assoc[2])
        end
      else
        pos << unparse(a)
        pos_literal << (a.is_a?(Array) && a[0] == :symbol_literal)
      end
    end
  end
  {
    "line" => line,
    "klass" => pos[0],
    "method" => (pos[1] || "").to_s.sub(/\A:/, ""),
    # FALSE when the method argument is a BLOCK VARIABLE, i.e. the site sits
    # inside `%i[...].each do |m| declare_target(recv, m, ...) end`. Such a
    # site is one site and SEVERAL declarations, and neither the receiver nor
    # the method is resolvable from the call site. Only an install! sees them.
    "method_is_literal" => (pos_literal[1] == true),
    "receiver_is_literal" => (pos[0].to_s =~ /\A(::)?[A-Z]/ ? true : false),
    "kind" => kw["kind"] || kw["kind__raw"],
    "type" => kw["type"],
    "has_returns" => kw.key?("returns") || kw.key?("returns__raw"),
    "raw" => (src_lines[line - 1] || "").strip
  }
end

def raw_kind(node)
  unparse(node)
end

path = ARGV[0]
src = File.read(path)
sexp = Ripper.sexp(src)
abort("PARSE FAILURE: #{path}") if sexp.nil?
lines = src.lines
out = []
walk(sexp, out, lines)
out.sort_by! { |h| h["line"] }
puts JSON.pretty_generate({ "file" => path, "count" => out.size, "sites" => out })
