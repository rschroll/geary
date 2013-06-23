/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooAccount : Geary.ImapEngine.GenericAccount {
    private static Geary.Endpoint? _imap_endpoint = null;
    public static Geary.Endpoint IMAP_ENDPOINT { get {
        if (_imap_endpoint == null) {
            _imap_endpoint = new Geary.Endpoint(
                "imap.mail.yahoo.com",
                Imap.ClientConnection.DEFAULT_PORT_SSL,
                Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Imap.ClientConnection.RECOMMENDED_TIMEOUT_SEC);
        }
        
        return _imap_endpoint;
    } }
    
    private static Geary.Endpoint? _smtp_endpoint = null;
    public static Geary.Endpoint SMTP_ENDPOINT { get {
        if (_smtp_endpoint == null) {
            _smtp_endpoint = new Geary.Endpoint(
                "smtp.mail.yahoo.com",
                Smtp.ClientConnection.DEFAULT_PORT_SSL,
                Geary.Endpoint.Flags.SSL | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
                Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
        }
        
        return _smtp_endpoint;
    } }
    
    private static Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>? special_map = null;
    
    public YahooAccount(string name, AccountInformation account_information,
        Imap.Account remote, ImapDB.Account local) {
        base (name, account_information, remote, local);
        
        if (special_map == null) {
            special_map = new Gee.HashMap<Geary.FolderPath, Geary.SpecialFolderType>();
            
            special_map.set(new Geary.FolderRoot(Imap.Account.INBOX_NAME, null, false),
                Geary.SpecialFolderType.INBOX);
            special_map.set(new Geary.FolderRoot("Sent", null, false), Geary.SpecialFolderType.SENT);
            special_map.set(new Geary.FolderRoot("Draft", null, false), Geary.SpecialFolderType.DRAFTS);
            special_map.set(new Geary.FolderRoot("Bulk Mail", null, false), Geary.SpecialFolderType.SPAM);
            special_map.set(new Geary.FolderRoot("Trash", null, false), Geary.SpecialFolderType.TRASH);
        }
    }
    
    protected override GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        SpecialFolderType special_folder_type = special_map.has_key(path) ? special_map.get(path)
            : Geary.SpecialFolderType.NONE;
        switch (special_folder_type) {
            case SpecialFolderType.SENT:
                return new GenericSentMailFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
            
            default:
                return new YahooFolder(this, remote_account, local_account, local_folder,
                    special_folder_type);
        }
    }
}

