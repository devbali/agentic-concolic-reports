# A04 — RE-VERIFY near-miss N1 (array post_id) and attack the `post_key`
# length dispatch at its boundary: 15 vs 16 char keys, an array whose to_s is
# SHORT (-> :id -> `posts.id IN (?, ?)`) and one whose to_s is LONG
# (-> :guid -> `posts.guid IN (?, ?)`), plus a Hash-shaped param.
require_relative "_common2"
adv_setup!("A04_param_shapes")
seed_people!

CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("posts", id: 101, author_id: 2, guid: "shortguid123456", type: "StatusMessage",
          text: "public, 15-char guid", public: true, comments_count: 1)
CE.insert("posts", id: 102, author_id: 2, guid: "guid16chars00000", type: "StatusMessage",
          text: "public, exactly-16-char guid", public: true, comments_count: 1)
CE.insert("comments", id: 320, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid320", text: "c100")
CE.insert("comments", id: 321, commentable_id: 101, commentable_type: "Post",
          author_id: 2, guid: "cguid321", text: "c101")
CE.insert("comments", id: 322, commentable_id: 102, commentable_type: "Post",
          author_id: 2, guid: "cguid322", text: "c102")

CONCRETE_SCENARIOS = adv_scenario("A04-param-shapes") do
  # Is an ARRAY post_id reachable through the REAL router at all?  Rails merges
  # request params then QUERY params then PATH params, so the path segment wins.
  # Real ActionDispatch code, no mocks — just an observation.
  begin
    env = Rack::MockRequest.env_for("/posts/100/comments?post_id[]=1&post_id[]=2", method: "GET")
    req = ActionDispatch::Request.new(env)
    rec = Rails.application.routes.recognize_path("/posts/100/comments", method: :get)
    req.path_parameters = rec
    warn "[adv2] ROUTER recognize_path=#{rec.inspect}"
    warn "[adv2] ROUTER query_parameters=#{req.query_parameters.inspect}"
    warn "[adv2] ROUTER parameters[:post_id]=#{req.parameters['post_id'].inspect} (#{req.parameters['post_id'].class})"
  rescue StandardError => e
    warn "[adv2] ROUTER probe EXC #{e.class}: #{e.message[0, 200]}"
  end
  # scalar controls
  adv_request(post_id: "100", format: :json, tag: "A04_id")
  adv_request(post_id: "guid16chars00000", format: :json, tag: "A04_guid16")
  adv_request(post_id: "shortguid123456", format: :json, tag: "A04_guid15_falls_to_id_key")
  # ARRAY param, SHORT to_s  ->  post_key == :id  ->  posts.id IN (?, ?)
  adv_request(post_id: %w[100 101], format: :json, tag: "A04_array_short")
  # ARRAY param, LONG to_s   ->  post_key == :guid ->  posts.guid IN (?, ?)
  adv_request(post_id: %w[guid16chars00000 postguid1000000001], format: :json, tag: "A04_array_long")
  # Hash-shaped param
  adv_request(post_id: { "a" => "b" }, format: :json, tag: "A04_hash")
  # controls: missing / empty
  adv_request(post_id: "999999", format: :json, tag: "A04_missing")
  adv_request(post_id: "", format: :json, tag: "A04_empty")
end
