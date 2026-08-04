require 'rails_helper'

RSpec.describe "Polls", type: :request do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }
  let!(:poll) { create(:poll, guild: guild, creator: user) }

  before do
    # Bypass MFA for test user
    user.update!(auth_method: :discord)
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in user
  end

  describe 'GET /guilds/:guild_id/polls' do
    it 'returns a successful response' do
      get guild_polls_path(guild)
      expect(response).to have_http_status(:success)
    end

    it 'displays polls for the guild' do
      get guild_polls_path(guild)
      expect(response.body).to include(poll.title)
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get guild_polls_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get guild_polls_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-polls-support.example/help")
        get guild_polls_path(guild)
        expect(response.body).to include("https://guild-polls-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-polls-support.example/help")
        get guild_polls_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-polls-support.example/help")
      end
    end
  end

  describe 'GET /guilds/:guild_id/polls/new' do
    it 'returns a successful response' do
      get new_guild_poll_path(guild)
      expect(response).to have_http_status(:success)
    end

    it 'shows the new poll form' do
      get new_guild_poll_path(guild)
      expect(response.body).to include('Create Poll')
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get new_guild_poll_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get new_guild_poll_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-polls-new-support.example/help")
        get new_guild_poll_path(guild)
        expect(response.body).to include("https://guild-polls-new-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-polls-new-support.example/help")
        get new_guild_poll_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-polls-new-support.example/help")
      end
    end
  end

  describe 'GET /guilds/:guild_id/polls/:id' do
    it 'returns a successful response' do
      get guild_poll_path(guild, poll)
      expect(response).to have_http_status(:success)
    end

    it 'displays the poll details' do
      get guild_poll_path(guild, poll)
      expect(response.body).to include(poll.title)
    end

    it 'wires poll-vote Stimulus for open polls (PollsChannel live updates)' do
      get guild_poll_path(guild, poll)
      expect(response.body).to include('data-controller="poll-vote"')
      expect(response.body).to include('click->poll-vote#vote')
      expect(response.body).to include('data-poll-vote-poll-id-value')
      expect(response.body).to include('data-poll-vote-vote-url-value')
    end

    describe 'support_center_url in member chrome' do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it 'includes default support URL in HTML' do
        get guild_poll_path(guild, poll)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes default support URL on mobile variant' do
        get guild_poll_path(guild, poll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it 'includes configured custom support URL when set' do
        SiteSetting.set("release_notes_url", "https://guild-poll-show-support.example/help")
        get guild_poll_path(guild, poll)
        expect(response.body).to include("https://guild-poll-show-support.example/help")
      end

      it 'includes configured custom support URL on mobile variant when set' do
        SiteSetting.set("release_notes_url", "https://guild-poll-show-support.example/help")
        get guild_poll_path(guild, poll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-poll-show-support.example/help")
      end
    end
  end

  describe 'POST /guilds/:guild_id/polls' do
    let(:valid_params) do
      {
        poll: {
          title: 'New Test Poll',
          description: 'A poll description',
          deadline: 1.week.from_now.to_s,
          anonymous: false
        }
      }
    end

    it 'creates a new poll' do
      expect {
        post guild_polls_path(guild), params: valid_params
      }.to change(Poll, :count).by(1)
    end

    it 'redirects to the poll show page' do
      post guild_polls_path(guild), params: valid_params
      expect(response).to redirect_to(guild_poll_path(guild, Poll.last))
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          poll: {
            title: '',
            deadline: nil
          }
        }
      end

      it 'does not create a poll' do
        expect {
          post guild_polls_path(guild), params: invalid_params
        }.not_to change(Poll, :count)
      end

      it 'returns unprocessable entity status' do
        post guild_polls_path(guild), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with discord role mentions' do
      let(:params_with_roles) do
        {
          poll: {
            title: 'Poll with Role Mentions',
            description: 'Testing role mentions',
            deadline: 1.week.from_now.to_s,
            anonymous: false
          },
          discord_role_mentions: ["111111111", "222222222", "111111111"] # Duplicate should be removed
        }
      end

      it 'stores unique role mentions' do
        post guild_polls_path(guild), params: params_with_roles
        created_poll = Poll.last
        expect(created_poll.discord_role_mentions).to eq(["111111111", "222222222"])
      end
    end
  end

  describe 'POST /guilds/:guild_id/polls/:id/vote' do
    context 'when poll is open' do
      it 'creates a new vote' do
        expect {
          post vote_guild_poll_path(guild, poll), params: { choice: 0 }, as: :json
        }.to change(PollVote, :count).by(1)
      end

      it 'returns vote counts and percentages' do
        post vote_guild_poll_path(guild, poll), params: { choice: 0 }, as: :json
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['vote_counts']).to be_present
        expect(json['vote_percentages']).to be_present
      end

      it 'updates an existing vote' do
        create(:poll_vote, poll: poll, user: user, choice: :yes)
        
        post vote_guild_poll_path(guild, poll), params: { choice: 1 }, as: :json
        
        expect(PollVote.count).to eq(1)
        expect(poll.poll_votes.first.reload.choice).to eq('no')
      end
    end

    context 'when poll is closed' do
      let(:closed_poll) { create(:poll, :closed, guild: guild, creator: user) }

      it 'returns an error' do
        post vote_guild_poll_path(guild, closed_poll), params: { choice: 0 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('closed')
      end
    end

    context 'with invalid choice' do
      it 'returns an error' do
        post vote_guild_poll_path(guild, poll), params: { choice: 99 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid choice')
      end
    end
  end

  describe 'DELETE /guilds/:guild_id/polls/:id' do
    it 'deletes the poll' do
      expect {
        delete guild_poll_path(guild, poll)
      }.to change(Poll, :count).by(-1)
    end

    it 'redirects to polls index' do
      delete guild_poll_path(guild, poll)
      expect(response).to redirect_to(guild_polls_path(guild))
    end

    context 'when user is not the creator or owner' do
      let(:other_user) { create(:user) }
      let(:member) { create(:guild_member, guild: guild, user: other_user) }

      before do
        member # Create membership
        sign_out user
        other_user.update!(auth_method: :discord)
        sign_in other_user
      end

      it 'does not allow deletion' do
        delete guild_poll_path(guild, poll)
        expect(response).to redirect_to(guild_poll_path(guild, poll))
      end
    end
  end

  describe 'anonymous polls' do
    let(:anonymous_poll) { create(:poll, :anonymous, guild: guild, creator: user) }

    it 'respects anonymous setting' do
      expect(anonymous_poll.anonymous?).to be true
    end
  end

  describe 'authorization' do
    context 'when user is not a guild member' do
      let(:other_guild) { create(:guild) }
      let(:other_poll) { create(:poll, guild: other_guild) }

      it 'redirects when accessing another guild polls' do
        get guild_polls_path(other_guild)
        expect(response).to redirect_to(my_guilds_path)
      end
    end

    context 'when user is a member but not owner' do
      let(:member_user) { create(:user) }
      let!(:membership) { create(:guild_member, guild: guild, user: member_user, discord_role_id: "poll-role-1") }

      before do
        sign_out user
        member_user.update!(auth_method: :discord)
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
        sign_in member_user
      end

      it 'can view polls' do
        get guild_polls_path(guild)
        expect(response).to have_http_status(:success)
      end

      it 'can vote on polls' do
        post vote_guild_poll_path(guild, poll), params: { choice: 0 }, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'cannot create polls' do
        post guild_polls_path(guild), params: {
          poll: { title: 'Test', deadline: 1.week.from_now.to_s }
        }
        expect(response).to redirect_to(guild_polls_path(guild))
      end

      it 'can create polls when custom role permission is enabled' do
        guild.update!(permission_role_1_id: "poll-role-1", role_1_can_manage_polls: true)
        expect {
          post guild_polls_path(guild), params: {
            poll: {
              title: "Permitted Poll",
              description: "Permitted poll description",
              deadline: 1.week.from_now.to_s,
              anonymous: false
            }
          }
        }.to change(Poll, :count).by(1)
      end
    end
  end
end

