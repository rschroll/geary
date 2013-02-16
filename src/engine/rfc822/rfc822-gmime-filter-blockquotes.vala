/* Copyright 2012 Yorba Foundation
*
* This software is licensed under the GNU Lesser General Public License
* (version 2.1 or later).  See the COPYING file in this distribution. 
*/

// Filter to insert blockquotes.
class GMime.FilterBlockquotes : GMime.Filter {
    // Invariant: True iff we are either at the beginning of a line, or all characters seen so far
    // have been quote markers or part of a tag.
    private bool in_prefix;
    
    // True if we're in a tag in the prefix only.
    private bool in_tag;
    
    // Invariant: The quote depth of the last complete line seen, or 0 if we have not yet seen a
    // complete line.
    private uint last_quote_level;
    
    // Invariant: The number of '>'s seen so far if we are parsing the prefix, or 0 if we are not
    // parsing the prefix.
    private uint current_quote_level;
    
    public FilterBlockquotes() {
        reset();
    }
    
    public override void reset() {
        in_prefix = true;
        in_tag = false;
        last_quote_level = 0;
        current_quote_level = 0;
    }
    
    public override GMime.Filter copy() {
        FilterBlockquotes new_filter = new FilterBlockquotes();
        
        new_filter.in_prefix = in_prefix;
        new_filter.in_tag = in_tag;
        new_filter.last_quote_level = last_quote_level;
        new_filter.current_quote_level = current_quote_level;
        
        return new_filter;
    }
    
    private void do_filter(char[] inbuf, size_t prespace, out unowned char[] processed_buffer,
        out size_t outprespace, bool flush) {
        
        // Is this necessary?
        set_size(inbuf.length, false);
        
        uint out_index = 0;
        for (uint i = 0; i < inbuf.length; i++) {
            char c = inbuf[i];
            
            if (in_prefix && !in_tag) {
                if (c == '\x7f') {
                    current_quote_level++;
                    continue;
                }
                if (c == '<') {
                    in_tag = true;
                    outbuf[out_index++] = c;
                    continue;
                }
                
                while (current_quote_level > last_quote_level) {
                    insert_string("<blockquote>", ref out_index);
                    last_quote_level += 1;
                }
                while (current_quote_level < last_quote_level) {
                    insert_string("</blockquote>", ref out_index);
                    last_quote_level -= 1;
                }
                
                // We saw a character other than '>', so we're done scanning the prefix.
                in_prefix = false;
            }
            
            if (c == '\n') {
                if(out_index > 3 &&
                    Geary.RFC822.Utils.comp_char_arr_slice(outbuf, out_index-4, "\n-- ")) {
                    out_index -= 3;
                    insert_string("<div>-- \n</div>", ref out_index);
                } else {
                    outbuf[out_index++] = c;
                }
                in_prefix = true;
                current_quote_level = 0;
            } else {
                if (c == '>') {
                    in_tag = false;
                }
                outbuf[out_index++] = c;
            }
        }
        
        if (flush) {
            while (last_quote_level > 0) {
                insert_string("</blockquote>", ref out_index);
                last_quote_level -= 1;
            }
        }
        
        // Slicing the buffer is important, because the buffer is not null-terminated,
        processed_buffer = outbuf[0:out_index];
        outprespace = this.outpre;
    }
    
    public override void filter(char[] inbuf, size_t prespace, out unowned char[] processed_buffer,
        out size_t outprespace) {
        do_filter(inbuf, prespace, out processed_buffer, out outprespace, false);
    }
    
    public override void complete(char[] inbuf, size_t prespace, out unowned char[] processed_buffer,
        out size_t outprespace) {
        do_filter(inbuf, prespace, out processed_buffer, out outprespace, true);
    }
    
    private void insert_string(string str, ref uint out_index) {
        set_size(outbuf.length + str.length, true);
        for (int i=0; i<str.length; i++)
            outbuf[out_index++] = str[i];
    }
}
