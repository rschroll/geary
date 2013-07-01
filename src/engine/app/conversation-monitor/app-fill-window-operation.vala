/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.FillWindowOperation : ConversationOperation {
    private bool is_insert;
    
    public FillWindowOperation(ConversationMonitor monitor, bool is_insert) {
        base(monitor);
        this.is_insert = is_insert;
    }
    
    public override async void execute_async() {
        yield monitor.fill_window_async(is_insert);
    }
}
