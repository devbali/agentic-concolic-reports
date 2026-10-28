#!/usr/bin/env python3
"""apply_fix12_asset_helpers.py — the rig cannot resolve an asset this
CHECKOUT deliberately does not contain, and the render aborts on it.

MEASURED.  Three endpoints stop with

    ActionView::Template::Error: couldn't find file 'underscore' with type
    'application/javascript'

(`home_show`, `home_podmin`, `streams_public`).  The chain, read rather than
guessed:

  app/views/layouts/application.html.haml:11   = javascript_include_tag :main
  app/assets/javascripts/main.js:7             //= require underscore
  -> Sprockets cannot resolve `underscore`

and it cannot resolve it because the application's OWN Gemfile says so, in
its header:

    # Minimal Gemfile for concolic analysis — strips dead diaspora-foundation
    # gem source and frontend-only assets. Keeps only backend gems needed to
    # load controllers/models/services and drive ActiveRecord queries.

There is no `config/storage.yml`-style misconfiguration to correct and no
precompiled `public/assets` to point at: the assets were removed on purpose,
because this checkout exists to drive ActiveRecord queries.

WHY THIS MATTERS MORE AFTER THE OTHER REPAIRS.  `javascript_include_tag` is in
the SHARED LAYOUT, so it is on the path of every HTML-rendering endpoint.  Only
three endpoints reached it so far because the rest stopped earlier; once the
principal resolves and relations materialise, many more will render, and every
one of them will abort at the layout's first asset tag — before any query the
template would have issued.

THE FIX IS IN THE RIG, NOT IN THE APP.  The asset pipeline issues no SQL and
decides nothing symbolic.  Returning an empty tag restores the behaviour of a
deployment that HAS its assets — which is the deployment this analysis is
about — instead of modelling one that has no JavaScript at all.  Nothing under
`app/` is touched.

MEASURED SECOND DOOR.  `manifest_show` does not render a template at all --
`app/controllers/manifest_controller.rb:11` is
`render json: {... src: helpers.image_path("branding/logos/app-icon.png") ...}`
-- and it stops with a BARE `Sprockets::FileNotFound`, same asset, same two
app frames (`app/assets/config/manifest.js:4`,
`app/assets/javascripts/main.js:7`).  Resolving ANY asset compiles the
manifest, so the `*_path` family is stubbed too.

DELIBERATELY NARROW: the tag helpers and the path helpers, both measured to
stop an endpoint.  If another asset helper raises, it will appear as its own
stopping site with its own frame, and that is the right way to find out.
"""
from __future__ import annotations
import shutil, sys

DRIVER = "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb"

OLD = '''    ActiveRecord::Base.establish_connection(:concolic)
    ActionController::Base.allow_forgery_protection = false
    $interceptor = CallInterceptor.instance'''

NEW = '''    ActiveRecord::Base.establish_connection(:concolic)
    ActionController::Base.allow_forgery_protection = false
    install_asset_helper_stubs!
    $interceptor = CallInterceptor.instance'''

OLD2 = '''  def install_module!(name)'''

NEW2 = '''  # e2e FIX-12 (2026-09-26). This CHECKOUT has no frontend assets, by its own
  # Gemfile header: "Minimal Gemfile for concolic analysis -- strips dead
  # diaspora-foundation gem source and frontend-only assets. Keeps only
  # backend gems needed to load controllers/models/services and drive
  # ActiveRecord queries."
  #
  # `app/views/layouts/application.html.haml:11` is
  # `= javascript_include_tag :main`, and `app/assets/javascripts/main.js:7`
  # is `//= require underscore`, which Sprockets cannot resolve. MEASURED:
  # `home_show`, `home_podmin` and `streams_public` all stop with
  # `ActionView::Template::Error: couldn't find file 'underscore' with type
  # 'application/javascript'`. The tag is in the SHARED LAYOUT, so it is on
  # the path of every HTML-rendering endpoint and aborts the render BEFORE
  # any query the template would have issued.
  #
  # The asset pipeline issues no SQL and decides nothing symbolic. An empty
  # tag restores the behaviour of a deployment that has its assets -- the
  # deployment this analysis is about -- rather than modelling one with no
  # JavaScript. IN THE RIG ONLY: nothing under app/ is touched.
  #
  # NARROW ON PURPOSE: only the two helpers measured to abort a render. Any
  # other asset helper that raises will show up as its own stopping site with
  # its own backtrace frame, which is how it should be found.
  def install_asset_helper_stubs!
    return unless defined?(::ActionView::Base)
    return if ::ActionView::Base.instance_variable_get(:@autolab_asset_stubs)
    stubs = Module.new do
      def javascript_include_tag(*_sources, **_opts)
        "".html_safe
      end

      def stylesheet_link_tag(*_sources, **_opts)
        "".html_safe
      end

      # `*_path` reaches Sprockets by a different door. MEASURED:
      # `manifest_show` is `render json: {... src: helpers.image_path(
      # "branding/logos/app-icon.png") ...}` (app/controllers/
      # manifest_controller.rb:11) and stops with a BARE
      # `Sprockets::FileNotFound` -- no `ActionView::Template::Error` wrapper,
      # because no template is involved. Resolving ANY asset compiles
      # `app/assets/config/manifest.js`, which pulls in `main.js`, which is
      # `//= require underscore`.
      #
      # A PLAUSIBLE PATH rather than "": this value is rendered INTO the JSON
      # body, and an empty `src` would be a different document from the one a
      # real pod serves. The digest is not modelled, and nothing downstream
      # reads it.
      def asset_path(source, *_args, **_opts)
        s = source.to_s
        s.start_with?("/", "http") ? s : "/assets/#{s}"
      end

      %i[image_path javascript_path stylesheet_path font_path
         audio_path video_path].each do |m|
        define_method(m) { |source, *a, **o| asset_path(source, *a, **o) }
      end
    end
    ::ActionView::Base.prepend(stubs)
    ::ActionView::Base.instance_variable_set(:@autolab_asset_stubs, true)
    warn "[autolab] rig: javascript_include_tag / stylesheet_link_tag stubbed " \\
         "(this checkout strips frontend assets -- see install_asset_helper_stubs!)"
  rescue StandardError => e
    warn "[autolab] rig: could not stub asset helpers: #{e.class}: #{e.message}"
  end

  def install_module!(name)'''


def main():
    apply = "--apply" in sys.argv
    s = open(DRIVER).read()
    for old in (OLD, OLD2):
        n = s.count(old)
        if n != 1:
            print(f"!! anchor x{n}: {old[:50]!r}")
            return 1
    s = s.replace(OLD, NEW).replace(OLD2, NEW2)
    if apply:
        shutil.copy(DRIVER, DRIVER + ".bak_e2e_fix12")
        open(DRIVER, "w").write(s)
        print(f"patched {DRIVER}")
    else:
        print("both anchors unique; would patch the driver")
    return 0


if __name__ == "__main__":
    sys.exit(main())
