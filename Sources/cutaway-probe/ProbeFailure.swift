/// What went wrong, in words meant for the terminal.
struct ProbeFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
