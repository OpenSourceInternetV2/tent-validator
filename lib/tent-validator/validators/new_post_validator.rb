require 'tent-validator/validators/post_validator'

module TentValidator
  class PostValidator

    shared_example :new_post do
      context "with valid attributes" do
        valid_post_expectation = proc do |post, expected_post|
          expect_response(:headers => :tent, :status => 200, :schema => :post) do
            expect_headers(:post)
            expect_properties(expected_post)
            expect_schema(get(:content_schema), "/content")

            if attachments = get(:post_attachments)
              expect_properties(
                :attachments => attachments.map { |a|
                  a = a.dup
                  a.merge!(:hash => hex_digest(a[:data]), :size => a[:data].size)
                  a.delete(:data)
                  a
                }
              )

              res = clients(:no_auth, :server => :remote).post.create(post, {}, :attachments => attachments)
            else
              res = clients(:no_auth, :server => :remote).post.create(post)
            end

            if Hash === res.body
              expect_properties(:version => { :id => generate_version_signature(res.body) })
            end

            res
          end
        end

        valid_post_expectation.call(get(:post), get(:post))

        context "when permissions.public member is null" do
          post = get(:post)
          pointer = JsonPointer.new(post, '/permissions/public', :symbolize_keys => true)
          pointer.value = nil

          valid_post_expectation.call(post, get(:post))
        end

        context "when permissions member is null" do
          post = get(:post)
          post[:permissions] = nil

          valid_post_expectation.call(post, get(:post))
        end

        context "when member set that should be ignored" do
          properties = TentValidator::Schemas[:post]["properties"]
          %w( /id /received_at /entity /original_entity /app /version/id /version/published_at /version/received_at ).each do |path|
            path_fragments = path.split('/')
            property_path = path_fragments[0] + path_fragments[1..-1].join('/properties/')
            property = JsonPointer.new(properties, property_path).value

            post = get(:post)
            pointer = JsonPointer.new(post, path, :symbolize_keys => true)
            pointer.value = valid_value(property['type'], property['format'])

            valid_post_expectation.call(post, get(:post))
          end
        end
      end

      context "with invalid attributes" do
        if attachments = get(:attachments)
          context "when attachment hash mismatch" do
            expect_response(:headers => :error, :status => 400, :schema => :error) do
              attachments = attachments.map do |attachment|
                attachment[:headers] = {
                  'Attachment-Digest' => 'foobar'
                }
              end
              clients(:no_auth, :server => :remote).post.create(post, {}, :attachments => attachments)
            end
          end
        end

        context "when extra field in content" do
          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            data[:content][:extra_member] = "I shouldn't be here!"
            clients(:no_auth, :server => :remote).post.create(data)
          end
        end

        invalid_member_expectation = proc do |path, property|
          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            pointer = JsonPointer.new(data, path, :symbolize_keys => true)
            pointer.value = invalid_value(property['type'], property['format'])
            clients(:no_auth, :server => :remote).post.create(data)
          end

          if property['type'] == 'object' && property['properties']
            property['properties'].each_pair do |name, property|
              invalid_member_expectation.call(path + "/#{name}", property)
            end
          end

          if property['type'] == 'array' && property['items']
            invalid_member_expectation.call(path + "/-", { 'type' => property['items']['type'], 'format' => property['items']['format'] })
          end
        end

        context "when content member is wrong type" do
          TentValidator::Schemas[get(:content_schema)]["properties"].each_pair do |name, property|
            invalid_member_expectation.call("/content/#{name}", property)
          end
        end

        context "when post member is wrong type" do
          properties = TentValidator::Schemas[:post]["properties"]
          %w( published_at version mentions licenses content attachments permissions ).each do |name|
            invalid_member_expectation.call("/#{name}", properties[name])
          end
        end

        context "when extra post member" do
          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            data[:extra_member] = "I shouldn't be here!"
            clients(:no_auth, :server => :remote).post.create(data)
          end
        end

        context "when content is wrong type" do
          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            data[:content] = "I should be an object"
            clients(:no_auth, :server => :remote).post.create(data)
          end

          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            data[:content] = ["My parent should be an object!"]
            clients(:no_auth, :server => :remote).post.create(data)
          end

          expect_response(:headers => :error, :status => 400, :schema => :error) do
            data = get(:post)
            data[:content] = true
            clients(:no_auth, :server => :remote).post.create(data)
          end
        end
      end

      context "without request body" do
        expect_response(:headers => :error, :status => 400, :schema => :error) do
          clients(:no_auth, :server => :remote).post.create(nil) do |request|
            request.headers['Content-Type'] = TentD::API::POST_CONTENT_TYPE % 'https://tent.io/types/app/v0#'
          end
        end
      end

      context "when request body is wrong type" do
        expect_response(:headers => :error, :status => 400, :schema => :error) do
          clients(:no_auth, :server => :remote).post.create("I should be an object") do |request|
            request.headers['Content-Type'] = TentD::API::POST_CONTENT_TYPE % 'https://tent.io/types/app/v0#'
          end
        end
      end

      context "with invalid content-type header" do
        data = get(:post)
        expect_response(:headers => :error, :status => 415, :schema => :error) do
          clients(:no_auth, :server => :remote).post.create(data) do |request|
            request.headers['Content-Type'] = 'application/json'
          end
        end
      end
    end

  end
end