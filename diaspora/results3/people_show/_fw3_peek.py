#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick check: for every dump .json, classify which SYM_* families appeared
# in run metadata. Intended for timing report cross-check, not final report.

require "json"
require "set"

DUMP_DIR = File.join(__dir__, "dumps")
submit_hist = Hash.new(0)

rules = {
  mobile_rows: /SYM_mobile_username|mobile_stream/,
  contact_bare: /SYM_relation_1_is_contact_\d|SYM_relation_2_is_contact_\d|SYM_contact/,
  block_bare: /SYM_relation_1_blocked_\d|SYM_relation_2_blocked_\d|SYM_block/,
  presenter_bare: /(?:^|punctuation)SYM_relation_1_(?:username|diaspora_id)/
}

def peek_entries(path, rules, n=6)
  first = File.open(path, "rb") { |f| f.read(4096) }
  return nil unless first.start_with?("dse01||") || first.start_with?("b64||")
  raw = first.split("||", 3)[2].to_s
  data = begin
    require "base64"
    require "json"
    raw = raw.strip
    j = if raw.start_with?("{") then raw else Base64.strict_decode64(raw) end
    JSON.parse(j)
  rescue => e
    return {err: e.message[0,120]}
  end
  data
end

files = Dir.glob("/home/dev/project/reports/diaspora/results3/people_show/dumps/*.json")
puts "files=#{files.size}"
sum = Hash.new(0)
data = nil
files.each do |f|
  begin
    d = JSON.parse(File.read(f))
    (d["events"] || []).each do |ev|
      kind = ev["kind"] || ev["event"] || "?"
      sum[kind] += 1
    end
  rescue => e
    sum["PARSE_ERR"] += 1
  end
end
sum.each { |k, v| puts "  %-24s %d" % [k, v] }
