/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationListView : Gtk.TreeView {
    const int LOAD_MORE_HEIGHT = 100;
    
    private bool enable_load_more = true;
    
    // Used to avoid repeated calls to load_more(). Contains the last "upper" bound of the
    // scroll adjustment seen at the call to load_more().
    private double last_upper = -1.0;
    private bool reset_adjustment = false;
    private Gee.Set<Geary.Conversation> selected = new Gee.HashSet<Geary.Conversation>();
    private ConversationListStore conversation_list_store;
    private Geary.ConversationMonitor? conversation_monitor;
    private Gee.Set<Geary.Conversation>? current_visible_conversations = null;
    private Geary.Scheduler.Scheduled? scheduled_update_visible_conversations = null;
    private Gtk.Menu? context_menu = null;
    
    public signal void conversations_selected(Gee.Set<Geary.Conversation> selected);
    
    public virtual signal void load_more() {
        enable_load_more = false;
    }
    
    public signal void mark_conversation(Geary.Conversation conversation,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview);
    
    public signal void visible_conversations_changed(Gee.Set<Geary.Conversation> visible);
    
    public ConversationListView(ConversationListStore conversation_list_store) {
        this.conversation_list_store = conversation_list_store;
        set_model(conversation_list_store);
        
        set_show_expanders(false);
        set_headers_visible(false);
        enable_grid_lines = Gtk.TreeViewGridLines.HORIZONTAL;
        
        append_column(create_column(ConversationListStore.Column.CONVERSATION_DATA,
            new ConversationListCellRenderer(), ConversationListStore.Column.CONVERSATION_DATA.to_string(),
            0));
        
        Gtk.TreeSelection selection = get_selection();
        selection.changed.connect(on_selection_changed);
        selection.set_mode(Gtk.SelectionMode.MULTIPLE);
        style_set.connect(on_style_changed);
        show.connect(on_show);
        
        get_model().row_inserted.connect(on_rows_changed);
        get_model().rows_reordered.connect(on_rows_changed);
        get_model().row_changed.connect(on_rows_changed);
        get_model().row_deleted.connect(on_rows_changed);
        get_model().row_deleted.connect(on_row_deleted);
        
        conversation_list_store.conversations_added_began.connect(on_conversations_added_began);
        conversation_list_store.conversations_added_finished.connect(on_conversations_added_finished);
        button_press_event.connect(on_button_press);

        // Set up drag and drop.
        Gtk.drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, FolderList.Tree.TARGET_ENTRY_LIST,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
    }
    
    public void set_conversation_monitor(Geary.ConversationMonitor? new_conversation_monitor) {
        if (conversation_monitor != null) {
            conversation_monitor.scan_started.disconnect(on_scan_started);
            conversation_monitor.scan_completed.disconnect(on_scan_completed);
            conversation_monitor.conversation_removed.disconnect(on_conversation_removed);
        }
        
        conversation_monitor = new_conversation_monitor;
        
        if (conversation_monitor != null) {
            conversation_monitor.scan_started.connect(on_scan_started);
            conversation_monitor.scan_completed.connect(on_scan_completed);
            conversation_monitor.conversation_removed.connect(on_conversation_removed);
        }
    }
    
    private void on_scan_started() {
        enable_load_more = false;
    }
    
    private void on_scan_completed() {
        enable_load_more = true;
        
        // Select first conversation.
        if (GearyApplication.instance.config.autoselect)
            select_first_conversation();
    }
    
    private void on_conversation_removed(Geary.Conversation conversation) {
        if (!GearyApplication.instance.config.autoselect)
            unselect_all();
    }
    
    private void on_conversations_added_began() {
        Gtk.Adjustment? adjustment = get_adjustment();
        // If we were at the top, we want to stay there after conversations are added.
        reset_adjustment = adjustment != null && adjustment.get_value() == 0;
    }
    
    private void on_conversations_added_finished() {
        if (!reset_adjustment)
            return;
        
        Gtk.Adjustment? adjustment = get_adjustment();
        if (adjustment == null)
            return;
        
        adjustment.set_value(0);
    }
    
    private Gtk.Adjustment? get_adjustment() {
        Gtk.ScrolledWindow? parent = get_parent() as Gtk.ScrolledWindow;
        if (parent == null) {
            debug("Parent was not scrolled window");
            return null;
        }
        
        return parent.get_vadjustment();
    }

    private bool on_button_press(Gdk.EventButton event) {
        // Get the coordinates on the cell as well as the clicked path.
        int cell_x;
        int cell_y;
        Gtk.TreePath? path;
        get_path_at_pos((int) event.x, (int) event.y, out path, null, out cell_x, out cell_y);
        
        // If the user clicked in an empty area, do nothing.
        if (path == null)
            return false;
        
        // If this is an unmodified click in the top-left of the cell, it is a star-click.
        if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0 &&
            (event.state & Gdk.ModifierType.CONTROL_MASK) == 0 &&
            event.type == Gdk.EventType.BUTTON_PRESS && cell_x < 25 && cell_y < 25) {
            
            Geary.Conversation conversation = conversation_list_store.get_conversation_at_path(path);
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.FLAGGED);
            if (conversation.is_flagged()) {
                mark_conversation(conversation, null, flags, false);
            } else {
                mark_conversation(conversation, flags, null, true);
            }
            return true;
        }
        
        if (!get_selection().path_is_selected(path) && !((MainWindow) GearyApplication.
            instance.controller.main_window).composer_embed.abandon_existing_composition())
            return true;
        
        if (event.button == 3 && event.type == Gdk.EventType.BUTTON_PRESS) {
            Geary.Conversation conversation = conversation_list_store.get_conversation_at_path(path);
            
            string?[] action_names = {};
            action_names += GearyController.ACTION_DELETE_MESSAGE;
            
            if (conversation.is_unread())
                action_names += GearyController.ACTION_MARK_AS_READ;
            
            if (conversation.has_any_read_message())
                action_names += GearyController.ACTION_MARK_AS_UNREAD;
            
            if (conversation.is_flagged())
                action_names += GearyController.ACTION_MARK_AS_UNSTARRED;
            else
                action_names += GearyController.ACTION_MARK_AS_STARRED;
            
            // treat null as separator
            action_names += null;
            action_names += GearyController.ACTION_REPLY_TO_MESSAGE;
            action_names += GearyController.ACTION_REPLY_ALL_MESSAGE;
            action_names += GearyController.ACTION_FORWARD_MESSAGE;
            
            context_menu = new Gtk.Menu();
            foreach (string? action_name in action_names) {
                if (action_name == null) {
                    context_menu.add(new Gtk.SeparatorMenuItem());
                    
                    continue;
                }
                
                Gtk.Action? menu_action = GearyApplication.instance.actions.get_action(action_name);
                if (menu_action != null)
                    context_menu.add(menu_action.create_menu_item());
            }
            
            context_menu.show_all();
            context_menu.popup(null, null, null, event.button, event.time);
            
            return false;
        }
        
        return false;
    }

    private void on_style_changed() {
        // Recalculate dimensions of child cells.
        ConversationListCellRenderer.style_changed(this);
        
        schedule_visible_conversations_changed();
    }
    
    private void on_show() {
        // Wait until we're visible to set this signal up.
        ((Gtk.Scrollable) this).get_vadjustment().value_changed.connect(on_value_changed);
    }
    
    private void on_value_changed() {
        if (!enable_load_more)
            return;
        
        // Check if we're at the very bottom of the list. If we are, it's time to
        // issue a load_more signal.
        Gtk.Adjustment adjustment = ((Gtk.Scrollable) this).get_vadjustment();
        double upper = adjustment.get_upper();
        if (adjustment.get_value() >= upper - adjustment.page_size - LOAD_MORE_HEIGHT &&
            upper > last_upper) {
            load_more();
            last_upper = upper;
        }
        
        schedule_visible_conversations_changed();
    }
    
    private static Gtk.TreeViewColumn create_column(ConversationListStore.Column column,
        Gtk.CellRenderer renderer, string attr, int width = 0) {
        Gtk.TreeViewColumn view_column = new Gtk.TreeViewColumn.with_attributes(column.to_string(),
            renderer, attr, column);
        view_column.set_resizable(true);
        
        if (width != 0) {
            view_column.set_sizing(Gtk.TreeViewColumnSizing.FIXED);
            view_column.set_fixed_width(width);
        }
        
        return view_column;
    }
    
    private List<Gtk.TreePath> get_all_selected_paths() {
        Gtk.TreeModel model;
        return get_selection().get_selected_rows(out model);
    }
    
    private Gtk.TreePath? get_selected_path() {
        return get_all_selected_paths().nth_data(0);
    }
    
    // Gtk.TreeSelection can fire its "changed" signal even when nothing's changed, so look for that
    // and prevent to avoid subscribers from doing the same things multiple times
    private void on_selection_changed() {
        List<Gtk.TreePath> paths = get_all_selected_paths();
        if (paths.length() == 0) {
            // only notify if this is different than what was previously reported
            if (selected.size != 0) {
                selected.clear();
                conversations_selected(selected.read_only_view);
            }
            
            return;
        }
        
        // Conversations are selected, so collect them and signal if different
        Gee.HashSet<Geary.Conversation> new_selected = new Gee.HashSet<Geary.Conversation>();
        foreach (Gtk.TreePath path in paths) {
            Geary.Conversation? conversation = conversation_list_store.get_conversation_at_path(path);
            if (conversation != null)
                new_selected.add(conversation);
        }
        
        // only notify if different than what was previously reported
        if (!Geary.Collection.are_sets_equal<Geary.Conversation>(selected, new_selected)) {
            selected = new_selected;
            conversations_selected(selected.read_only_view);
        }
    }
    
    public Gee.Set<Geary.Conversation> get_visible_conversations() {
        Gee.HashSet<Geary.Conversation> visible_conversations = new Gee.HashSet<Geary.Conversation>();
        
        Gtk.TreePath start_path;
        Gtk.TreePath end_path;
        if (!get_visible_range(out start_path, out end_path))
            return visible_conversations;
        
        while (start_path.compare(end_path) <= 0) {
            Geary.Conversation? conversation = conversation_list_store.get_conversation_at_path(start_path);
            if (conversation != null)
                visible_conversations.add(conversation);
            
            start_path.next();
        }
        
        return visible_conversations;
    }
    
    public Gee.Set<Geary.Conversation> get_selected_conversations() {
        Gee.HashSet<Geary.Conversation> selected_conversations = new Gee.HashSet<Geary.Conversation>();
        
        foreach (Gtk.TreePath path in get_all_selected_paths()) {
            Geary.Conversation? conversation = conversation_list_store.get_conversation_at_path(path);
            if (path != null)
                selected_conversations.add(conversation);
        }
        
        return selected_conversations;
    }
    
    // Always returns false, so it can be used as a one-time SourceFunc
    private bool update_visible_conversations() {
        Gee.Set<Geary.Conversation> visible_conversations = get_visible_conversations();
        if (current_visible_conversations != null
            && Geary.Collection.are_sets_equal<Geary.Conversation>(current_visible_conversations, visible_conversations)) {
            return false;
        }
        
        current_visible_conversations = visible_conversations;
        
        visible_conversations_changed(current_visible_conversations.read_only_view);
        
        return false;
    }
    
    private void schedule_visible_conversations_changed() {
        scheduled_update_visible_conversations = Geary.Scheduler.on_idle(update_visible_conversations);
    }
    
    // Selects the first conversation, if nothing has been selected yet and we're not composing.
    public void select_first_conversation() {
        if (get_selected_path() == null && !((MainWindow) GearyApplication.instance.
            controller.main_window).composer_embed.is_active) {
            set_cursor(new Gtk.TreePath.from_indices(0, -1), null, false);
        }
    }

    public void select_conversation(Geary.Conversation conversation) {
        Gtk.TreePath path = conversation_list_store.get_path_for_conversation(conversation);
        if (path != null)
            set_cursor(path, null, false);
    }
    
    public void select_conversations(Gee.Set<Geary.Conversation> conversations) {
        Gtk.TreeSelection selection = get_selection();
        foreach (Geary.Conversation conversation in conversations) {
            Gtk.TreePath path = conversation_list_store.get_path_for_conversation(conversation);
            if (path != null)
                selection.select_path(path);
        }
    }
    
    private void on_row_deleted(Gtk.TreePath path) {
        // if one or more rows are deleted in the model, reset the last upper limit so scrolling to
        // the bottom will always activate a reload (this is particularly important if the model
        // is cleared)
        last_upper = -1.0;
    }
    
    private void on_rows_changed() {
        schedule_visible_conversations_changed();
    }
    
    private void on_display_preview_changed() {
        style_set(null);
        model.foreach(refresh_path);
        
        schedule_visible_conversations_changed();
    }
    
    private bool refresh_path(Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
        model.row_changed(path, iter);
        return false;
    }
}

