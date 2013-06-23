/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Geary.Account : BaseObject {
    public enum Problem {
        RECV_EMAIL_LOGIN_FAILED,
        SEND_EMAIL_LOGIN_FAILED,
        HOST_UNREACHABLE,
        NETWORK_UNAVAILABLE,
        DATABASE_FAILURE
    }
    
    public abstract Geary.AccountInformation information { get; protected set; }
    
    public signal void opened();
    
    public signal void closed();
    
    public signal void email_sent(Geary.RFC822.Message rfc822);
    
    public signal void report_problem(Geary.Account.Problem problem, Error? err);
    
    /**
     * Fired when folders become available or unavailable in the account.
     *
     * Folders become available when the account is first opened or when
     * they're created later; they become unavailable when the account is
     * closed or they're deleted later.
     *
     * Folders are ordered for the convenience of the caller from the top of the heirarchy to
     * lower in the heirarchy.  In other words, parents are listed before children, assuming the
     * lists are traversed in natural order.
     *
     * @see sort_by_path
     */
    public signal void folders_available_unavailable(Gee.List<Geary.Folder>? available,
        Gee.List<Geary.Folder>? unavailable);

    /**
     * Fired when folders are created or deleted.
     *
     * Folders are ordered for the convenience of the caller from the top of the heirarchy to
     * lower in the heirarchy.  In other words, parents are listed before children, assuming the
     * lists are traversed in natural order.
     *
     * @see sort_by_path
     */
    public signal void folders_added_removed(Gee.List<Geary.Folder>? added,
        Gee.List<Geary.Folder>? removed);
    
    /**
     * Fired when a Folder's contents is detected having changed.
     */
    public signal void folders_contents_altered(Gee.Collection<Geary.Folder> altered);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_opened();
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_closed();
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_email_sent(Geary.RFC822.Message rfc822);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_report_problem(Geary.Account.Problem problem, Error? err);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_available_unavailable(Gee.List<Geary.Folder>? available,
        Gee.List<Geary.Folder>? unavailable);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_added_removed(Gee.List<Geary.Folder>? added,
        Gee.List<Geary.Folder>? removed);
    
    /**
     * Signal notification method for subclasses to use.
     */
    protected abstract void notify_folders_contents_altered(Gee.Collection<Geary.Folder> altered);
    
    /**
     * A utility method to sort a Gee.Collection of {@link Folder}s by their {@link FolderPath}s
     * to ensure they comport with {@link folders_available_unavailable} and
     * {@link folders_added_removed} signals' contracts.
     */
    protected Gee.List<Geary.Folder> sort_by_path(Gee.Collection<Geary.Folder> folders) {
        Gee.TreeSet<Geary.Folder> sorted = new Gee.TreeSet<Geary.Folder>(folder_path_comparator);
        sorted.add_all(folders);
        
        return Collection.to_array_list<Geary.Folder>(sorted);
    }
    
    private int folder_path_comparator(Geary.Folder a, Geary.Folder b) {
        return a.get_path().compare_to(b.get_path());
    }
    
    /**
     *
     */
    public abstract async void open_async(Cancellable? cancellable = null) throws Error;
    
    /**
     *
     */
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns true if this account is open, else false.
     */
    public abstract bool is_open();
    
    /**
     * Lists all the currently-available folders found under the parent path
     * unless it's null, in which case it lists all the root folders.  If the
     * parent path cannot be found, EngineError.NOT_FOUND is thrown.  If no
     * folders exist in the root, EngineError.NOT_FOUND may be thrown as well.
     * However, the caller should be prepared to deal with an empty list being
     * returned instead.
     *
     * The same Geary.Folder objects (instances) will be returned if the same path is submitted
     * multiple times.  This means that multiple callers may be holding references to the same
     * Folders.  This is important when thinking of opening and closing folders and signal
     * notifications.
     */
    public abstract Gee.Collection<Geary.Folder> list_matching_folders(
        Geary.FolderPath? parent) throws Error;
    
    /**
     * Lists all currently-available folders.  See caveats under
     * list_matching_folders().
     */
    public abstract Gee.Collection<Geary.Folder> list_folders() throws Error;
    
    /**
     * Gets a perpetually update-to-date collection of autocompletion contacts.
     */
    public abstract Geary.ContactStore get_contact_store();

    /**
     * Returns true if the folder exists.
     *
     * This method never throws EngineError.NOT_FOUND.
     */
    public abstract async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Fetches a Folder object corresponding to the supplied path.  If the backing medium does
     * not have a record of a folder at the path, EngineError.NOT_FOUND will be thrown.
     *
     * The same Geary.Folder object (instance) will be returned if the same path is submitted
     * multiple times.  This means that multiple callers may be holding references to the same
     * Folders.  This is important when thinking of opening and closing folders and signal
     * notifications.
     */
    public abstract async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Returns the folder representing the given special folder type.  If no such folder exists,
     * null is returned.
     */
    public abstract Geary.Folder? get_special_folder(Geary.SpecialFolderType special) throws Error;
    
    /**
     * Submits a ComposedEmail for delivery.  Messages may be scheduled for later delivery or immediately
     * sent.  Subscribe to the "email-sent" signal to be notified of delivery.  Note that that signal
     * does not return the ComposedEmail object but an RFC822-formatted object.  Allowing for the
     * subscriber to attach some kind of token for later comparison is being considered.
     */
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
    
    /**
     * Search the local account for emails referencing a Message-ID value
     * (which can appear in the Message-ID header itself, as well as the
     * In-Reply-To header, and maybe more places).  Fetch the requested fields,
     * optionally ignoring emails that don't have the requested fields set.
     * Don't include emails that appear in any of the blacklisted folders in
     * the result.  If null is included in the blacklist, omit emails appearing
     * in no folders.  Return a map of Email object to a list of FolderPaths
     * it's in, which can be null if it's in no folders.
     */
    public abstract async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Cancellable? cancellable = null) throws Error;
    
    /**
     * Return a single email fulfilling the required fields.  The email to pull
     * is identified by an EmailIdentifier from a previous call to
     * local_search_message_id_async().  Throw EngineError.NOT_FOUND if the
     * email isn't found and EngineError.INCOMPLETE_MESSAGE if the fields
     * aren't available.
     */
    public abstract async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error;
    
    /**
     * Used only for debugging.  Should not be used for user-visible strings.
     */
    public abstract string to_string();
}

