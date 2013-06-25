/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Nonblocking.Mailbox<G> : BaseObject {
    public int size { get { return queue.size; } }
    public bool allow_duplicates { get; set; default = true; }
    public bool requeue_duplicate { get; set; default = false; }
    
    private Gee.Queue<G> queue;
    private Nonblocking.Spinlock spinlock = new Nonblocking.Spinlock();
    
    public Mailbox(owned CompareDataFunc<G>? comparator = null) {
        // can't use ternary here, Vala bug
        if (comparator == null)
            queue = new Gee.LinkedList<G>();
        else
            queue = new Gee.PriorityQueue<G>((owned) comparator);
    }
    
    public bool send(G msg) {
        if (!allow_duplicates && queue.contains(msg)) {
            if (requeue_duplicate)
                queue.remove(msg);
            else
                return false;
        }
        
        if (!queue.offer(msg))
            return false;
        
        spinlock.blind_notify();
        
        return true;
    }
    
    /**
     * Returns true if the message was revoked.
     */
    public bool revoke(G msg) {
        return queue.remove(msg);
    }
    
    /**
     * Returns number of removed items.
     */
    public int clear() {
        int count = queue.size;
        if (count != 0)
            queue.clear();
        
        return count;
    }
    
    /**
     * Remove messages matching the given predicate.  Return the number of
     * removed messages.
     */
    public int remove_matching(owned Gee.Predicate<G> predicate) {
        int count = 0;
        // Iterate over a copy so we can modify the original.
        foreach (G msg in queue.to_array()) {
            if (predicate(msg)) {
                queue.remove(msg);
                ++count;
            }
        }
        
        return count;
    }
    
    public async G recv_async(Cancellable? cancellable = null) throws Error {
        for (;;) {
            if (queue.size > 0)
                return queue.poll();
            
            yield spinlock.wait_async(cancellable);
        }
    }
    
    /**
     * Since the queue could potentially alter when the main loop runs, it's important to only
     * examine the queue when not allowing other operations to process.
     *
     * This returns a read-only list in queue-order.  Altering will not affect the queue.  Use
     * revoke() to remove enqueued operations.
     */
    public Gee.Collection<G> get_all() {
        return queue.read_only_view;
    }
}

