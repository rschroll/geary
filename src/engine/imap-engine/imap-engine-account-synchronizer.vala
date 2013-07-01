/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.AccountSynchronizer : Geary.BaseObject {
    private const int FETCH_DATE_RECEIVED_CHUNK_COUNT = 25;
    
    public GenericAccount account { get; private set; }
    
    private Nonblocking.Mailbox<GenericFolder> bg_queue = new Nonblocking.Mailbox<GenericFolder>(bg_queue_comparator);
    private Gee.HashSet<GenericFolder> made_available = new Gee.HashSet<GenericFolder>();
    private GenericFolder? current_folder = null;
    private Cancellable? bg_cancellable = null;
    private Nonblocking.Semaphore stopped = new Nonblocking.Semaphore();
    private Nonblocking.Semaphore prefetcher_semaphore = new Nonblocking.Semaphore();
    
    public AccountSynchronizer(GenericAccount account) {
        this.account = account;
        
        account.opened.connect(on_account_opened);
        account.closed.connect(on_account_closed);
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.folders_contents_altered.connect(on_folders_contents_altered);
    }
    
    ~AccountSynchronizer() {
        account.opened.disconnect(on_account_opened);
        account.closed.disconnect(on_account_closed);
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.folders_contents_altered.disconnect(on_folders_contents_altered);
    }
    
    public async void stop_async() {
        bg_cancellable.cancel();
        
        try {
            yield stopped.wait_async();
        } catch (Error err) {
            debug("Error waiting for AccountSynchronizer background task for %s to complete: %s",
                account.to_string(), err.message);
        }
    }
    
    private void on_account_opened() {
        if (stopped.is_passed())
            return;
        
        bg_queue.allow_duplicates = false;
        bg_queue.requeue_duplicate = false;
        bg_cancellable = new Cancellable();
        
        // immediately start processing folders as they are announced as available
        process_queue_async.begin();
    }
    
    private void on_account_closed() {
        bg_cancellable.cancel();
        bg_queue.clear();
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Folder>? available,
        Gee.Collection<Folder>? unavailable) {
        if (stopped.is_passed())
            return;
        
        if (available != null)
            send_all(available, true);
        
        if (unavailable != null)
            revoke_all(unavailable);
    }
    
    private void on_folders_contents_altered(Gee.Collection<Folder> altered) {
        send_all(altered, false);
    }
    
    private void send_all(Gee.Collection<Folder> folders, bool reason_available) {
        foreach (Folder folder in folders) {
            GenericFolder? generic_folder = folder as GenericFolder;
            
            // only deal with ImapEngine.GenericFolders
            if (generic_folder == null)
                continue;
            
            // don't requeue the currently processing folder
            if (generic_folder != current_folder)
                bg_queue.send(generic_folder);
            
            // If adding because now available, make sure it's flagged as such, since there's an
            // additional check for available folders ... if not, remove from the map so it's
            // not treated as such, in case both of these come in back-to-back
            if (reason_available && generic_folder != current_folder)
                made_available.add(generic_folder);
            else
                made_available.remove(generic_folder);
        }
    }
    
    private void revoke_all(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            GenericFolder? generic_folder = folder as GenericFolder;
            if (generic_folder != null) {
                bg_queue.revoke(generic_folder);
                made_available.remove(generic_folder);
            }
        }
    }
    
    // This is used to ensure that certain special folders get prioritized over others, so folders
    // important to the user (i.e. Inbox) and folders handy for pulling all mail (i.e. All Mail) go
    // first while less-used folders (Trash, Spam) are fetched last
    private static int bg_queue_comparator(GenericFolder a, GenericFolder b) {
        if (a == b)
            return 0;
        
        int cmp = score_folder(a) - score_folder(b);
        if (cmp != 0)
            return cmp;
        
        // sort by path to stabilize the sort
        return a.path.compare_to(b.path);
    }
    
    // Lower the score, the higher the importance.
    private static int score_folder(Folder a) {
        switch (a.special_folder_type) {
            case SpecialFolderType.INBOX:
                return -60;
            
            case SpecialFolderType.ALL_MAIL:
                return -50;
            
            case SpecialFolderType.SENT:
                return -40;
            
            case SpecialFolderType.FLAGGED:
                return -30;
            
            case SpecialFolderType.IMPORTANT:
                return -20;
            
            case SpecialFolderType.DRAFTS:
                return -10;
            
            case SpecialFolderType.SPAM:
                return 10;
            
            case SpecialFolderType.TRASH:
                return 20;
            
            default:
                return 0;
        }
    }
    
    private async void process_queue_async() {
        for (;;) {
            GenericFolder folder;
            try {
                folder = yield bg_queue.recv_async(bg_cancellable);
            } catch (Error err) {
                if (!(err is IOError.CANCELLED))
                    debug("Failed to receive next folder for background sync: %s", err.message);
                
                break;
            }
            
            // mark as current folder to prevent requeues while processing
            current_folder = folder;
            
            // generate the current epoch for synchronization (could cache this value, obviously, but
            // doesn't seem like this biggest win in this class)
            DateTime epoch;
            if (account.information.prefetch_period_days >= 0) {
                epoch = new DateTime.now_local();
                epoch = epoch.add_days(0 - account.information.prefetch_period_days);
            } else {
                epoch = new DateTime(new TimeZone.local(), 1, 1, 1, 0, 0, 0.0);
            }
            
            bool ok = yield process_folder_async(folder, made_available.remove(folder), epoch);
            
            // clear current folder in every event
            current_folder = null;
            
            if (!ok)
                break;
        }
        
        // clear queue of any remaining folders so references aren't held
        bg_queue.clear();
        
        // same with made_available table
        made_available.clear();
        
        // flag as stopped for any waiting tasks
        stopped.blind_notify();
    }
    
    // Returns false if IOError.CANCELLED received
    private async bool process_folder_async(GenericFolder folder, bool availability_check, DateTime epoch) {
        // get oldest local email and its position to start syncing from
        DateTime? oldest_local = null;
        Geary.EmailIdentifier? oldest_local_id = null;
        try {
            Gee.List<Geary.Email>? list = yield folder.local_folder.local_list_email_async(1, 1,
                Email.Field.PROPERTIES, ImapDB.Folder.ListFlags.NONE, bg_cancellable);
            if (list != null && list.size > 0) {
                oldest_local = list[0].properties.date_received;
                oldest_local_id = list[0].id;
            }
        } catch (Error err) {
            debug("Unable to fetch oldest local email for %s: %s", folder.to_string(), err.message);
        }
        
        if (availability_check) {
            // Compare the oldest mail in the local store and see if it is before the epoch; if so, no
            // need to synchronize simply because this Folder is available; wait for its contents to
            // change instead
            if (oldest_local != null) {
                if (oldest_local.compare(epoch) < 0) {
                    // Oldest local email before epoch, don't sync from network
                    return true;
                } else {
                    debug("Oldest local email in %s not old enough (%s vs. %s), synchronizing...",
                        folder.to_string(), oldest_local.to_string(), epoch.to_string());
                }
            } else if (folder.properties.email_total == 0) {
                // no local messages, no remote messages -- this is as good as having everything up
                // to the epoch
                return true;
            } else {
                debug("No oldest message found for %s, synchronizing...", folder.to_string());
            }
        }
        
        try {
            yield folder.open_async(Folder.OpenFlags.FAST_OPEN, bg_cancellable);
            yield folder.wait_for_open_async(bg_cancellable);
        } catch (Error err) {
            // don't need to close folder; if either calls throws an error, the folder is not open
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Unable to open %s: %s", folder.to_string(), err.message);
            
            return true;
        }
        
        // set up monitoring the Folder's prefetcher so an exception doesn't leave dangling
        // signal subscriptions
        prefetcher_semaphore = new Nonblocking.Semaphore();
        folder.email_prefetcher.halting.connect(on_email_prefetcher_completed);
        folder.closed.connect(on_email_prefetcher_completed);
        
        // turn off the flag watcher whilst synchronizing, as that can cause addt'l load on the
        // CPU
        folder.email_flag_watcher.enabled = false;
        
        try {
            yield sync_folder_async(folder, epoch, oldest_local, oldest_local_id);
        } catch (Error err) {
            if (err is IOError.CANCELLED)
                return false;
            
            debug("Error background syncing folder %s: %s", folder.to_string(), err.message);
            
            // fallthrough and close
        } finally {
            folder.email_prefetcher.halting.disconnect(on_email_prefetcher_completed);
            folder.closed.disconnect(on_email_prefetcher_completed);
            
            folder.email_flag_watcher.enabled = true;
        }
        
        try {
            // don't pass Cancellable; really need this to complete in all cases
            yield folder.close_async();
        } catch (Error err) {
            debug("Error closing %s: %s", folder.to_string(), err.message);
        }
        
        return true;
    }
    
    private async void sync_folder_async(GenericFolder folder, DateTime epoch, DateTime? oldest_local,
        Geary.EmailIdentifier? oldest_local_id) throws Error {
        debug("Background sync'ing %s", folder.to_string());
        
        // only perform vector expansion if oldest isn't old enough
        if (oldest_local == null || oldest_local.compare(epoch) > 0)
            yield expand_folder_async(folder, epoch, oldest_local, oldest_local_id);
        
        // always give email prefetcher time to finish its work
        if (folder.email_prefetcher.has_work()) {
            // expanding an already opened folder doesn't guarantee the prefetcher will start
            debug("Waiting for email prefetcher to complete %s...", folder.to_string());
            try {
                yield prefetcher_semaphore.wait_async(bg_cancellable);
            } catch (Error err) {
                debug("Error waiting for email prefetcher to complete %s: %s", folder.to_string(),
                    err.message);
            }
        }
        
        debug("Done background sync'ing %s", folder.to_string());
    }
    
    private async void expand_folder_async(GenericFolder folder, DateTime epoch, DateTime? oldest_local,
        Geary.EmailIdentifier? oldest_local_id) throws Error {
        // if oldest local ID is known, attempt to turn that into a position on the remote server
        int oldest_local_pos = -1;
        if (oldest_local_id != null) {
            try {
                Geary.Email email = yield folder.fetch_email_async(oldest_local_id,
                    Geary.Email.Field.PROPERTIES, Geary.Folder.ListFlags.NONE);
                oldest_local_pos = email.position;
                debug("%s oldest_id=%s oldest_local=%s oldest_position=%d", folder.to_string(),
                    oldest_local_id.to_string(), oldest_local.to_string(), oldest_local_pos);
            } catch (Error err) {
                debug("Error fetching oldest position on %s: %s", folder.to_string(), err.message);
            }
        }
        
        // TODO: This could be done in a single IMAP SEARCH command, as INTERNALDATE may be searched
        // upon (returning all messages that fit the criteria).  For now, simply iterating backward
        // in the folder until the oldest is found, then pulling the email down in chunks
        int low = (oldest_local_pos >= 1)
            ? Numeric.int_floor(oldest_local_pos - FETCH_DATE_RECEIVED_CHUNK_COUNT, 1) : -1;
        int count = FETCH_DATE_RECEIVED_CHUNK_COUNT;
        for (;;) {
            Gee.List<Email>? list = yield folder.list_email_async(low, count, Geary.Email.Field.PROPERTIES,
                Folder.ListFlags.NONE, bg_cancellable);
            if (list == null || list.size == 0)
                break;
            
            // sort these by their received date so they're walked in order
            Gee.TreeSet<Email> sorted_list = new Collection.FixedTreeSet<Email>(Email.compare_date_received_descending);
            sorted_list.add_all(list);
            
            // look for any that are older than epoch and bail out if found
            bool found = false;
            int lowest = int.MAX;
            foreach (Email email in sorted_list) {
                if (email.properties.date_received.compare(epoch) < 0) {
                    debug("Found epoch for %s at %s (%s)", folder.to_string(), email.id.to_string(),
                        email.properties.date_received.to_string());
                    
                    found = true;
                    
                    break;
                }
                
                // find lowest position for next round of fetching
                if (email.position < lowest)
                    lowest = email.position;
            }
            
            if (found || low == 1)
                break;
            
            low = Numeric.int_floor(lowest - FETCH_DATE_RECEIVED_CHUNK_COUNT, 1);
            count = (lowest - low).clamp(1, FETCH_DATE_RECEIVED_CHUNK_COUNT);
        }
    }
    
    private void on_email_prefetcher_completed() {
        debug("on_email_prefetcher_completed");
        prefetcher_semaphore.blind_notify();
    }
}

