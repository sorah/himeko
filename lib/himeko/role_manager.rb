require 'aws-sdk-dynamodb'
require 'himeko/user_mimicking_role'

module Himeko
  class RoleManager
    def initialize(iam:, prefix:, path:, ttl: 86400, dynamodb_table:)
      @iam = iam
      @prefix = prefix
      @path = path
      @table = dynamodb_table
      @ttl = ttl
    end

    attr_reader :iam, :prefix, :path, :table, :ttl

    def fetch(username, recreate: false, assume_role_policy_document: nil)
      item = table.query(
        limit: 1,
        select: 'ALL_ATTRIBUTES',
        key_condition_expression: 'username = :username',
        expression_attribute_values: {":username" => username},
      ).items.first

      if recreate || item.nil?
        role_existing = false
        begin
          return create(username, role_existing: role_existing, assume_role_policy_document: assume_role_policy_document)
        rescue Aws::IAM::Errors::EntityAlreadyExists
          remove(username, delete_record: false, delete_role: false)
          role_existing = true
          retry
        end
      end

      table.update_item(
        key: {
          'username' => username,
        },
        update_expression: 'SET expires_at = :expires_at',
        expression_attribute_values: {
          ':expires_at' => (Time.now + ttl).to_i,
        },
      )

      item.fetch('role_arn')
    end

    def remove(username, role_name: nil, delete_record: true, delete_role: true)
      role_name ||= role_name_for_username(username)

      iam.list_attached_role_policies(role_name: role_name).each.flat_map(&:attached_policies).map(&:policy_arn).each do |policy_arn|
        iam.detach_role_policy(role_name: role_name, policy_arn: policy_arn)
      end
      iam.list_role_policies(role_name: role_name).policy_names.each do |policy_name|
        iam.delete_role_policy(role_name: role_name, policy_name: policy_name)
      end
      iam.delete_role(role_name: role_name) if delete_role

      if delete_record
        table.delete_item(
          key: {
            'username' => username,
          },
        )
      end
    rescue Aws::IAM::Errors::NoSuchEntity
      # do nothing
    end

    def create(username, role_existing: false, assume_role_policy_document: nil)
      role_arn = UserMimickingRole.new(
        iam,
        username,
        role_name_for_username(username),
        path,
        role_existing: role_existing,
        assume_role_policy_document: assume_role_policy_document,
      ).create

      table.update_item(
        key: {
          'username' => username,
        },
        update_expression: 'SET expires_at = :expires_at, role_arn = :role_arn',
        expression_attribute_values: {
          ':expires_at' => (Time.now + ttl).to_i,
          ':role_arn' => role_arn,
        },
      )
      
      role_arn
    end

    def prune
      table.client.scan(
        table_name: table.table_name,
        select: 'ALL_ATTRIBUTES',
        filter_expression: 'expires_at < :now',
        expression_attribute_values: {
          ':now' => Time.now.to_i,
        },
      ).each do |page|
        page.items.each do |item|
          puts "==> #{item['username']} (#{item['role_arn']})"
          remove(item['username'], role_name: item['role_arn'].split(?/)[-1])
          table.delete_item(key: {'username' => item['username']})
        end
      end
    end

    def role_name_for_username(username)
      "#{prefix}#{username}"
    end
  end
end
