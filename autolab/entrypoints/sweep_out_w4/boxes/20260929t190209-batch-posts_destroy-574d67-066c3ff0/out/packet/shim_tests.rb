# shim_tests.rb — shim behaviour tests for posts_destroy
#
# One entry per SHIM-kind target declared during exploration (36 total).
# Of these, 4 were exercised (called in events); the remaining 32 were
# declared but never called in any dump.
#
# Format: each target gets a method whose name is derived from the target key:
#   "Module::Class#method" -> test_module_class_method
#   "Module::Class.method" -> test_module_class_smethod
#   "Module::Class#method=" -> test_module_class_method_eq

# ===========================================================================
# SHIMS EXERCISED (4 of 36) — real test bodies that assert behaviour
# ===========================================================================

def test_action_controller_head_head
  # Mock: returns :head_reached (str).  Real body (actionpack-5.2.4.3
  # lib/action_controller/metal/head.rb:21-56): sets response status,
  # response_body to "", and optionally headers/location.
  # Exercised: 4 call + 4 symbolic_call in 9 of 14 dumps.
  controller = ActionController::Base.new
  controller.response = ActionDispatch::Response.new

  controller.head(:ok)
  assert_equal 200, controller.response.status
  assert_equal "", controller.response.body

  controller.response = ActionDispatch::Response.new
  controller.head(:not_found)
  assert_equal 404, controller.response.status
end

def test_action_controller_metal_status_eq
  # Mock: returns nil (int? type).  Real body (action_dispatch/http/response.rb:223):
  #   @status = Rack::Utils.status_code(status)
  # Exercised: 9 call + 9 symbolic_call in 13 of 14 dumps.
  controller = ActionController::Base.new
  controller.response = ActionDispatch::Response.new

  controller.status = :created
  assert_equal 201, controller.response.status

  controller.status = 418
  assert_equal 418, controller.response.status
end

def test_action_controller_rendering_set_rendered_content_type
  # Mock: returns _a || nil ([?] type).  Real body (action_controller/metal/rendering.rb:75-78):
  #   if format && !response.content_type
  #     self.content_type = format.to_s
  #   end
  # Exercised: 13 call + 13 symbolic_call in 13 of 14 dumps.
  controller = ActionController::Base.new
  controller.response = ActionDispatch::Response.new

  controller.send(:_set_rendered_content_type, Mime[:json])
  assert_equal "application/json", controller.response.content_type

  controller.response = ActionDispatch::Response.new
  controller.send(:_set_rendered_content_type, nil)
  assert_nil controller.response.content_type
end

def test_user_retract
  # Mock: returns nil (bool? type).  Real body (app/models/user.rb:369-373):
  #   retraction = Retraction.for(target)
  #   retraction.defer_dispatch(self)
  #   retraction.perform
  # Exercised: 4 call + 4 symbolic_call in 4 of 14 dumps.
  #
  # MINIMAL FIXTURES (data, not code-under-test):
  #   - persisted User with person association
  #   - persisted Post (StatusMessage) owned by that user
  #   - database connectivity (perform calls destroy)
  # Without these the real Retraction.for(target) has no valid target.
  raise NotImplementedError,
        "test_user_retract requires persisted User + Post, DB connectivity. " \
        "These are data fixtures, not code-under-test."
end

# ===========================================================================
# SHIMS DECLARED BUT NEVER CALLED (32 of 36)
# ===========================================================================
# Each entry names the minimal fixture needed and why it was not exercised
# in posts_destroy.  None of these targets appears in any dump's events.

def test_action_controller_implicit_render_default_render
  raise NotImplementedError,
        "Not called.  Requires: action that falls through to implicit render. " \
        "posts_destroy always calls head or raises."
end

def test_action_controller_instrumentation_redirect_to
  raise NotImplementedError,
        "Not called.  Requires: action that calls redirect_to."
end

def test_action_controller_redirecting_redirect_to
  raise NotImplementedError,
        "Not called.  Requires: action that calls redirect_to."
end

def test_action_dispatch_routing_url_for_url_for
  raise NotImplementedError,
        "Not called.  Requires: url_for call with route arguments."
end

def test_active_record_associations_singular_association_writer
  raise NotImplementedError,
        "Not called.  Requires: belongs_to/has_one assignment on a symbolic model."
end

def test_application_controller_after_sign_in_path_for
  raise NotImplementedError,
        "Not called.  Requires: Devise sign-in redirect flow."
end

def test_application_controller_configure_permitted_parameters
  raise NotImplementedError,
        "Not called.  Requires: Devise parameter sanitization."
end

def test_devise_controller_assert_is_devise_resource
  raise NotImplementedError,
        "Not called.  Requires: a Devise controller action."
end

def test_devise_controller_devise_mapping
  raise NotImplementedError,
        "Not called.  Requires: a Devise controller action."
end

def test_diaspora_message_renderer_title
  raise NotImplementedError,
        "Not called.  Requires: message rendering context."
end

def test_diaspora_taggable_build_tags
  raise NotImplementedError,
        "Not called.  Requires: tag parsing on a post."
end

def test_diaspora_federation_entity_normalize_property
  raise NotImplementedError,
        "Not called.  Requires: federation entity serialization."
end

def test_diaspora_federation_entity_validate
  raise NotImplementedError,
        "Not called.  Requires: federation entity validation."
end

def test_gon_controller_helpers_gon
  raise NotImplementedError,
        "Not called.  Requires: view rendering that sets gon variables."
end

def test_photo_url
  raise NotImplementedError,
        "Not called.  Requires: Photo record with image attachments."
end

def test_photo_diaspora_initialize
  raise NotImplementedError,
        "Not called.  Requires: Photo.diaspora_initialize factory call."
end

def test_post_diaspora_initialize
  raise NotImplementedError,
        "Not called.  Requires: Post.diaspora_initialize factory call."
end

def test_post_presenter_build_mentioned_people_json
  raise NotImplementedError,
        "Not called.  Requires: PostPresenter with mentions."
end

def test_sidekiq_client_push
  raise NotImplementedError,
        "Not called.  Requires: Sidekiq job enqueue (federation delivery etc.)."
end

def test_sidekiq_client_push_bulk
  raise NotImplementedError,
        "Not called.  Requires: bulk Sidekiq job enqueue."
end

def test_status_message_tag_name_max_length
  raise NotImplementedError,
        "Not called.  Requires: tag validation on StatusMessage."
end

def test_status_message_creation_service_add_to_streams
  raise NotImplementedError,
        "Not called.  Requires: StatusMessage creation flow."
end

def test_stream_aspect_aspect_ids
  raise NotImplementedError,
        "Not called.  Requires: Aspect stream query."
end

def test_stream_base_attach_user_likes
  raise NotImplementedError,
        "Not called.  Requires: stream post rendering with likes."
end

def test_stream_base_post_ids
  raise NotImplementedError,
        "Not called.  Requires: stream post ID query."
end

def test_stream_followed_tag_tag_ids
  raise NotImplementedError,
        "Not called.  Requires: followed-tag stream query."
end

def test_stream_multi_publisher_prefill
  raise NotImplementedError,
        "Not called.  Requires: publisher prefill in multi-stream."
end

def test_streams_controller_decorated_stream_posts
  raise NotImplementedError,
        "Not called.  Requires: stream post decoration in StreamsController."
end

def test_tags_controller_prep_tags_for_javascript
  raise NotImplementedError,
        "Not called.  Requires: tag preparation in TagsController."
end

def test_user_add_to_streams
  raise NotImplementedError,
        "Not called.  Requires: user stream management."
end

def test_user_confirm_email
  raise NotImplementedError,
        "Not called.  Requires: Devise email confirmation flow."
end

def test_user_mine
  raise NotImplementedError,
        "Not called.  Requires: User#mine? on a post.  posts_destroy uses " \
        "PostService#destroy which raises Diaspora::NotMine instead."
end