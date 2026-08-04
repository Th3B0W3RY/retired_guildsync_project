# frozen_string_literal: true

require "bcrypt"

class BackupCodeGenerator
  CODE_LENGTH = 24
  CODES_PER_USER = 1
  CHARACTER_SET = ([ *"A".."Z", *"0".."9" ] - %w[O 0 I 1]).freeze

  def self.generate_for_user(user)
    user.backup_codes.active.update_all(
      active: false,
      invalidated_at: Time.current,
      invalidated_reason: "new_codes_generated"
    )

    codes = []
    code_objects = []

    code = CODE_LENGTH.times.map { CHARACTER_SET.sample }.join
    formatted = code.scan(/.{4}/).join("-")
    digest = BCrypt::Password.create(code)
    last_four = code[-4..]

    code_object = user.backup_codes.create!(
      code_digest: digest,
      last_four: last_four,
      active: true,
      used: false,
      generated_at: Time.current
    )
    code_objects << code_object
    codes << formatted

    file_content = generate_txt_file(user, codes)
    {
      codes: codes,
      file_content: file_content,
      code_objects: code_objects
    }
  end

  def self.generate_txt_file(user, codes)
    <<~TXT
      ================================================
        GUILDSYNC BACKUP CODE
        Generated: #{Time.current.strftime("%B %d, %Y at %I:%M %p %Z")}
        User: #{user.email}
      ================================================

      ⚠️  IMPORTANT SAFETY INFORMATION  ⚠️
      • Each code can be used ONLY ONCE
      • Store these codes OFFLINE (print or password manager)
      • Keep them secure - anyone with these can access your account
      • We will NEVER show these codes again

      YOUR BACKUP CODE (24 characters):
      ────────────────────────────────────────────────

      #{codes.first}

      ────────────────────────────────────────────────

      HOW TO USE:
      1. Go to the sign-in page and click "Forgot password?"
      2. Choose "Backup Code" and enter your email and this code
      3. You'll be able to reset your password AND/OR MFA

      KEEP THIS FILE SAFE!
      ================================================
    TXT
  end
end
