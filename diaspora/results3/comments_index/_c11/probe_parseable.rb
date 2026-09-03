# M-15 re-derivation, MY OWN evidence (cycle 11). Real gem, no rig.
require File.expand_path("../../../../../../ruby_examples/dse-apps/apps/diaspora/config/environment", __FILE__)
require "diaspora_federation/discovery"
puts "[c11] default_adapter=#{Faraday.default_adapter.inspect}"
handles = ["ghost@example.invalid"]
handles.each do |h|
  begin
    r = DiasporaFederation::Discovery::Discovery.new(h).fetch_and_save
    puts "[c11] #{h.inspect} -> RETURNED #{r.class} (SUCCESS ARM REACHED)"
  rescue Exception => e
    puts "[c11] #{h.inspect} -> #{e.class}: #{e.message.to_s[0, 160]}"
  end
end
puts "[c11] SURVIVED - no JVM abort"
