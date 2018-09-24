# Himeko: AWS IAM access key self service & management console federated login

This web application provides self service of AWS IAM access keys (which belongs to an IAM user) and management console federated logging in via an auto generated IAM role which mimicked the IAM user.

1. Prepare proper authentication method for this web application (Pass IAM username for the authenticated user as a Rack environment)
2. This webapp creates an IAM role from the authenticated IAM user (when it hasn't existed yet)
3. This webapp redirects the user to AWS management console via Federated Login https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_enable-console-custom-url.html

## Prerequisites

- DynamoDB table for managing temporary IAM roles
  - primary key: `username` (string)
- (optional, recommended) AWS IAM _user_ for calling `sts:AssumeRole`
  - AWS restricts having more than an hour for session `DurationSeconds` when assuming a new role using an identity derived from IAM roles (["Role Chaining"](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html))
  - At [Cookpad](https://info.cookpad.com/), we use [Vault AWS Secrets Engine](https://www.vaultproject.io/docs/secrets/aws/index.html) to rotate IAM user access key for `sts:AssumeRole` API calls.

## Set up

This application is implemented as a Rack application.

```ruby
# Gemfile
source 'https://rubygems.org'
gem 'himeko'
```

### Web app: Authentication

Make sure to set the following rack environment variable to a request before passing it to the application.

- `himeko.user`: IAM user name authenticated for the request

It is your responsibility to provide proper user data to this application. 

Refer to [config.ru](./config.ru) for the example configuration. It uses OmniAuth for user authentication and the inline middleware ensures to set `himeko.user` for `Himeko::App`.

### Batch tasks: Cleaning temporary IAM roles

Set up to run the following task periodically on your system:

```
bundle exec himeko-clean-roles
```

This command accepts the following environment variables:

- `HIMEKO_ROLE_PATH`
- `HIMEKO_ROLE_PREFIX`
- `HIMEKO_DYNAMODB_TABLE`

### Docker Image

TODO:

But since the configuration above is required, you'll need to add your `config.ru` to the image or bind mount your `config.ru` on runtime.

## Management

### IAM Policy

#### Access Key Management

``` json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "iam:CreateAccessKey",
                "iam:DeleteAccessKey",
                "iam:GetAccessKeyLastUsed",
                "iam:ListAccessKeys",
                "iam:UpdateAccessKey"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:iam::*:user/*"
            ]
        }
    ]
}
```

#### Role creation and management for user console access

``` json
{
    "Version": "2012-10-17",
    "Statement": [
       {
            "Action": [
                "dynamodb:DescribeTable",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:GetItem",
                "dynamodb:BatchGetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:dynamodb:REGION:ACCOUNT:table/TABLE",
                "arn:aws:dynamodb:REGION:ACCOUNT:table/TABLE/index/*"
            ]
        },
        {
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetGroupPolicy",
                "iam:GetUserPolicy",
                "iam:GetUser",
                "iam:ListAttachedGroupPolicies",
                "iam:ListAttachedRolePolicies",
                "iam:ListAttachedUserPolicies",
                "iam:ListGroupPolicies",
                "iam:ListGroupsForUser",
                "iam:ListRolePolicies",
                "iam:ListUserPolicies",
                "iam:PutRolePolicy"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:iam::ACCOUNT:user/*",
                "arn:aws:iam::ACCOUNT:group/*",
                "arn:aws:iam::ACCOUNT:role/user-role/*"
            ]
        }
    ]
}
```

(`/user-role/` is a default path for IAM roles which this webapp creates)

#### Console Login

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": [
                "arn:aws:iam::ACCOUNT:role/user-role/*"
            ]
        }
    ]
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/himeko.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
