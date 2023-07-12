require 'uri'
require 'json'
require 'aws-sdk-iam'

module Himeko
  class UserMimickingRole
    def initialize(iam, username, role_name, path = nil, driver: nil, role_existing: false, assume_role_policy_document: nil)
      @driver = driver || Driver.new(iam)
      @username = username
      @role_name = role_name
      @path = path
      @role_existing = role_existing
      @assume_role_policy_document = assume_role_policy_document
    end

    attr_reader :driver, :username, :role_name, :path
    attr_reader :role_existing

    # @return [String] role arn
    def create
      if role_existing
        arn = driver.get_role(
          role_name: role_name,
        )
      else
        arn = driver.create_role(
          path: path,
          role_name: role_name,
          assume_role_policy_document: assume_role_policy_document,
        )
      end

      managed_policies.each do |policy_arn|
        driver.attach_role_policy(role_name, policy_arn)
      end

      policies.each do |policy_name, policy|
        driver.put_role_policy(role_name, policy_name, policy)
      end

      return arn
    end

    def user
      @user ||= driver.get_user(username)
    end

    def account_id
      user.arn.split(?:)[4]
    end

    def assume_role_policy_document
      @assume_role_policy_document || {
        "Version"=>"2012-10-17",
        "Statement"=>[
          {
            "Effect"=>"Allow",
            "Principal"=>{
              "AWS"=>[
                "arn:aws:iam::#{account_id}:root",
              ]
            },
            "Action"=>"sts:AssumeRole",
            "Condition"=>{},
          },
        ],
      }
    end

    def groups
      @groups ||= driver.list_groups_for_user(username)
    end

    def managed_policies
      @managed_policies ||= [
        *driver.list_attached_user_policies(username),
        *groups.flat_map do |group_name|
          driver.list_attached_group_policies(group_name)
        end,
      ].sort.uniq
    end

    def policies
      @policies ||= [
        *driver.list_user_policies(username).map do |policy_name|
          [policy_name, driver.get_user_policy(username, policy_name)]
        end,
        *groups.flat_map do |group_name|
          driver.list_group_policies(group_name).map do |policy_name|
            ["#{group_name}_#{policy_name}"[0..127], driver.get_group_policy(group_name, policy_name)]
          end
        end,
      ].to_h
    end

    class Driver
      def initialize(iam)
        @iam = iam
      end

      attr_reader :iam

      def get_user(username)
        iam.get_user(user_name: username).user
      end

      def list_attached_user_policies(username)
        iam.list_attached_user_policies(user_name: username).each.flat_map(&:attached_policies).map(&:policy_arn)
      end

      def list_user_policies(username)
        iam.list_user_policies(user_name: username).policy_names
      end

      def get_user_policy(username, policy_name)
        URI.decode_www_form_component(iam.get_user_policy(user_name: username, policy_name: policy_name).policy_document)
      end

      def list_groups_for_user(username)
        iam.list_groups_for_user(user_name: username).groups.map(&:group_name)
      end

      def list_group_policies(group_name)
        iam.list_group_policies(group_name: group_name).policy_names
      end

      def get_group_policy(group_name, policy_name)
        URI.decode_www_form_component(iam.get_group_policy(group_name: group_name, policy_name: policy_name).policy_document)
      end

      def list_attached_group_policies(group_name)
        iam.list_attached_group_policies(group_name: group_name).each.flat_map(&:attached_policies).map(&:policy_arn)
      end

      def create_role(path:, role_name:, assume_role_policy_document:, max_session_duration: 43200)
        iam.create_role(
          path: path,
          role_name: role_name,
          assume_role_policy_document: assume_role_policy_document.to_json,
          max_session_duration: max_session_duration
        ).role.arn
      end

      def get_role(role_name:)
        iam.get_role(role_name: role_name).role.arn
      end

      def attach_role_policy(role_name, policy_arn)
        iam.attach_role_policy(role_name: role_name, policy_arn: policy_arn)
      end

      def put_role_policy(role_name, policy_name, policy)
        iam.put_role_policy(
          role_name: role_name,
          policy_name: policy_name,
          policy_document: policy,
        )
      end
    end
  end
end
