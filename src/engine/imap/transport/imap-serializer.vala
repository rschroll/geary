/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The Serializer asynchronously writes serialized IMAP commands to the supplied output stream.
 * Since most IMAP commands are small in size (one line of data, often under 64 bytes), the
 * Serializer writes them to a temporary buffer, only writing to the actual stream when literal data
 * is written (which can often be large and coming off of disk) or commit_async() is called, which
 * should be invoked when convenient, to prevent the buffer from growing too large.
 *
 * Because of this situation, the serialized commands will not necessarily reach the output stream
 * unless commit_async() is called, which pushes the in-memory bytes to it.  Since the
 * output stream itself may be buffered, flush_async() should be called to verify the bytes have
 * reached the wire.
 * 
 * flush_async() implies commit_async(), but the reverse is not true.
 */

public class Geary.Imap.Serializer : BaseObject {
    private string identifier;
    private OutputStream outs;
    private ConverterOutputStream couts;
    private MemoryOutputStream mouts;
    private DataOutputStream douts;
    private Geary.Stream.MidstreamConverter midstream = new Geary.Stream.MidstreamConverter("Serializer");
    
    public Serializer(string identifier, OutputStream outs) {
        this.identifier = identifier;
        this.outs = outs;
        
        couts = new ConverterOutputStream(outs, midstream);
        couts.set_close_base_stream(false);
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
        douts.set_close_base_stream(false);
    }
    
    public bool install_converter(Converter converter) {
        return midstream.install(converter);
    }
    
    public void push_ascii(char ch) throws Error {
        douts.put_byte(ch, null);
    }
    
    /**
     * Pushes the string to the IMAP server with quoting applied whether required or not.  Returns
     * true if quoting was required.
     */
    public bool push_quoted_string(string str) throws Error {
        string quoted;
        DataFormat.Quoting requirement = DataFormat.convert_to_quoted(str, out quoted);
        
        douts.put_string(quoted);
        
        return (requirement == DataFormat.Quoting.REQUIRED);
    }
    
    /**
     * This will push the string to IMAP as-is.  Use only if you absolutely know what you're doing.
     */
    public void push_unquoted_string(string str) throws Error {
        douts.put_string(str);
    }
    
    public void push_space() throws Error {
        douts.put_byte(' ', null);
    }
    
    public void push_nil() throws Error {
        douts.put_string(NilParameter.VALUE, null);
    }
    
    public void push_eol() throws Error {
        douts.put_string("\r\n", null);
    }
    
    public async void push_input_stream_literal_data_async(InputStream ins,
        int priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
        // commit the in-memory buffer to the output stream
        yield commit_async(priority, cancellable);
        
        // splice the literal data directly to the output stream
        yield couts.splice_async(ins, OutputStreamSpliceFlags.NONE, priority, cancellable);
    }
    
    // commit_async() takes the stored (in-memory) serialized data and writes it asynchronously
    // to the wrapped OutputStream.  Note that this is *not* a flush, as it's possible the
    // serialized data will be stored in a buffer in the OutputStream.  Use flush_async() to force
    // data onto the wire.
    public async void commit_async(int priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null)
        throws Error {
        size_t length = mouts.get_data_size();
        if (length == 0)
            return;
        
        if (Logging.are_all_flags_set(Logging.Flag.SERIALIZER)) {
            StringBuilder builder = new StringBuilder();
            for (size_t ctr = 0; ctr < length; ctr++)
                builder.append_c((char) mouts.get_data()[ctr]);
            
            Logging.debug(Logging.Flag.SERIALIZER, "[%s] send %s", to_string(), builder.str.strip());
        }
        
        ssize_t index = 0;
        do {
            index += yield couts.write_async(mouts.get_data()[index:length], priority, cancellable);
        } while (index < length);
        
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
    }
    
    // This pushes all serialized data onto the wire.  This calls commit_async() before 
    // flushing.
    public async void flush_async(int priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null)
        throws Error {
        yield commit_async(priority, cancellable);
        yield couts.flush_async(priority, cancellable);
        yield outs.flush_async(priority, cancellable);
    }
    
    public string to_string() {
        return "ser:%s".printf(identifier);
    }
}

