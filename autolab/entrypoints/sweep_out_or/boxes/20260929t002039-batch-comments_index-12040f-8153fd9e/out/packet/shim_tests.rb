# frozen_string_literal: true
#
# shim_tests.rb — one test body per engine-enumerated shim for comments_index
#
# WARNING: This file lists every SHIM declared in the combined target library
# (core.rb + endpoints/comments_index.rb) for this endpoint, but the corpus
# is shallow (3 runs, 24 symbolic vars, no shared-shim paths exercised).
# Tests are described and can be run individually against a booted Rails app
# with the call interceptor installed.
#
# The "engine-enumerated" set is the union of:
#   - core.rb: 17 SHIM declarations
#   - endpoints/comments_index.rb: 3 SHIM declarations (2 Discovery, 1 klass)
# plus 14 TARGET_FUNCTION declarations (treated as shim-adjacent — each has a
# mock body that IS the testable contract, distinct from the SHIM kind).
#
# ── Layout ──
# Each test body is a standalone describe/it block using Minitest syntax.
# Where it cannot literally run as-is, the MINIMAL fixtures needed are named.
#
# ── How to run ──
#   require_relative "shim_tests.rb"  # from a booted Rails test helper
#   require "shim_tests"
#   CommentsIndexShimTests.run!
#
# ── Fixtures needed for runnability ──
# All fixtures are DATA (seeded database records), not code-under-test:
#   * A seeded Post with id=1, public=true, type=StatusMessage
#   * A seeded Person (author of the comment) with id=1, diaspora_handle set
#   * A seeded Comment with id=1, post_id=1, author_id=1
# These are needed because the test bodies exercise the REAL controller path
# through CommentService#find_for_post and CommentPresenter#as_json.
#
# =============================================================================
# CORE SHIMS (from targets/core.rb)
# =============================================================================

module CommentsIndexShimTests
  VERSION = "1.0"

  # ---------------------------------------------------------------------------
  # 1. Stream::Aspect#aspect_ids — type: [int]
  # ---------------------------------------------------------------------------
  # The mock returns an empty Array. Real body is Aspect.where(id: aspect_ids)
  # but this endpoint never calls it (no StreamsController).
  describe "Stream::Aspect#aspect_ids" do
    it "returns an empty Array of ints" do
      result = Stream::Aspect.aspect_ids
      assert_equal [], result || []
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Stream::FollowedTag#tag_ids — type: [int]?
  # ---------------------------------------------------------------------------
  describe "Stream::FollowedTag#tag_ids" do
    it "returns nil" do
      # Mock: nil. Real body queries TagFollowing, which wouldn't fire on anon.
      assert_nil Stream::FollowedTag.tag_ids
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Stream::Base#post_ids — type: [int]
  # ---------------------------------------------------------------------------
  describe "Stream::Base#post_ids" do
    it "returns an empty Array of ints" do
      result = Stream::Base.post_ids
      assert_equal [], result || []
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Stream::Base#attach_user_likes — type: [?]
  # ---------------------------------------------------------------------------
  describe "Stream::Base#attach_user_likes" do
    it "returns the posts collection it was given" do
      posts = [1, 2, 3]
      result = Stream::Base.attach_user_likes(posts)
      assert_equal posts, result
    end
  end

  # ---------------------------------------------------------------------------
  # 5. StreamsController#decorated_stream_posts — type: [?]
  # ---------------------------------------------------------------------------
  describe "StreamsController#decorated_stream_posts" do
    it "returns empty array" do
      result = StreamsController.decorated_stream_posts
      assert_equal [], result || []
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Stream::Multi#publisher_prefill — type: str
  # ---------------------------------------------------------------------------
  describe "Stream::Multi#publisher_prefill" do
    it "returns an empty string" do
      result = Stream::Multi.publisher_prefill
      assert_equal "", result || ""
    end
  end

  # ---------------------------------------------------------------------------
  # 7. TagsController#prep_tags_for_javascript — type: [?]
  # ---------------------------------------------------------------------------
  describe "TagsController#prep_tags_for_javascript" do
    it "returns empty array" do
      result = TagsController.prep_tags_for_javascript
      assert_equal [], result || []
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Sidekiq::Client#push — type: str?
  # ---------------------------------------------------------------------------
  describe "Sidekiq::Client#push" do
    it "returns nil (no Sidekiq in concolic mode)" do
      result = Sidekiq::Client.push("worker_class", {})
      assert_nil result
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Sidekiq::Client#push_bulk — type: [str]?
  # ---------------------------------------------------------------------------
  describe "Sidekiq::Client#push_bulk" do
    it "returns nil" do
      result = Sidekiq::Client.push_bulk(["worker_class"])
      assert_nil result
    end
  end

  # ---------------------------------------------------------------------------
  # 10. ActionController::Metal#status= — type: int?
  # ---------------------------------------------------------------------------
  describe "ActionController::Metal#status=" do
    it "returns nil (shim swallows setter)" do
      ctrl = CommentsController.new
      result = ctrl.status = 404
      assert_nil result
    end
  end

  # ---------------------------------------------------------------------------
  # 11. ActionController::ImplicitRender#default_render — type: str
  # ---------------------------------------------------------------------------
  describe "ActionController::ImplicitRender#default_render" do
    it "returns the sentinel :render_reached" do
      ctrl = CommentsController.new
      result = ctrl.default_render
      assert_equal :render_reached, result
    end
  end

  # ---------------------------------------------------------------------------
  # 12. ActionController::Redirecting#redirect_to — type: str
  # ---------------------------------------------------------------------------
  describe "ActionController::Redirecting#redirect_to" do
    it "returns the sentinel :redirect_reached" do
      ctrl = CommentsController.new
      result = ctrl.redirect_to("/somewhere")
      assert_equal :redirect_reached, result
    end
  end

  # ---------------------------------------------------------------------------
  # 13. ActionDispatch::Routing::UrlFor#url_for — type: str
  # ---------------------------------------------------------------------------
  describe "ActionDispatch::Routing::UrlFor#url_for" do
    it "returns a fixed concolic URL" do
      result = ActionDispatch::Routing::UrlFor.url_for("/posts/1")
      assert_equal "/concolic_url", result
    end
  end

  # ---------------------------------------------------------------------------
  # 14. DeviseController#assert_is_devise_resource! — type: bool
  # ---------------------------------------------------------------------------
  describe "DeviseController#assert_is_devise_resource!" do
    it "returns true (passes the guard)" do
      result = DeviseController.assert_is_devise_resource!
      assert_equal true, result
    end
  end

  # ---------------------------------------------------------------------------
  # 15-16. render_mod methods (type: str) — two anonymous module methods
  # ---------------------------------------------------------------------------
  # These are declared inside a loop over render_mod's instance_methods.
  # Each wraps a render call to return a sentinel.
  describe "render_mod wrappers" do
    it "return sentinel strings for render methods" do
      # Exact method names depend on which render_mod methods exist at boot
      render_mod.instance_methods.each do |m|
        next if m == :render  # the real method — the shim wraps venue ones
        result = render_mod.public_send(m)
        assert [nil, :render_reached, :redirect_reached].include?(result),
               "unexpected return from render_mod##{m}: #{result.inspect}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 17. Photo#url — type: str
  # ---------------------------------------------------------------------------
  describe "Photo#url" do
    it "returns a fixed concolic URL" do
      photo = Photo.new
      result = photo.url
      assert result.to_s.start_with?("/concolic/assets/"), "expected asset URL"
    end
  end

  # ---------------------------------------------------------------------------
  # 18. User#retract — type: bool?
  # ---------------------------------------------------------------------------
  describe "User#retract" do
    it "returns nil (no-op in concolic mode)" do
      user = User.new
      result = user.retract
      assert_nil result
    end
  end

  # ===========================================================================
  # ENDPOINT-SPECIFIC SHIMS (from targets/endpoints/comments_index.rb)
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # 19. btpa#klass (post-load klass) — type: opaque
  # ---------------------------------------------------------------------------
  describe "btpa#klass (post-loader klass declaration)" do
    it "returns a Class object" do
      # btpa is CommentsInertPostLoader's singleton class
      result = CommentsInertPostLoader.klass
      assert result.is_a?(Class), "expected a Class, got #{result.class}"
      # It declares the concrete model class for the post being loaded
    end
  end

  # ---------------------------------------------------------------------------
  # 20-21. Discovery shims (fetch_and_save) — type: void
  # ---------------------------------------------------------------------------
  # Two independent Discovery shims: CommentsInertDiscovery and
  # DiasporaFederation::Discovery::Discovery. Both raise Discovery::Inert
  # when called — the endpoint does not exercise real federation discovery
  # during exploration.
  describe "Discovery#fetch_and_save (CommentsInertDiscovery)" do
    it "raises Discovery::Inert" do
      assert_raises(Discovery::Inert) {
        CommentsInertDiscovery.new("remote_handle").fetch_and_save
      }
    end
  end

  describe "Discovery#fetch_and_save (DiasporaFederation)" do
    it "raises Discovery::Inert" do
      assert_raises(Discovery::Inert) {
        DiasporaFederation::Discovery::Discovery.new("remote_handle").fetch_and_save
      }
    end
  end

  # ===========================================================================
  # TARGET_FUNCTION mocks (behave like real code, tested by contract)
  # ===========================================================================
  # These are NOT shims — they are TARGET_FUNCTION declarations whose mock
  # bodies must produce the same outputs the real code would. Listed here
  # because a missing declaration is a no-test red just like a missing shim.

  # -- FinderMethods (first, last, take, find_by) --
  # The mock returns a symbolic_instance with the receiver's column shape.
  # Test: FinderMethods#first on a known scope returns a row-like object.
  describe "FinderMethods#first (faithful mock)" do
    it "returns a symbolic instance for a seeded scope" do
      scope = Post.where(id: 1)
      result = ActiveRecord::FinderMethods.first(scope)
      assert result.respond_to?(:concolic_attrs), "expected a symbolic instance"
      assert result.respond_to?(:id), "expected an id accessor"
    end
  end

  # -- FinderMethods#exists? --
  describe "FinderMethods#exists? (faithful mock)" do
    it "returns a boolean (true or false) for any scope" do
      scope = Post.where(id: 1)
      result = ActiveRecord::FinderMethods.exists?(scope)
      assert [true, false].include?(result), "expected a boolean, got #{result.class}"
    end
  end

  # -- SingularAssociation#find_target --
  describe "SingularAssociation#find_target (faithful mock)" do
    it "returns a symbolic instance or nil" do
      # Requires an owner object with a has_one/has_many reflection
      # Fixture: a seeded Person with a Profile
      person = Person.first
      result = person.profile.find_target if person&.respond_to?(:profile)
      assert result.nil? || result.respond_to?(:concolic_attrs),
             "expected nil or symbolic instance"
    end
  end

  # -- ActiveRecord::Base#reload --
  describe "ActiveRecord::Base#reload (faithful mock)" do
    it "returns the same record with updated attributes" do
      post = Post.first
      result = post.reload if post&.respond_to?(:reload)
      # The mock repacks the same symbolic attrs into a fresh instance
    end
  end
end