/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An optional status code accompanying a {@link ServerResponse}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 */

public enum Geary.Imap.Status {
    OK,
    NO,
    BAD,
    PREAUTH,
    BYE;
    
    public string to_string() {
        switch (this) {
            case OK:
                return "ok";
            
            case NO:
                return "no";
            
            case BAD:
                return "bad";
            
            case PREAUTH:
                return "preauth";
            
            case BYE:
                return "bye";
            
            default:
                assert_not_reached();
        }
    }
    
    public static Status decode(string value) throws ImapError {
        switch (value.down()) {
            case "ok":
                return OK;
            
            case "no":
                return NO;
            
            case "bad":
                return BAD;
            
            case "preauth":
                return PREAUTH;
            
            case "bye":
                return BYE;
            
            default:
                throw new ImapError.PARSE_ERROR("Unrecognized status response \"%s\"", value);
        }
    }
    
    public static Status from_parameter(StringParameter strparam) throws ImapError {
        return decode(strparam.value);
    }
    
    public Parameter to_parameter() {
        return new AtomParameter(to_string());
    }
}

