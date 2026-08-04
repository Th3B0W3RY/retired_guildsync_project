# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildMember::ApiAttributes do
  let(:guild) { create(:guild) }
  let(:acting_user) { guild.owner }

  def extract(raw)
    described_class.extract(raw, guild: guild, acting_user: acting_user)
  end

  it "allows member and status when keys are valid" do
    h = extract({ "role" => "member", "status" => "active" })
    expect(h).to eq(role: "member", status: "active")
  end

  it "strips unknown enum values" do
    h = extract({ "role" => "superuser", "status" => "active" })
    expect(h).to eq(status: "active")
  end

  it "does not allow non-owners to assign owner role" do
    admin_user = create(:user)
    create(:guild_member, guild: guild, user: admin_user, role: :admin, status: :active)

    h = described_class.extract(
      { "role" => "owner" },
      guild: guild,
      acting_user: admin_user
    )
    expect(h).to eq({})
  end

  it "allows the guild owner to assign owner role" do
    h = described_class.extract(
      { "role" => "owner", "status" => "active" },
      guild: guild,
      acting_user: guild.owner
    )
    expect(h[:role]).to eq("owner")
    expect(h[:status]).to eq("active")
  end
end
