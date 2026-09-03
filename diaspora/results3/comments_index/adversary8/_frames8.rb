# ROUND 8 — ENTRYPOINT EVIDENCE (DISCIPLINE 15 addendum / CONCRETE_CHECKER step 4).
# A win must prove the novel statement was issued INSIDE the declared entrypoint
# (the post-auth action frame), not by authentication / middleware / a filter.
# This is HARNESS-side observation only: an ActiveSupport::Notifications
# subscriber that records `caller` at the moment each statement is issued.
# Nothing in the app, in src/ or in the batch is touched.
ADV_FRAMES = []
$adv_tag = nil
APP_RE = %r{apps/diaspora/(app|lib)/|action_controller|actionpack|abstract_controller|warden|devise}
ActiveSupport::Notifications.subscribe("sql.active_record") do |*a|
  ev = ActiveSupport::Notifications::Event.new(*a)
  nm = ev.payload[:name].to_s
  next if nm =~ /SCHEMA|TRANSACTION/
  fr = caller.grep(APP_RE).map { |f| f.sub(%r{\A.*/apps/diaspora/}, "app:").sub(%r{\A.*/gems/}, "gem:") }
  ADV_FRAMES << {"tag" => $adv_tag, "name" => nm,
                 "sql" => ev.payload[:sql].to_s.gsub(/\s+/, " ").strip[0, 240],
                 "cached" => !!ev.payload[:cached],
                 "frames" => fr[0, 14]}
end

def req!(**kw)
  $adv_tag = kw[:tag]
  r = adv_request(**kw)
  $adv_tag = nil
  r
end

def dump_frames!(name)
  File.write(File.join(ADV_DIR, "runs", "_frames_#{name}.json"), JSON.pretty_generate(ADV_FRAMES))
  warn "[adv8] frames written: #{ADV_FRAMES.size} statements -> _frames_#{name}.json"
end
