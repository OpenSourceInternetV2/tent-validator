require 'tentd/core_ext/hash/slice'

module TentValidator
  module Spec
    class GroupsValidation < Validation
      create_authorizations = describe "Create authorizations" do
        # Create app
        app = JSONGenerator.generate(:app, :with_auth)
        expect_response(:tent, :schema => :app, :status => 200, :properties => app) do
          clients(:app, :server => :remote).app.create(app)
        end.after do |result|
          if result.response.success?
            set(:app, app)
          end
        end

        # Create authorized authorization
        authorization = JSONGenerator.generate(:app_authorization, :with_auth, :scopes => %w[ read_groups write_groups ])
        set(:authorized_app_authorization, authorization)
        expect_response(:tent, :schema => :app_authorization, :status => 200) do
          clients(:app, :server => :remote).app.authorization.create(app[:id], authorization)
        end.after do |result|
          if result.response.success?
          end
        end

        # Create unauthorized authorization
        authorization2 = JSONGenerator.generate(:app_authorization, :with_auth, :scopes => %w[ read_posts write_posts ])
        set(:unauthorized_app_authorization, authorization2)
        expect_response(:tent, :schema => :app_authorization, :status => 200) do
          clients(:app, :server => :remote).app.authorization.create(app[:id], authorization2)
        end
      end

      create_group = describe "POST /groups (when authorized)", :depends_on => create_authorizations do
        authorization = get(:authorized_app_authorization)
        group = JSONGenerator.generate(:group, :simple)
        expect_response(:tent, :schema => :group, :status => 200, :properties => group) do
          clients(:custom, authorization.slice(:mac_key_id, :mac_algorithm, :mac_key).merge(:server => :remote)).group.create(group)
        end.after do |result|
          if result.response.success?
            set(:group, result.response.body)
          end
        end
      end

      describe "POST /groups (when unauthorized)", :depends_on => create_authorizations do
        authorization = get(:unauthorized_app_authorization)
        group = JSONGenerator.generate(:group, :simple)
        expect_response(:tent, :schema => :error, :status => 403) do
          clients(:custom, authorization.slice(:mac_key_id, :mac_algorithm, :mac_key).merge(:server => :remote)).group.create(group)
        end
      end
    end
  end
end