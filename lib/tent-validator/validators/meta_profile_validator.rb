require 'faker'

module TentValidator

  class MetaProfileValidator < TentValidator::Spec

    require 'tent-validator/validators/support/post_generators'
    include Support::PostGenerators

    describe "Meta profile" do
      ##
      # Update meta post to contain a profile
      expect_response(:status => 200, :schema => :data) do
        expect_schema(:post, '/post')
        expect_schema(:post_meta, '/post/content')

        meta_post = TentValidator.remote_server_meta
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

        set(:meta_profile_data, expected_data)

        expected_data = TentD::Utils::Hash.deep_dup(expected_data['content']['profile'])
        expected_data['avatar_digest'] = avatar_digest
        set(:meta_profile, expected_data)

        res = clients(:app_auth).post.update(meta_post['entity'], meta_post['id'], data, {}, :attachments => attachments)

        if res.status == 200
          TentValidator.remote_server_meta = res.body['post']
        end

        res
      end

      expect_response(:status => 200, :schema => :data) do
        expect_schema(:post, '/post')
        expect_schema(:post_meta, '/post/content')

        expect_properties(:post => get(:meta_profile_data))

        TentClient::Discovery.discover(clients(:no_auth), TentValidator.remote_entity_uri, :return_response => true) || Faraday::Response.new({})
      end

      context "GET post" do
        ##
        # Create a post with mentions and refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          data = generate_status_post

          data[:mentions] = [
            { :entity => TentValidator.remote_entity_uri }
          ]

          meta_post = TentValidator.remote_server_meta
          data[:refs] = [
            { :entity => meta_post['content']['entity'], :post => meta_post['id'] }
          ]

          expected_data = TentD::Utils::Hash.deep_dup(data)
          expected_data[:permissions] = property_absent
          expected_data[:mentions][0].delete(:entity)
          expected_data[:refs][0].delete(:entity)

          expect_properties(:post => expected_data)

          clients(:app_auth).post.create(data)
        end.after do |response, results, validator|
          if results.any? { |r| !r[:valid] }
            raise SetupFailure.new("Failed to create post", response, results, validator)
          else
            set(:post, response.body['post'])
          end
        end

        ##
        # Expect profile to be returned via profiles=entity
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'entity')
        end

        ##
        # Expect profile to be returned via profiles=mentions
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'mentions')
        end

        ##
        # Expect profile to be returned via profiles=refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'refs')
        end

        ##
        # Expect no profile to be returned via profile=permissions
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'permissions')
        end

        ##
        # Expect profile to be returned via profile=parents
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'parents')
        end

        ##
        # Create version of post without mentions or refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          parent_post = get(:post)
          set(:parent_post, parent_post)

          data = generate_status_post
          data[:version] = {
            :parents => [
              { :version => parent_post['version']['id'], :post => parent_post['id'] }
            ]
          }

          expected_data = TentD::Utils::Hash.deep_dup(data)
          expected_data[:permissions] = property_absent
          expected_data[:version][:parents][0].delete(:post)

          expect_properties(:post => expected_data)

          clients(:app_auth).post.update(parent_post['entity'], parent_post['id'], data)
        end.after do |response, results, validator|
          if results.any? { |r| !r[:valid] }
            raise SetupFailure.new("Failed to create version of post", response, results, validator)
          else
            set(:post, response.body['post'])
          end
        end

        ##
        # Expect profile to be returned via profile=parents
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'parents')
        end

        ##
        # Expect no profile to be returned via profile=mentions
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'mentions')
        end

        ##
        # Expect no profile to be returned via profile=refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.get(post['entity'], post['id'], :profiles => 'refs')
        end

        context "with children accept header" do
          ##
          # Expect profile to be returned via profiles=entity
          expect_response(:status => 200, :schema => :data) do
            parent_post = get(:parent_post)

            meta_profile = get(:meta_profile)
            expect_properties(:profiles => {
              parent_post['entity'] => meta_profile
            })

            expect_property_length('/versions', 1)

            clients(:app_auth).post.children(parent_post['entity'], parent_post['id'], :version => parent_post['version']['id'], :profiles => 'entity')
          end
        end

        context "with mentions accept header" do
          ##
          # Create post mentioning other post
          expect_response(:status => 200, :schema => :data) do
            expect_schema(:post, '/post')
            expect_schema(:post_status, '/post/content')

            post = get(:post)

            data = generate_status_post

            data[:mentions] = [
              { :entity => post['entity'], :post => post['id'] }
            ]

            expected_data = TentD::Utils::Hash.deep_dup(data)
            expected_data[:permissions] = property_absent
            expected_data[:mentions][0].delete(:entity)

            expect_properties(:post => expected_data)

            res = clients(:app_auth).post.create(data)

            if res.status == 200
              set(:mention_post, res.body['post'])
            else
              set(:mention_post, {})
            end

            res
          end

          ##
          # Expect profile to be returned via profiles=entity
          expect_response(:status => 200, :schema => :data) do
            post = get(:post)

            meta_profile = get(:meta_profile)
            expect_properties(:profiles => {
              post['entity'] => meta_profile
            })

            expect_property_length('/mentions', 1)

            clients(:app_auth).post.mentions(post['entity'], post['id'], :profiles => 'entity')
          end
        end

        context "with versions accept header" do
          expect_response(:status => 200, :schema => :data) do
            post = get(:post)

            meta_profile = get(:meta_profile)
            expect_properties(:profiles => {
              post['entity'] => meta_profile
            })

            expect_property_length('/versions', 2)

            clients(:app_auth).post.versions(post['entity'], post['id'], :profiles => 'entity')
          end
        end
      end

      context "GET posts_feed" do
        ##
        # Create a post with mentions and refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          data = generate_status_post

          data[:mentions] = [
            { :entity => TentValidator.remote_entity_uri }
          ]

          meta_post = TentValidator.remote_server_meta
          data[:refs] = [
            { :entity => meta_post['content']['entity'], :post => meta_post['id'] }
          ]

          expected_data = TentD::Utils::Hash.deep_dup(data)
          expected_data[:permissions] = property_absent
          expected_data[:mentions][0].delete(:entity)
          expected_data[:refs][0].delete(:entity)

          expect_properties(:post => expected_data)

          clients(:app_auth).post.create(data)
        end.after do |response, results, validator|
          if results.any? { |r| !r[:valid] }
            raise SetupFailure.new("Failed to create post", response, results, validator)
          else
            set(:post, response.body['post'])
          end
        end

        ##
        # Expect profile to be returned via profiles=entity
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.list(:profiles => 'entity', :limit => 1)
        end

        ##
        # Expect profile to be returned via profiles=mentions
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.list(:profiles => 'mentions', :limit => 1)
        end

        ##
        # Expect profile to be returned via profiles=refs
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.list(:profiles => 'refs', :limit => 1)
        end

        ##
        # Expect profile not to be returned via profiles=parents
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.list(:profiles => 'parents', :limit => 1)
        end

        ##
        # Create version of post without mentions or refs
        expect_response(:status => 200, :schema => :data) do
          expect_schema(:post, '/post')
          expect_schema(:post_status, '/post/content')

          parent_post = get(:post)
          set(:parent_post, parent_post)

          data = generate_status_post
          data[:version] = {
            :parents => [
              { :version => parent_post['version']['id'], :post => parent_post['id'] }
            ]
          }

          expected_data = TentD::Utils::Hash.deep_dup(data)
          expected_data[:permissions] = property_absent
          expected_data[:version][:parents][0].delete(:post)

          expect_properties(:post => expected_data)

          clients(:app_auth).post.update(parent_post['entity'], parent_post['id'], data)
        end.after do |response, results, validator|
          if results.any? { |r| !r[:valid] }
            raise SetupFailure.new("Failed to create version of post", response, results, validator)
          else
            set(:post, response.body['post'])
          end
        end

        ##
        # Expect profile to be returned via profiles=parents
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          meta_profile = get(:meta_profile)
          expect_properties(:profiles => {
            post['entity'] => meta_profile
          })

          clients(:app_auth).post.list(:profiles => 'parents', :limit => 1)
        end

        ##
        # Expect profile not to be returned via profiles=mentions
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.list(:profiles => 'mentions', :limit => 1)
        end

        ##
        # Expect profile not to be returned via profiles=refs
        expect_response(:status => 200, :schema => :data) do
          post = get(:post)

          expect_properties(:profiles => {})

          clients(:app_auth).post.list(:profiles => 'refs', :limit => 1)
        end
      end
    end

  end

  TentValidator.validators << MetaProfileValidator
end
