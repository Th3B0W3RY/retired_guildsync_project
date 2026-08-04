module ThemeHelper
  # Get current theme (defaults to 'dark')
  def current_theme
    session[:theme] || "dark"
  end

  # Set theme in session
  def set_theme(theme)
    session[:theme] = theme
  end

  # Get theme class for HTML element
  def theme_class
    current_theme == "dark" ? "theme-dark dark" : "theme-light"
  end

  # Check if dark theme is active
  def dark_theme?
    current_theme == "dark"
  end

  # Get theme-specific CSS classes
  def theme_bg_primary
    dark_theme? ? "bg-dark-bg-primary" : "bg-light-bg-primary"
  end

  def theme_bg_secondary
    dark_theme? ? "bg-dark-bg-secondary" : "bg-light-bg-secondary"
  end

  def theme_text_primary
    dark_theme? ? "text-dark-text-primary" : "text-light-text-primary"
  end

  def theme_text_secondary
    dark_theme? ? "text-dark-text-secondary" : "text-light-text-secondary"
  end
end
