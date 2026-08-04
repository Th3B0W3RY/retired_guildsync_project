# frozen_string_literal: true

require "rails_helper"

RSpec.describe SoftDeletable, type: :model do
  let(:user) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: user) }

  it "hides soft-deleted records from default queries and restores them" do
    poll = create(:poll, guild: guild, creator: user, title: "Soft Delete Me")

    expect(Poll.where(id: poll.id)).to exist

    poll.soft_delete!

    expect(Poll.where(id: poll.id)).not_to exist
    expect(Poll.deleted.where(id: poll.id)).to exist
    expect(Poll.with_deleted.find(poll.id)).to be_deleted

    poll.restore!

    expect(Poll.where(id: poll.id)).to exist
    expect(Poll.find(poll.id)).to be_active
  end

  it "reports restorability only inside the admin retention window" do
    poll = create(:poll, guild: guild, creator: user, title: "Retention")

    poll.soft_delete!
    expect(poll).to be_soft_delete_restorable

    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.day)
    expect(poll.reload).not_to be_soft_delete_restorable
  end
end
