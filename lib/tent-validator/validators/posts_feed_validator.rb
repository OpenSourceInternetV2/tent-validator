module TentValidator
  class PostsFeedValidator < TentValidator::Spec

    SetupFailure = Class.new(StandardError)

    require 'tent-validator/validators/support/post_generators'
    include Support::PostGenerators

    def create_posts
      client = clients(:app)
      posts_attribtues = [generate_status_post, generate_random_post, generate_status_reply_post, generate_status_post]
      post_types = posts_attribtues.map { |a| a[:type] }.reverse

      posts = []
      posts_attribtues.each do |post|
        res = client.post.create(post)
        raise SetupFailure.new("Failed to create post: #{res.status}\n#{res.body.inspect}") unless res.success?
        posts << res.body
      end
      set(:posts, posts)

      set(:post_types, post_types)
    end

    def create_posts_with_mentions
      client = clients(:app)
      posts = []

      _create_post = proc do |post|
        res = client.post.create(post)
        raise SetupFailure.new("Failed to create post: #{res.status}\n#{res.body.inspect}") unless res.success?
        posts << res.body
        res.body
      end

      _ref = _create_post.call(generate_status_post)
      _create_post.call(generate_status_reply_post.merge(:mentions => [{ :entity => _ref['entity'], :post => _ref['id']}]))

      _ref = _create_post.call(generate_status_post)
      _create_post.call(generate_status_reply_post.merge(:mentions => [{ :entity => _ref['entity'], :post => _ref['id']}]))

      set(:posts, posts)
    end

    describe "GET posts_feed", :before => :create_posts do
      context "without params" do
        expect_response(:status => 200, :schema => :data) do
          expect_properties(:posts => get(:post_types).map { |type| { :type => type } })

          clients(:app).post.list
        end
      end

      context "with type param" do
        expect_response(:status => 200, :schema => :data) do
          types = get(:post_types)
          types = [types.first, types.last]

          expect_properties(:posts => types.map { |type| { :type => type } })

          clients(:app).post.list(:types => types)
        end

        context "when using fragment wildcard" do
          expect_response(:status => 200, :schema => :data) do
            type = TentClient::TentType.new('https://tent.io/types/status/v0')
            expected_types = get(:post_types).select { |t|
              TentClient::TentType.new(t).base == type.base
            }.map { |t| { :type => t } }

            expect_properties(:posts => expected_types)

            clients(:app).post.list(:types => [type.to_s(:fragment => false)])
          end
        end
      end

      context "with entities param" do
        context "when no matching entities" do
          expect_response(:status => 200, :schema => :data) do
            expect_properties(:posts => [])

            clients(:app).post.list(:entities => "https://fictitious.entity.example.org")
          end
        end

        context "when matching entities" do
          expect_response(:status => 200, :schema => :data) do
            entities = get(:posts).map { |p| p['entity'] }
            expect_properties(:posts => entities.map { |e| { :entity => e } })

            clients(:app).post.list(:entities => entities.uniq.join(','))
          end
        end

        # TODO: validate feed with entities param (with proxy)
      end

      context "with limit param" do
        expect_response(:status => 200, :schema => :data) do
          expect_property_length("/posts", 2)

          clients(:app).post.list(:limit => 2)
        end
      end

      # default limit is 25, make sure there are more than 25 posts (create_posts already called once and it creates 4 posts)
      context "when using default limit", :before => 6.times.map { :create_posts } do
        expect_response(:status => 200, :schema => :data) do
          expect_property_length("/posts", 25)

          clients(:app).post.list
        end
      end

      context "with mentions param", :before => :create_posts_with_mentions do
        context "when single param" do
          context "entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              posts = get(:posts).select { |post|
                post['mentions'] && post['mentions'].any? { |m| m['entity'] == entity }
              }
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity=>m['entity']} } } })

              clients(:app).post.list(:mentions => entity)
            end
          end

          context "entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              post = get(:posts).first['id'] # first status post
              posts = [get(:posts)[1]] # first status post reply
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity=>m['entity'],:post=>m['post']} } } })

              clients(:app).post.list(:mentions => [entity, post].join(' '))
            end
          end

          context "entity OR entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = get(:posts).select { |post|
                post['mentions'] && post['mentions'].any? { |m| m['entity'] == entity }
              }
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity=>m['entity']} } } })

              clients(:app).post.list(:mentions => [entity, fictitious_entity].join(','))
            end
          end

          context "entity OR entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:posts).first['id'] # first status post
              posts = [get(:posts)[1]] # first status post reply
              expect_properties(:posts => posts.map { |post| { :mentions => post['mentions'].map {|m| {:entity=>m['entity'],:post=>m['post']} } } })

              clients(:app).post.list(:mentions => [fictitious_entity, [entity, post].join(' ')].join(','))
            end
          end
        end

        context "when multiple params" do
          context "entity AND entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = []

              clients(:app).post.list(:mentions => [fictitious_entity, entity])
            end
          end

          context "entity AND entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              post = get(:posts).first['id'] # first status post
              posts = [get(:posts)[1]] # first status post reply

              clients(:app).post.list(:mentions => [entity, [entity, post].join(' ')])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              post = get(:posts).first['id'] # first status post
              posts = []

              clients(:app).post.list(:mentions => [fictitious_entity, [entity, post].join(' ')])
            end
          end

          context "(entity OR entity) AND entity" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = [get(:posts)[1]] # first status post reply

              clients(:app).post.list(:mentions => [[fictitious_entity, entity].join(','), entity])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              posts = []

              clients(:app).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), entity])
            end
          end

          context "(entity OR entity) AND (entity OR entity)" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              posts = [get(:posts)[1]] # first status post reply

              clients(:app).post.list(:mentions => 2.times.map { [fictitious_entity, entity].join(',') })
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              posts = []

              clients(:app).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [fictitious_entity, entity].join(',')])
            end
          end

          context "(entity OR entity) AND entity with post" do
            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:posts).first['id'] # first status post
              posts = []

              clients(:app).post.list(:mentions => [[fictitious_entity, other_fictitious_entity].join(','), [entity, post].join(' ')])
            end

            expect_response(:status => 200, :schema => :data) do
              entity = get(:posts).first['entity'] # remote entity
              fictitious_entity = "https://fictitious.entity.example.org" # an entity not mentioned by any post on remote server
              other_fictitious_entity = "https://other.fictitious.entity.example.com"
              post = get(:posts).first['id'] # first status post
              posts = [get(:posts)[1]] # first status post reply

              clients(:app).post.list(:mentions => [[fictitious_entity, entity].join(','), [entity, post].join(' ')])
            end
          end
        end
      end
    end
  end

  TentValidator.validators << PostsFeedValidator
end
