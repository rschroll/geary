/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ReplayDisconnect : Geary.ImapEngine.ReceiveReplayOperation {
    public GenericFolder owner;
    public Imap.ClientSession.DisconnectReason reason;
    
    public ReplayDisconnect(GenericFolder owner, Imap.ClientSession.DisconnectReason reason) {
        base ("Disconnect");
        
        this.owner = owner;
        this.reason = reason;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        yield owner.do_replay_remote_disconnected(reason);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "reason=%s".printf(reason.to_string());
    }
}

