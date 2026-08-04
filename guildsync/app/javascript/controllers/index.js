import { application } from "./application"
import ToastController from "./toast_controller"
import AvatarDropdownController from "./avatar_dropdown_controller"
import GuildDropdownController from "./guild_dropdown_controller"
import DiscordRoleSyncController from "./discord_role_sync_controller"
import EditorController from "./editor_controller"
import DocumentRendererController from "./document_renderer_controller"
import StorageController from "./storage_controller"
import FileUploadController from "./file_upload_controller"
import FileGridController from "./file_grid_controller"
import FolderTreeController from "./folder_tree_controller"
import FolderFormController from "./folder_form_controller"
import MoveFilesController from "./move_files_controller"
import GlobalSearchController from "./global_search_controller"
import SidebarScrollController from "./sidebar_scroll_controller"
import LanguageSwitcherController from "./language_switcher_controller"
import DiscordAuthLinkController from "./discord_auth_link_controller"
import MessageCenterController from "./message_center_controller"
import RecentActivityPollController from "./recent_activity_poll_controller"
import DashboardStatsPollController from "./dashboard_stats_poll_controller"
import RoadmapController from "./roadmap_controller"
import RoadmapCommentsController from "./roadmap_comments_controller"
import AdminRoadmapController from "./admin_roadmap_controller"
import ReactRolesController from "./react_roles_controller"
import NativeFilePickController from "./native_file_pick_controller"
import MobileShellController from "./mobile_shell_controller"
import PricingPlansController from "./pricing_plans_controller"
import AdminSystemMonitoringController from "./admin_system_monitoring_controller"
import LandingHeroVideoController from "./landing_hero_video_controller"
import LandingFeedbackCarouselController from "./landing_feedback_carousel_controller"
import FontawesomeIconPickerController from "./fontawesome_icon_picker_controller"
import AdminOrderListController from "./admin_order_list_controller"
import AllianceChatController from "./alliance_chat_controller"
import PollVoteController from "./poll_vote_controller"
import AlliancePollVoteController from "./alliance_poll_vote_controller"
import LootRollController from "./loot_roll_controller"
import AllianceLootRollLiveController from "./alliance_loot_roll_live_controller"
import MemberStatRowController from "./member_stat_row_controller"
import SubmitScrollRestoreController from "./submit_scroll_restore_controller"
import AccountDeletionController from "./account_deletion_controller"

application.register("toast", ToastController)
application.register("submit-scroll-restore", SubmitScrollRestoreController)
application.register("account-deletion", AccountDeletionController)
application.register("discord-auth-link", DiscordAuthLinkController)
application.register("recent-activity-poll", RecentActivityPollController)
application.register("dashboard-stats-poll", DashboardStatsPollController)
application.register("avatar-dropdown", AvatarDropdownController)
application.register("guild-dropdown", GuildDropdownController)
application.register("discord-role-sync", DiscordRoleSyncController)
application.register("editor", EditorController)
application.register("document-renderer", DocumentRendererController)
application.register("storage", StorageController)
application.register("file-upload", FileUploadController)
application.register("file-grid", FileGridController)
application.register("folder-tree", FolderTreeController)
application.register("folder-form", FolderFormController)
application.register("move-files", MoveFilesController)
application.register("global-search", GlobalSearchController)
application.register("sidebar-scroll", SidebarScrollController)
application.register("language-switcher", LanguageSwitcherController)
application.register("message-center", MessageCenterController)
application.register("roadmap", RoadmapController)
application.register("roadmap-comments", RoadmapCommentsController)
application.register("admin-roadmap", AdminRoadmapController)
application.register("react-roles", ReactRolesController)
application.register("native-file-pick", NativeFilePickController)
application.register("mobile-shell", MobileShellController)
application.register("pricing-plans", PricingPlansController)
application.register("admin-system-monitoring", AdminSystemMonitoringController)
application.register("landing-hero-video", LandingHeroVideoController)
application.register("landing-feedback-carousel", LandingFeedbackCarouselController)
application.register("fontawesome-icon-picker", FontawesomeIconPickerController)
application.register("admin-order-list", AdminOrderListController)
application.register("alliance-chat", AllianceChatController)
application.register("poll-vote", PollVoteController)
application.register("alliance-poll-vote", AlliancePollVoteController)
application.register("loot-roll", LootRollController)
application.register("alliance-loot-roll-live", AllianceLootRollLiveController)
application.register("member-stat-row", MemberStatRowController)
