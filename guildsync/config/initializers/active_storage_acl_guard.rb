# frozen_string_literal: true

# Guardrail: never run marketing/document uploads with public object ACLs.
# GuildSync expects private buckets + signed blob URLs.
if Rails.env.production?
  acl = (ENV["S3_ACL"].presence || ENV["AWS_S3_ACL"]).to_s.downcase.strip
  if %w[public-read public-read-write authenticated-read].include?(acl)
    raise ArgumentError, "Unsafe S3 ACL configured (#{acl}). Use private bucket policy and unset S3_ACL/AWS_S3_ACL (or set private)."
  end
end
