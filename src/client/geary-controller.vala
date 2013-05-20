/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Primary controller object for Geary.
public class GearyController {
    // Named actions.
    public const string ACTION_HELP = "GearyHelp";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    public const string ACTION_REPLY_TO_MESSAGE = "GearyReplyToMessage";
    public const string ACTION_REPLY_ALL_MESSAGE = "GearyReplyAllMessage";
    public const string ACTION_FORWARD_MESSAGE = "GearyForwardMessage";
    public const string ACTION_DELETE_MESSAGE = "GearyDeleteMessage";
    public const string ACTION_FIND_IN_CONVERSATION = "GearyFindInConversation";
    public const string ACTION_FIND_NEXT_IN_CONVERSATION = "GearyFindNextInConversation";
    public const string ACTION_FIND_PREVIOUS_IN_CONVERSATION = "GearyFindPreviousInConversation";
    public const string ACTION_ZOOM_IN = "GearyZoomIn";
    public const string ACTION_ZOOM_OUT = "GearyZoomOut";
    public const string ACTION_ZOOM_NORMAL = "GearyZoomNormal";
    public const string ACTION_ACCOUNTS = "GearyAccounts";
    public const string ACTION_PREFERENCES = "GearyPreferences";
    public const string ACTION_MARK_AS_MENU = "GearyMarkAsMenuButton";
    public const string ACTION_MARK_AS_READ = "GearyMarkAsRead";
    public const string ACTION_MARK_AS_UNREAD = "GearyMarkAsUnread";
    public const string ACTION_MARK_AS_STARRED = "GearyMarkAsStarred";
    public const string ACTION_MARK_AS_UNSTARRED = "GearyMarkAsUnStarred";
    public const string ACTION_MARK_AS_SPAM = "GearyMarkAsSpam";
    public const string ACTION_COPY_MENU = "GearyCopyMenuButton";
    public const string ACTION_MOVE_MENU = "GearyMoveMenuButton";
    public const string ACTION_GEAR_MENU = "GearyGearMenuButton";

    public const int FETCH_EMAIL_CHUNK_COUNT = 200;
    
    private const string DELETE_MESSAGE_LABEL = _("_Delete");
    private const string DELETE_MESSAGE_TOOLTIP_SINGLE = _("Delete conversation (Delete, Backspace, A)");
    private const string DELETE_MESSAGE_TOOLTIP_MULTIPLE = _("Delete conversations (Delete, Backspace, A)");
    private const string DELETE_MESSAGE_ICON_NAME = "user-trash-full";
    
    private const string ARCHIVE_MESSAGE_LABEL = _("_Archive");
    private const string ARCHIVE_MESSAGE_TOOLTIP_SINGLE = _("Archive conversation (Delete, Backspace, A)");
    private const string ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE = _("Archive conversations (Delete, Backspace, A)");
    private const string ARCHIVE_MESSAGE_ICON_NAME = "mail-archive";
    
    private const string MARK_AS_SPAM_LABEL = _("Mark as s_pam");
    private const string MARK_AS_NOT_SPAM_LABEL = _("Mark as not s_pam");
    
    private const string MARK_MESSAGE_MENU_TOOLTIP_SINGLE = _("Mark conversation");
    private const string MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE = _("Mark conversations");
    private const string LABEL_MESSAGE_TOOLTIP_SINGLE = _("Add label to conversation");
    private const string LABEL_MESSAGE_TOOLTIP_MULTIPLE = _("Add label to conversations");
    private const string MOVE_MESSAGE_TOOLTIP_SINGLE = _("Move conversation");
    private const string MOVE_MESSAGE_TOOLTIP_MULTIPLE = _("Move conversations");
    
    private const int SELECT_FOLDER_TIMEOUT_MSEC = 100;
    
    public MainWindow main_window { get; private set; }
    
    private Geary.Account? current_account = null;
    private Gee.HashMap<Geary.Account, Geary.Folder> inboxes
        = new Gee.HashMap<Geary.Account, Geary.Folder>();
    private Geary.Folder? current_folder = null;
    private Geary.ConversationMonitor? current_conversations = null;
    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_message = new Cancellable();
    private Gee.HashMap<Geary.Account, Cancellable> inbox_cancellables
        = new Gee.HashMap<Geary.Account, Cancellable>();
    private int busy_count = 0;
    private Gee.Set<Geary.Conversation> selected_conversations = new Gee.HashSet<Geary.Conversation>();
    private Geary.Conversation? last_deleted_conversation = null;
    private Gee.LinkedList<ComposerWidget> composer_widgets = new Gee.LinkedList<ComposerWidget>();
    private File? last_save_directory = null;
    private NewMessagesMonitor? new_messages_monitor = null;
    private NewMessagesIndicator? new_messages_indicator = null;
    private UnityLauncher? unity_launcher = null;
    private NotificationBubble? notification_bubble = null;
    private uint select_folder_timeout_id = 0;
    private Geary.Folder? folder_to_select = null;
    private Geary.Nonblocking.Mutex select_folder_mutex = new Geary.Nonblocking.Mutex();
    private Geary.Account? account_to_select = null;
    
    public GearyController() {
        // This initializes the IconFactory, important to do before the actions are created (as they
        // refer to some of Geary's custom icons)
        IconFactory.instance.init();
        
        // Setup actions.
        GearyApplication.instance.actions.add_actions(create_actions(), this);
        GearyApplication.instance.actions.add_toggle_actions(create_toggle_actions(), this);
        GearyApplication.instance.ui_manager.insert_action_group(
            GearyApplication.instance.actions, 0);
        GearyApplication.instance.load_ui_file("accelerators.ui");
        
        // some actions need a little extra help
        prepare_actions();
        
        // Listen for attempts to close the application.
        GearyApplication.instance.exiting.connect(on_application_exiting);
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow();
        main_window.notify["has-toplevel-focus"].connect(on_has_toplevel_focus);
        
        enable_message_buttons(false);

        // Connect to various UI signals.
        main_window.conversation_list_view.conversations_selected.connect(on_conversations_selected);
        main_window.conversation_list_view.load_more.connect(on_load_more);
        main_window.conversation_list_view.mark_conversation.connect(on_mark_conversation);
        main_window.conversation_list_view.visible_conversations_changed.connect(on_visible_conversations_changed);
        main_window.folder_list.folder_selected.connect(on_folder_selected);
        main_window.folder_list.copy_conversation.connect(on_copy_conversation);
        main_window.folder_list.move_conversation.connect(on_move_conversation);
        main_window.main_toolbar.copy_folder_menu.folder_selected.connect(on_copy_conversation);
        main_window.main_toolbar.move_folder_menu.folder_selected.connect(on_move_conversation);
        main_window.conversation_viewer.link_selected.connect(on_link_selected);
        main_window.conversation_viewer.reply_to_message.connect(on_reply_to_message);
        main_window.conversation_viewer.reply_all_message.connect(on_reply_all_message);
        main_window.conversation_viewer.forward_message.connect(on_forward_message);
        main_window.conversation_viewer.mark_message.connect(on_conversation_viewer_mark_message);
        main_window.conversation_viewer.open_attachment.connect(on_open_attachment);
        main_window.conversation_viewer.save_attachments.connect(on_save_attachments);

        new_messages_monitor = new NewMessagesMonitor(should_notify_new_messages);
        main_window.folder_list.set_new_messages_monitor(new_messages_monitor);
        
        // New messages indicator (Ubuntuism)
        new_messages_indicator = NewMessagesIndicator.create(new_messages_monitor);
        new_messages_indicator.application_activated.connect(on_indicator_activated_application);
        new_messages_indicator.composer_activated.connect(on_indicator_activated_composer);
        new_messages_indicator.inbox_activated.connect(on_indicator_activated_inbox);
        
        unity_launcher = new UnityLauncher(new_messages_monitor);
        
        // libnotify
        notification_bubble = new NotificationBubble(new_messages_monitor);
        notification_bubble.invoked.connect(on_notification_bubble_invoked);
        
        // This is fired after the accounts are ready.
        Geary.Engine.instance.opened.connect(on_engine_opened);
        
        main_window.conversation_list_view.grab_focus();
        
        set_busy(false);
        
        main_window.show_all();
    }
    
    ~GearyController() {
        assert(current_account == null);
    }

    private void add_accelerator(string accelerator, string action) {
        GtkUtil.add_accelerator(GearyApplication.instance.ui_manager, GearyApplication.instance.actions,
            accelerator, action);
    }

    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry accounts = { ACTION_ACCOUNTS, null, TRANSLATABLE, "<Ctrl>M",
            null, on_accounts };
        accounts.label = _("A_ccounts");
        entries += accounts;
        
        Gtk.ActionEntry prefs = { ACTION_PREFERENCES, Gtk.Stock.PREFERENCES, TRANSLATABLE, "<Ctrl>E",
            null, on_preferences };
        prefs.label = _("_Preferences");
        entries += prefs;

        Gtk.ActionEntry help = { ACTION_HELP, Gtk.Stock.HELP, TRANSLATABLE, "F1", null, on_help };
        help.label = _("_Help");
        entries += help;

        Gtk.ActionEntry about = { ACTION_ABOUT, Gtk.Stock.ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        Gtk.ActionEntry quit = { ACTION_QUIT, Gtk.Stock.QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        Gtk.ActionEntry mark_menu = { ACTION_MARK_AS_MENU, null, TRANSLATABLE, null, null,
            on_show_mark_menu };
        mark_menu.label = _("_Mark as...");
        mark_menu.tooltip = MARK_MESSAGE_MENU_TOOLTIP_SINGLE;
        entries += mark_menu;

        Gtk.ActionEntry mark_read = { ACTION_MARK_AS_READ, "mail-mark-read", TRANSLATABLE, "<Ctrl>I",
            null, on_mark_as_read };
        mark_read.label = _("Mark as _read");
        entries += mark_read;
        add_accelerator("<Shift>I", ACTION_MARK_AS_READ);

        Gtk.ActionEntry mark_unread = { ACTION_MARK_AS_UNREAD, "mail-mark-unread", TRANSLATABLE,
            "<Ctrl>U", null, on_mark_as_unread };
        mark_unread.label = _("Mark as _unread");
        entries += mark_unread;
        add_accelerator("<Shift>U", ACTION_MARK_AS_UNREAD);
        
        Gtk.ActionEntry mark_starred = { ACTION_MARK_AS_STARRED, "starred", TRANSLATABLE, "S", null,
            on_mark_as_starred };
        mark_starred.label = _("_Star");
        entries += mark_starred;

        Gtk.ActionEntry mark_unstarred = { ACTION_MARK_AS_UNSTARRED, "non-starred", TRANSLATABLE, "D",
            null, on_mark_as_unstarred };
        mark_unstarred.label = _("U_nstar");
        entries += mark_unstarred;
        
        Gtk.ActionEntry mark_spam = { ACTION_MARK_AS_SPAM, null, TRANSLATABLE, "<Ctrl>J", null,
            on_mark_as_spam };
        mark_spam.label = MARK_AS_SPAM_LABEL;
        entries += mark_spam;
        add_accelerator("exclam", ACTION_MARK_AS_SPAM); // Exclamation mark (!)
        
        Gtk.ActionEntry copy_menu = { ACTION_COPY_MENU, null, TRANSLATABLE, "L", null, null };
        copy_menu.label = _("_Label");
        entries += copy_menu;

        Gtk.ActionEntry move_menu = { ACTION_MOVE_MENU, null, TRANSLATABLE, "M", null, null };
        move_menu.label = _("_Move");
        entries += move_menu;

        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, null, TRANSLATABLE, "<Ctrl>N", null,
            on_new_message };
        new_message.label = _("_New Message");
        entries += new_message;
        add_accelerator("N", ACTION_NEW_MESSAGE);

        Gtk.ActionEntry reply_to_message = { ACTION_REPLY_TO_MESSAGE, null, TRANSLATABLE, "<Ctrl>R",
            null, on_reply_to_message_action };
        reply_to_message.label = _("_Reply");
        entries += reply_to_message;
        add_accelerator("R", ACTION_REPLY_TO_MESSAGE);
        
        Gtk.ActionEntry reply_all_message = { ACTION_REPLY_ALL_MESSAGE, null, TRANSLATABLE,
            "<Ctrl><Shift>R", null, on_reply_all_message_action };
        reply_all_message.label = _("Reply _all");
        entries += reply_all_message;
        add_accelerator("<Shift>R", ACTION_REPLY_ALL_MESSAGE);
        
        Gtk.ActionEntry forward_message = { ACTION_FORWARD_MESSAGE, null, TRANSLATABLE, "<Ctrl>L", null,
            on_forward_message_action };
        forward_message.label = _("_Forward");
        entries += forward_message;
        add_accelerator("F", ACTION_FORWARD_MESSAGE);
        
        Gtk.ActionEntry find_in_conversation = { ACTION_FIND_IN_CONVERSATION, null, null, "<Ctrl>F",
        null, on_find_in_conversation_action };
        entries += find_in_conversation;
        add_accelerator("slash", ACTION_FIND_IN_CONVERSATION);
        
        Gtk.ActionEntry find_next_in_conversation = { ACTION_FIND_NEXT_IN_CONVERSATION, null, null,
            "<Ctrl>G", null, on_find_next_in_conversation_action };
        entries += find_next_in_conversation;
        
        Gtk.ActionEntry find_previous_in_conversation = { ACTION_FIND_PREVIOUS_IN_CONVERSATION,
            null, null, "<Shift><Ctrl>G", null, on_find_previous_in_conversation_action };
        entries += find_previous_in_conversation;
        
        // although this action changes according to Geary.Folder capabilities, set to Archive
        // until they're known so the "translatable" string doesn't first appear
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, ARCHIVE_MESSAGE_ICON_NAME,
            ARCHIVE_MESSAGE_LABEL, "A", null, on_delete_message };
        delete_message.tooltip = ARCHIVE_MESSAGE_TOOLTIP_SINGLE;
        entries += delete_message;
        add_accelerator("Delete", ACTION_DELETE_MESSAGE);
        add_accelerator("BackSpace", ACTION_DELETE_MESSAGE);

        Gtk.ActionEntry zoom_in = { ACTION_ZOOM_IN, null, null, "<Ctrl>equal",
            null, on_zoom_in };
        entries += zoom_in;
        add_accelerator("equal", ACTION_ZOOM_IN);

        Gtk.ActionEntry zoom_out = { ACTION_ZOOM_OUT, null, null, "<Ctrl>minus",
            null, on_zoom_out };
        entries += zoom_out;
        add_accelerator("minus", ACTION_ZOOM_OUT);

        Gtk.ActionEntry zoom_normal = { ACTION_ZOOM_NORMAL, null, null, "<Ctrl>0",
            null, on_zoom_normal };
        entries += zoom_normal;
        add_accelerator("0", ACTION_ZOOM_NORMAL);
        
        return entries;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] entries = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry gear_menu = { ACTION_GEAR_MENU, null, null, "F10",
            null, null, false };
        entries += gear_menu;
        
        return entries;
    }
    
    private void prepare_actions() {
        GearyApplication.instance.get_action(ACTION_NEW_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_REPLY_TO_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_REPLY_ALL_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_FORWARD_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_DELETE_MESSAGE).is_important = true;
    }
    
    public async void connect_account_async(Geary.Account account, Cancellable? cancellable = null) {
        account.folders_available_unavailable.connect(on_folders_available_unavailable);

        try {
            yield account.open_async(cancellable);
        } catch (Error open_err) {
            // TODO: Better error reporting to user
            debug("Unable to open account %s: %s", account.to_string(), open_err.message);
            
            GearyApplication.instance.panic();
        }
        
        inbox_cancellables.set(account, new Cancellable());
        
        account.email_sent.connect(on_sent);
        
        main_window.folder_list.set_user_folders_root_name(account, _("Labels"));
    }
    
    public async void disconnect_account_async(Geary.Account account, Cancellable? cancellable = null) {
        cancel_inbox(account);
        if (current_account == account) {
            cancel_folder();
            cancel_message();
        }
        
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        
        if (main_window.conversation_list_store.account_owner_email == account.information.email)
            main_window.conversation_list_store.account_owner_email = null;
        main_window.folder_list.remove_account(account);
        
        if (inboxes.has_key(account)) {
            try {
                yield inboxes.get(account).close_async(cancellable);
            } catch (Error close_inbox_err) {
                debug("Unable to close monitored inbox: %s", close_inbox_err.message);
            }
            
            inboxes.unset(account);
        }
        
        try {
            yield account.close_async(cancellable);
        } catch (Error close_err) {
            debug("Unable to close account %s: %s", account.to_string(), close_err.message);
        }
        
        inbox_cancellables.unset(account);
        
        // If there are no accounts available, exit.  (This can happen if the user declines to
        // enter a password on their account.)
        try {
            if (get_num_open_accounts() == 0)
                GearyApplication.instance.exit();
        } catch (Error e) {
            message("Error enumerating accounts: %s", e.message);
        }
    }
    
    // Returns the number of open accounts.
    private int get_num_open_accounts() throws Error {
        int num = 0;
        foreach (Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
            Geary.Account a = Geary.Engine.instance.get_account_instance(info);
            if (a.is_open())
                num++;
        }
        
        return num;
    }
    
    private bool is_viewed_conversation(Geary.Conversation? conversation) {
        return conversation != null && selected_conversations.size > 0 &&
            Geary.Collection.get_first<Geary.Conversation>(selected_conversations) == conversation;
    }
    
    // Update widgets and such to match capabilities of the current folder ... sensitivity is handled
    // by other utility methods
    private void update_ui() {
        update_tooltips();
        Gtk.Action delete_message = GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE);
        if (current_folder is Geary.FolderSupport.Archive) {
            delete_message.label = ARCHIVE_MESSAGE_LABEL;
            delete_message.icon_name = ARCHIVE_MESSAGE_ICON_NAME;
        } else {
            // even if not Geary.FolderSupportsrRemove, use delete icons and label, although they
            // may be insensitive the entire time
            delete_message.label = DELETE_MESSAGE_LABEL;
            delete_message.icon_name = DELETE_MESSAGE_ICON_NAME;
        }
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        debug("Folder %s selected", folder != null ? folder.to_string() : "(null)");
        
        // If the folder is being unset, clear the message list and exit here.
        if (folder == null) {
            current_folder = null;
            main_window.conversation_list_store.clear();
            main_window.conversation_viewer.clear(null, null);
            
            return;
        }
        
        // To prevent the user from selecting folders too quickly, we actually
        // schedule the action to happen after a timeout instead of acting
        // directly.  If the user selects another folder during the timeout,
        // we nix the original timeout and start a new one.
        if (select_folder_timeout_id != 0)
            Source.remove(select_folder_timeout_id);
        folder_to_select = folder;
        select_folder_timeout_id = Timeout.add(SELECT_FOLDER_TIMEOUT_MSEC, on_select_folder_timeout);
    }
    
    private bool on_select_folder_timeout() {
        assert(folder_to_select != null);
        
        select_folder_timeout_id = 0;
        
        do_select_folder.begin(folder_to_select, on_select_folder_completed);
        
        folder_to_select = null;
        return false;
    }
    
    private async void do_select_folder(Geary.Folder folder) throws Error {
        set_busy(true);
        
        cancel_folder();
        
        // This function is not reentrant.  It should be, because it can be
        // called reentrant-ly if you select folders quickly enough.  This
        // mutex lock is a bandaid solution to make the function safe to
        // reenter.
        int mutex_token = yield select_folder_mutex.claim_async(cancellable_folder);
        
        bool current_is_inbox = inboxes.values.contains(current_folder);
        
        Cancellable? conversation_cancellable = (current_is_inbox ?
            inbox_cancellables.get(folder.account) : cancellable_folder);
        
        // stop monitoring for conversations and close the folder (but only if not an inbox,
        // which we leave open for notifications)
        if (current_conversations != null) {
            yield current_conversations.stop_monitoring_async(!current_is_inbox, null);
            current_conversations = null;
        } else if (current_folder != null && !current_is_inbox) {
            yield current_folder.close_async();
        }
        
        if (folder != null)
            debug("switching to %s", folder.to_string());
        
        current_folder = folder;
        current_account = folder.account;
        
        main_window.conversation_list_store.set_current_folder(current_folder, conversation_cancellable);
        main_window.conversation_list_store.account_owner_email = current_account.information.email;
        
        main_window.main_toolbar.copy_folder_menu.clear();
        main_window.main_toolbar.move_folder_menu.clear();
        foreach(Geary.Folder f in current_folder.account.list_folders()) {
            main_window.main_toolbar.copy_folder_menu.add_folder(f);
            main_window.main_toolbar.move_folder_menu.add_folder(f);
        }
        
        update_ui();
        
        current_conversations = new Geary.ConversationMonitor(current_folder, Geary.Folder.OpenFlags.NONE,
            ConversationListStore.REQUIRED_FIELDS);
        
        if (inboxes.values.contains(current_folder)) {
            // Inbox selected, clear new messages if visible
            clear_new_messages("do_select_folder (inbox)", null);
        }
        
        current_conversations.scan_started.connect(on_scan_started);
        current_conversations.scan_error.connect(on_scan_error);
        current_conversations.scan_completed.connect(on_scan_completed);
        current_conversations.seed_completed.connect(on_seed_completed);
        current_conversations.conversation_appended.connect(on_conversation_appended);
        current_conversations.conversation_trimmed.connect(on_conversation_trimmed);
        current_conversations.email_flags_changed.connect(on_email_flags_changed);
        
        main_window.conversation_list_store.set_conversation_monitor(current_conversations);
        main_window.conversation_list_view.set_conversation_monitor(current_conversations);
        
        if (!current_conversations.is_monitoring)
            yield current_conversations.start_monitoring_async(FETCH_EMAIL_CHUNK_COUNT, conversation_cancellable);
        
        select_folder_mutex.release(ref mutex_token);
        
        set_busy(false);
    }
    
    private void on_scan_started() {
        set_busy(true);
    }
    
    private void on_scan_error(Error err) {
        set_busy(false);
    }
    
    private void on_scan_completed() {
        set_busy(false);
    }
    
    private void on_seed_completed() {
        // Done scanning.  Check if we have enough messages to fill the conversation list; if not,
        // trigger a load_more();
        if (!main_window.conversation_list_has_scrollbar()) {
            debug("Not enough messages, loading more for folder %s", current_folder.to_string());
            on_load_more();
        }
    }
    
    private void on_notification_bubble_invoked(Geary.Folder? folder, Geary.Email? email) {
        new_messages_monitor.clear_all_new_messages();
        
        if (folder == null || email == null)
            return;
        
        main_window.folder_list.select_folder(folder);
        Geary.Conversation? conversation = current_conversations.get_conversation_for_email(email.id);
        if (conversation != null)
            main_window.conversation_list_view.select_conversation(conversation);
    }
    
    private void on_indicator_activated_application(uint32 timestamp) {
        main_window.present_with_time(timestamp);
    }
    
    private void on_indicator_activated_composer(uint32 timestamp) {
        main_window.present_with_time(timestamp);
        on_new_message();
    }
    
    private void on_indicator_activated_inbox(Geary.Folder folder, uint32 timestamp) {
        main_window.present_with_time(timestamp);
        
        main_window.folder_list.select_folder(folder);
    }
    
    private void on_conversation_appended(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        if (is_viewed_conversation(conversation)) {
            do_show_message.begin(conversation.get_emails(Geary.Conversation.Ordering.NONE), cancellable_message,
                false, on_show_message_completed);
        }
    }
    
    private void on_conversation_trimmed(Geary.Conversation conversation, Geary.Email email) {
        if (is_viewed_conversation(conversation))
            main_window.conversation_viewer.remove_message(email);
    }
    
    private void on_load_more() {
        debug("on_load_more");
        Geary.EmailIdentifier? low_id = main_window.conversation_list_store.get_lowest_email_id();
        if (low_id == null)
            return;
        
        set_busy(true);
        current_conversations.load_by_id_async.begin(low_id, - FETCH_EMAIL_CHUNK_COUNT,
            Geary.Folder.ListFlags.EXCLUDING_ID, cancellable_folder, on_load_more_completed);
    }
    
    private void on_load_more_completed(Object? source, AsyncResult result) {
        debug("on load more completed");
        try {
            current_conversations.load_by_id_async.end(result);
        } catch (Error err) {
            debug("Error, unable to load conversations: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_email_flags_changed(Geary.Conversation conversation, Geary.Email email) {
        main_window.conversation_viewer.update_flags(email);
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
    
    private void on_conversations_selected(Gee.Set<Geary.Conversation> selected) {
        cancel_message();

        selected_conversations = selected;
        
        // Disable message buttons until conversation loads.
        enable_message_buttons(false);
        
        if (selected.size == 1 && current_folder != null) {
            Geary.Conversation conversation = Geary.Collection.get_first(selected);
            do_show_message.begin(conversation.get_emails(Geary.Conversation.Ordering.DATE_ASCENDING),
                cancellable_message, true, on_conversation_selected_completed);
        } else if (current_folder != null) {
            main_window.conversation_viewer.show_multiple_selected(selected.size);
            if (selected.size > 1) {
                enable_multiple_message_buttons();
            } else {
                enable_message_buttons(false);
            }
        }
    }
    
    private async void do_show_message(Gee.Collection<Geary.Email> messages, Cancellable? 
        cancellable = null, bool clear_view = true) throws Error {
        set_busy(true);
        
        // Clear view before we yield, to make sure it happens
        if (clear_view) {
            main_window.conversation_viewer.clear(current_folder, current_account.information);
            main_window.conversation_viewer.scroll_reset();
        }
        
        // Fetch full messages.
        Gee.Collection<Geary.Email> messages_to_add = new Gee.HashSet<Geary.Email>();
        foreach (Geary.Email email in messages) {
            Geary.Email.Field required_fields = ConversationViewer.REQUIRED_FIELDS |
                Geary.ComposedEmail.REQUIRED_REPLY_FIELDS;
            
            Geary.Email full_email;
            if (email.id.get_folder_path() == null) {
                full_email = yield current_folder.account.local_fetch_email_async(
                    email.id, required_fields, cancellable);
            } else {
                full_email = yield current_folder.fetch_email_async(email.id,
                    required_fields, Geary.Folder.ListFlags.NONE, cancellable);
            }
            
            if (cancellable.is_cancelled())
                throw new IOError.CANCELLED("do_select_message cancelled");
            
            messages_to_add.add(full_email);
        }
        
        // Add messages.  conversation_viewer.add_message only adds new messages
        foreach (Geary.Email email in messages_to_add)
            main_window.conversation_viewer.add_message(email);
        
        main_window.conversation_viewer.unhide_last_email();
        main_window.conversation_viewer.compress_emails();
    }
    
    private void on_show_message_completed(Object? source, AsyncResult result) {
        try {
            do_show_message.end(result);
            enable_message_buttons(true);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Unable to show message: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_conversation_selected_completed(Object? source, AsyncResult result) {
        on_show_message_completed(source, result);
        main_window.conversation_viewer.mark_read();
    }
    
    private void on_special_folder_type_changed(Geary.Folder folder, Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        main_window.folder_list.remove_folder(folder);
        main_window.folder_list.add_folder(folder);
    }
    
    private void on_engine_opened() {
        // Locate the first account so we can select its inbox when available.
        try {
            Gee.ArrayList<Geary.AccountInformation> all_accounts =
                new Gee.ArrayList<Geary.AccountInformation>();
            all_accounts.add_all(Geary.Engine.instance.get_accounts().values);
            if (all_accounts.size == 0) {
                debug("No accounts found.");
                return;
            }
            
            all_accounts.sort(Geary.AccountInformation.compare_ascending);
            account_to_select = Geary.Engine.instance.get_account_instance(all_accounts.get(0));
        } catch (Error e) {
            debug("Error selecting first inbox: %s", e.message);
        }
    }
    
    // Meant to be called inside the available block of on_folders_available_unavailable,
    // after we've located the first account.
    private Geary.Folder? get_initial_selection_folder(Geary.Folder folder_being_added) {
        if (folder_being_added.account == account_to_select &&
            !main_window.folder_list.is_any_selected() && inboxes.has_key(account_to_select)) {
            return inboxes.get(account_to_select);
        } else if (account_to_select == null) {
            // This is the first account being added, so select the inbox.
            return inboxes.get(folder_being_added.account);
        }
        
        return null;
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        if (available != null && available.size > 0) {
            foreach (Geary.Folder folder in available) {
                main_window.folder_list.add_folder(folder);
                if (folder.account == current_account) {
                    if (!main_window.main_toolbar.copy_folder_menu.has_folder(folder))
                        main_window.main_toolbar.copy_folder_menu.add_folder(folder);
                    if (!main_window.main_toolbar.move_folder_menu.has_folder(folder))
                        main_window.main_toolbar.move_folder_menu.add_folder(folder);
                }
                
                // monitor the Inbox for notifications
                if (folder.get_special_folder_type() == Geary.SpecialFolderType.INBOX &&
                    !inboxes.has_key(folder.account)) {
                    inboxes.set(folder.account, folder);
                    Geary.Folder? select_folder = get_initial_selection_folder(folder);
                    
                    if (select_folder != null) {
                        // First we try to select the Inboxes branch inbox if
                        // it's there, falling back to the main folder list.
                        if (!main_window.folder_list.select_inbox(select_folder.account))
                            main_window.folder_list.select_folder(select_folder);
                    }
                    
                    folder.open_async.begin(Geary.Folder.OpenFlags.NONE, inbox_cancellables.get(folder.account));
                    
                    new_messages_monitor.add_folder(folder, inbox_cancellables.get(folder.account));
                }
                
                folder.special_folder_type_changed.connect(on_special_folder_type_changed);
            }
        }
        
        if (unavailable != null) {
            foreach (Geary.Folder folder in unavailable) {
                if (folder.get_special_folder_type() == Geary.SpecialFolderType.INBOX &&
                    inboxes.has_key(folder.account)) {
                    new_messages_monitor.remove_folder(folder);
                }
            }
        }
    }
    
    private void cancel_folder() {
        Cancellable old_cancellable = cancellable_folder;
        cancellable_folder = new Cancellable();
        cancel_message();
        
        old_cancellable.cancel();
    }
    
    private void cancel_inbox(Geary.Account account) {
        if (!inbox_cancellables.has_key(account)) {
            debug("Unable to cancel inbox operation for %s", account.to_string());
            return;
        }
        
        Cancellable old_cancellable = inbox_cancellables.get(account);
        inbox_cancellables.set(account, new Cancellable());

        old_cancellable.cancel();
    }
    
    private void cancel_message() {
        Cancellable old_cancellable = cancellable_message;
        cancellable_message = new Cancellable();
        
        set_busy(false);
        
        old_cancellable.cancel();
    }
    
    // We need to include the second parameter, or valac doesn't recognize the function as matching
    // YorbaApplication.exiting's signature.
    private bool on_application_exiting(YorbaApplication sender, bool panicked) {
        if (close_composition_windows())
            return true;
        
        return sender.cancel_exit();
    }
    
    private void on_quit() {
        GearyApplication.instance.exit();
    }

    private void on_help() {
        try {
            if (GearyApplication.instance.is_installed()) {
                Gtk.show_uri(null, "ghelp:geary", Gdk.CURRENT_TIME);
            } else {
                Pid pid;
                File exec_dir = GearyApplication.instance.get_exec_dir();
                string[] argv = new string[3];
                argv[0] = "gnome-help";
                argv[1] = GearyApplication.SOURCE_ROOT_DIR + "/help/C/";
                argv[2] = null;
                if (!Process.spawn_async(exec_dir.get_path(), argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out pid)) {
                    debug("Failed to launch help locally.");
                }
            }
        } catch (Error error) {
            debug("Error showing help: %s", error.message);
            Gtk.Dialog dialog = new Gtk.Dialog.with_buttons("Error", null,
                Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.Stock.CLOSE, Gtk.ResponseType.CLOSE, null);
            dialog.response.connect(() => { dialog.destroy(); });
            dialog.get_content_area().add(new Gtk.Label("Error showing help: %s".printf(error.message)));
            dialog.show_all();
            dialog.run();
        }
    }

    private void on_about() {
        Gtk.show_about_dialog(main_window,
            "program-name", GearyApplication.NAME,
            "comments", GearyApplication.DESCRIPTION,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL,
            "title", _("About %s").printf(GearyApplication.NAME),
            /// Translators: add your name and email address to receive credit in the About dialog
            /// For example: Yamada Taro <yamada.taro@example.com>
            "translator-credits", _("translator-credits")
        );
    }
    
    // this signal does not necessarily indicate that the application previously didn't have
    // focus and now it does
    private void on_has_toplevel_focus() {
        clear_new_messages("on_has_toplevel_focus", null);
    }
    
    private void on_accounts() {
        AccountDialog dialog = new AccountDialog();
        dialog.run();
        dialog.destroy();
    }
    
    private void on_preferences() {
        PreferencesDialog dialog = new PreferencesDialog(GearyApplication.instance.config);
        dialog.run();
    }

    private Gee.List<Geary.EmailIdentifier> get_selected_folder_email_ids(
        bool preview_message_only = false) {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Conversation conversation in selected_conversations)
            ids.add_all(get_conversation_email_ids(conversation, true, preview_message_only));
        return ids;
    }
    
    private Gee.Collection<Geary.EmailIdentifier> get_conversation_email_ids(Geary.Conversation conversation,
        bool folder_email_ids_only = false, bool preview_message_only = false) {
        if (preview_message_only) {
            Gee.ArrayList<Geary.EmailIdentifier> id = new Gee.ArrayList<Geary.EmailIdentifier>();
            Geary.Email? preview_message = conversation.get_latest_email(folder_email_ids_only);
            if (preview_message != null)
                id.add(preview_message.id);
            return id;
        } else {
            return conversation.get_email_ids(folder_email_ids_only);
        }
    }

    private void mark_selected_conversations(Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, bool preview_message_only = false) {
        Geary.FolderSupport.Mark? supports_mark = current_folder as Geary.FolderSupport.Mark;
        if (supports_mark == null)
            return;
        
        // Mark the emails.
        Gee.List<Geary.EmailIdentifier> ids = get_selected_folder_email_ids(preview_message_only);
        if (ids.size > 0) {
            set_busy(true);
            supports_mark.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
                cancellable_message, on_mark_complete);
        }
    }

    private void on_show_mark_menu() {
        bool unread_selected = false;
        bool read_selected = false;
        bool starred_selected = false;
        bool unstarred_selected = false;
        foreach (Geary.Conversation conversation in selected_conversations) {
            if (conversation.is_unread())
                unread_selected = true;
            if (conversation.has_any_read_message())
                read_selected = true;

            if (conversation.is_flagged()) {
                starred_selected = true;
            } else {
                unstarred_selected = true;
            }
        }
        var actions = GearyApplication.instance.actions;
        actions.get_action(ACTION_MARK_AS_READ).set_visible(unread_selected);
        actions.get_action(ACTION_MARK_AS_UNREAD).set_visible(read_selected);
        actions.get_action(ACTION_MARK_AS_STARRED).set_visible(unstarred_selected);
        actions.get_action(ACTION_MARK_AS_UNSTARRED).set_visible(starred_selected);
        
        Geary.Folder? spam_folder = null;
        try {
            spam_folder = current_account.get_special_folder(Geary.SpecialFolderType.SPAM);
        } catch (Error e) {
            debug("Could not locate special spam folder: %s", e.message);
        }
        
        if (spam_folder != null &&
            current_folder.get_special_folder_type() != Geary.SpecialFolderType.DRAFTS &&
            current_folder.get_special_folder_type() != Geary.SpecialFolderType.OUTBOX) {
            if (current_folder.get_special_folder_type() == Geary.SpecialFolderType.SPAM) {
                // We're in the spam folder.
                actions.get_action(ACTION_MARK_AS_SPAM).sensitive = true;
                actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_NOT_SPAM_LABEL;
            } else {
                // We're not in the spam folder, but we are in a folder that allows mark-as-spam.
                actions.get_action(ACTION_MARK_AS_SPAM).sensitive = true;
                actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_SPAM_LABEL;
            }
        } else {
            // No Spam folder, or we're in Drafts/Outbox, so gray-out the option.
            actions.get_action(ACTION_MARK_AS_SPAM).sensitive = false;
            actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_SPAM_LABEL;
        }
    }
    
    private void on_visible_conversations_changed(Gee.Set<Geary.Conversation> visible) {
        clear_new_messages("on_visible_conversations_changed", visible);
    }
    
    private bool should_notify_new_messages(Geary.Folder folder) {
        // A monitored folder must be selected to squelch notifications;
        // if conversation list is at top of display, don't display
        // and don't display if main window has top-level focus
        return folder != current_folder
            || main_window.conversation_list_view.vadjustment.value != 0.0
            || !main_window.has_toplevel_focus;
    }
    
    // Clears messages if conditions are true: anything in should_notify_new_messages() is
    // false and the supplied visible messages are visible in the conversation list view
    private void clear_new_messages(string caller, Gee.Set<Geary.Conversation>? supplied) {
        if (current_folder == null || !new_messages_monitor.get_folders().contains(current_folder)
            || should_notify_new_messages(current_folder))
            return;
        
        Gee.Set<Geary.Conversation> visible =
            supplied ?? main_window.conversation_list_view.get_visible_conversations();
        
        foreach (Geary.Conversation conversation in visible) {
            if (new_messages_monitor.are_any_new_messages(current_folder, conversation.get_email_ids())) {
                debug("Clearing new messages: %s", caller);
                new_messages_monitor.clear_new_messages(current_folder);
                
                break;
            }
        }
    }
    
    private void on_mark_conversation(Geary.Conversation conversation,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview = false) {
        Geary.FolderSupport.Mark? supports_mark = current_folder as Geary.FolderSupport.Mark;
        if (supports_mark == null)
            return;
        
        Gee.Collection<Geary.EmailIdentifier> ids
            = get_conversation_email_ids(conversation, true, only_mark_preview);
        if (ids.size > 0) {
            set_busy(true);
            supports_mark.mark_email_async.begin(Geary.Collection.to_array_list<Geary.EmailIdentifier>(ids),
                flags_to_add, flags_to_remove, cancellable_message, on_mark_complete);
        }
    }

    private void on_conversation_viewer_mark_message(Geary.Email message, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove) {
        Geary.FolderSupport.Mark? supports_mark = current_folder as Geary.FolderSupport.Mark;
        if (supports_mark == null)
            return;
        
        set_busy(true);
        supports_mark.mark_single_email_async.begin(message.id, flags_to_add, flags_to_remove,
            cancellable_message, on_mark_complete);
    }
    
    private void on_mark_as_read() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_selected_conversations(null, flags);
        foreach (Geary.EmailIdentifier id in get_selected_folder_email_ids())
            main_window.conversation_viewer.mark_manual_read(id);
    }

    private void on_mark_as_unread() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_selected_conversations(flags, null);
        foreach (Geary.EmailIdentifier id in get_selected_folder_email_ids())
            main_window.conversation_viewer.mark_manual_read(id);
    }

    private void on_mark_as_starred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_selected_conversations(flags, null, true);
    }

    private void on_mark_as_unstarred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_selected_conversations(null, flags);
    }
    
    private void on_mark_complete() {
        set_busy(false);
    }
    
    private void on_mark_as_spam() {
        Geary.Folder? destination_folder = null;
        if (current_folder.get_special_folder_type() != Geary.SpecialFolderType.SPAM) {
            // Move to spam folder.
            try {
                destination_folder = current_account.get_special_folder(Geary.SpecialFolderType.SPAM);
            } catch (Error e) {
                debug("Error getting spam folder: %s", e.message);
            }
        } else {
            // Move out of spam folder, back to inbox.
            try {
                destination_folder = current_account.get_special_folder(Geary.SpecialFolderType.INBOX);
            } catch (Error e) {
                debug("Error getting inbox folder: %s", e.message);
            }
        }
        
        if (destination_folder != null)
            on_move_conversation(destination_folder);
    }
    
    private void on_copy_conversation(Geary.Folder destination) {
        // Nothing to do if nothing selected.
        if (selected_conversations == null || selected_conversations.size == 0)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_folder_email_ids();
        if (ids.size == 0)
            return;
        
        Geary.FolderSupport.Copy? supports_copy = current_folder as Geary.FolderSupport.Copy;
        if (supports_copy == null)
            return;
        
        set_busy(true);
        supports_copy.copy_email_async.begin(ids, destination.get_path(), cancellable_message,
            on_copy_complete);
    }

    private void on_copy_complete() {
        set_busy(false);
    }

    private void on_move_conversation(Geary.Folder destination) {
        // Nothing to do if nothing selected.
        if (selected_conversations == null || selected_conversations.size == 0)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_folder_email_ids();
        if (ids.size == 0)
            return;
        
        Geary.FolderSupport.Move? supports_move = current_folder as Geary.FolderSupport.Move;
        if (supports_move == null)
            return;
        
        set_busy(true);
        supports_move.move_email_async.begin(ids, destination.get_path(), cancellable_message,
            on_move_complete);
    }

    private void on_move_complete() {
        set_busy(false);
    }

    private void on_open_attachment(Geary.Attachment attachment) {
        if (GearyApplication.instance.config.ask_open_attachment) {
            QuestionDialog ask_to_open = new QuestionDialog.with_checkbox(main_window,
                _("Are you sure you want to open \"%s\"?").printf(attachment.filename),
                _("Attachments may cause damage to your system if opened.  Only open files from trusted sources."),
                Gtk.Stock.OPEN, Gtk.Stock.CANCEL, _("Don't _ask me again"), false);
            if (ask_to_open.run() != Gtk.ResponseType.OK)
                return;
            
            // only save checkbox state if OK was selected
            GearyApplication.instance.config.ask_open_attachment = !ask_to_open.is_checked;
        }
        
        open_uri("file://" + attachment.filepath);
    }
    
    private bool do_overwrite_confirmation(File to_overwrite) {
        string primary = _("A file named \"%s\" already exists.  Do you want to replace it?").printf(
            to_overwrite.get_basename());
        string secondary = _("The file already exists in \"%s\".  Replacing it will overwrite its contents.").printf(
            to_overwrite.get_parent().get_basename());
        
        ConfirmationDialog dialog = new ConfirmationDialog(main_window, primary, secondary, _("_Replace"));
        
        return (dialog.run() == Gtk.ResponseType.OK);
    }
    
    private Gtk.FileChooserConfirmation on_confirm_overwrite(Gtk.FileChooser chooser) {
        // this is only called when choosing one file
        return do_overwrite_confirmation(chooser.get_file()) ? Gtk.FileChooserConfirmation.ACCEPT_FILENAME
            : Gtk.FileChooserConfirmation.SELECT_AGAIN;
    }
    
    private void on_save_attachments(Gee.List<Geary.Attachment> attachments) {
        if (attachments.size == 0)
            return;
        
        Gtk.FileChooserAction action = (attachments.size == 1)
            ? Gtk.FileChooserAction.SAVE
            : Gtk.FileChooserAction.SELECT_FOLDER;
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(null, main_window, action,
            Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT, null);
        if (last_save_directory != null)
            dialog.set_current_folder(last_save_directory.get_path());
        if (attachments.size == 1) {
            dialog.set_current_name(attachments[0].filename);
            dialog.set_do_overwrite_confirmation(true);
            // use custom overwrite confirmation so it looks consistent whether one or many
            // attachments are being saved
            dialog.confirm_overwrite.connect(on_confirm_overwrite);
        }
        dialog.set_create_folders(true);
        dialog.set_local_only(false);
        
        bool accepted = (dialog.run() == Gtk.ResponseType.ACCEPT);
        File destination = File.new_for_path(dialog.get_filename());
        
        dialog.destroy();
        
        if (!accepted)
            return;
        
        // Proceeding, save this as last destination directory
        last_save_directory = (attachments.size == 1) ? destination.get_parent() : destination;
        
        debug("Saving attachments to %s", destination.get_path());
        
        // Save each one, checking for overwrite only if multiple attachments are being written
        foreach (Geary.Attachment attachment in attachments) {
            File source_file = File.new_for_path(attachment.filepath);
            File dest_file = (attachments.size == 1) ? destination : destination.get_child(attachment.filename);
            
            if (attachments.size > 1 && dest_file.query_exists() && !do_overwrite_confirmation(dest_file))
                return;
            
            debug("Copying %s to %s...", source_file.get_path(), dest_file.get_path());
            
            source_file.copy_async.begin(dest_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null,
                null, on_save_completed);
        }
    }
    
    private void on_save_completed(Object? source, AsyncResult result) {
        try {
            ((File) source).copy_async.end(result);
        } catch (Error error) {
            warning("Failed to copy attachment %s to destination: %s", ((File) source).get_path(),
                error.message);
        }
    }

    // Opens a link in an external browser.
    private void open_uri(string _link) {
        string link = _link;
        
        // Support web URLs that ommit the protocol.
        if (!link.contains(":"))
            link = "http://" + link;
        
        try {
            Gtk.show_uri(main_window.get_screen(), link, Gdk.CURRENT_TIME);
        } catch (Error err) {
            debug("Unable to open URL. %s", err.message);
        }
    }
    
    private bool close_composition_windows() {
        // We want to allow the user to cancel a quit when they have unsent text.
        
        // We are modifying the list as we go, so we can't simply iterate through it.
        while (composer_widgets.size > 0) {
            ComposerWidget composer_widget = composer_widgets.first();
            if (!composer_widget.should_close())
                return false;
            
            // This will remove composer_window from composer_windows.
            // See GearyController.on_composer_widget_destroy.
            composer_widget.close();
        }
        
        // If we deleted all composer windows without the user cancelling, we can exit.
        return true;
    }
    
    private void create_compose_widget(ComposerWidget.ComposeType compose_type,
        Geary.Email? referred = null, string? mailto = null) {
        if (current_account == null)
            return;
        
        ComposerWidget widget;
        if (mailto != null)
            widget = new ComposerWidget.from_mailto(current_account, mailto);
        else
            widget = new ComposerWidget(current_account, compose_type, referred);
        widget.send.connect(on_send);
        
        // We want to keep track of the open composer windows, so we can allow the user to cancel
        // an exit without losing their data.
        composer_widgets.add(widget);
        widget.destroy.connect(on_composer_widget_destroy);
    }
    
    private void on_composer_widget_destroy(Gtk.Widget sender) {
        composer_widgets.remove((ComposerWidget) sender);
    }
    
    private void on_new_message() {
        create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE);
    }
    
    private void on_reply_to_message(Geary.Email message) {
        create_compose_widget(ComposerWidget.ComposeType.REPLY, message);
    }
    
    private void on_reply_to_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_reply_to_message(message);
    }
    
    private void on_reply_all_message(Geary.Email message) {
        create_compose_widget(ComposerWidget.ComposeType.REPLY_ALL, message);
    }
    
    private void on_reply_all_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_reply_all_message(message);
    }
    
    private void on_forward_message(Geary.Email message) {
        create_compose_widget(ComposerWidget.ComposeType.FORWARD, message);
    }
    
    private void on_forward_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_forward_message(message);
    }
    
    private void on_find_in_conversation_action() {
            main_window.conversation_viewer.show_find_bar();
    }
    
    private void on_find_next_in_conversation_action() {
            main_window.conversation_viewer.find(true);
    }
    
    private void on_find_previous_in_conversation_action() {
            main_window.conversation_viewer.find(false);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder
    private void on_delete_message() {
        // Prevent deletes of the same conversation from repeating.
        if (is_viewed_conversation(last_deleted_conversation)) {
            debug("not archiving/deleting, viewed conversation is last deleted conversation");
            
            return;
        }
        
        // There should always be at least one conversation selected here, otherwise the archive
        // button is disabled, but better safe than segfaulted.
        last_deleted_conversation = selected_conversations.size > 0
            ? Geary.Collection.get_first<Geary.Conversation>(selected_conversations) : null;

        // If the user clicked the toolbar button, we want to move focus back to the message list.
        main_window.conversation_list_view.grab_focus();
        set_busy(true);
        
        delete_messages.begin(get_selected_folder_email_ids(), cancellable_folder, on_delete_messages_completed);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder.  This will try archiving first, then remove.
    private async void delete_messages(Gee.List<Geary.EmailIdentifier> ids, Cancellable? cancellable)
        throws Error {
        Geary.FolderSupport.Archive? supports_archive = current_folder as Geary.FolderSupport.Archive;
        if (supports_archive != null) {
            yield supports_archive.archive_email_async(ids, cancellable);
            
            return;
        }
        
        Geary.FolderSupport.Remove? supports_remove = current_folder as Geary.FolderSupport.Remove;
        if (supports_remove != null) {
            yield supports_remove.remove_email_async(ids, cancellable);
            
            return;
        }
        
        debug("Folder %s supports neither remove nor archive", current_folder.to_string());
    }

    private void on_delete_messages_completed(Object? source, AsyncResult result) {
        try {
            delete_messages.end(result);
        } catch (Error err) {
            debug("Error, unable to delete messages: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_zoom_in() {
        main_window.conversation_viewer.web_view.zoom_in();
    }

    private void on_zoom_out() {
        main_window.conversation_viewer.web_view.zoom_out();
    }

    private void on_zoom_normal() {
        main_window.conversation_viewer.web_view.zoom_level = 1.0f;
    }
    
    private void on_send(ComposerWidget composer_widget) {
        composer_widget.account.send_email_async.begin(composer_widget.get_composed_email());
        composer_widget.close();
    }

    private void on_sent(Geary.RFC822.Message rfc822) {
        NotificationBubble.play_sound("message-sent-email");
    }
    
    public void set_busy(bool is_busy) {
        busy_count += is_busy ? 1 : -1;
        if (busy_count < 0)
            busy_count = 0;
        
        main_window.set_busy(busy_count > 0);
    }

    private void on_link_selected(string link) {
        if (link.down().has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            compose_mailto(link);
        } else {
            open_uri(link);
        }
    }

    // Disables all single-message buttons and enables all multi-message buttons.
    public void enable_multiple_message_buttons() {
        update_tooltips();
        
        // Single message only buttons.
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = false;

        // Mutliple message buttons.
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive =
            (current_folder is Geary.FolderSupport.Remove) || (current_folder is Geary.FolderSupport.Archive);
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive =
            current_folder is Geary.FolderSupport.Mark;
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).sensitive =
            current_folder is Geary.FolderSupport.Copy;
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            current_folder is Geary.FolderSupport.Move;
    }

    // Enables or disables the message buttons on the toolbar.
    public void enable_message_buttons(bool sensitive) {
        update_tooltips();
        
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = sensitive
            && ((current_folder is Geary.FolderSupport.Remove) || (current_folder is Geary.FolderSupport.Archive));
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupport.Mark);
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupport.Copy);
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupport.Move);
    }
    
    // Updates tooltip text depending on number of conversations selected.
    private void update_tooltips() {
        bool single = selected_conversations.size == 1;
        
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).tooltip = single ?
            MARK_MESSAGE_MENU_TOOLTIP_SINGLE : MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).tooltip = single ?
            LABEL_MESSAGE_TOOLTIP_SINGLE : LABEL_MESSAGE_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).tooltip = single ?
            MOVE_MESSAGE_TOOLTIP_SINGLE : MOVE_MESSAGE_TOOLTIP_MULTIPLE;
        
        if (current_folder is Geary.FolderSupport.Archive) {
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip = single ?
                ARCHIVE_MESSAGE_TOOLTIP_SINGLE : ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE;
        } else {
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip = single ?
                DELETE_MESSAGE_TOOLTIP_SINGLE : DELETE_MESSAGE_TOOLTIP_MULTIPLE;
        }
    }
    
    public void compose_mailto(string mailto) {
        create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE, null, mailto);
    }
    
    // Returns a list of composer windows for an account, or null if none.
    public Gee.List<ComposerWidget>? get_composer_widgets_for_account(Geary.AccountInformation account) {
        Gee.List<ComposerWidget> ret = new Gee.LinkedList<ComposerWidget>();
        foreach (ComposerWidget cw in composer_widgets) {
            if (cw.account.information == account)
                ret.add(cw);
        }
        
        return ret.size >= 1 ? ret : null;
    }
}

