module TentValidator
  class RequestProxyValidator < TentValidator::Spec
    require 'tent-validator/validators/support/post_generators'
    include Support::PostGenerators

    context "" do
      setup do
        set(:user, TentD::Model::User.generate)
      end

      # Update meta post to contain a profile
      expect_response(:status => 200, :schema => :data) do
        expect_schema(:post, '/post')
        expect_schema(:post_meta, '/post/content')

        user = get(:user)
        meta_post = TentD::Utils::Hash.stringify_keys(user.meta_post.as_json)
        data = TentD::Utils::Hash.deep_dup(meta_post)

        data['version'] = {
          'parents' => [
            { 'version' => meta_post['version']['id'], 'post' => meta_post['id'] }
          ]
        }

        data['content']['profile'] = {
          'name' => Faker::Lorem.paragraphs(2).join(' ').slice(0, 256),
          'bio' => Faker::Lorem.paragraphs(2).join(' ').slice(0, 256),
          'website' => "https://#{Faker::Internet.domain_word}.example.com/#{Faker::Internet.domain_word}",
          'location' => Faker::Address.city
        }

        expected_data = TentD::Utils::Hash.deep_dup(data)
        expected_data['version']['parents'][0]['post'] = property_absent
        expected_data['permissions'] = property_absent
        expected_data.delete('published_at')

        avatar_attachment = {
          :content_type => "image/png",
          :category => 'avatar',
          :name => 'fictitious.png',
          :data => "Fake image data"
        }
        attachments = [avatar_attachment]

        set(:avatar_attachment, avatar_attachment)

        avatar_digest = hex_digest(avatar_attachment[:data])

        expected_data['attachments'] = attachments.map { |a|
          a = a.dup
          a.merge!(:digest => hex_digest(a[:data]), :size => a[:data].size)
          a.delete(:data)
          a
        }

        expect_properties(
          :post => expected_data
        )

        res = clients(:app_auth, :server => :local, :user => user).post.update(meta_post['entity'], meta_post['id'], data, {}, :attachments => attachments)

        user.reload

        res
      end

      expect_response(:status => 200, :schema => :data) do
        data = generate_status_post

        res = clients(:app_auth, :server => :local, :user => get(:user)).post.create(data)

        data.delete(:permissions)
        expect_properties(:post => data)

        res
      end.after do |response, results|
        if !results.any? { |r| !r[:valid] }
          post = TentD::Utils::Hash.symbolize_keys(response.body['post'])
          post.delete(:received_at)
          post[:version].delete(:received_at)
          set(:local_uncached_post, post)
        else
          raise SetupFailure.new("Failed to create post on local server", response, results)
        end
      end

      expect_response(:status => 200, :schema => :data) do
        data = generate_status_post

        res = clients(:app_auth, :server => :local, :user => get(:user)).post.create(data)

        data.delete(:permissions)
        expect_properties(:post => data)

        res
      end.after do |response, results|
        if !results.any? { |r| !r[:valid] }
          post = TentD::Utils::Hash.symbolize_keys(response.body['post'])
          post.delete(:received_at)
          post[:version].delete(:received_at)
          set(:local_cached_post, post)
        else
          raise SetupFailure.new("Failed to create post on local server", response, results)
        end
      end

      expect_response(:status => 200, :schema => :data) do
        post = get(:local_cached_post)
        clients(:app_auth).post.update(post[:entity], post[:id], post, {}, :import => true)
      end.after do |response, results|
        if results.any? { |r| !r[:valid] }
          raise SetupFailure.new("Failed to deliver post notification on remote server", response, results)
        end
      end

      describe "GET post when foreign entity" do
        shared_example :get_post_via_proxy do
          expect_response(:status => 200, :schema => :data) do
            post, user = get(:post), get(:user)
            cache_control = get(:cache_control)

            expect_properties(:post => post)

            watch_local_requests(true, user.id)

            res = catch_faraday_exceptions("Proxied request failed") do
              get(:client).post.get(post[:entity], post[:id]) do |request|
                if cache_control
                  request.headers['Cache-Control'] = cache_control
                end
              end
            end

            watch_local_requests(true, user.id)

            # Expect discovery (no relationship exists)
            expect_request(
              :method => :head,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/"
            )
            expect_request(
              :method => :get,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/posts/#{URI.encode_www_form_component(user.entity)}/#{user.meta_post.public_id}",
              :headers => {
                "Accept" => Regexp.new("\\A" + Regexp.escape(TentD::API::POST_CONTENT_MIME))
              }
            ).expect_response(:status => 200, :schema => :data) do
              expect_properties(:post => user.meta_post.as_json)
            end

            # Expect post to be fetched
            expect_request(
              :method => :get,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/posts/#{URI.encode_www_form_component(user.entity)}/#{post[:id]}",
              :headers => {
                "Accept" => Regexp.new("\\A" + Regexp.escape(TentD::API::POST_CONTENT_MIME))
              }
            ).expect_response(:status => 200, :schema => :data) do
              expect_properties(:post => post)
            end

            res
          end
        end

        shared_example :get_post_without_proxy do
          expect_response(:status => 200, :schema => :data) do
            post, user = get(:post), get(:user)
            cache_control = get(:cache_control)

            expect_properties(:post => post)

            catch_faraday_exceptions("Proxied request failed") do
              get(:client).post.get(post[:entity], post[:id]) do |request|
                request.headers['Cache-Control'] = cache_control
              end
            end
          end
        end

        shared_example :get_post_not_found do
          expect_response(:status => 404, :schema => :error) do
            post = get(:post)
            catch_faraday_exceptions("Request failed") do
              get(:client).post.get(post[:entity], post[:id])
            end
          end
        end

        context "when post not cached" do
          setup do
            set(:post, get(:local_uncached_post))
          end

          context "when app authorized" do
            setup do
              set(:client, clients(:app_auth))
            end

            context "when `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:get_post_via_proxy)
            end

            context "when `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:get_post_via_proxy)
            end

            context "when `Cache-Control: only-if-cached` (default)" do
              expect_response(:status => 404, :schema => :error) do
                post = get(:post)
                catch_faraday_exceptions("Request failed") do
                  get(:client).post.get(post[:entity], post[:id]) do |request|
                    request.headers['Cache-Control'] = 'only-if-cached'
                  end
                end
              end

              expect_response(:status => 404, :schema => :error) do
                post = get(:post)
                catch_faraday_exceptions("Request failed") do
                  get(:client).post.get(post[:entity], post[:id])
                end
              end
            end
          end

          context "when authorization is not an app" do
            setup do
              set(:client, clients(:app))
            end

            expect_response(:status => 404, :schema => :error) do
              post = get(:post)
              catch_faraday_exceptions("Request failed") do
                get(:client).post.get(post[:entity], post[:id])
              end
            end

            context "when `Cache-Control: no-cache`" do
              expect_response(:status => 404, :schema => :error) do
                post = get(:post)
                catch_faraday_exceptions("Request failed") do
                  get(:client).post.get(post[:entity], post[:id]) do |request|
                    request.headers['Cache-Control'] = 'only-if-cached'
                  end
                end
              end
            end
          end

          context "without authentication" do
            setup do
              set(:client, clients(:no_auth))
            end

            expect_response(:status => 404, :schema => :error) do
              post = get(:post)
              catch_faraday_exceptions("Request failed") do
                get(:client).post.get(post[:entity], post[:id])
              end
            end

            context "when `Cache-Control: no-cache`" do
              expect_response(:status => 404, :schema => :error) do
                post = get(:post)
                catch_faraday_exceptions("Request failed") do
                  get(:client).post.get(post[:entity], post[:id]) do |request|
                    request.headers['Cache-Control'] = 'only-if-cached'
                  end
                end
              end
            end
          end
        end

        context "when post cached" do
          setup do
            set(:post, get(:local_cached_post))
          end

          context "when app authorized" do
            setup do
              set(:client, clients(:app_auth))
            end

            context "when `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:get_post_via_proxy)
            end

            context "when `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:get_post_without_proxy)
            end

            context "when `Cache-Control: only-if-cached` (default)" do
              setup do
                set(:cache_control, 'only-if-cached')
              end

              behaves_as(:get_post_without_proxy)
            end
          end

          context "when authorization is not an app" do
            setup do
              set(:client, clients(:app))
            end

            behaves_as(:get_post_not_found)
          end

          context "when not authenticated" do
            setup do
              set(:client, clients(:no_auth))
            end

            behaves_as(:get_post_not_found)
          end
        end
      end

      describe "GET posts_feed refs" do
        # fetch feed with proxied reffed post
        shared_example :fetch_via_proxy do
          expect_response(:status => 200, :schema => :data) do
            reffed_post = get(:reffed_post)
            user = get(:user)
            post = get(:post)
            cache_control = get(:cache_control)

            unless get(:is_app)
              post = TentD::Utils::Hash.deep_dup(post)
              post[:received_at] = property_absent
              post[:version][:received_at] = property_absent
            end

            expect_properties(:posts => [post])
            expect_properties(:refs => [reffed_post])

            watch_local_requests(true, user.id)

            res = get(:client).post.list(:limit => 1, :max_refs => 1) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end

            watch_local_requests(false, user.id)

            # Expect discovery (no relationship exists)
            expect_request(
              :method => :head,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/"
            )
            expect_request(
              :method => :get,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/posts/#{URI.encode_www_form_component(user.entity)}/#{user.meta_post.public_id}",
              :headers => {
                "Accept" => Regexp.new("\\A" + Regexp.escape(TentD::API::POST_CONTENT_MIME))
              }
            ).expect_response(:status => 200, :schema => :data) do
              expect_properties(:post => user.meta_post.as_json)
            end

            # Expect post to be fetched
            expect_request(
              :method => :get,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/posts/#{URI.encode_www_form_component(user.entity)}/#{reffed_post[:id]}",
              :headers => {
                "Accept" => Regexp.new("\\A" + Regexp.escape(TentD::API::POST_CONTENT_MIME))
              }
            ).expect_response(:status => 200, :schema => :data) do
              expect_properties(:post => reffed_post)
            end

            res
          end
        end

        # fetch feed with cached reffed post
        shared_example :fetch_without_proxy do
          expect_response(:status => 200, :schema => :data) do
            reffed_post = get(:reffed_post)
            post = get(:post)
            cache_control = get(:cache_control)

            unless get(:is_app)
              post = TentD::Utils::Hash.deep_dup(post)
              post[:received_at] = property_absent
              post[:version][:received_at] = property_absent
            end

            reffed_post = TentD::Utils::Hash.deep_dup(reffed_post)
            reffed_post.delete(:received_at)
            reffed_post[:version].delete(:received_at)

            expect_properties(:posts => [post])
            expect_properties(:refs => [reffed_post])

            get(:client).post.list(:limit => 1, :max_refs => 1) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end
          end
        end

        # fetch feed without proxying reffed post
        shared_example :fetch_no_refs do
          expect_response(:status => 200, :schema => :data) do
            reffed_post = get(:reffed_post)
            post = get(:post)
            cache_control = get(:cache_control)

            unless get(:is_app)
              post = TentD::Utils::Hash.deep_dup(post)
              post[:received_at] = property_absent
              post[:version][:received_at] = property_absent
            end

            expect_properties(:posts => [post])
            expect_properties(:refs => [])

            get(:client).post.list(:limit => 1, :max_refs => 1) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end
          end
        end

        context "when not cached" do
          setup do
            set(:reffed_post, get(:local_uncached_post))
          end

          expect_response(:status => 200, :schema => :data) do
            reffed_post = get(:reffed_post)

            data = generate_status_post

            data[:refs] = [{ :entity => reffed_post[:entity], :post => reffed_post[:id], :type => reffed_post[:type] }]

            res = clients(:app_auth).post.create(data)

            data.delete(:permissions)
            expect_properties(:post => data)

            res
          end.after do |response, results|
            if !results.any? { |r| !r[:valid] }
              set(:post, TentD::Utils::Hash.symbolize_keys(response.body['post']))
            else
              raise SetupFailure.new("Failed to create post on remote server", response, results)
            end
          end

          context "when authenticated" do
            context "when app authorized" do
              setup do
                set(:client, clients(:app_auth))
                set(:is_app, true)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: only-if-cached` (default)" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_refs)
              end
            end

            context "when authorization is not an app" do
              setup do
                set(:client, clients(:app))
                set(:is_app, false)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_no_refs)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_no_refs)
              end

              context "with `Cache-Control: only-if-cached` (default)" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_refs)
              end
            end
          end

          context "when not authenticated" do
            setup do
              set(:client, clients(:no_auth))
              set(:is_app, false)
            end

            context "with `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:fetch_no_refs)
            end

            context "with `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:fetch_no_refs)
            end

            context "with `Cache-Control: only-if-cached` (default)" do
              setup do
                set(:cache_control, 'only-if-cached')
              end

              behaves_as(:fetch_no_refs)
            end
          end
        end

        context "when cached" do
          setup do
            set(:reffed_post, get(:local_cached_post))
          end

          expect_response(:status => 200, :schema => :data) do
            reffed_post = get(:reffed_post)

            data = generate_status_post

            data[:refs] = [{ :entity => reffed_post[:entity], :post => reffed_post[:id], :type => reffed_post[:type] }]

            res = clients(:app_auth).post.create(data)

            data.delete(:permissions)
            expect_properties(:post => data)

            res
          end.after do |response, results|
            if !results.any? { |r| !r[:valid] }
              set(:post, TentD::Utils::Hash.symbolize_keys(response.body['post']))
            else
              raise SetupFailure.new("Failed to create post on remote server", response, results)
            end
          end

          context "when authenticated" do
            context "when app authorized" do
              setup do
                set(:client, clients(:app_auth))
                set(:is_app, true)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_without_proxy)
              end

              context "with `Cache-Control: only-if-cached` (default)" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_without_proxy)
              end
            end

            context "when authorization is not an app" do
              setup do
                set(:client, clients(:app))
                set(:is_app, false)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_no_refs)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_no_refs)
              end

              context "with `Cache-Control: only-if-cached` (default)" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_refs)
              end
            end
          end

          context "when not authenticated" do
            setup do
              set(:client, clients(:no_auth))
              set(:is_app, false)
            end

            context "with `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:fetch_no_refs)
            end

            context "with `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:fetch_no_refs)
            end

            context "with `Cache-Control: only-if-cached` (default)" do
              setup do
                set(:cache_control, 'only-if-cached')
              end

              behaves_as(:fetch_no_refs)
            end
          end
        end
      end

      describe "GET posts_feed profiles" do
        setup do
          set(:post, get(:local_cached_post))
        end

        shared_example :fetch_via_proxy do
          expect_response(:status => 200, :schema => :data) do
            user = get(:user)
            post = get(:post)
            cache_control = get(:cache_control)

            unless get(:is_app)
              post = TentD::Utils::Hash.deep_dup(post)
              post[:received_at] = property_absent
              post[:version][:received_at] = property_absent
            end

            expect_properties(:posts => [post])
            expect_properties(:profiles => { user.entity => TentD::API::MetaProfile.profile_as_json(user.meta_post) })

            watch_local_requests(true, user.id)

            res = get(:client).post.list(:limit => 1, :profiles => :entity, :entities => user.entity) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end

            watch_local_requests(false, user.id)

            # Expect discovery (no relationship exists)
            expect_request(
              :method => :head,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/"
            )
            expect_request(
              :method => :get,
              :url => %r{\A#{Regexp.escape(user.entity)}},
              :path => "/posts/#{URI.encode_www_form_component(user.entity)}/#{user.meta_post.public_id}",
              :headers => {
                "Accept" => Regexp.new("\\A" + Regexp.escape(TentD::API::POST_CONTENT_MIME))
              }
            ).expect_response(:status => 200, :schema => :data) do
              expect_properties(:post => user.meta_post.as_json)
            end

            res
          end
        end

        shared_example :fetch_without_proxy do
          expect_response(:status => 200, :schema => :data) do
            user = get(:user)
            post = get(:post)
            cache_control = get(:cache_control)

            unless get(:is_app)
              post = TentD::Utils::Hash.deep_dup(post)
              post[:received_at] = property_absent
              post[:version][:received_at] = property_absent
            end

            expect_properties(:posts => [post])
            expect_properties(:profiles => { user.entity => TentD::API::MetaProfile.profile_as_json(user.meta_post) })

            get(:client).post.list(:limit => 1, :profiles => :entity, :entities => user.entity) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end
          end
        end

        shared_example :fetch_no_profiles do
          expect_response(:status => 200, :schema => :data) do
            user = get(:user)
            post = get(:post)
            cache_control = get(:cache_control)

            if get(:is_app)
              expect_properties(:posts => [post])
            else
              expect_properties(:posts => [])
            end

            expect_properties(:profiles => {})

            get(:client).post.list(:limit => 1, :profiles => :entity, :entities => user.entity) do |request|
              if cache_control
                request.headers['Cache-Control'] = cache_control
              end
            end
          end
        end

        context "when not cached" do
          context "with authentication" do
            context "when app authorized" do
              setup do
                set(:client, clients(:app_auth))
                set(:is_app, true)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: only-if-cached`" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_profiles)
              end
            end

            context "when authorization is not an app" do
              setup do
                set(:client, clients(:app))
                set(:is_app, false)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_no_profiles)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_no_profiles)
              end

              context "with `Cache-Control: only-if-cached`" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_profiles)
              end
            end
          end

          context "without authentication" do
            setup do
              set(:client, clients(:no_auth))
              set(:is_app, false)
            end

            context "with `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:fetch_no_profiles)
            end

            context "with `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:fetch_no_profiles)
            end

            context "with `Cache-Control: only-if-cached`" do
              setup do
                set(:cache_control, 'only-if-cached')
              end

              behaves_as(:fetch_no_profiles)
            end
          end
        end

        context "when cached" do

          expect_response(:status => 200, :schema => :data) do
            post = get(:user).meta_post.as_json

            # ensure it's not at the top of feed
            post[:received_at] = 0
            post[:version][:received_at] = 0

            attachments = [get(:avatar_attachment)]

            clients(:app_auth).post.update(post[:entity], post[:id], post, {}, :import => true, :attachments => attachments)
          end.after do |response, results|
            if results.any? { |r| !r[:valid] }
              raise SetupFailure.new("Failed to deliver post notification on remote server", response, results)
            end
          end

          context "with authentication" do
            context "when app authorized" do
              setup do
                set(:client, clients(:app_auth))
                set(:is_app, true)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_via_proxy)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_without_proxy)
              end

              context "with `Cache-Control: only-if-cached`" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_without_proxy)
              end
            end

            context "when authorization is not an app" do
              setup do
                set(:client, clients(:app))
                set(:is_app, false)
              end

              context "with `Cache-Control: no-cache`" do
                setup do
                  set(:cache_control, 'no-cache')
                end

                behaves_as(:fetch_no_profiles)
              end

              context "with `Cache-Control: proxy-if-miss`" do
                setup do
                  set(:cache_control, 'proxy-if-miss')
                end

                behaves_as(:fetch_no_profiles)
              end

              context "with `Cache-Control: only-if-cached`" do
                setup do
                  set(:cache_control, 'only-if-cached')
                end

                behaves_as(:fetch_no_profiles)
              end
            end
          end

          context "without authentication" do
            setup do
              set(:client, clients(:no_auth))
              set(:is_app, false)
            end

            context "with `Cache-Control: no-cache`" do
              setup do
                set(:cache_control, 'no-cache')
              end

              behaves_as(:fetch_no_profiles)
            end

            context "with `Cache-Control: proxy-if-miss`" do
              setup do
                set(:cache_control, 'proxy-if-miss')
              end

              behaves_as(:fetch_no_profiles)
            end

            context "with `Cache-Control: only-if-cached`" do
              setup do
                set(:cache_control, 'only-if-cached')
              end

              behaves_as(:fetch_no_profiles)
            end
          end
        end
      end
    end

  end

  TentValidator.validators << RequestProxyValidator
end
