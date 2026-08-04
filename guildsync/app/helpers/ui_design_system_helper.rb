# frozen_string_literal: true

module UiDesignSystemHelper
  UI_COLOR_TOKENS = [
    { name: "bg-theme-primary", value: "#0f172a", usage: "Primary app background" },
    { name: "bg-theme-secondary", value: "#1e293b", usage: "Secondary surface" },
    { name: "bg-theme-card", value: "#1e293b", usage: "Card and panel backgrounds" },
    { name: "text-theme-primary", value: "#f1f5f9", usage: "Primary text" },
    { name: "text-theme-secondary", value: "#cbd5e1", usage: "Secondary/help text" },
    { name: "text-theme-accent", value: "#6366f1", usage: "Primary accent" },
    { name: "border-theme-primary", value: "#334155", usage: "Default border" },
    { name: "Brand gradient", value: "var(--gs-gradient-brand)", usage: "Use via `bg-theme-brand-gradient` for primary CTA and brand treatments" }
  ].freeze

  UI_TYPOGRAPHY_TOKENS = [
    { name: "Body font", value: "font-sans (Tailwind sans stack)", usage: "Layout body text" },
    { name: "Heading XL", value: "text-3xl font-bold", usage: "Admin page headings" },
    { name: "Heading L", value: "text-xl font-semibold", usage: "Card and section headings" },
    { name: "Body", value: "text-sm / text-base", usage: "Forms, tables, support copy" },
    { name: "Caption", value: "text-xs text-theme-secondary", usage: "Meta details and helper text" },
    { name: "Tracking", value: "tracking-tight / tracking-wide", usage: "Hero and metric labels" }
  ].freeze

  UI_SPACING_TOKENS = [
    { name: "Section spacing", value: "space-y-6 / space-y-8", usage: "Vertical rhythm for admin pages" },
    { name: "Container", value: "max-w-7xl px-4 sm:px-6 lg:px-8", usage: "Primary page container" },
    { name: "Card padding", value: "p-6", usage: "Cards/panels across admin" },
    { name: "Control spacing", value: "gap-2 / gap-3 / gap-4", usage: "Buttons, form rows, compact layouts" }
  ].freeze

  UI_SURFACE_TOKENS = [
    { name: "Glass panel", value: "rounded-xl border border-white/10 bg-[rgba(15,23,43,0.5)] p-6 shadow-lg", usage: "Dashboard cards and hero sections" },
    { name: "Theme card", value: "rounded-xl border border-theme-primary bg-theme-card p-6 shadow-lg", usage: "Admin forms and content panels" },
    { name: "Muted state panel", value: "rounded-lg border border-theme-primary bg-theme-secondary/50", usage: "Sub-sections and inactive blocks" }
  ].freeze

  UI_BUTTON_TOKENS = [
    { name: "Primary gradient", value: "inline-flex items-center justify-center rounded-lg bg-theme-brand-gradient px-4 py-2 text-sm font-semibold text-white transition-opacity hover:opacity-95" },
    { name: "Secondary theme", value: "rounded-lg bg-theme-secondary px-4 py-2 text-theme-primary hover:bg-theme-hover transition-colors" },
    { name: "Danger", value: "rounded-lg bg-red-600 px-4 py-2 text-white hover:bg-red-700 transition-colors" },
    { name: "Success", value: "rounded-lg bg-green-600 px-4 py-2 text-white hover:bg-green-700 transition-colors" }
  ].freeze

  UI_FORM_TOKENS = [
    { name: "Text input", value: "bg-theme-primary border border-theme-primary rounded-lg text-theme-primary focus:ring-2 focus:ring-theme-accent", usage: "Search fields and admin forms" },
    { name: "Textarea", value: "bg-theme-primary border border-theme-primary rounded-lg text-theme-primary", usage: "Rich and plain text forms" },
    { name: "Checkbox", value: '<%= f.check_box :permission_flag, class: "w-4 h-4" %> (inside `.guild-permission-checkbox-grid`)', usage: "Permission matrix checkboxes; scoped CSS enforces canonical 1rem sizing + accent color" }
  ].freeze

  UI_TABLE_TOKENS = [
    { name: "Table shell", value: "overflow-hidden rounded-lg border border-theme-primary", usage: "Data lists" },
    { name: "Header", value: "bg-theme-secondary/50 text-theme-secondary", usage: "Column headings" },
    { name: "Row separators", value: "divide-y divide-theme-primary", usage: "Body rows" }
  ].freeze

  UI_MOTION_TOKENS = [
    { name: "Default transition", value: "transition-colors / transition-opacity", usage: "Buttons, links, nav" },
    { name: "Ambient drift A", value: "ambientDriftA 18s ease-in-out infinite alternate", usage: "Global ambient background" },
    { name: "Ambient drift B", value: "ambientDriftB 22s ease-in-out infinite alternate", usage: "Global ambient background" },
    { name: "Reduced motion", value: "@media (prefers-reduced-motion: reduce) { animation: none }", usage: "Accessibility safeguard" }
  ].freeze

  UI_RESPONSIVE_TOKENS = [
    { name: "Breakpoints", value: "sm 640 / md 768 / lg 1024 / xl 1280", usage: "Tailwind responsive conventions" },
    { name: "Grid pattern", value: "grid-cols-1 md:grid-cols-2 lg:grid-cols-4", usage: "Dashboard/stat cards" },
    { name: "Mobile-first spacing", value: "px-4 sm:px-6 lg:px-8", usage: "Page shells" }
  ].freeze

  UI_COMPONENT_RULES = [
    { name: "Navigation links", value: "text-theme-secondary hover:text-theme-accent transition-colors", usage: "Top nav and admin links" },
    { name: "Modal/dropdown shell", value: "bg-theme-card border border-theme-primary rounded-lg shadow-xl", usage: "Search dropdowns and menus" },
    { name: "Badge state", value: "rounded-full text-xs font-bold", usage: "Pending counts and inline status" },
    { name: "Icons", value: "w-4 h-4 / w-5 h-5 with currentColor", usage: "Inline SVG icons" }
  ].freeze

  def ui_design_system_sections
    [
      { title: t("admin.ui_design_system.sections.colors.title"), description: t("admin.ui_design_system.sections.colors.description"), type: :swatches, tokens: UI_COLOR_TOKENS },
      { title: t("admin.ui_design_system.sections.typography.title"), description: t("admin.ui_design_system.sections.typography.description"), type: :rows, tokens: UI_TYPOGRAPHY_TOKENS },
      { title: t("admin.ui_design_system.sections.spacing.title"), description: t("admin.ui_design_system.sections.spacing.description"), type: :rows, tokens: UI_SPACING_TOKENS },
      { title: t("admin.ui_design_system.sections.surfaces.title"), description: t("admin.ui_design_system.sections.surfaces.description"), type: :rows, tokens: UI_SURFACE_TOKENS },
      { title: t("admin.ui_design_system.sections.buttons.title"), description: t("admin.ui_design_system.sections.buttons.description"), type: :buttons, tokens: UI_BUTTON_TOKENS },
      { title: t("admin.ui_design_system.sections.forms.title"), description: t("admin.ui_design_system.sections.forms.description"), type: :rows, tokens: UI_FORM_TOKENS },
      { title: t("admin.ui_design_system.sections.tables.title"), description: t("admin.ui_design_system.sections.tables.description"), type: :rows, tokens: UI_TABLE_TOKENS },
      { title: t("admin.ui_design_system.sections.motion.title"), description: t("admin.ui_design_system.sections.motion.description"), type: :rows, tokens: UI_MOTION_TOKENS },
      { title: t("admin.ui_design_system.sections.responsive.title"), description: t("admin.ui_design_system.sections.responsive.description"), type: :rows, tokens: UI_RESPONSIVE_TOKENS },
      { title: t("admin.ui_design_system.sections.patterns.title"), description: t("admin.ui_design_system.sections.patterns.description"), type: :rows, tokens: UI_COMPONENT_RULES }
    ]
  end
end
