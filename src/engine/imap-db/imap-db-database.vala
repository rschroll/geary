/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern int sqlite3_unicodesn_register_tokenizer(Sqlite.Database db);

private class Geary.ImapDB.Database : Geary.Db.VersionedDatabase {
    private const string DB_FILENAME = "geary.db";
    private string account_owner_email;
    
    public Database(File db_dir, File schema_dir, string account_owner_email) {
        base (db_dir.get_child(DB_FILENAME), schema_dir);
        this.account_owner_email = account_owner_email;
    }
    
    public override void open(Db.DatabaseFlags flags, Db.PrepareConnection? prepare_cb,
        Cancellable? cancellable = null) throws Error {
        // have to do it this way because delegates don't play well with the ternary or nullable
        // operators
        if (prepare_cb != null)
            base.open(flags, prepare_cb, cancellable);
        else
            base.open(flags, on_prepare_database_connection, cancellable);
    }
    
    protected override void post_upgrade(int version) {
        switch (version) {
            case 5:
                post_upgrade_populate_autocomplete();
            break;
            
            case 6:
                post_upgrade_encode_folder_names();
            break;
            
            case 11:
                post_upgrade_add_search_table();
            break;
            
            case 12:
                post_upgrade_populate_internal_date_time_t();
            break;
        }
    }
    
    // Version 5.
    private void post_upgrade_populate_autocomplete() {
        try {
            Db.Result result = query("SELECT sender, from_field, to_field, cc, bcc FROM MessageTable");
            while (!result.finished) {
                MessageAddresses message_addresses =
                    new MessageAddresses.from_result(account_owner_email, result);
                foreach (Contact contact in message_addresses.contacts)
                    do_update_contact(get_master_connection(), contact, null);
                result.next();
            }
        } catch (Error err) {
            debug("Error populating autocompletion table during upgrade to database schema 5");
        }
    }
    
    // Version 6.
    private void post_upgrade_encode_folder_names() {
        try {
            Db.Result select = query("SELECT id, name FROM FolderTable");
            while (!select.finished) {
                int64 id = select.int64_at(0);
                string encoded_name = select.string_at(1);
                
                try {
                    string canonical_name = Geary.ImapUtf7.imap_utf7_to_utf8(encoded_name);
                    
                    Db.Statement update = prepare("UPDATE FolderTable SET name=? WHERE id=?");
                    update.bind_string(0, canonical_name);
                    update.bind_int64(1, id);
                    update.exec();
                } catch (Error e) {
                    debug("Error renaming folder %s to its canonical representation: %s", encoded_name, e.message);
                }
                
                select.next();
            }
        } catch (Error e) {
            debug("Error decoding folder names during upgrade to database schema 6: %s", e.message);
        }
    }
    
    // Version 11.
    private void post_upgrade_add_search_table() {
        try {
            string stemmer = find_appropriate_search_stemmer();
            debug("Creating search table using %s stemmer", stemmer);
            
            // This can't go in the .sql file because its schema (the stemmer
            // algorithm) is determined at runtime.
            exec("""
                CREATE VIRTUAL TABLE MessageSearchTable USING fts4(
                    id INTEGER PRIMARY KEY,
                    body,
                    attachment,
                    subject,
                    from_field,
                    receivers,
                    cc,
                    bcc,
                    
                    tokenize=unicodesn "stemmer=%s",
                    prefix="2,4,6,8,10",
                );
            """.printf(stemmer));
        } catch (Error e) {
            error("Error creating search table: %s", e.message);
        }
    }
    
    private string find_appropriate_search_stemmer() {
        // Unfortunately, the stemmer library only accepts the full language
        // name for the stemming algorithm.  This translates between the user's
        // preferred language ISO 639-1 code and our available stemmers.
        // FIXME: the available list here is determined by what's included in
        // src/sqlite3-unicodesn/CMakeLists.txt.  We should pass that list in
        // instead of hardcoding it here.
        foreach (string l in Intl.get_language_names()) {
            switch (l) {
                case "da": return "danish";
                case "nl": return "dutch";
                case "en": return "english";
                case "fi": return "finnish";
                case "fr": return "french";
                case "de": return "german";
                case "hu": return "hungarian";
                case "it": return "italian";
                case "no": return "norwegian";
                case "pt": return "portuguese";
                case "ro": return "romanian";
                case "ru": return "russian";
                case "es": return "spanish";
                case "sv": return "swedish";
                case "tr": return "turkish";
            }
        }
        
        // Default to English because it seems to be on average the language
        // most likely to be present in emails, regardless of the user's
        // language setting.  This is not an exact science, and search results
        // should be ok either way in most cases.
        return "english";
    }
    
    // Version 12.
    private void post_upgrade_populate_internal_date_time_t() {
        try {
            exec_transaction(Db.TransactionType.RW, (cx) => {
                Db.Result select = cx.query("SELECT id, internaldate FROM MessageTable");
                while (!select.finished) {
                    int64 id = select.rowid_at(0);
                    string? internaldate = select.string_at(1);
                    
                    try {
                        time_t as_time_t = (internaldate != null ?
                            new Geary.Imap.InternalDate(internaldate).as_time_t : -1);
                        
                        Db.Statement update = cx.prepare(
                            "UPDATE MessageTable SET internaldate_time_t=? WHERE id=?");
                        update.bind_int64(0, (int64) as_time_t);
                        update.bind_rowid(1, id);
                        update.exec();
                    } catch (Error e) {
                        debug("Error converting internaldate '%s' to time_t: %s",
                            internaldate, e.message);
                    }
                    
                    select.next();
                }
                
                return Db.TransactionOutcome.COMMIT;
            });
        } catch (Error e) {
            debug("Error populating internaldate_time_t column during upgrade to database schema 11: %s",
                e.message);
        }
    }
    
    private void on_prepare_database_connection(Db.Connection cx) throws Error {
        cx.set_busy_timeout_msec(Db.Connection.RECOMMENDED_BUSY_TIMEOUT_MSEC);
        cx.set_foreign_keys(true);
        cx.set_recursive_triggers(true);
        cx.set_synchronous(Db.SynchronousMode.OFF);
        sqlite3_unicodesn_register_tokenizer(cx.db);
    }
}

