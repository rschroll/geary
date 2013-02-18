/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.HTML {

public inline string escape_markup(string? plain) {
    return (!String.is_empty(plain) && plain.validate()) ? Markup.escape_text(plain) : "";
}

public inline string newlines_to_br(string? text) {
    return !String.is_empty(text) ? text.replace("\n", "<br />") : "";
}

// Removes any text between < and >.  Additionally, if input terminates in the middle of a tag, 
// the tag will be removed.
// If the HTML is invalid, the original string will be returned.
public string remove_html_tags(string input) {
    try {
        string output = input;
        
        // Count the number of < and > characters.
        unichar c;
        uint64 less_than = 0;
        uint64 greater_than = 0;
        for (int i = 0; output.get_next_char (ref i, out c);) {
            if (c == '<')
                less_than++;
            else if (c == '>')
                greater_than++;
        }
        
        if (less_than == greater_than + 1) {
            output += ">"; // Append an extra > so our regex works.
            greater_than++;
        }
        
        if (less_than != greater_than)
            return input; // Invalid HTML.
        
        // Removes script tags and everything between them.
        // Based on regex here: http://stackoverflow.com/questions/116403/im-looking-for-a-regular-expression-to-remove-a-given-xhtml-tag-from-a-string
        Regex script = new Regex("<script[^>]*?>[\\s\\S]*?<\\/script>", RegexCompileFlags.CASELESS);
        output = script.replace(output, -1, 0, "");
        
        // Removes style tags and everything between them.
        // Based on regex above.
        Regex style = new Regex("<style[^>]*?>[\\s\\S]*?<\\/style>", RegexCompileFlags.CASELESS);
        output = style.replace(output, -1, 0, "");
        
        // Removes remaining tags. Based on this regex:
        // http://osherove.com/blog/2003/5/13/strip-html-tags-from-a-string-using-regular-expressions.html
        Regex tags = new Regex("<(.|\n)*?>", RegexCompileFlags.CASELESS);
        return tags.replace(output, -1, 0, "");
    } catch (Error e) {
        debug("Error stripping HTML tags: %s", e.message);
    }
    
    return input;
}

// TODO_: This is currently destructive to the DOM!  Is this a problem?
public string html_to_flowed_text(WebKit.DOM.Document doc) {
    WebKit.DOM.NodeList blockquotes;
    try {
        blockquotes = doc.query_selector_all("blockquote");
    } catch (Error error) {
        debug("Error selecting blockquotes: %s", error.message);
        return "Sorry, we had an error";
    }
    
    for (int i=0; i<blockquotes.length; i++) {
        WebKit.DOM.Text token = doc.create_text_node(@"$i");
        WebKit.DOM.Node bq = blockquotes.item(i);
        WebKit.DOM.Node parent = bq.get_parent_node();
        try {
            parent.replace_child(token, bq);
        } catch (Error error) {
            debug("Error manipulating DOM: %s", error.message);
        }
    }
    
    string doctext = doc.get_body().get_inner_text();
    string[] bqtexts = new string[blockquotes.length];
    for (int i=0; i<blockquotes.length; i++)
        bqtexts[i] = ((WebKit.DOM.HTMLElement) blockquotes.item(i)).get_inner_text();
    
    doctext = resolve_nesting(doctext, bqtexts);
    
    // wrap, space stuff, quote
    string[] lines = doctext.split("\n");
    GLib.StringBuilder flowed = new GLib.StringBuilder.sized(doctext.length);
    foreach (string line in lines) {
        int quote_level = 0;
        while (line[quote_level] == '\x7f')
            quote_level += 1;
        line = line[quote_level:line.length];
        string prefix = quote_level > 0 ? string.nfill(quote_level, '>') + " " : "";
        int max_len = 72 - prefix.length;
        
        do {
            if (quote_level == 0 && (begins_with(line, ">") || begins_with(line, "From")))
                line = " " + line;
            
            int cut_ind = line.length;
            if (cut_ind > max_len) {
                string beg = line[0:max_len];
                cut_ind = beg.last_index_of(" ") + 1;
                if (cut_ind == 0) {
                    cut_ind = line.index_of(" ") + 1;
                    if (cut_ind == 0)
                        cut_ind = line.length;
                    if (cut_ind > 998 - prefix.length)
                        cut_ind = 998 - prefix.length;
                }
            }
            flowed.append(prefix + line[0:cut_ind] + "\n");
            line = line[cut_ind:line.length];
        } while (line.length > 0);
    }
    
    return flowed.str;
}

public inline bool begins_with(string text, string prefix) {
    return text.length >= prefix.length && text[0:prefix.length] == prefix;
}

public string quote_lines(string text) {
    string[] lines = text.split("\n");
    for (int i=0; i<lines.length; i++)
        lines[i] = "\x7f" + lines[i];
    return string.joinv("\n", lines);
}

public string resolve_nesting(string text, string[] values) {
    try {
        GLib.Regex tokenregex = new GLib.Regex("([0-9]*)(.?)");
        return tokenregex.replace_eval(text, -1, 0, 0, (info, res) => {
            int key = int.parse(info.fetch(1));
            string next_char = info.fetch(2);
            // If there is a next character, and it's not a newline, insert a newline
            // before it.  Otherwise, that text will become part of the inserted quote.
            if (next_char != "" && next_char != "\n")
                next_char = "\n" + next_char;
            if (key >= 0 && key < values.length) {
                res.append(quote_lines(resolve_nesting(values[key], values)) + next_char);
            } else {
                debug("Regex error in denesting blockquotes: Invalid key");
                res.append("");
            }
            return false;
        });
    } catch (Error error) {
        debug("Regex error in denesting blockquotes: %s", error.message);
        return "";
    }
}

public string html_to_flowed_text_alt(WebKit.DOM.Document doc) {
    //WebKit.DOM.HTMLDocument doc = new WebKit.DOM.HTMLDocument(html);
    string html = doc.get_body().get_inner_html();
    StringBuilder flowed = new GLib.StringBuilder.sized(html.length);
    int i = 0, j = 0, k = 0, quote_level = 0;
    bool check_quote_level = false;
    
    while (i < html.length) {
        j = html.index_of("<", i);
        k = html.index_of("\n", i);
        if (k > -1 && k < j) {
            flowed.append(html[i:k+1]);
            if (quote_level > 0)
                flowed.append(string.nfill(quote_level, '>') + " ");
            i = k + 1;
            continue;
        }
        
        if (j == -1)
            j = html.length;
        if (j > i)
            flowed.append(html[i:j]);
        
        i = html.index_of(">", j);
        if (i == -1) {
            debug("Couldn't find end of tag.");
            break;
        }
        string tag = html[j+1:i];
        if (tag[0:2] == "br") {
            flowed.append("\n");
            if (quote_level > 0)
                flowed.append(string.nfill(quote_level, '>') + " ");
        } else if (tag[0:9] == "blockquote") {
            quote_level += 1;
            check_quote_level = true;
        } else if (tag[0:10] == "/blockquote") {
            if (quote_level > 0)
                quote_level -= 1;
            else
                debug("Got an extra </blockquote>.");
            check_quote_level = true;
        }
        
        if (check_quote_level) {
            // If a new line is coming up, then the quote level will be set there
            if (html[i+1] != '\n') {
                int existing_prefix = prefix_length(flowed);
                // If no prefix, start a new line; otherwise erase prefix
                if (existing_prefix == -1)
                    flowed.append("\n");
                else
                    flowed.erase(flowed.len - (existing_prefix + 1), existing_prefix + 1);
                
                if (quote_level > 0)
                    flowed.append(string.nfill(quote_level, '>') + " ");
                //if prefix_length
            }
            check_quote_level = false;
        }
        
        i += 1;
    }
    
    // Now, unescape entities, space stuff if necessary, and wrap lines
    
    return flowed.str;
}

private int prefix_length(StringBuilder str) {
    int i = (int) str.len - 1, count = 0;
    if (str.data[i] != ' ')
        return -1;
    i -= 1;
    while (str.data[i] != '\n') {
        if (str.data[i] != '>')
            return -1;
        count += 1;
        i -= 1;
    }
    return count;
}

}
