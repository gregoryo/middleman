require 'set'
require 'middleman-core/contracts'

module Middleman
  module Sitemap
    module Extensions
      class OnDisk < Extension
        attr_accessor :waiting_for_ready

        def initialize(app, config={}, &block)
          super

          @file_paths_on_disk = Set.new

          scoped_self = self
          @waiting_for_ready = true

          @app.ready do
            scoped_self.waiting_for_ready = false
            # Make sure the sitemap is ready for the first request
            sitemap.ensure_resource_list_updated!
          end
        end

        Contract None => Any
        def before_configuration
          app.files.changed(:source, &method(:update_files))
        end

        def ignored?(file)
          @app.config[:ignored_sitemap_matchers].any? do |_, callback|
            callback.call(file, @app)
          end
        end

        # Update or add an on-disk file path
        # @param [String] file
        # @return [void]
        Contract ArrayOf[IsA['Middleman::SourceFile']], ArrayOf[IsA['Middleman::SourceFile']] => Any
        def update_files(updated_files, removed_files)
          return if (updated_files + removed_files).all?(&method(:ignored?))

          # Rebuild the sitemap any time a file is touched
          # in case one of the other manipulators
          # (like asset_hash) cares about the contents of this file,
          # whether or not it belongs in the sitemap (like a partial)
          @app.sitemap.rebuild_resource_list!(:touched_file)

          # Force sitemap rebuild so the next request is ready to go.
          # Skip this during build because the builder will control sitemap refresh.
          @app.sitemap.ensure_resource_list_updated! unless waiting_for_ready || @app.build?
        end

        def files_for_sitemap
          @app.files.by_type(:source).files.reject(&method(:ignored?))
        end

        # Update the main sitemap resource list
        # @return Array<Middleman::Sitemap::Resource>
        Contract ResourceList => ResourceList
        def manipulate_resource_list(resources)
          resources + files_for_sitemap.map do |file|
            ::Middleman::Sitemap::Resource.new(
              @app.sitemap,
              @app.sitemap.file_to_path(file),
              file
            )
          end
        end
      end
    end
  end
end
