/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Widget for sending messages.
public class ComposerWidget : Gtk.EventBox {
    public enum ComposeType {
        NEW_MESSAGE,
        REPLY,
        REPLY_ALL,
        FORWARD
    }
    
    private const string ACTION_UNDO = "undo";
    private const string ACTION_REDO = "redo";
    private const string ACTION_CUT = "cut";
    private const string ACTION_COPY = "copy";
    private const string ACTION_COPY_LINK = "copy link";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_PASTE_FORMAT = "paste with formatting";
    private const string ACTION_BOLD = "bold";
    private const string ACTION_ITALIC = "italic";
    private const string ACTION_UNDERLINE = "underline";
    private const string ACTION_STRIKETHROUGH = "strikethrough";
    private const string ACTION_REMOVE_FORMAT = "removeformat";
    private const string ACTION_INDENT = "indent";
    private const string ACTION_OUTDENT = "outdent";
    private const string ACTION_JUSTIFY_LEFT = "justifyleft";
    private const string ACTION_JUSTIFY_RIGHT = "justifyright";
    private const string ACTION_JUSTIFY_CENTER = "justifycenter";
    private const string ACTION_JUSTIFY_FULL = "justifyfull";
    private const string ACTION_MENU = "menu";
    private const string ACTION_COLOR = "color";
    private const string ACTION_INSERT_LINK = "insertlink";
    private const string ACTION_COMPOSE_AS_HTML = "compose as html";
    private const string ACTION_CLOSE = "close";
    
    private const string URI_LIST_MIME_TYPE = "text/uri-list";
    private const string FILE_URI_PREFIX = "file://";
    private const string BODY_ID = "message-body";
    private const string HTML_BODY = """
        <html><head><title></title>
        <style>
        body {
            margin: 10px !important;
            padding: 0 !important;
            background-color: white !important;
            font-size: medium !important;
        }
        body.plain, body.plain * {
            font-family: monospace !important;
            font-weight: normal;
            font-style: normal;
            font-size: 10pt;
            color: black;
            text-decoration: none;
        }
        body.plain a {
            cursor: text;
        }
        blockquote {
            margin-top: 0px;
            margin-bottom: 0px;
            margin-left: 10px;
            margin-right: 10px;
            padding-left: 5px;
            padding-right: 5px;
            background-color: white;
            border: 0;
            border-left: 3px #aaa solid;
        }
        pre {
            white-space: pre-wrap;
            margin: 0;
        }
        </style>
        </head><body id="message-body"></body></html>""";
    
    // Signal sent when the "Send" button is clicked.
    public signal void send(ComposerWidget composer);
    
    public Geary.Account account { get; private set; }
    
    public string from { get; set; }
    
    public string to {
        get { return to_entry.get_text(); }
        set { to_entry.set_text(value); }
    }
    
    public string cc {
        get { return cc_entry.get_text(); }
        set { cc_entry.set_text(value); }
    }
    
    public string bcc {
        get { return bcc_entry.get_text(); }
        set { bcc_entry.set_text(value); }
    }
    
    public string in_reply_to { get; set; }
    public string references { get; set; }
    
    public string subject {
        get { return subject_entry.get_text(); }
        set { subject_entry.set_text(value); }
    }
    
    public string message {
        owned get { return get_html(); }
        set {
            body_html = value;
            editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        }
    }
    
    public bool compose_as_html {
        get { return ((Gtk.ToggleAction) actions.get_action(ACTION_COMPOSE_AS_HTML)).active; }
        set { ((Gtk.ToggleAction) actions.get_action(ACTION_COMPOSE_AS_HTML)).active = value; }
    }
    
    public ComposeType compose_type { get; private set; default = ComposeType.NEW_MESSAGE; }
    
    private string? body_html = null;
    private Gee.Set<File> attachment_files = new Gee.HashSet<File>(Geary.Files.nullable_hash,
        Geary.Files.nullable_equal);
    
    private Gtk.Builder builder;
    private Gtk.Label from_label;
    private Gtk.Label from_single;
    private Gtk.ComboBoxText from_multiple = new Gtk.ComboBoxText();
    private EmailEntry to_entry;
    private EmailEntry cc_entry;
    private EmailEntry bcc_entry;
    public Gtk.Entry subject_entry;
    private Gtk.Button discard_button;
    private Gtk.Button send_button;
    private Gtk.ToggleToolButton menu_button;
    private Gtk.Label message_overlay_label;
    private WebKit.DOM.Element? prev_selected_link = null;
    private Gtk.Box attachments_box;
    private Gtk.Button add_attachment_button;
    private Gtk.Button pending_attachments_button;
    private Gtk.Alignment hidden_on_attachment_drag_over;
    private Gtk.Alignment visible_on_attachment_drag_over;
    private Gtk.Widget hidden_on_attachment_drag_over_child;
    private Gtk.Widget visible_on_attachment_drag_over_child;
    
    private Gtk.Menu menu_html;
    private Gtk.Menu menu_plain;
    private Gtk.RadioMenuItem font_small;
    private Gtk.RadioMenuItem font_medium;
    private Gtk.RadioMenuItem font_large;
    private Gtk.RadioMenuItem font_sans;
    private Gtk.RadioMenuItem font_serif;
    private Gtk.RadioMenuItem font_monospace;
    
    private Gtk.ActionGroup actions;
    private string? hover_url = null;
    private bool action_flag = false;
    private bool is_attachment_overlay_visible = false;
    private Gee.List<Geary.Attachment>? pending_attachments = null;
    private string? current_folder = null;
    
    private WebKit.WebView editor;
    // We need to keep a reference to the edit-fixer in composer-window, so it doesn't get
    // garbage-collected.
    private WebViewEditFixer edit_fixer;
    public Gtk.UIManager ui;
    private ComposerContainer container {
        get { return (ComposerContainer) parent; }
    }
    
    public ComposerWidget(Geary.Account account, ComposeType compose_type,
        Geary.Email? referred = null) {
        this.account = account;
        this.compose_type = compose_type;
        
        setup_drag_destination(this);
        
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);
        builder = GearyApplication.instance.create_builder("composer.glade");
        
        // Add the content-view style class for the elementary GTK theme.
        Gtk.Box button_area = (Gtk.Box) builder.get_object("button_area");
        button_area.get_style_context().add_class("content-view");
        
        Gtk.Box box = builder.get_object("composer") as Gtk.Box;
        discard_button = builder.get_object("Discard") as Gtk.Button;
        discard_button.clicked.connect(on_discard);
        send_button = builder.get_object("Send") as Gtk.Button;
        send_button.clicked.connect(on_send);
        add_attachment_button  = builder.get_object("add_attachment_button") as Gtk.Button;
        add_attachment_button.clicked.connect(on_add_attachment_button_clicked);
        pending_attachments_button = builder.get_object("add_pending_attachments") as Gtk.Button;
        pending_attachments_button.clicked.connect(on_pending_attachments_button_clicked);
        attachments_box = builder.get_object("attachments_box") as Gtk.Box;
        hidden_on_attachment_drag_over = (Gtk.Alignment) builder.get_object("hidden_on_attachment_drag_over");
        hidden_on_attachment_drag_over_child = (Gtk.Widget) builder.get_object("hidden_on_attachment_drag_over_child");
        visible_on_attachment_drag_over = (Gtk.Alignment) builder.get_object("visible_on_attachment_drag_over");
        visible_on_attachment_drag_over_child = (Gtk.Widget) builder.get_object("visible_on_attachment_drag_over_child");
        visible_on_attachment_drag_over.remove(visible_on_attachment_drag_over_child);
        
        // TODO: It would be nicer to set the completions inside the EmailEntry constructor. But in
        // testing, this can cause non-deterministic segfaults. Investigate why, and fix if possible.
        from_label = (Gtk.Label) builder.get_object("from label");
        from_single = (Gtk.Label) builder.get_object("from_single");
        from_multiple = (Gtk.ComboBoxText) builder.get_object("from_multiple");
        to_entry = new EmailEntry();
        (builder.get_object("to") as Gtk.EventBox).add(to_entry);
        cc_entry = new EmailEntry();
        (builder.get_object("cc") as Gtk.EventBox).add(cc_entry);
        bcc_entry = new EmailEntry();
        (builder.get_object("bcc") as Gtk.EventBox).add(bcc_entry);
        set_entry_completions();
        subject_entry = builder.get_object("subject") as Gtk.Entry;
        Gtk.Alignment message_area = builder.get_object("message area") as Gtk.Alignment;
        actions = builder.get_object("compose actions") as Gtk.ActionGroup;
        // Can only happen after actions exits
        compose_as_html = GearyApplication.instance.config.compose_as_html;
        
        // Listen to account signals to update from menu.
        Geary.Engine.instance.account_available.connect(update_from_field);
        Geary.Engine.instance.account_unavailable.connect(update_from_field);
        
        Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        Gtk.Overlay message_overlay = new Gtk.Overlay();
        message_overlay.add(scroll);
        message_area.add(message_overlay);
        
        message_overlay_label = new Gtk.Label(null);
        message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        message_overlay_label.halign = Gtk.Align.START;
        message_overlay_label.valign = Gtk.Align.END;
        message_overlay.add_overlay(message_overlay_label);
        
        to_entry.changed.connect(validate_send_button);
        cc_entry.changed.connect(validate_send_button);
        bcc_entry.changed.connect(validate_send_button);
        
        Gtk.Toolbar compose_toolbar = (Gtk.Toolbar) builder.get_object("compose_toolbar");
        
        actions.get_action(ACTION_UNDO).activate.connect(on_action);
        actions.get_action(ACTION_REDO).activate.connect(on_action);
        
        actions.get_action(ACTION_CUT).activate.connect(on_cut);
        actions.get_action(ACTION_COPY).activate.connect(on_copy);
        actions.get_action(ACTION_COPY_LINK).activate.connect(on_copy_link);
        actions.get_action(ACTION_PASTE).activate.connect(on_paste);
        actions.get_action(ACTION_PASTE_FORMAT).activate.connect(on_paste_with_formatting);
        
        actions.get_action(ACTION_BOLD).activate.connect(on_formatting_action);
        actions.get_action(ACTION_ITALIC).activate.connect(on_formatting_action);
        actions.get_action(ACTION_UNDERLINE).activate.connect(on_formatting_action);
        actions.get_action(ACTION_STRIKETHROUGH).activate.connect(on_formatting_action);
        
        actions.get_action(ACTION_REMOVE_FORMAT).activate.connect(on_remove_format);
        actions.get_action(ACTION_COMPOSE_AS_HTML).activate.connect(on_compose_as_html);
        
        actions.get_action(ACTION_INDENT).activate.connect(on_indent);
        actions.get_action(ACTION_OUTDENT).activate.connect(on_action);
        
        actions.get_action(ACTION_JUSTIFY_LEFT).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_RIGHT).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_CENTER).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_FULL).activate.connect(on_formatting_action);
        
        actions.get_action(ACTION_MENU).activate.connect(on_open_menu);
        actions.get_action(ACTION_COLOR).activate.connect(on_select_color);
        actions.get_action(ACTION_INSERT_LINK).activate.connect(on_insert_link);
        
        actions.get_action(ACTION_CLOSE).activate.connect(on_close);
        
        ui = new Gtk.UIManager();
        ui.insert_action_group(actions, 0);
        GearyApplication.instance.load_ui_file_for_manager(ui, "composer_accelerators.ui");
        
        add_extra_accelerators();
        
        from = account.information.get_from().to_rfc822_string();
        update_from_field();
        from_multiple.changed.connect(on_from_changed);
        
        if (referred != null) {
           switch (compose_type) {
                case ComposeType.NEW_MESSAGE:
                    if (referred.to != null)
                        to = referred.to.to_rfc822_string();
                    if (referred.cc != null)
                        cc = referred.cc.to_rfc822_string();
                    if (referred.bcc != null)
                        bcc = referred.bcc.to_rfc822_string();
                    if (referred.in_reply_to != null)
                        in_reply_to = referred.in_reply_to.value;
                    if (referred.references != null)
                        references = referred.references.to_rfc822_string();
                    if (referred.subject != null)
                        subject = referred.subject.value;
                    try {
                        body_html = referred.get_message().get_body(true);
                    } catch (Error error) {
                        debug("Error getting messae body: %s", error.message);
                    }
                    add_attachments(referred.attachments);
                break;
                
                case ComposeType.REPLY:
                case ComposeType.REPLY_ALL:
                    string? sender_address = account.information.get_mailbox_address().address;
                    to = Geary.RFC822.Utils.create_to_addresses_for_reply(referred, sender_address);
                    if (compose_type == ComposeType.REPLY_ALL)
                        cc = Geary.RFC822.Utils.create_cc_addresses_for_reply_all(referred, sender_address);
                    subject = Geary.RFC822.Utils.create_subject_for_reply(referred);
                    in_reply_to = referred.message_id.value;
                    references = Geary.RFC822.Utils.reply_references(referred);
                    body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_reply(referred, true);
                    pending_attachments = referred.attachments;
                break;
                
                case ComposeType.FORWARD:
                    subject = Geary.RFC822.Utils.create_subject_for_forward(referred);
                    body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_forward(referred, true);
                    add_attachments(referred.attachments);
                    pending_attachments = referred.attachments;
                break;
            }
        }
        
        editor = new WebKit.WebView();
        edit_fixer = new WebViewEditFixer(editor);

        editor.editable = true;
        editor.load_finished.connect(on_load_finished);
        editor.hovering_over_link.connect(on_hovering_over_link);
        editor.context_menu.connect(on_context_menu);
        editor.move_focus.connect(update_actions);
        editor.copy_clipboard.connect(update_actions);
        editor.cut_clipboard.connect(update_actions);
        editor.paste_clipboard.connect(update_actions);
        editor.undo.connect(update_actions);
        editor.redo.connect(update_actions);
        editor.selection_changed.connect(update_actions);
        
        // only do this after setting body_html
        editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        
        editor.navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        editor.new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        
        GearyApplication.instance.config.spell_check_changed.connect(on_spell_check_changed);
        
        menu_button = builder.get_object("menu button") as Gtk.ToggleToolButton;
        
        // Build menu
        menu_html = new Gtk.Menu();
        menu_html.deactivate.connect(on_deactivate_menu);
        menu_html.attach_to_widget(menu_button, null);
        
        font_sans = new Gtk.RadioMenuItem.with_label(new SList<Gtk.RadioMenuItem>(),
            _("Sans Serif"));
        font_sans.activate.connect(on_font_sans);
        menu_html.append(font_sans);
        font_serif = new Gtk.RadioMenuItem.with_label_from_widget(font_sans, _("Serif"));
        font_serif.activate.connect(on_font_serif);
        menu_html.append(font_serif);
        font_monospace = new Gtk.RadioMenuItem.with_label_from_widget(font_sans,
            _("Fixed width"));
        font_monospace.activate.connect(on_font_monospace);
        menu_html.append(font_monospace);
        menu_html.append(new Gtk.SeparatorMenuItem());
        
        font_small = new Gtk.RadioMenuItem.with_label(new SList<Gtk.RadioMenuItem>(), _("Small"));
        font_small.activate.connect(on_font_size_small);
        menu_html.append(font_small);
        font_medium = new Gtk.RadioMenuItem.with_label_from_widget(font_small, _("Medium"));
        font_medium.activate.connect(on_font_size_medium);
        menu_html.append(font_medium);
        font_large = new Gtk.RadioMenuItem.with_label_from_widget(font_small, _("Large"));
        font_large.activate.connect(on_font_size_large);
        menu_html.append(font_large);
        menu_html.append(new Gtk.SeparatorMenuItem());
        
        Gtk.MenuItem color_item = new Gtk.MenuItem();
        color_item.related_action = ui.get_action("ui/color");
        menu_html.append(color_item);
        menu_html.append(new Gtk.SeparatorMenuItem());
        Gtk.MenuItem html_item = new Gtk.CheckMenuItem();
        html_item.related_action = ui.get_action("ui/htmlcompose");
        menu_html.append(html_item);
        
        menu_plain = new Gtk.Menu();
        menu_plain.deactivate.connect(on_deactivate_menu);
        menu_plain.attach_to_widget(menu_button, null);
        
        Gtk.MenuItem html_item2 = new Gtk.CheckMenuItem();
        html_item2.related_action = ui.get_action("ui/htmlcompose");
        menu_plain.append(html_item2);
        
        WebKit.WebSettings s = new WebKit.WebSettings();
        s.enable_spell_checking = GearyApplication.instance.config.spell_check;
        s.auto_load_images = false;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        editor.settings = s;
        
        scroll.add(editor);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        add(box);
        validate_send_button();
        
        check_pending_attachments();

        // Place the message area before the compose toolbar in the focus chain, so that
        // the user can tab directly from the Subject: field to the message area.
        List<Gtk.Widget> chain = new List<Gtk.Widget>();
        chain.append(hidden_on_attachment_drag_over);
        chain.append(message_area);
        chain.append(compose_toolbar);
        chain.append(attachments_box);
        chain.append(button_area);
        box.set_focus_chain(chain);
        
        ((MainWindow) GearyApplication.instance.get_main_window()).composer_embed.new_composer(
            this, referred);
    }
    
    public ComposerWidget.from_mailto(Geary.Account account, string mailto) {
        this(account, ComposeType.NEW_MESSAGE);
        
        Gee.HashMultiMap<string, string> headers = new Gee.HashMultiMap<string, string>();
        if (mailto.length > Geary.ComposedEmail.MAILTO_SCHEME.length) {
            // Parse the mailto link.
            string[] parts = mailto.substring(Geary.ComposedEmail.MAILTO_SCHEME.length).split("?", 2);
            string email = Uri.unescape_string(parts[0]);
            string[] params = parts.length == 2 ? parts[1].split("&") : new string[0];
            foreach (string param in params) {
                string[] param_parts = param.split("=", 2);
                if (param_parts.length == 2) {
                    headers.set(Uri.unescape_string(param_parts[0]).down(),
                        Uri.unescape_string(param_parts[1]));
                }
            }
            
            // Assemble the headers.
            if (email.length > 0 && headers.contains("to"))
                to = "%s,%s".printf(email, Geary.Collection.get_first(headers.get("to")));
            else if (email.length > 0)
                to = email;
            else if (headers.contains("to"))
                to = Geary.Collection.get_first(headers.get("to"));
            
            if (headers.contains("cc"))
                cc = Geary.Collection.get_first(headers.get("cc"));
            
            if (headers.contains("bcc"))
                bcc = Geary.Collection.get_first(headers.get("bcc"));
            
            if (headers.contains("subject"))
                subject = Geary.Collection.get_first(headers.get("subject"));
            
            if (headers.contains("body"))
                body_html = Geary.HTML.preserve_whitespace(Geary.HTML.escape_markup(
                    Geary.Collection.get_first(headers.get("body"))));
            
            foreach (string attachment in headers.get("attach"))
                add_attachment(File.new_for_uri(attachment));
            foreach (string attachment in headers.get("attachment"))
                add_attachment(File.new_for_uri(attachment));
        }
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        WebKit.DOM.HTMLElement? body = editor.get_dom_document().get_element_by_id(
            BODY_ID) as WebKit.DOM.HTMLElement;
        assert(body != null);

        if (!Geary.String.is_empty(body_html)) {
            try {
                body.set_inner_html(body_html);
            } catch (Error e) {
                debug("Failed to load prefilled body: %s", e.message);
            }
        }

        protect_blockquote_styles();
        
        // Set focus.
        if (Geary.String.is_empty(to)) {
            to_entry.grab_focus();
        } else if (Geary.String.is_empty(subject)) {
            subject_entry.grab_focus();
        } else {
            editor.grab_focus();
            body.focus();
        }
        
        // Ensure the editor is in correct mode re HTML
        on_compose_as_html();

        bind_event(editor,"a", "click", (Callback) on_link_clicked, this);
        update_actions();
    }
    
    // Glade only allows one accelerator per-action. This method adds extra accelerators not defined
    // in the Glade file.
    private void add_extra_accelerators() {
        GtkUtil.add_accelerator(ui, actions, "Escape", ACTION_CLOSE);
    }
    
    private void setup_drag_destination(Gtk.Widget destination) {
        const Gtk.TargetEntry[] target_entries = { { URI_LIST_MIME_TYPE, 0, 0 } };
        Gtk.drag_dest_set(destination, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            target_entries, Gdk.DragAction.COPY);
        destination.drag_data_received.connect(on_drag_data_received);
        destination.drag_drop.connect(on_drag_drop);
        destination.drag_motion.connect(on_drag_motion);
        destination.drag_leave.connect(on_drag_leave);
    }
    
    private void show_attachment_overlay(bool visible) {
        if (is_attachment_overlay_visible == visible)
            return;
            
        is_attachment_overlay_visible = visible;
        
        // If we just make the widget invisible, it can still intercept drop signals. So we
        // completely remove it instead.
        if (visible) {
            int height = hidden_on_attachment_drag_over.get_allocated_height();
            hidden_on_attachment_drag_over.remove(hidden_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.add(visible_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.set_size_request(-1, height);
        } else {
            hidden_on_attachment_drag_over.add(hidden_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.remove(visible_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.set_size_request(-1, -1);
        }
   }
    
    private bool on_drag_motion() {
        show_attachment_overlay(true);
        return false;
    }
    
    private void on_drag_leave() {
        show_attachment_overlay(false);
    }
    
    private void on_drag_data_received(Gtk.Widget sender, Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time_) {
        
        bool dnd_success = false;
        if (selection_data.get_length() >= 0) {
            dnd_success = true;
            
            string uri_list = (string) selection_data.get_data();
            string[] uris = uri_list.strip().split("\n");
            foreach (string uri in uris) {
                if (!uri.has_prefix(FILE_URI_PREFIX))
                    continue;
                
                add_attachment(File.new_for_uri(uri.strip()));
            }
        }
        
        Gtk.drag_finish(context, dnd_success, false, time_);
    }
    
    private bool on_drag_drop(Gtk.Widget sender, Gdk.DragContext context, int x, int y, uint time_) {
        if (context.list_targets() == null)
            return false;
        
        uint length = context.list_targets().length();
        Gdk.Atom? target_type = null;
        for (uint i = 0; i < length; i++) {
            Gdk.Atom target = context.list_targets().nth_data(i);
            if (target.name() == URI_LIST_MIME_TYPE)
                target_type = target;
        }
        
        if (target_type == null)
            return false;
        
        Gtk.drag_get_data(sender, context, target_type, time_);
        return true;
    }
    
    public Geary.ComposedEmail get_composed_email(DateTime? date_override = null) {
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            date_override ?? new DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.from_rfc822_string(from)
        );
        
        if (to_entry.addresses != null)
            email.to = to_entry.addresses;
        
        if (cc_entry.addresses != null)
            email.cc = cc_entry.addresses;
        
        if (bcc_entry.addresses != null)
            email.bcc = bcc_entry.addresses;
        
        if (!Geary.String.is_empty(in_reply_to))
            email.in_reply_to = in_reply_to;
        
        if (!Geary.String.is_empty(references))
            email.references = references;
        
        if (!Geary.String.is_empty(subject))
            email.subject = subject;
        
        email.attachment_files.add_all(attachment_files);
        
        if (compose_as_html)
            email.body_html = get_html();
        email.body_text = get_text();

        // User-Agent
        email.mailer = GearyApplication.PRGNAME + "/" + GearyApplication.VERSION;
        
        return email;
    }
    
    public override void show_all() {
        base.show_all();
        update_from_field();
    }
    
    public void close() {
        container.close();
    }
    
    public bool should_close() {
        // TODO: Check if the message was (automatically) saved
        if (editor.can_undo()) {
            container.present();
            ConfirmationDialog dialog = new ConfirmationDialog(container.top_window,
                _("Do you want to discard the unsaved message?"), null, Gtk.Stock.DISCARD);
            if (dialog.run() != Gtk.ResponseType.OK)
                return false;
        }
        return true;
    }
    
    private void on_discard() {
        if (should_close())
            close();
    }
    
    private void on_close() {
        // Accelerator <Primary>w was pressed to close the composer window. Do the same as
        // when clicking the Discard button, at least for now.
        on_discard();
    }
    
    private bool should_send() {
        bool has_subject = !Geary.String.is_empty(subject.strip());
        bool has_body_or_attachment = !Geary.String.is_empty(get_html()) || attachment_files.size > 0;
        string? confirmation = null;
        if (!has_subject && !has_body_or_attachment) {
            confirmation = _("Send message with an empty subject and body?");
        } else if (!has_subject) {
            confirmation = _("Send message with an empty subject?");
        } else if (!has_body_or_attachment) {
            confirmation = _("Send message with an empty body?");
        }
        if (confirmation != null) {
            ConfirmationDialog dialog = new ConfirmationDialog(container.top_window,
                confirmation, null, Gtk.Stock.OK);
            if (dialog.run() != Gtk.ResponseType.OK)
                return false;
        }
        return true;
    }
    
    private void on_send() {
        if (should_send()) {
            linkify_document(editor.get_dom_document());
            send(this);
        }
    }
    
    private void on_add_attachment_button_clicked() {
        bool finished = true;
        do {
            Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(
                _("Choose a file"), container.top_window, Gtk.FileChooserAction.OPEN,
                Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                _("_Attach"), Gtk.ResponseType.ACCEPT);
            if (!Geary.String.is_empty(current_folder))
                dialog.set_current_folder(current_folder);
            dialog.set_local_only(false);
            dialog.set_select_multiple(true);
            
            if (dialog.run() == Gtk.ResponseType.ACCEPT) {
                current_folder = dialog.get_current_folder();
                
                foreach (File file in dialog.get_files()) {
                    if (!add_attachment(file)) {
                        finished = false;
                        break;
                    }
                }
            } else {
                finished = true;
            }
            
            dialog.destroy();
        } while (!finished);
    }
    
    private void on_pending_attachments_button_clicked() {
        add_attachments(pending_attachments, false);
    }
    
    private void check_pending_attachments() {
        if (pending_attachments != null) {
            Gee.Set<string> filenames = new Gee.HashSet<string>();
            foreach (File file in attachment_files)
                filenames.add(file.get_path());
            
            foreach (Geary.Attachment attachment in pending_attachments) {
                if (!filenames.contains(attachment.filepath)) {
                    pending_attachments_button.show();
                    return;
                }
            }
        }
        pending_attachments_button.hide();
    }
    
    private void attachment_failed(string msg) {
        ErrorDialog dialog = new ErrorDialog(container.top_window, _("Cannot add attachment"), msg);
        dialog.run();
    }
    
    private bool add_attachment(File attachment_file, bool alert_errors = true) {
        FileInfo attachment_file_info;
        try {
            attachment_file_info = attachment_file.query_info("standard::size,standard::type",
                FileQueryInfoFlags.NONE);
        } catch(Error e) {
            if (alert_errors)
                attachment_failed(_("\"%s\" could not be found.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        if (attachment_file_info.get_file_type() == FileType.DIRECTORY) {
            if (alert_errors)
                attachment_failed(_("\"%s\" is a folder.").printf(attachment_file.get_path()));
            
            return false;
        }

        if (attachment_file_info.get_size() == 0){
            if (alert_errors)
                attachment_failed(_("\"%s\" is an empty file.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        try {
            FileInputStream? stream = attachment_file.read();
            if (stream != null)
                stream.close();
        } catch(Error e) {
            debug("File '%s' could not be opened for reading. Error: %s", attachment_file.get_path(),
                e.message);
            
            if (alert_errors)
                attachment_failed(_("\"%s\" could not be opened for reading.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        if (!attachment_files.add(attachment_file)) {
            if (alert_errors)
                attachment_failed(_("\"%s\" already attached for delivery.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        attachments_box.pack_start(box);
        
        Gtk.Label label = new Gtk.Label(attachment_file.get_basename());
        box.pack_start(label);
        label.halign = Gtk.Align.START;
        label.xpad = 4;
        
        Gtk.Button remove_button = new Gtk.Button.from_stock(Gtk.Stock.REMOVE);
        box.pack_start(remove_button, false, false);
        remove_button.clicked.connect(() => remove_attachment(attachment_file, box));
        
        attachments_box.show_all();
        
        check_pending_attachments();
        
        return true;
    }
    
    private void add_attachments(Gee.List<Geary.Attachment> attachments, bool alert_errors = true) {
        foreach(Geary.Attachment attachment in attachments) {
            File? attachment_file = File.new_for_path(attachment.filepath);
            if (attachment_file != null)
                add_attachment(attachment_file, alert_errors);
        }
    }
    
    private void remove_attachment(File file, Gtk.Box box) {
        if (!attachment_files.remove(file))
            return;
        
        foreach (weak Gtk.Widget child in attachments_box.get_children()) {
            if (child == box) {
                attachments_box.remove(box);
                break;
            }
        }
        
        check_pending_attachments();
    }
    
    private void validate_send_button() {
        send_button.sensitive =
            to_entry.valid_or_empty && cc_entry.valid_or_empty && bcc_entry.valid_or_empty
         && (!to_entry.empty || !cc_entry.empty || !bcc_entry.empty);
    }
    
    private void on_formatting_action(Gtk.Action action) {
        if (compose_as_html)
            on_action(action);
    }
    
    private void on_action(Gtk.Action action) {
        if (action_flag)
            return;
        
        action_flag = true; // prevents recursion
        editor.get_dom_document().exec_command(action.get_name(), false, "");
        action_flag = false;
    }
    
    private void on_cut() {
        if (container.get_focus() == editor)
            editor.cut_clipboard();
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).cut_clipboard();
    }
    
    private void on_copy() {
        if (container.get_focus() == editor)
            editor.copy_clipboard();
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).copy_clipboard();
    }
    
    private void on_copy_link() {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(hover_url, -1);
        c.store();
    }
    
    private WebKit.DOM.Node? get_left_text(WebKit.DOM.Node node, long offset) {
        WebKit.DOM.Document document = editor.get_dom_document();
        string node_value = node.node_value;

        // Offset is in unicode characters, but index is in bytes. We need to get the corresponding
        // byte index for the given offset.
        int char_count = node_value.char_count();
        int index = offset > char_count ? node_value.length : node_value.index_of_nth_char(offset);

        return offset > 0 ? document.create_text_node(node_value[0:index]) : null;
    }
    
    private void on_clipboard_text_received(Gtk.Clipboard clipboard, string? text) {
        if (text == null)
            return;
        
        // Insert plain text from clipboard.
        WebKit.DOM.Document document = editor.get_dom_document();
        document.exec_command("inserttext", false, text);
    
        // The inserttext command will not scroll if needed, but we can't use the clipboard
        // for plain text. WebKit allows us to scroll a node into view, but not an arbitrary
        // position within a text node. So we add a placeholder node at the cursor position,
        // scroll to that, then remove the placeholder node.
        try {
            WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
            WebKit.DOM.Node selection_base_node = selection.get_base_node();
            long selection_base_offset = selection.get_base_offset();
            
            WebKit.DOM.NodeList selection_child_nodes = selection_base_node.get_child_nodes();
            WebKit.DOM.Node ref_child = selection_child_nodes.item(selection_base_offset);
        
            WebKit.DOM.Element placeholder = document.create_element("SPAN");
            WebKit.DOM.Text placeholder_text = document.create_text_node("placeholder");
            placeholder.append_child(placeholder_text);
            
            if (selection_base_node.node_name == "#text") {
                WebKit.DOM.Node? left = get_left_text(selection_base_node, selection_base_offset);
                
                WebKit.DOM.Node parent = selection_base_node.parent_node;
                if (left != null)
                    parent.insert_before(left, selection_base_node);
                parent.insert_before(placeholder, selection_base_node);
                parent.remove_child(selection_base_node);
                
                placeholder.scroll_into_view_if_needed(false);
                parent.insert_before(selection_base_node, placeholder);
                if (left != null)
                    parent.remove_child(left);
                parent.remove_child(placeholder);
                selection.set_base_and_extent(selection_base_node, selection_base_offset, selection_base_node, selection_base_offset);
            } else {
                selection_base_node.insert_before(placeholder, ref_child);
                placeholder.scroll_into_view_if_needed(false);
                selection_base_node.remove_child(placeholder);
            }
            
        } catch (Error err) {
            debug("Error scrolling pasted text into view: %s", err.message);
        }
    }
    
    private void on_paste() {
        if (container.get_focus() == editor)
            get_clipboard(Gdk.SELECTION_CLIPBOARD).request_text(on_clipboard_text_received);
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).paste_clipboard();
    }
    
    private void on_paste_with_formatting() {
        if (container.get_focus() == editor)
            editor.paste_clipboard();
    }
    
    private void on_select_all() {
        editor.select_all();
    }
    
    private void on_remove_format() {
        editor.get_dom_document().exec_command("removeformat", false, "");
        editor.get_dom_document().exec_command("removeparaformat", false, "");
        editor.get_dom_document().exec_command("unlink", false, "");
        editor.get_dom_document().exec_command("backcolor", false, "#ffffff");
        editor.get_dom_document().exec_command("forecolor", false, "#000000");
    }
    
    private void on_compose_as_html() {
        WebKit.DOM.DOMTokenList body_classes = editor.get_dom_document().body.get_class_list();
        if (!compose_as_html) {
            toggle_toolbar_buttons(false);
            try {
                body_classes.add("plain");
            } catch (Error error) {
                debug("Error setting composer style: %s", error.message);
            }
        } else {
            toggle_toolbar_buttons(true);
            try {
                body_classes.remove("plain");
            } catch (Error error) {
                debug("Error setting composer style: %s", error.message);
            }
        }
        GearyApplication.instance.config.compose_as_html = compose_as_html;
    }
    
    private void toggle_toolbar_buttons(bool show) {
        string[] buttons = {"bold button", "italic button", "underline button",
            "strikethrough button", "toolbar separator 1", "toolbar separator 2",
            "link button", "remove format button"};
        foreach (string button in buttons) {
            Gtk.Widget widget = (Gtk.Widget) builder.get_object(button);
            if (show)
                widget.show();
            else
                widget.hide();
        }
    }
    
    private void on_open_menu() {
        if (!menu_button.active)
            return;
        
        if (compose_as_html) {
            menu_html.show_all();
            menu_html.popup(null, null, GtkUtil.menu_popup_relative, 0, 0);
        } else {
            menu_plain.show_all();
            menu_plain.popup(null, null, GtkUtil.menu_popup_relative, 0, 0);
        }
    }
    
    private void on_deactivate_menu() {
        menu_button.active = false;
    }
    
    private void on_font_sans() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "sans");
    }
    
    private void on_font_serif() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "serif");
    }
    
    private void on_font_monospace() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "monospace");
    }
    
    private void on_font_size_small() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "1");
    }
    
    private void on_font_size_medium() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "3");
    }
    
    private void on_font_size_large() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "7");
    }
    
    private void on_select_color() {
        if (compose_as_html) {
            Gtk.ColorChooserDialog dialog = new Gtk.ColorChooserDialog(_("Select Color"), container.top_window);
            if (dialog.run() == Gtk.ResponseType.OK)
                editor.get_dom_document().exec_command("forecolor", false, dialog.get_rgba().to_string());
            
            dialog.destroy();
        }
    }
    
    private void on_indent(Gtk.Action action) {
        on_action(action);
        
        // Undo styling of blockquotes
        try {
            WebKit.DOM.NodeList node_list = editor.get_dom_document().query_selector_all(
                "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
            for (int i = 0; i < node_list.length; ++i) {
                WebKit.DOM.Element element = (WebKit.DOM.Element) node_list.item(i);
                element.remove_attribute("style");
                element.set_attribute("type", "cite");
            }
        } catch (Error error) {
            warning("Error removing blockquote style: %s", error.message);
        }
    }
    
    private void protect_blockquote_styles() {
        // We will search for an remove a particular styling when we quote text.  If that style
        // exists in the quoted text, we alter it slightly so we don't mess with it later.
        try {
            WebKit.DOM.NodeList node_list = editor.get_dom_document().query_selector_all(
                "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
            for (int i = 0; i < node_list.length; ++i) {
                ((WebKit.DOM.Element) node_list.item(i)).set_attribute("style", 
                    "margin: 0 0 0 40px; padding: 0px; border:none;");
            }
        } catch (Error error) {
            warning("Error protecting blockquotes: %s", error.message);
        }
    }
    
    private void on_insert_link() {
        if (compose_as_html)
            link_dialog("http://");
    }
    
    private static void on_link_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ComposerWidget composer) {
        try {
            composer.editor.get_dom_document().get_default_view().get_selection().
                select_all_children(element);
        } catch (Error e) {
            debug("Error selecting link: %s", e.message);
        }
        
        composer.prev_selected_link = element;
    }
    
    private void link_dialog(string link) {
        Gtk.Dialog dialog = new Gtk.Dialog();
        bool existing_link = false;
        
        // Allow user to remove link if they're editing an existing one.
        WebKit.DOM.Node selected = editor.get_dom_document().get_default_view().
            get_selection().focus_node;
        if (selected != null && (selected is WebKit.DOM.HTMLAnchorElement ||
            selected.get_parent_element() is WebKit.DOM.HTMLAnchorElement)) {
            existing_link = true;
            dialog.add_buttons(Gtk.Stock. REMOVE, Gtk.ResponseType.REJECT);
        }
        
        dialog.add_buttons(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.OK,
            Gtk.ResponseType.OK);
        
        Gtk.Entry entry = new Gtk.Entry();
        entry.changed.connect(() => {
            // Only allow OK when there's text in the box.
            dialog.set_response_sensitive(Gtk.ResponseType.OK, 
                !Geary.String.is_empty(entry.text.strip()));
        });
        
        dialog.width_request = 350;
        dialog.get_content_area().spacing = 7;
        dialog.get_content_area().border_width = 10;
        dialog.get_content_area().pack_start(new Gtk.Label("Link URL:"));
        dialog.get_content_area().pack_start(entry);
        dialog.get_widget_for_response(Gtk.ResponseType.OK).can_default = true;
        dialog.set_default_response(Gtk.ResponseType.OK);
        dialog.show_all();
        
        entry.set_text(link);
        entry.activates_default = true;
        entry.move_cursor(Gtk.MovementStep.BUFFER_ENDS, 0, false);
        
        int response = dialog.run();
        
        // If it's an existing link, re-select it.  This is necessary because selecting
        // text in the Gtk.Entry will de-select all in the WebView.
        if (existing_link) {
            try {
                editor.get_dom_document().get_default_view().get_selection().
                    select_all_children(prev_selected_link);
            } catch (Error e) {
                debug("Error selecting link: %s", e.message);
            }
        }
        
        if (response == Gtk.ResponseType.OK)
            editor.get_dom_document().exec_command("createLink", false, entry.text);
        else if (response == Gtk.ResponseType.REJECT)
            editor.get_dom_document().exec_command("unlink", false, "");
        
        dialog.destroy();
        
        // Re-bind to anchor links.  This must be done every time link have changed.
        bind_event(editor,"a", "click", (Callback) on_link_clicked, this);
    }
    
    private string get_html() {
        return editor.get_dom_document().get_body().get_inner_html();
    }
    
    private string get_text() {
        return html_to_flowed_text(editor.get_dom_document());
    }
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
        if (compose_as_html)
            link_dialog(request.uri);
        return true;
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        if (compose_as_html) {
            message_overlay_label.label = url;
            hover_url = url;
            update_actions();
        }
    }
    
    private void on_spell_check_changed() {
        editor.settings.enable_spell_checking = GearyApplication.instance.config.spell_check;
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        update_actions();
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Return":
            case "KP_Enter":
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 && send_button.sensitive) {
                    on_send();
                    return true;
                }
            break;
        }
        
        return base.key_press_event(event);
    }
    
    private bool on_context_menu(Gtk.Widget default_menu, WebKit.HitTestResult hit_test_result,
        bool keyboard_triggered) {
        Gtk.Menu context_menu = (Gtk.Menu) default_menu;
        Gtk.MenuItem? ignore_spelling = null, learn_spelling = null;
        bool suggestions = false;
        
        GLib.List<weak Gtk.Widget> children = context_menu.get_children();
        foreach (weak Gtk.Widget child in children) {
            Gtk.MenuItem item = (Gtk.MenuItem) child;
            WebKit.ContextMenuAction action = WebKit.context_menu_item_get_action(item);
            if (action == WebKit.ContextMenuAction.SPELLING_GUESS) {
                suggestions = true;
                continue;
            }
            
            if (action == WebKit.ContextMenuAction.IGNORE_SPELLING)
                ignore_spelling = item;
            else if (action == WebKit.ContextMenuAction.LEARN_SPELLING)
                learn_spelling = item;
            context_menu.remove(child);
        }
        
        if (suggestions)
            context_menu.append(new Gtk.SeparatorMenuItem());
        if (ignore_spelling != null)
            context_menu.append(ignore_spelling);
        if (learn_spelling != null)
            context_menu.append(learn_spelling);
        if (ignore_spelling != null || learn_spelling != null)
            context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Undo
        Gtk.MenuItem undo = new Gtk.ImageMenuItem();
        undo.related_action = actions.get_action(ACTION_UNDO);
        context_menu.append(undo);
        
        // Redo
        Gtk.MenuItem redo = new Gtk.ImageMenuItem();
        redo.related_action = actions.get_action(ACTION_REDO);
        context_menu.append(redo);
        
        context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Cut
        Gtk.MenuItem cut = new Gtk.ImageMenuItem();
        cut.related_action = actions.get_action(ACTION_CUT);
        context_menu.append(cut);
        
        // Copy
        Gtk.MenuItem copy = new Gtk.ImageMenuItem();
        copy.related_action = actions.get_action(ACTION_COPY);
        context_menu.append(copy);
        
        // Copy link.
        Gtk.MenuItem copy_link = new Gtk.ImageMenuItem();
        copy_link.related_action = actions.get_action(ACTION_COPY_LINK);
        context_menu.append(copy_link);
        
        // Paste
        Gtk.MenuItem paste = new Gtk.ImageMenuItem();
        paste.related_action = actions.get_action(ACTION_PASTE);
        context_menu.append(paste);
        
        // Paste with formatting
        if (compose_as_html) {
            Gtk.MenuItem paste_format = new Gtk.ImageMenuItem();
            paste_format.related_action = actions.get_action(ACTION_PASTE_FORMAT);
            context_menu.append(paste_format);
        }
        
        context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.SELECT_ALL, null);
        select_all_item.activate.connect(on_select_all);
        context_menu.append(select_all_item);
        
        context_menu.show_all();
        
        update_actions();
        
        return false;
    }
    
    private void update_actions() {
        // Undo/redo.
        actions.get_action(ACTION_UNDO).sensitive = editor.can_undo();
        actions.get_action(ACTION_REDO).sensitive = editor.can_redo();
        
        // Clipboard.
        actions.get_action(ACTION_CUT).sensitive = editor.can_cut_clipboard();
        actions.get_action(ACTION_COPY).sensitive = editor.can_copy_clipboard();
        actions.get_action(ACTION_COPY_LINK).sensitive = hover_url != null;
        actions.get_action(ACTION_PASTE).sensitive = editor.can_paste_clipboard();
        actions.get_action(ACTION_PASTE_FORMAT).sensitive = editor.can_paste_clipboard() && compose_as_html;
        
        // Style toggle buttons.
        WebKit.DOM.DOMWindow window = editor.get_dom_document().get_default_view();
        WebKit.DOM.Element? active = window.get_selection().focus_node as WebKit.DOM.Element;
        if (active == null && window.get_selection().focus_node != null)
            active = window.get_selection().focus_node.get_parent_element();
        
        if (active != null && !action_flag) {
            action_flag = true;
            
            WebKit.DOM.CSSStyleDeclaration styles = window.get_computed_style(active, "");
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_BOLD)).active = 
                styles.get_property_value("font-weight") == "bold";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_ITALIC)).active = 
                styles.get_property_value("font-style") == "italic";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_UNDERLINE)).active = 
                styles.get_property_value("text-decoration") == "underline";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_STRIKETHROUGH)).active = 
                styles.get_property_value("text-decoration") == "line-through";
            
            // Font family.
            string font_name = styles.get_property_value("font-family").down();
            if (font_name.contains("sans-serif") ||
                font_name.contains("arial") ||
                font_name.contains("trebuchet") ||
                font_name.contains("helvetica"))
                font_sans.activate();
            else if (font_name.contains("serif") ||
                font_name.contains("georgia") ||
                font_name.contains("times"))
                font_serif.activate();
            else if (font_name.contains("monospace") ||
                font_name.contains("courier") ||
                font_name.contains("console"))
                font_monospace.activate();
            
            // Font size.
            int font_size;
            styles.get_property_value("font-size").scanf("%dpx", out font_size);
            if (font_size < 11)
                font_small.activate();
            else if (font_size > 20)
                font_large.activate();
            else
                font_medium.activate();
            
            action_flag = false;
        }
    }
    
    private void update_from_field() {
        from_single.visible = from_multiple.visible = from_label.visible = false;
        
        Gee.Map<string, Geary.AccountInformation> accounts;
        try {
            accounts = Geary.Engine.instance.get_accounts();
        } catch (Error e) {
            debug("Could not fetch account info: %s", e.message);
            
            return;
        }
        
        // If there's only one account, show nothing. (From fields are hidden above.)
        if (accounts.size <= 1)
            return;
        
        from_label.visible = true;
        
        if (compose_type == ComposeType.NEW_MESSAGE) {
            // For new messages, show the account combo-box.
            from_multiple.visible = true;
            from_multiple.remove_all();
            foreach (Geary.AccountInformation a in accounts.values)
                from_multiple.append(a.email, a.get_mailbox_address().get_full_address());
            
            // Set the active account to the currently selected account, or failing that, set it
            // to the first account in the list.
            if (!from_multiple.set_active_id(account.information.email))
                from_multiple.set_active(0);
        } else {
            // For other types of messages, just show the from account.
            from_single.label = account.information.get_mailbox_address().get_full_address();
            from_single.visible = true;
        }
    }
    
    private void on_from_changed() {
        if (compose_type != ComposeType.NEW_MESSAGE)
            return;
        
        // Since we've set the combo box ID to the email addresses, we can
        // fetch that and use it to grab the account from the engine.
        string? id = from_multiple.get_active_id();
        Geary.AccountInformation? new_account_info = null;
        
        if (id != null) {
            try {
                new_account_info = Geary.Engine.instance.get_accounts().get(id);
                if (new_account_info != null) {
                    account = Geary.Engine.instance.get_account_instance(new_account_info);
                    from = new_account_info.get_from().to_rfc822_string();
                    set_entry_completions();
                }
            } catch (Error e) {
                debug("Error updating account in Composer: %s", e.message);
            }
        }
    }
    
    private void set_entry_completions() {
        Geary.ContactStore contact_store = account.get_contact_store();
        to_entry.completion = new ContactEntryCompletion(contact_store);
        cc_entry.completion = new ContactEntryCompletion(contact_store);
        bcc_entry.completion = new ContactEntryCompletion(contact_store);
    }
}

