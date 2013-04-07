require 'tent-canonical-json'
require 'tent-validator/request_expectation'

module TentValidator
  class Spec < ApiValidator::Spec

    def watch_local_requests(should, user_id)
      if should
        TentValidator.watch_local_requests[user_id] = should
      else
        TentValidator.watch_local_requests.delete(user_id)
      end
    end

    def expect_request(options = {}, &block)
      expectation = RequestExpectation.new(self, options, &block)
      self.expectations << expectation
      expectation
    end

    def clients(type, options = {})
      server = options.delete(:server) || :remote
      if server == :remote
        TentClient.new(TentValidator.remote_entity_uri, auth_details_for_app_type(type, options).merge(
          :faraday_adapter => TentValidator.remote_adapter,
          :server_meta => TentValidator.remote_server_meta
        ))
      else
      end
    end

    def generate_version_signature(post)
      canonical_post_json = TentCanonicalJson.encode(post)
      hex_digest(canonical_post_json)
    end

    def hex_digest(input)
      TentD::Utils.hex_digest(input)
    end

    def invalid_value(type, format = nil)
      case type
      when "array"
        Hash.new
      when "boolean"
        "false"
      when "number", "integer"
        "123"
      when "null"
        true
      when "object"
        ["My parent should be an object!"]
      when "string"
        if format
          case format
          when 'uri'
            "I'm not a uri!"
          end
        else
          421
        end
      end
    end

    def valid_value(type, format = nil)
      case type
      when "array"
        []
      when "boolean"
        true
      when "number", "integer"
        123
      when "null"
        nil
      when "object"
        Hash.new
      when "string"
        if format
          case format
          when 'uri'
            "https://example.com"
          end
        else
          ""
        end
      end
    end

    private

    def auth_details_for_app_type(type, options={})
      case type
      when :app
        TentValidator.remote_auth_details
      when :custom
        TentD::Utils::Hash.slice(options, :mac_key_id, :mac_algorithm, :mac_key)
      else
        Hash.new
      end
    end

  end
end
