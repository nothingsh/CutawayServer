#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// The two names the hierarchy gives for a class.
enum ClassNames {
    /// The name the runtime knows the class by: `Demo.CardView`, or a mangled name such as
    /// `_TtCC4Demo5Outer5Inner` for classes that are private, nested or generic.
    static func runtimeName(of type: AnyClass) -> String {
        NSStringFromClass(type)
    }

    /// The name as written in source, without the module and without mangling: `CardView`,
    /// `Inner`, `Cell<Int>`. For Objective-C classes it is the runtime name.
    static func displayName(of type: AnyClass) -> String {
        String(describing: type)
    }

    /// Both names of each class met in one capture, worked out once per class: a hierarchy
    /// has many layers of few classes.
    struct Cache {
        private var names: [ObjectIdentifier: (runtime: String, display: String)] = [:]

        mutating func names(of type: AnyClass) -> (runtime: String, display: String) {
            let key = ObjectIdentifier(type)
            if let known = names[key] { return known }
            let found = (ClassNames.runtimeName(of: type), ClassNames.displayName(of: type))
            names[key] = found
            return found
        }
    }
}
#endif
