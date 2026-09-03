# Ground-truth probe (C1 spirit): what SQL does profile.tags.pluck(:name)
# really issue? Renders relation SQL statically — no execution, no mocks.
require "./config/environment"
p = Profile.new
p.id = 1
rel = p.tags
puts "ASSN_TO_SQL: #{rel.to_sql}"
puts "SELECT_NAME_TO_SQL: #{rel.select(:name).to_sql}"
puts "DISTINCT?: #{rel.distinct_value.inspect}"
puts "ORDER: #{rel.order_values.map(&:to_s).inspect rescue rel.order_values.inspect}"
refl = Profile.reflect_on_association(:tags)
puts "REFL: #{refl.class} macro=#{refl.macro} through=#{(refl.through_reflection && refl.through_reflection.name).inspect}"
begin
  # what pluck actually renders: relation.pluck builds select(*cols) on a
  # spawned relation and calls to_sql via select_all — emulate:
  r2 = rel.select(*[:name])
  puts "PLUCK_EMULATED: #{r2.to_sql}"
rescue => e
  puts "PLUCK_EMULATED_ERR: #{e.class}: #{e.message}"
end
