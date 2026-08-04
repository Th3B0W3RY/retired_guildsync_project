# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "LootRolls", type: :request do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }
  let!(:discord_setting) do
    create(:guild_discord_setting,
           guild: guild,
           discord_guild_id: "123456789",
           loot_rolls_channel_id: "987654321",
           bot_token: "test_bot_token")
  end
  let!(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

  before do
    # Bypass MFA for test user
    user.update!(auth_method: :discord)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in user
    
    # Stub Discord API calls
    stub_request(:any, /discord\.com/).to_return(
      status: 200,
      body: '{"id": "999888777"}',
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe 'GET /guilds/:guild_id/loot_rolls' do
    it 'returns a successful response' do
      get guild_loot_rolls_path(guild)
      expect(response).to have_http_status(:success)
    end

    it 'displays loot rolls for the guild' do
      get guild_loot_rolls_path(guild)
      expect(response.body).to include(loot_roll.title)
    end

    it 'shows open and closed status badges' do
      closed_roll = create(:loot_roll, :closed, guild: guild, creator: user, title: "Closed Roll")
      get guild_loot_rolls_path(guild)
      expect(response.body).to include('Open')
      expect(response.body).to include('Closed')
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get guild_loot_rolls_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get guild_loot_rolls_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-rolls-support.example/help")
        get guild_loot_rolls_path(guild)
        expect(response.body).to include("https://guild-loot-rolls-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-rolls-support.example/help")
        get guild_loot_rolls_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-loot-rolls-support.example/help")
      end
    end
  end

  describe 'GET /guilds/:guild_id/loot_rolls/new' do
    it 'returns a successful response' do
      get new_guild_loot_roll_path(guild)
      expect(response).to have_http_status(:success)
    end

    it 'shows the new loot roll form' do
      get new_guild_loot_roll_path(guild)
      expect(response.body).to include('Create New Loot Roll')
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get new_guild_loot_roll_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get new_guild_loot_roll_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-rolls-new-support.example/help")
        get new_guild_loot_roll_path(guild)
        expect(response.body).to include("https://guild-loot-rolls-new-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-rolls-new-support.example/help")
        get new_guild_loot_roll_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-loot-rolls-new-support.example/help")
      end
    end

    context 'when loot rolls channel is not configured' do
      before do
        discord_setting.update!(loot_rolls_channel_id: nil)
      end

      it 'shows a warning message' do
        get new_guild_loot_roll_path(guild)
        expect(response.body).to include('configure')
      end
    end
  end

  describe 'GET /guilds/:guild_id/loot_rolls/:id' do
    it 'returns a successful response' do
      get guild_loot_roll_path(guild, loot_roll)
      expect(response).to have_http_status(:success)
    end

    it 'displays the loot roll details' do
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include(loot_roll.title)
    end

    it 'shows the leaderboard' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll, display_name: "TestPlayer", roll_value: 85)
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("TestPlayer")
      expect(response.body).to include("85")
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get guild_loot_roll_path(guild, loot_roll)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get guild_loot_roll_path(guild, loot_roll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-roll-show-support.example/help")
        get guild_loot_roll_path(guild, loot_roll)
        expect(response.body).to include("https://guild-loot-roll-show-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-loot-roll-show-support.example/help")
        get guild_loot_roll_path(guild, loot_roll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-loot-roll-show-support.example/help")
      end
    end

    it 'shows tie detection when there is a tie' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: "user1")
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: "user2")
      
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("Tie")
    end

    it 'shows winner when loot roll is closed' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll, display_name: "Winner", roll_value: 95)
      loot_roll.update!(status: :closed, winner_entry: entry)
      
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("Winner")
    end

    it 'wires loot-roll Stimulus for LootRollsChannel live updates' do
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include('data-controller="loot-roll"')
      expect(response.body).to include('data-loot-roll-loot-roll-id-value')
    end
  end

  describe 'POST /guilds/:guild_id/loot_rolls' do
    let(:valid_params) do
      {
        loot_roll: {
          title: 'New Loot Roll',
          description: 'A test loot roll',
          min_roll: 1,
          max_roll: 100,
          deadline_at: 1.week.from_now.to_s
        }
      }
    end

    it 'creates a new loot roll' do
      expect {
        post guild_loot_rolls_path(guild), params: valid_params
      }.to change(LootRoll, :count).by(1)
    end

    it 'redirects to the loot roll show page' do
      post guild_loot_rolls_path(guild), params: valid_params
      expect(response).to redirect_to(guild_loot_roll_path(guild, LootRoll.last))
    end

    it 'sets the creator to the current user' do
      post guild_loot_rolls_path(guild), params: valid_params
      expect(LootRoll.last.creator).to eq(user)
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          loot_roll: {
            title: '',
            min_roll: 100,
            max_roll: 50
          }
        }
      end

      it 'does not create a loot roll' do
        expect {
          post guild_loot_rolls_path(guild), params: invalid_params
        }.not_to change(LootRoll, :count)
      end

      it 'returns unprocessable entity status' do
        post guild_loot_rolls_path(guild), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with allowed roles' do
      let(:params_with_roles) do
        {
          loot_roll: {
            title: 'Loot Roll with Roles',
            min_roll: 1,
            max_roll: 100
          },
          allowed_role_ids: ["111111111", "222222222", "111111111"] # Duplicate should be removed
        }
      end

      it 'stores unique role IDs' do
        post guild_loot_rolls_path(guild), params: params_with_roles
        created_roll = LootRoll.last
        expect(created_roll.allowed_role_ids).to eq(["111111111", "222222222"])
      end
    end

    context 'when loot rolls channel is not configured' do
      before do
        discord_setting.update!(loot_rolls_channel_id: nil)
      end

      it 'returns an error' do
        post guild_loot_rolls_path(guild), params: valid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /guilds/:guild_id/loot_rolls/:id/close' do
    it 'closes the loot roll' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75)
      
      post close_guild_loot_roll_path(guild, loot_roll)
      
      expect(loot_roll.reload.status).to eq('closed')
      expect(response).to redirect_to(guild_loot_roll_path(guild, loot_roll))
    end

    it 'determines the winner' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75)
      
      post close_guild_loot_roll_path(guild, loot_roll)
      
      expect(loot_roll.reload.winner_entry).to eq(entry)
    end

    context 'when already closed' do
      before { loot_roll.update!(status: :closed) }

      it 'shows an error message' do
        post close_guild_loot_roll_path(guild, loot_roll)
        expect(flash[:alert]).to include('already closed')
      end
    end
  end

  describe 'POST /guilds/:guild_id/loot_rolls/:id/force_reroll' do
    let!(:entry) { create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75) }

    it 'marks the entry as a reroll' do
      post force_reroll_guild_loot_roll_path(guild, loot_roll), params: { entry_id: entry.id }
      
      expect(entry.reload.is_reroll).to be true
    end

    it 'redirects back to the loot roll' do
      post force_reroll_guild_loot_roll_path(guild, loot_roll), params: { entry_id: entry.id }
      
      expect(response).to redirect_to(guild_loot_roll_path(guild, loot_roll))
    end

    context 'when entry not found' do
      it 'shows an error' do
        post force_reroll_guild_loot_roll_path(guild, loot_roll), params: { entry_id: 99999 }
        
        expect(flash[:alert]).to include('not found')
      end
    end
  end

  describe 'DELETE /guilds/:guild_id/loot_rolls/:id' do
    it 'soft deletes the loot roll from standard queries' do
      expect {
        delete guild_loot_roll_path(guild, loot_roll)
      }.to change(LootRoll, :count).by(-1)
    end

    it 'redirects to loot rolls index' do
      delete guild_loot_roll_path(guild, loot_roll)
      expect(response).to redirect_to(guild_loot_rolls_path(guild))
    end

    it 'preserves associated entries for possible restoration' do
      create(:loot_roll_entry, loot_roll: loot_roll)
      
      expect {
        delete guild_loot_roll_path(guild, loot_roll)
      }.not_to change(LootRollEntry, :count)
    end

    context 'when user is not the creator or owner' do
      let(:other_user) { create(:user) }
      let!(:membership) { create(:guild_member, guild: guild, user: other_user) }

      before do
        sign_out user
        other_user.update!(auth_method: :discord)
        sign_in other_user
      end

      it 'does not allow deletion' do
        delete guild_loot_roll_path(guild, loot_roll)
        expect(response).to redirect_to(guild_loot_roll_path(guild, loot_roll))
      end
    end
  end

  describe 'authorization' do
    context 'when user is not a guild member' do
      let(:other_guild) { create(:guild) }
      let(:other_roll) { create(:loot_roll, guild: other_guild) }

      it 'redirects when accessing another guild loot rolls' do
        get guild_loot_rolls_path(other_guild)
        expect(response).to redirect_to(my_guilds_path)
      end
    end

    context 'when user is a member but not owner' do
      let(:member_user) { create(:user) }
      let!(:membership) { create(:guild_member, guild: guild, user: member_user, discord_role_id: "loot-role-1") }

      before do
        sign_out user
        member_user.update!(auth_method: :discord)
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
        sign_in member_user
      end

      it 'can view loot rolls' do
        get guild_loot_rolls_path(guild)
        expect(response).to have_http_status(:success)
      end

      it 'can view individual loot roll' do
        get guild_loot_roll_path(guild, loot_roll)
        expect(response).to have_http_status(:success)
      end

      it 'cannot create loot rolls' do
        post guild_loot_rolls_path(guild), params: {
          loot_roll: { title: 'Test', min_roll: 1, max_roll: 100 }
        }
        expect(response).to redirect_to(guild_loot_rolls_path(guild))
      end

      it 'can create loot rolls when custom role permission is enabled' do
        guild.update!(permission_role_1_id: "loot-role-1", role_1_can_manage_loot_rolls: true)
        expect {
          post guild_loot_rolls_path(guild), params: {
            loot_roll: { title: "Permitted Loot Roll", min_roll: 1, max_roll: 100 }
          }
        }.to change(LootRoll, :count).by(1)
      end

      it 'cannot delete loot rolls' do
        delete guild_loot_roll_path(guild, loot_roll)
        expect(response).to redirect_to(guild_loot_roll_path(guild, loot_roll))
      end
    end
  end

  describe 'roll range validation' do
    it 'displays the roll range' do
      loot_roll.update!(min_roll: 10, max_roll: 50)
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("10")
      expect(response.body).to include("50")
    end
  end

  describe 'deadline handling' do
    it 'shows deadline when set' do
      loot_roll.update!(deadline_at: 2.days.from_now)
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("Deadline")
    end

    it 'shows countdown timer for open rolls with deadline' do
      loot_roll.update!(deadline_at: 2.days.from_now)
      get guild_loot_roll_path(guild, loot_roll)
      expect(response.body).to include("countdown")
    end
  end
end
