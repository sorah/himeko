require 'himeko/user_mimicking_role'

RSpec.describe Himeko::UserMimickingRole do
  let(:role_arn) { 'dummy-role-arn' }
  let(:user) { double('user', arn: 'arn:dummy:user::12345678:root') }
  let(:driver) {
    double(
      'driver',
      get_user: user,
      create_role: role_arn,
      list_attached_user_policies: [],
      list_user_policies: [],
      list_groups_for_user: [],
    )
  }
  subject { described_class.new(nil, 'username', 'role_name', '/', driver: driver) }

  describe "#create" do
    it "creates role" do
      expect(driver).to receive(:create_role).with(
        path: '/',
        role_name: 'role_name',
        assume_role_policy_document: {
        "Version"=>"2012-10-17",
        "Statement"=>[
          {
            "Effect"=>"Allow",
            "Principal"=>{
              "AWS"=>[
                "arn:aws:iam::12345678:root",
              ]
            },
            "Action"=>"sts:AssumeRole",
            "Condition"=>{},
          },
        ],
      }

      ).and_return(role_arn)

      expect(subject.create).to eq(role_arn)
    end

    describe "user attached policies" do
      before do
        allow(driver).to receive(:list_attached_user_policies).with('username').and_return(
          %w(
            arn:dummy:iam::12345678:policy/dummy
          )
        )
      end

      it "attaches same policy to role" do
        expect(driver).to receive(:attach_role_policy).with('role_name', 'arn:dummy:iam::12345678:policy/dummy')
        subject.create
      end
    end

    describe "user inline policies" do
      before do
        allow(driver).to receive(:list_user_policies).with('username').and_return(
          %w(
            user-policy1
          )
        )
        allow(driver).to receive(:get_user_policy).with('username', 'user-policy1').and_return(
          'user-policy1 document',
        )
      end

      it "attaches same policy to role" do
        expect(driver).to receive(:put_role_policy).with('role_name', 'user-policy1', 'user-policy1 document')
        subject.create
      end
    end

    describe "group attached policies" do
      before do
        allow(driver).to receive(:list_groups_for_user).with('username').and_return(
          %w(
            group1
          )
        )
        allow(driver).to receive(:list_group_policies).with('group1').and_return([])
        allow(driver).to receive(:list_attached_group_policies).with('group1').and_return(
          %w(
            arn:dummy:iam::12345678:policy/dummy
          )
        )
      end

      it "attaches same policy to role" do
        expect(driver).to receive(:attach_role_policy).with('role_name', 'arn:dummy:iam::12345678:policy/dummy')
        subject.create
      end
    end

    describe "group inline policies" do
      before do
        allow(driver).to receive(:list_groups_for_user).with('username').and_return(
          %w(
            group1
          )
        )
        allow(driver).to receive(:list_group_policies).with('group1').and_return(
          %w(
            group-policy1
          )
        )
        allow(driver).to receive(:list_attached_group_policies).with('group1').and_return([])
        allow(driver).to receive(:get_group_policy).with('group1', 'group-policy1').and_return(
          'group-policy1 document',
        )
      end

      it "attaches same policy to role" do
        expect(driver).to receive(:put_role_policy).with('role_name', "group1_group-policy1", 'group-policy1 document')
        subject.create
      end
    end
  end
end
