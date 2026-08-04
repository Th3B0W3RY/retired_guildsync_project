# frozen_string_literal: true

module UserActivity
  # Request-level gate for the Recent Activity feed: only signed-in, top-level GET
  # navigations are candidates for recording. Background polling (XHR) and non-GET
  # requests are ignored here; action-specific exclusions live in UserActivity::Descriptor.
  class RecordingPolicy
    def initialize(request:, user:)
      @request = request
      @user = user
    end

    def record?
      get_request? && signed_in? && !polling_request?
    end

    private

    attr_reader :request, :user

    def get_request?
      request.get? || request.head?
    end

    def signed_in?
      user.present?
    end

    def polling_request?
      request.xhr?
    end
  end
end
