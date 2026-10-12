; Outbound JSON only. Incoming UI commands use a small validated string protocol.
class JsonWriter {
    static Encode(value) {
        if value is Map {
            parts := []
            for key, item in value
                parts.Push(this.Quote(String(key)) ":" this.Encode(item))
            return "{" this.Join(parts) "}"
        }
        if value is Array {
            parts := []
            for item in value
                parts.Push(this.Encode(item))
            return "[" this.Join(parts) "]"
        }
        if value is Integer || value is Float
            return String(value)
        if value is String
            return this.Quote(value)
        throw TypeError("Unsupported JSON value")
    }

    static Quote(value) {
        value := StrReplace(value, "\", "\\")
        value := StrReplace(value, Chr(34), "\" Chr(34))
        value := StrReplace(value, "`r", "\r")
        value := StrReplace(value, "`n", "\n")
        value := StrReplace(value, "`t", "\t")
        value := StrReplace(value, Chr(8), "\b")
        value := StrReplace(value, Chr(12), "\f")
        return Chr(34) value Chr(34)
    }

    static Join(parts) {
        result := ""
        for index, part in parts
            result .= (index > 1 ? "," : "") part
        return result
    }
}
